#import "BRPPCMachOLoader.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCResolveRegistry.h"
#import <mach/machine.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>

static NSString * const BRPPCMachOErrorDomain = @"theoderoy.Bismuth.macho";
enum {
    BRPPCThreadStateFlavor = 1, BRPPCThreadStateWordCount = 40,
    BRPPCThreadStateSRR0Index = 0,
};

static uint32_t U32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
}
static uint16_t U16(const uint8_t *p) {
    return (uint16_t)p[0] << 8 | p[1];
}
static NSString *FixedName(const uint8_t *p) {
    NSUInteger length = 0;
    while (length < 16 && p[length]) length++;
    return [[NSString alloc] initWithBytes:p length:length encoding:NSASCIIStringEncoding] ?: @"";
}
static NSString *CStringInData(NSData *data, uint32_t offset, uint32_t limit) {
    if (offset >= data.length) return nil;
    const uint8_t *p = data.bytes;
    NSUInteger end = MIN(data.length, (NSUInteger)offset + limit), i = offset;
    while (i < end && p[i]) i++;
    if (i == end) return nil;
    return [[NSString alloc] initWithBytes:p + offset length:i - offset encoding:NSUTF8StringEncoding];
}

@implementation BRPPCMachOSection
@end

@interface BRPPCMachOImage ()
@property(nonatomic) uint32_t entryPoint;
@property(nonatomic) uint32_t mainAddress;
@property(nonatomic, strong) NSDictionary<NSString *, NSNumber *> *symbols;
@property(nonatomic, strong) NSArray<NSString *> *dependencies;
@property(nonatomic, strong) NSArray<BRPPCMachOSection *> *sections;
@property(nonatomic, strong) NSArray<NSString *> *undefinedSymbols;
@property(nonatomic, strong) NSSet<NSString *> *weakUndefinedSymbols;
@property(nonatomic, strong) NSData *slice;
@property(nonatomic) uint32_t symoff, nsyms, stroff, strsize;
@property(nonatomic) uint32_t indirectsymoff, nindirectsyms;
@end

@implementation BRPPCMachOImage
- (BRPPCMachOSection *)sectionInSegment:(NSString *)segment name:(NSString *)name {
    for (BRPPCMachOSection *section in _sections)
        if ([section.segmentName isEqualToString:segment] && [section.sectionName isEqualToString:name])
            return section;
    return nil;
}
@end

@implementation BRPPCMachOLoader
- (NSData *)powerPCSliceFromData:(NSData *)file error:(NSError **)error {
    if (file.length < 4) goto bad;
    const uint8_t *p = file.bytes;
    uint32_t magic = U32(p);
    if (magic == MH_MAGIC) return file;
    if (magic != FAT_MAGIC || file.length < 8) goto bad;
    uint32_t count = U32(p + 4);
    if (count > 64 || file.length < 8ull + 20ull * count) goto bad;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *arch = p + 8 + 20 * i;
        uint32_t type = U32(arch), offset = U32(arch + 8), size = U32(arch + 12);
        if (type == CPU_TYPE_POWERPC && (uint64_t)offset + size <= file.length)
            return [file subdataWithRange:NSMakeRange(offset, size)];
    }
    if (error) *error = [NSError errorWithDomain:BRPPCMachOErrorDomain code:2
        userInfo:@{NSLocalizedDescriptionKey: @"Mach-O has no PowerPC32 slice."}];
    return nil;
bad:
    if (error) *error = [NSError errorWithDomain:BRPPCMachOErrorDomain code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Malformed or unsupported Mach-O file."}];
    return nil;
}

