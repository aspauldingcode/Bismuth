#import "BRPPCAddressSpace.h"

static NSString * const BRPPCAddressSpaceErrorDomain = @"theoderoy.Bismuth.AddressSpace";

@interface BRPPCMemoryRegion : NSObject
@property(nonatomic) uint32_t address;
@property(nonatomic) uint32_t size;
@property(nonatomic) BRPPCMemoryProtection protection;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, strong) NSMutableData *bytes;
@end
@implementation BRPPCMemoryRegion
@end

typedef struct {
    uint32_t address;
    uint64_t end;
    BRPPCMemoryProtection protection;
    uint8_t *bytes;
} BRPPCRegionCacheEntry;

@interface BRPPCAddressSpace ()
{
    BRPPCRegionCacheEntry _regionCache[4];
    NSUInteger _nextRegionCacheSlot;
    BRPPCRegionCacheEntry *_mostRecentRegion;
    BRPPCInstructionCacheInvalidationHandler _instructionCacheInvalidationHandler;
}
@property(nonatomic, strong) NSMutableArray<BRPPCMemoryRegion *> *regions;
- (BRPPCRegionCacheEntry *)regionAt:(uint32_t)address
                             length:(size_t)length
    __attribute__((objc_direct));
@end

@implementation BRPPCAddressSpace
- (instancetype)init {
    if ((self = [super init])) _regions = [NSMutableArray array];
    return self;
}

- (BRPPCRegionCacheEntry *)regionAt:(uint32_t)address length:(size_t)length {
    uint64_t end = (uint64_t)address + length;
    if (end > (1ull << 32)) return nil;
    BRPPCRegionCacheEntry *recent = _mostRecentRegion;
    if (recent && address >= recent->address && end <= recent->end) return recent;
    for (NSUInteger index = 0; index < 4; index++) {
        BRPPCRegionCacheEntry *entry = &_regionCache[index];
        if (entry->bytes && address >= entry->address && end <= entry->end) {
            _mostRecentRegion = entry;
            return entry;
        }
    }
    for (BRPPCMemoryRegion *region in _regions) {
        uint64_t regionEnd = (uint64_t)region.address + region.size;
        if (address >= region.address && end <= regionEnd) {
            BRPPCRegionCacheEntry *entry = &_regionCache[_nextRegionCacheSlot++ & 3];
            entry->address = region.address;
            entry->end = regionEnd;
            entry->protection = region.protection;
            entry->bytes = region.bytes.mutableBytes;
            _mostRecentRegion = entry;
            return entry;
        }
    }
    return nil;
}

- (BOOL)mapAddress:(uint32_t)address size:(uint32_t)size
        protection:(BRPPCMemoryProtection)protection name:(NSString *)name
             error:(NSError **)error {
    uint64_t end = (uint64_t)address + size;
    if (!size || end > (1ull << 32)) {
        if (error) *error = [NSError errorWithDomain:BRPPCAddressSpaceErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid guest memory range."}];
        return NO;
    }
    for (BRPPCMemoryRegion *region in _regions) {
        uint64_t regionEnd = (uint64_t)region.address + region.size;
        if ((uint64_t)address < regionEnd && end > region.address) {
            if (error) *error = [NSError errorWithDomain:BRPPCAddressSpaceErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Guest mapping %@ overlaps %@.", name, region.name]}];
            return NO;
        }
    }
    BRPPCMemoryRegion *region = [BRPPCMemoryRegion new];
    region.address = address;
    region.size = size;
    region.protection = protection;
    region.name = name;
    region.bytes = [NSMutableData dataWithLength:size];
    [_regions addObject:region];
    return YES;
}

- (BOOL)readBytes:(void *)destination address:(uint32_t)address length:(size_t)length {
    BRPPCRegionCacheEntry *region = [self regionAt:address length:length];
    if (!region || !(region->protection & BRPPCMemoryRead)) return NO;
    memcpy(destination, region->bytes + (address - region->address), length);
    return YES;
}

- (BOOL)writeBytes:(const void *)source address:(uint32_t)address length:(size_t)length {
    BRPPCRegionCacheEntry *region = [self regionAt:address length:length];
    if (!region || !(region->protection & BRPPCMemoryWrite)) return NO;
    memcpy(region->bytes + (address - region->address), source, length);
    if ((region->protection & BRPPCMemoryExecute) && _instructionCacheInvalidationHandler)
        _instructionCacheInvalidationHandler(address, length);
    return YES;
}

- (void)setInstructionCacheInvalidationHandler:
    (BRPPCInstructionCacheInvalidationHandler)handler {
    _instructionCacheInvalidationHandler = [handler copy];
}

- (BOOL)copyData:(NSData *)data toAddress:(uint32_t)address error:(NSError **)error {
    if (![self writeBytes:data.bytes address:address length:data.length]) {
        if (error) *error = [NSError errorWithDomain:BRPPCAddressSpaceErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Guest destination is not writable."}];
        return NO;
    }
    return YES;
}

- (BOOL)readUInt32:(uint32_t *)value address:(uint32_t)address {
    BRPPCRegionCacheEntry *region = [self regionAt:address length:4];
    if (!region || !(region->protection & BRPPCMemoryRead)) return NO;
    const uint8_t *bytes = region->bytes + (address - region->address);
    *value = (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 |
             (uint32_t)bytes[2] << 8 | bytes[3];
    return YES;
}

- (BOOL)writeUInt32:(uint32_t)value address:(uint32_t)address {
    BRPPCRegionCacheEntry *region = [self regionAt:address length:4];
    if (!region || !(region->protection & BRPPCMemoryWrite)) return NO;
    uint8_t *bytes = region->bytes + (address - region->address);
    bytes[0] = (uint8_t)(value >> 24);
    bytes[1] = (uint8_t)(value >> 16);
    bytes[2] = (uint8_t)(value >> 8);
    bytes[3] = (uint8_t)value;
    if ((region->protection & BRPPCMemoryExecute) && _instructionCacheInvalidationHandler)
        _instructionCacheInvalidationHandler(address, 4);
    return YES;
}

- (NSString *)readCStringAtAddress:(uint32_t)address maximumLength:(NSUInteger)limit {
    NSMutableData *data = nil;
    uint32_t cursor = address;
    NSUInteger remaining = limit;
    while (remaining) {
        BRPPCRegionCacheEntry *region = [self regionAt:cursor length:1];
        if (!region || !(region->protection & BRPPCMemoryRead)) return nil;
        uint64_t regionLength = region->end - cursor;
        NSUInteger length = (NSUInteger)MIN((uint64_t)remaining, regionLength);
        const uint8_t *bytes = region->bytes + (cursor - region->address);
        const uint8_t *terminator = memchr(bytes, 0, length);
        NSUInteger chunkLength = terminator ? (NSUInteger)(terminator - bytes) : length;
        if (terminator) {
            if (!data)
                return [[NSString alloc] initWithBytes:bytes length:chunkLength
                                              encoding:NSUTF8StringEncoding];
            [data appendBytes:bytes length:chunkLength];
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if (!data) data = [NSMutableData data];
        [data appendBytes:bytes length:chunkLength];
        remaining -= length;
        if (length > UINT32_MAX - cursor) return nil;
        cursor += (uint32_t)length;
    }
    return nil;
}
@end