- (BRPPCMachOImage *)loadURL:(NSURL *)URL intoMemory:(BRPPCAddressSpace *)memory
                         error:(NSError **)error {
    NSData *file = [NSData dataWithContentsOfURL:URL options:NSDataReadingMappedIfSafe error:error];
    if (!file) return nil;
    NSData *slice = [self powerPCSliceFromData:file error:error];
    if (!slice || slice.length < 28) return nil;
    const uint8_t *p = slice.bytes;
    if (U32(p) != MH_MAGIC || U32(p + 4) != CPU_TYPE_POWERPC) {
        if (error) *error = [NSError errorWithDomain:BRPPCMachOErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Slice is not a big-endian PowerPC32 Mach-O."}];
        return nil;
    }
    uint32_t ncmds = U32(p + 16), sizeofcmds = U32(p + 20);
    if ((uint64_t)28 + sizeofcmds > slice.length || ncmds > 4096) return nil;

    BRPPCMachOImage *image = [BRPPCMachOImage new];
    image.slice = slice;
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *dependencies = [NSMutableArray array];
    uint32_t commandOffset = 28;
    for (uint32_t i = 0; i < ncmds; i++) {
        if ((uint64_t)commandOffset + 8 > slice.length) return nil;
        const uint8_t *command = p + commandOffset;
        uint32_t cmd = U32(command), cmdsize = U32(command + 4);
        if (cmdsize < 8 || (uint64_t)commandOffset + cmdsize > slice.length) return nil;
        if (cmd == LC_SEGMENT && cmdsize >= 56) {
            NSString *segmentName = FixedName(command + 8);
            uint32_t vmaddr = U32(command + 24), vmsize = U32(command + 28);
            uint32_t fileoff = U32(command + 32), filesize = U32(command + 36);
            uint32_t initprot = U32(command + 44), nsects = U32(command + 48);
            if ((uint64_t)fileoff + filesize > slice.length || 56ull + 68ull * nsects > cmdsize) return nil;
            if (vmsize && ![segmentName isEqualToString:@"__PAGEZERO"]) {
                BRPPCMemoryProtection protection = 0;
                if (initprot & 1) protection |= BRPPCMemoryRead;
                if (initprot & 2) protection |= BRPPCMemoryWrite;
                if (initprot & 4) protection |= BRPPCMemoryExecute;

                if (![memory mapAddress:vmaddr size:vmsize protection:protection | BRPPCMemoryWrite
                                   name:segmentName error:error]) return nil;
                if (filesize) {
                    NSData *contents = [NSData dataWithBytesNoCopy:(void *)(p + fileoff)
                                                             length:filesize
                                                       freeWhenDone:NO];
                    if (![memory copyData:contents toAddress:vmaddr error:error]) return nil;
                }
            }
            for (uint32_t s = 0; s < nsects; s++) {
                const uint8_t *sectionData = command + 56 + 68 * s;
                BRPPCMachOSection *section = [BRPPCMachOSection new];
                section.sectionName = FixedName(sectionData);
                section.segmentName = FixedName(sectionData + 16);
                section.address = U32(sectionData + 32);
                section.size = U32(sectionData + 36);
                section.flags = U32(sectionData + 56);
                section.reserved1 = U32(sectionData + 60);
                [sections addObject:section];
            }
        } else if (cmd == LC_SYMTAB && cmdsize >= 24) {
            image.symoff = U32(command + 8); image.nsyms = U32(command + 12);
            image.stroff = U32(command + 16); image.strsize = U32(command + 20);
        } else if (cmd == LC_DYSYMTAB && cmdsize >= 80) {
            image.indirectsymoff = U32(command + 56);
            image.nindirectsyms = U32(command + 60);
        } else if ((cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB) && cmdsize >= 24) {
            uint32_t nameOffset = U32(command + 8);
            NSString *name = nameOffset < cmdsize ? CStringInData(slice, commandOffset + nameOffset,
                                                                   cmdsize - nameOffset) : nil;
            if (name) [dependencies addObject:name];
        } else if (cmd == LC_THREAD || cmd == LC_UNIXTHREAD) {
            uint32_t stateOffset = 8;
            while ((uint64_t)stateOffset + 8 <= cmdsize) {
                uint32_t flavor = U32(command + stateOffset);
                uint32_t count = U32(command + stateOffset + 4);
                uint64_t stateBytes = 4ull * count;
                if ((uint64_t)stateOffset + 8 + stateBytes > cmdsize) return nil;
                if (flavor == BRPPCThreadStateFlavor && count >= BRPPCThreadStateWordCount)
                    image.entryPoint = U32(command + stateOffset + 8 +
                                           4 * BRPPCThreadStateSRR0Index);
                stateOffset += 8 + (uint32_t)stateBytes;
            }
        }
        commandOffset += cmdsize;
    }
    image.sections = sections;
    image.dependencies = dependencies;

    if ((uint64_t)image.symoff + 12ull * image.nsyms > slice.length ||
        (uint64_t)image.stroff + image.strsize > slice.length) return nil;
    NSMutableDictionary *symbols = [NSMutableDictionary dictionary];
    NSMutableArray *undefined = [NSMutableArray array];
    NSMutableSet *weakUndefined = [NSMutableSet set];
    for (uint32_t i = 0; i < image.nsyms; i++) {
        const uint8_t *nlist = p + image.symoff + 12 * i;
        uint32_t stringIndex = U32(nlist), value = U32(nlist + 8);
        NSString *name = stringIndex < image.strsize
            ? CStringInData(slice, image.stroff + stringIndex, image.strsize - stringIndex) : nil;
        if (!name.length) continue;
        uint8_t type = nlist[4] & N_TYPE;
        if (type == 0) {
            [undefined addObject:name];
            if (U16(nlist + 6) & N_WEAK_REF) [weakUndefined addObject:name];
        }
        else {
            symbols[name] = @(value);
            if ([name isEqualToString:@"_main"]) image.mainAddress = value;
        }
    }
    image.symbols = symbols;
    image.undefinedSymbols = undefined;
    image.weakUndefinedSymbols = weakUndefined;
    return image;
}

- (BOOL)bindImage:(BRPPCMachOImage *)image registry:(BRPPCResolveRegistry *)registry
             error:(NSError **)error {
    if ((uint64_t)image.indirectsymoff + 4ull * image.nindirectsyms > image.slice.length) return NO;
    const uint8_t *p = image.slice.bytes;
    NSMutableArray<NSString *> *symbolNames = [NSMutableArray arrayWithCapacity:image.nsyms];
    for (uint32_t i = 0; i < image.nsyms; i++) {
        const uint8_t *nlist = p + image.symoff + 12 * i;
        uint32_t index = U32(nlist);
        NSString *name = index < image.strsize
            ? CStringInData(image.slice, image.stroff + index, image.strsize - index) : nil;
        [symbolNames addObject:name ?: @""];
    }
    for (BRPPCMachOSection *section in image.sections) {
        uint32_t type = section.flags & SECTION_TYPE;
        if (type != S_LAZY_SYMBOL_POINTERS && type != S_NON_LAZY_SYMBOL_POINTERS) continue;
        uint32_t count = section.size / 4;
        for (uint32_t i = 0; i < count; i++) {
            uint32_t indirectIndex = section.reserved1 + i;
            if (indirectIndex >= image.nindirectsyms) return NO;
            uint32_t symbolIndex = U32(p + image.indirectsymoff + 4 * indirectIndex);
            if (symbolIndex & (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
            if (symbolIndex >= symbolNames.count) return NO;
            NSString *name = symbolNames[symbolIndex];
            uint32_t target = [registry addressForSymbol:name lazy:type == S_LAZY_SYMBOL_POINTERS error:error];
            if (!target) {
                if (error && !*error) *error = [NSError errorWithDomain:BRPPCMachOErrorDomain code:4
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"No compatibility resolver for %@.", name]}];
                return NO;
            }
            if (![registry.memory writeUInt32:target address:section.address + 4 * i]) return NO;
        }
    }
    return YES;
}
@end
