#import "BRPPCNetworkResolve.h"
#import "BRPPCAddressSpace.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <poll.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

static NSString * const BRPPCNetworkErrorDomain = @"theoderoy.Bismuth.network";

@interface BRPPCGuestMessage : NSObject {
@public
    struct msghdr _message;
    struct iovec *_vectors;
}
@property(nonatomic, strong) NSMutableData *nameData;
@property(nonatomic, strong) NSMutableData *controlData;
@property(nonatomic, strong) NSMutableArray<NSMutableData *> *buffers;
@property(nonatomic, strong) NSArray<NSNumber *> *guestBufferAddresses;
@property(nonatomic, strong) NSArray<NSNumber *> *guestBufferLengths;
@end
@implementation BRPPCGuestMessage
- (void)dealloc { free(_vectors); }
@end

@interface BRPPCNetworkResolve ()
@property(nonatomic, weak) BRPPCResolveRegistry *registry;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<NSNumber *> *> *addressInfoAllocations;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *errorStrings;
@property(nonatomic, strong) NSArray<NSNumber *> *legacyHostAllocations;
@property(nonatomic, strong) NSArray<NSNumber *> *legacyServiceAllocations;
@property(nonatomic, strong) NSArray<NSNumber *> *legacyProtocolAllocations;
@property(nonatomic) uint32_t guestHerrnoAddress;
@end

@implementation BRPPCNetworkResolve

static void NetworkFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

static uint64_t ReadBigEndianInteger(const uint8_t *bytes, NSUInteger size) {
    uint64_t value = 0;
    for (NSUInteger i = 0; i < size; i++) value = value << 8 | bytes[i];
    return value;
}

static void WriteBigEndianInteger(uint8_t *bytes, NSUInteger size, uint64_t value) {
    for (NSUInteger i = 0; i < size; i++) bytes[size - i - 1] = (uint8_t)(value >> (i * 8));
}

- (void)setErrno:(int)value {
    if (_registry.guestErrnoAddress)
        [_registry.memory writeUInt32:(uint32_t)value address:_registry.guestErrnoAddress];
}

- (void)fail:(BRPPCState *)state error:(int)value {
    [self setErrno:value];
    NetworkFinish(state, UINT32_MAX);
}

- (NSString *)stringAtAddress:(uint32_t)address {
    return address ? [_registry.memory readCStringAtAddress:address maximumLength:1u << 20] : nil;
}

- (BOOL)readSocketAddress:(struct sockaddr_storage *)storage address:(uint32_t)address
                   length:(socklen_t)length {
    if (!address || length > sizeof(*storage)) return NO;
    memset(storage, 0, sizeof(*storage));
    return [_registry.memory readBytes:storage address:address length:length];
}

- (BOOL)writeSocketAddress:(const struct sockaddr *)address length:(socklen_t)length
              guestAddress:(uint32_t)guestAddress guestLengthAddress:(uint32_t)lengthAddress {
    uint32_t capacity = length;
    if (lengthAddress && ![_registry.memory readUInt32:&capacity address:lengthAddress]) return NO;
    if (guestAddress && capacity && ![_registry.memory writeBytes:address address:guestAddress
                                                          length:MIN((socklen_t)capacity, length)]) return NO;
    return !lengthAddress || [_registry.memory writeUInt32:length address:lengthAddress];
}

- (BOOL)readGuestFDSet:(fd_set *)set address:(uint32_t)address count:(int)count {
    FD_ZERO(set);
    if (!address) return YES;
    uint32_t cachedWord = 0; int cachedIndex = -1;
    for (int descriptor = 0; descriptor < count; descriptor++) {
        int index = descriptor / 32;
        if (index != cachedIndex) {
            if (![_registry.memory readUInt32:&cachedWord address:address + (uint32_t)index * 4]) return NO;
            cachedIndex = index;
        }
        if (cachedWord & (1u << (descriptor % 32))) FD_SET(descriptor, set);
    }
    return YES;
}

- (BOOL)writeGuestFDSet:(fd_set *)set address:(uint32_t)address count:(int)count {
    if (!address) return YES;
    int words = (count + 31) / 32;
    for (int index = 0; index < words; index++) {
        uint32_t word = 0;
        for (int bit = 0; bit < 32; bit++) {
            int descriptor = index * 32 + bit;
            if (descriptor < count && FD_ISSET(descriptor, set)) word |= 1u << bit;
        }
        if (![_registry.memory writeUInt32:word address:address + (uint32_t)index * 4]) return NO;
    }
    return YES;
}

- (uint32_t)copyCStringToGuest:(const char *)string allocations:(NSMutableArray<NSNumber *> *)allocations {
    if (!string) return 0;
    size_t length = strlen(string) + 1;
    if (length > UINT32_MAX || !_registry.guestAllocator) return 0;
    uint32_t address = _registry.guestAllocator((uint32_t)length, NO);
    if (!address || ![_registry.memory writeBytes:string address:address length:length]) return 0;
    if (allocations) [allocations addObject:@(address)];
    return address;
}

- (NSMutableData *)hostControlFromGuestAddress:(uint32_t)address length:(uint32_t)length {
    NSMutableData *guest = [NSMutableData dataWithLength:length];
    if (length && ![_registry.memory readBytes:guest.mutableBytes address:address length:length]) return nil;
    NSMutableData *host = [guest mutableCopy];
    const uint8_t *source = guest.bytes; uint8_t *destination = host.mutableBytes;
    for (uint32_t offset = 0; offset < length;) {
        if (length - offset < sizeof(struct cmsghdr)) return nil;
        uint32_t itemLength = (uint32_t)ReadBigEndianInteger(source + offset, 4);
        uint32_t level = (uint32_t)ReadBigEndianInteger(source + offset + 4, 4);
        uint32_t type = (uint32_t)ReadBigEndianInteger(source + offset + 8, 4);
        if (itemLength < sizeof(struct cmsghdr) || itemLength > length - offset) return nil;
        memcpy(destination + offset, &itemLength, 4);
        memcpy(destination + offset + 4, &level, 4);
        memcpy(destination + offset + 8, &type, 4);
        if ((int)level == SOL_SOCKET && (int)type == SCM_RIGHTS) {
            uint32_t payload = itemLength - (uint32_t)sizeof(struct cmsghdr);
            if (payload % 4) return nil;
            for (uint32_t position = 0; position < payload; position += 4) {
                uint32_t descriptor = (uint32_t)ReadBigEndianInteger(
                    source + offset + sizeof(struct cmsghdr) + position, 4);
                memcpy(destination + offset + sizeof(struct cmsghdr) + position, &descriptor, 4);
            }
        }
        uint32_t advance = (itemLength + 3) & ~3u;
        if (!advance || advance > length - offset) {
            if (itemLength == length - offset) break;
            return nil;
        }
        offset += advance;
    }
    return host;
}

- (NSMutableData *)guestControlFromHostBytes:(const void *)bytes length:(uint32_t)length {
    NSMutableData *guest = [NSMutableData dataWithBytes:bytes length:length];
    const uint8_t *source = bytes; uint8_t *destination = guest.mutableBytes;
    for (uint32_t offset = 0; offset < length;) {
        if (length - offset < sizeof(struct cmsghdr)) return nil;
        uint32_t itemLength = 0, level = 0, type = 0;
        memcpy(&itemLength, source + offset, 4); memcpy(&level, source + offset + 4, 4);
        memcpy(&type, source + offset + 8, 4);
        if (itemLength < sizeof(struct cmsghdr) || itemLength > length - offset) return nil;
        WriteBigEndianInteger(destination + offset, 4, itemLength);
        WriteBigEndianInteger(destination + offset + 4, 4, level);
        WriteBigEndianInteger(destination + offset + 8, 4, type);
        if ((int)level == SOL_SOCKET && (int)type == SCM_RIGHTS) {
            uint32_t payload = itemLength - (uint32_t)sizeof(struct cmsghdr);
            if (payload % 4) return nil;
            for (uint32_t position = 0; position < payload; position += 4) {
                uint32_t descriptor = 0;
                memcpy(&descriptor, source + offset + sizeof(struct cmsghdr) + position, 4);
                WriteBigEndianInteger(destination + offset + sizeof(struct cmsghdr) + position,
                                      4, descriptor);
            }
        }
        uint32_t advance = (itemLength + 3) & ~3u;
        if (!advance || advance > length - offset) {
            if (itemLength == length - offset) break;
            return nil;
        }
        offset += advance;
    }
    return guest;
}

- (BRPPCGuestMessage *)messageAtAddress:(uint32_t)address sending:(BOOL)sending
                            errorNumber:(int *)errorNumber {
    uint32_t fields[7];
    for (NSUInteger i = 0; i < 7; i++)
        if (![_registry.memory readUInt32:&fields[i] address:address + (uint32_t)i * 4]) {
            *errorNumber = EFAULT; return nil;
        }
    uint32_t nameAddress = fields[0], nameLength = fields[1], vectorsAddress = fields[2];
    uint32_t vectorCount = fields[3], controlAddress = fields[4], controlLength = fields[5];
    if ((nameLength && !nameAddress) || (vectorCount && !vectorsAddress) ||
        (controlLength && !controlAddress) || nameLength > sizeof(struct sockaddr_storage) || vectorCount > IOV_MAX ||
        controlLength > (1u << 24)) { *errorNumber = EINVAL; return nil; }
    BRPPCGuestMessage *record = [BRPPCGuestMessage new];
    record.buffers = [NSMutableArray arrayWithCapacity:vectorCount];
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:vectorCount];
    NSMutableArray *lengths = [NSMutableArray arrayWithCapacity:vectorCount];
    record->_vectors = calloc(vectorCount ?: 1, sizeof(struct iovec));
    if (!record->_vectors) { *errorNumber = ENOMEM; return nil; }
    uint64_t total = 0;
    for (uint32_t i = 0; i < vectorCount; i++) {
        uint32_t bufferAddress = 0, bufferLength = 0;
        if (![_registry.memory readUInt32:&bufferAddress address:vectorsAddress + i * 8] ||
            ![_registry.memory readUInt32:&bufferLength address:vectorsAddress + i * 8 + 4] ||
            (total += bufferLength) > (1u << 28)) { *errorNumber = EFAULT; return nil; }
        NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];
        if (sending && bufferLength && ![_registry.memory readBytes:buffer.mutableBytes
                                                               address:bufferAddress length:bufferLength]) {
            *errorNumber = EFAULT; return nil;
        }
        [record.buffers addObject:buffer]; [addresses addObject:@(bufferAddress)]; [lengths addObject:@(bufferLength)];
        record->_vectors[i].iov_base = buffer.mutableBytes; record->_vectors[i].iov_len = bufferLength;
    }
    record.guestBufferAddresses = addresses; record.guestBufferLengths = lengths;
    if (nameAddress && nameLength) {
        record.nameData = [NSMutableData dataWithLength:nameLength];
        if (sending && ![_registry.memory readBytes:record.nameData.mutableBytes
                                              address:nameAddress length:nameLength]) { *errorNumber = EFAULT; return nil; }
    }
    if (controlAddress && controlLength) {
        record.controlData = sending
            ? [self hostControlFromGuestAddress:controlAddress length:controlLength]
            : [NSMutableData dataWithLength:controlLength];
        if (!record.controlData) { *errorNumber = EINVAL; return nil; }
    }
    record->_message.msg_name = record.nameData.mutableBytes;
    record->_message.msg_namelen = nameLength;
    record->_message.msg_iov = record->_vectors; record->_message.msg_iovlen = (int)vectorCount;
    record->_message.msg_control = record.controlData.mutableBytes;
    record->_message.msg_controllen = controlLength; record->_message.msg_flags = (int)fields[6];
    return record;
}

- (void)setGuestHerrno:(int)value {
    if (_guestHerrnoAddress) [_registry.memory writeUInt32:(uint32_t)value address:_guestHerrnoAddress];
}

- (uint32_t)hostEntryWithName:(NSString *)name addresses:(NSArray<NSData *> *)addresses
                        family:(int)family {
    if (!_registry.guestAllocator || !name.length || !addresses.count) return 0;
    for (NSNumber *allocation in _legacyHostAllocations)
        if (_registry.guestDeallocator) _registry.guestDeallocator(allocation.unsignedIntValue);
    self.legacyHostAllocations = nil;
    NSMutableArray<NSNumber *> *allocations = [NSMutableArray array];
    uint32_t root = _registry.guestAllocator(20, YES);
    uint32_t aliases = _registry.guestAllocator(4, YES);
    uint32_t addressList = _registry.guestAllocator((uint32_t)(addresses.count + 1) * 4, YES);
    if (root) [allocations addObject:@(root)];
    if (aliases) [allocations addObject:@(aliases)];
    if (addressList) [allocations addObject:@(addressList)];
    uint32_t nameAddress = [self copyCStringToGuest:name.UTF8String allocations:allocations];
    if (!root || !aliases || !addressList || !nameAddress) goto failed;
    uint32_t addressLength = family == AF_INET6 ? 16 : 4;
    for (NSUInteger i = 0; i < addresses.count; i++) {
        NSData *data = addresses[i];
        if (data.length != addressLength) goto failed;
        uint32_t guestAddress = _registry.guestAllocator(addressLength, NO);
        if (!guestAddress || ![_registry.memory writeBytes:data.bytes address:guestAddress length:addressLength] ||
            ![_registry.memory writeUInt32:guestAddress address:addressList + (uint32_t)i * 4]) goto failed;
        [allocations addObject:@(guestAddress)];
    }
    if (![_registry.memory writeUInt32:nameAddress address:root] ||
        ![_registry.memory writeUInt32:aliases address:root + 4] ||
        ![_registry.memory writeUInt32:(uint32_t)family address:root + 8] ||
        ![_registry.memory writeUInt32:addressLength address:root + 12] ||
        ![_registry.memory writeUInt32:addressList address:root + 16]) goto failed;
    self.legacyHostAllocations = allocations;
    [self setGuestHerrno:0];
    return root;
failed:
    for (NSNumber *allocation in allocations)
        if (_registry.guestDeallocator) _registry.guestDeallocator(allocation.unsignedIntValue);
    [self setGuestHerrno:NO_RECOVERY];
    return 0;
}

- (uint32_t)resolveLegacyHostName:(NSString *)name family:(int)requestedFamily {
    if (!name.length) { [self setGuestHerrno:HOST_NOT_FOUND]; return 0; }
    struct addrinfo hints = {0}, *results = NULL;
    hints.ai_family = requestedFamily; hints.ai_socktype = SOCK_STREAM; hints.ai_flags = AI_CANONNAME;
    int result = getaddrinfo(name.UTF8String, NULL, &hints, &results);
    if (result) {
        [self setGuestHerrno:result == EAI_AGAIN ? TRY_AGAIN :
            (result == EAI_NONAME ? HOST_NOT_FOUND : NO_RECOVERY)];
        return 0;
    }
    int family = AF_UNSPEC; NSString *canonical = name; NSMutableArray<NSData *> *addresses = [NSMutableArray array];
    for (struct addrinfo *item = results; item; item = item->ai_next) {
        if (item->ai_family != AF_INET && item->ai_family != AF_INET6) continue;
        if (family == AF_UNSPEC) family = item->ai_family;
        if (item->ai_family != family) continue;
        if (item->ai_canonname) canonical = [NSString stringWithUTF8String:item->ai_canonname] ?: canonical;
        const void *bytes = item->ai_family == AF_INET
            ? (const void *)&((struct sockaddr_in *)item->ai_addr)->sin_addr
            : (const void *)&((struct sockaddr_in6 *)item->ai_addr)->sin6_addr;
        NSData *address = [NSData dataWithBytes:bytes length:item->ai_family == AF_INET ? 4 : 16];
        if (![addresses containsObject:address]) [addresses addObject:address];
    }
    freeaddrinfo(results);
    if (!addresses.count) { [self setGuestHerrno:NO_DATA]; return 0; }
    return [self hostEntryWithName:canonical addresses:addresses family:family];
}

- (uint32_t)guestStringVector:(char *const *)strings allocations:(NSMutableArray<NSNumber *> *)allocations {
    NSUInteger count = 0;
    char *string = NULL;
    if (strings) {
        do {
            memcpy(&string, (const uint8_t *)strings + count * sizeof(string), sizeof(string));
            if (string) count++;
        } while (string && count < 4096);
    }
    if (!_registry.guestAllocator || count == 4096) return 0;
    uint32_t vector = _registry.guestAllocator((uint32_t)(count + 1) * 4, YES);
    if (!vector) return 0; [allocations addObject:@(vector)];
    for (NSUInteger i = 0; i < count; i++) {
        memcpy(&string, (const uint8_t *)strings + i * sizeof(string), sizeof(string));
        uint32_t guestString = [self copyCStringToGuest:string allocations:allocations];
        if (!guestString || ![_registry.memory writeUInt32:guestString
            address:vector + (uint32_t)i * 4]) return 0;
    }
    return vector;
}

- (void)freeLegacyAllocations:(NSArray<NSNumber *> *)allocations {
    for (NSNumber *allocation in allocations)
        if (_registry.guestDeallocator) _registry.guestDeallocator(allocation.unsignedIntValue);
}

- (uint32_t)guestServiceEntry:(struct servent *)entry {
    if (!entry || !_registry.guestAllocator) return 0;
    [self freeLegacyAllocations:_legacyServiceAllocations];
    self.legacyServiceAllocations = nil;
    NSMutableArray<NSNumber *> *allocations = [NSMutableArray array];
    uint32_t root = _registry.guestAllocator(16, YES);
    if (root) [allocations addObject:@(root)];
    uint32_t name = [self copyCStringToGuest:entry->s_name allocations:allocations];
    uint32_t aliases = [self guestStringVector:entry->s_aliases allocations:allocations];
    uint32_t protocol = [self copyCStringToGuest:entry->s_proto allocations:allocations];
    if (!root || !name || !aliases || !protocol ||
        ![_registry.memory writeUInt32:name address:root] ||
        ![_registry.memory writeUInt32:aliases address:root + 4] ||
        ![_registry.memory writeUInt32:ntohs((uint16_t)entry->s_port) address:root + 8] ||
        ![_registry.memory writeUInt32:protocol address:root + 12]) {
        [self freeLegacyAllocations:allocations]; return 0;
    }
    self.legacyServiceAllocations = allocations; return root;
}

- (uint32_t)guestProtocolEntry:(struct protoent *)entry {
    if (!entry || !_registry.guestAllocator) return 0;
    [self freeLegacyAllocations:_legacyProtocolAllocations];
    self.legacyProtocolAllocations = nil;
    NSMutableArray<NSNumber *> *allocations = [NSMutableArray array];
    uint32_t root = _registry.guestAllocator(12, YES);
    if (root) [allocations addObject:@(root)];
    uint32_t name = [self copyCStringToGuest:entry->p_name allocations:allocations];
    uint32_t aliases = [self guestStringVector:entry->p_aliases allocations:allocations];
    if (!root || !name || !aliases ||
        ![_registry.memory writeUInt32:name address:root] ||
        ![_registry.memory writeUInt32:aliases address:root + 4] ||
        ![_registry.memory writeUInt32:(uint32_t)entry->p_proto address:root + 8]) {
        [self freeLegacyAllocations:allocations]; return 0;
    }
    self.legacyProtocolAllocations = allocations; return root;
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    self.registry = registry;
    self.addressInfoAllocations = [NSMutableDictionary dictionary];
    self.errorStrings = [NSMutableDictionary dictionary];
    self.guestHerrnoAddress = registry.guestAllocator ? registry.guestAllocator(4, YES) : 0;
    if (!self.guestHerrnoAddress ||
        ![registry registerSymbol:@"_h_errno" atAddress:self.guestHerrnoAddress
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                (void)state;
                if (callError) *callError = [NSError errorWithDomain:BRPPCNetworkErrorDomain code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"h_errno is data, not callable code."}];
                return NO;
            } error:error]) return NO;
    __weak typeof(self) weakSelf = self;

    [registry registerSymbol:@"___h_errno" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NetworkFinish(state, weakSelf.guestHerrnoAddress); return YES;
    }];

    [registry registerSymbol:@"_socket" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int result = socket((int)state->gpr[3], (int)state->gpr[4], (int)state->gpr[5]);
        if (getenv("BISMUTH_NETWORK_TRACE"))
            fprintf(stderr, "network socket domain=%d type=%d protocol=%d result=%d errno=%d\n",
                    (int)state->gpr[3], (int)state->gpr[4], (int)state->gpr[5], result,
                    result < 0 ? errno : 0);
        if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_socketpair" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int sockets[2];
        if (socketpair((int)state->gpr[3], (int)state->gpr[4], (int)state->gpr[5], sockets) < 0)
            [weakSelf fail:state error:errno];
        else if (![weakSelf.registry.memory writeUInt32:(uint32_t)sockets[0] address:state->gpr[6]] ||
                 ![weakSelf.registry.memory writeUInt32:(uint32_t)sockets[1] address:state->gpr[6] + 4]) {
            close(sockets[0]); close(sockets[1]); [weakSelf fail:state error:EFAULT];
        } else NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_listen" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int result = listen((int)state->gpr[3], (int)state->gpr[4]);
        if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_shutdown" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int result = shutdown((int)state->gpr[3], (int)state->gpr[4]);
        if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_bind", @"_connect"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; struct sockaddr_storage address;
            if (![weakSelf readSocketAddress:&address address:state->gpr[4] length:(socklen_t)state->gpr[5]]) {
                [weakSelf fail:state error:EFAULT]; return YES;
            }
            int result = [symbol isEqualToString:@"_bind"]
                ? bind((int)state->gpr[3], (struct sockaddr *)&address, (socklen_t)state->gpr[5])
                : connect((int)state->gpr[3], (struct sockaddr *)&address, (socklen_t)state->gpr[5]);
            if (getenv("BISMUTH_NETWORK_TRACE"))
                fprintf(stderr, "network %s fd=%d family=%d length=%u result=%d errno=%d\n",
                        symbol.UTF8String, (int)state->gpr[3], address.ss_family,
                        state->gpr[5], result, result < 0 ? errno : 0);
            if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_accept", @"_getsockname", @"_getpeername"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; struct sockaddr_storage address; socklen_t length = sizeof(address); int result;
            if ([symbol isEqualToString:@"_accept"])
                result = accept((int)state->gpr[3], (struct sockaddr *)&address, &length);
            else if ([symbol isEqualToString:@"_getsockname"])
                result = getsockname((int)state->gpr[3], (struct sockaddr *)&address, &length);
            else result = getpeername((int)state->gpr[3], (struct sockaddr *)&address, &length);
            if (result < 0) [weakSelf fail:state error:errno];
            else if (![weakSelf writeSocketAddress:(struct sockaddr *)&address length:length
                                      guestAddress:state->gpr[4] guestLengthAddress:state->gpr[5]]) {
                if ([symbol isEqualToString:@"_accept"]) close(result);
                [weakSelf fail:state error:EFAULT];
            } else NetworkFinish(state, (uint32_t)result); return YES;
        }];
    }

    for (NSString *symbol in @[@"_send", @"_recv"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t length = state->gpr[5];
            if (length > (1u << 26)) { [weakSelf fail:state error:EOVERFLOW]; return YES; }
            NSMutableData *buffer = [NSMutableData dataWithLength:length]; ssize_t result;
            if ([symbol isEqualToString:@"_send"]) {
                if (length && ![weakSelf.registry.memory readBytes:buffer.mutableBytes address:state->gpr[4] length:length])
                    { [weakSelf fail:state error:EFAULT]; return YES; }
                result = send((int)state->gpr[3], buffer.bytes, length, (int)state->gpr[6]);
            } else {
                result = recv((int)state->gpr[3], buffer.mutableBytes, length, (int)state->gpr[6]);
                if (result >= 0 && result && ![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[4]
                                                                           length:(size_t)result])
                    { [weakSelf fail:state error:EFAULT]; return YES; }
            }
            if (getenv("BISMUTH_NETWORK_TRACE"))
            {
                fprintf(stderr, "network %s fd=%d requested=%u flags=%d result=%zd errno=%d",
                        symbol.UTF8String, (int)state->gpr[3], length, (int)state->gpr[6],
                        result, result < 0 ? errno : 0);
                if (result > 0 && result <= 256) {
                    const uint8_t *bytes = buffer.bytes;
                    fputs(" bytes=", stderr);
                    for (ssize_t i = 0; i < result; i++) fprintf(stderr, "%02x", bytes[i]);
                }
                fputc('\n', stderr);
            }
            if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, (uint32_t)result); return YES;
        }];
    }
    [registry registerSymbol:@"_sendto" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5]; struct sockaddr_storage address;
        if (length > (1u << 26) || ![weakSelf readSocketAddress:&address address:state->gpr[7]
                                                        length:(socklen_t)state->gpr[8]]) {
            [weakSelf fail:state error:length > (1u << 26) ? EOVERFLOW : EFAULT]; return YES;
        }
        NSMutableData *buffer = [NSMutableData dataWithLength:length];
        if (length && ![weakSelf.registry.memory readBytes:buffer.mutableBytes address:state->gpr[4] length:length])
            { [weakSelf fail:state error:EFAULT]; return YES; }
        ssize_t result = sendto((int)state->gpr[3], buffer.bytes, length, (int)state->gpr[6],
                                (struct sockaddr *)&address, (socklen_t)state->gpr[8]);
        if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_recvfrom" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5]; struct sockaddr_storage address;
        if (length > (1u << 26)) { [weakSelf fail:state error:EOVERFLOW]; return YES; }
        NSMutableData *buffer = [NSMutableData dataWithLength:length]; socklen_t addressLength = sizeof(address);
        ssize_t result = recvfrom((int)state->gpr[3], buffer.mutableBytes, length, (int)state->gpr[6],
                                  (struct sockaddr *)&address, &addressLength);
        if (result < 0) [weakSelf fail:state error:errno];
        else if ((result && ![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[4]
                                                               length:(size_t)result]) ||
                 ![weakSelf writeSocketAddress:(struct sockaddr *)&address length:addressLength
                                  guestAddress:state->gpr[7] guestLengthAddress:state->gpr[8]])
            [weakSelf fail:state error:EFAULT];
        else NetworkFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_sendmsg" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        BRPPCGuestMessage *record = [weakSelf messageAtAddress:state->gpr[4] sending:YES
                                                   errorNumber:&errorNumber];
        if (!record) { [weakSelf fail:state error:errorNumber]; return YES; }
        ssize_t result = sendmsg((int)state->gpr[3], &record->_message, (int)state->gpr[5]);
        if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, (uint32_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_recvmsg" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0; uint32_t messageAddress = state->gpr[4];
        uint32_t nameAddress = 0, controlAddress = 0;
        if (![registry.memory readUInt32:&nameAddress address:messageAddress] ||
            ![registry.memory readUInt32:&controlAddress address:messageAddress + 16]) {
            [weakSelf fail:state error:EFAULT]; return YES;
        }
        BRPPCGuestMessage *record = [weakSelf messageAtAddress:messageAddress sending:NO
                                                   errorNumber:&errorNumber];
        if (!record) { [weakSelf fail:state error:errorNumber]; return YES; }
        ssize_t result = recvmsg((int)state->gpr[3], &record->_message, (int)state->gpr[5]);
        if (result < 0) { [weakSelf fail:state error:errno]; return YES; }
        size_t remaining = (size_t)result;
        for (NSUInteger i = 0; i < record.buffers.count && remaining; i++) {
            NSUInteger length = MIN(remaining, record.guestBufferLengths[i].unsignedIntegerValue);
            if (![weakSelf.registry.memory writeBytes:record.buffers[i].bytes
                                              address:record.guestBufferAddresses[i].unsignedIntValue length:length]) {
                [weakSelf fail:state error:EFAULT]; return YES;
            }
            remaining -= length;
        }
        socklen_t copiedNameLength = MIN(record->_message.msg_namelen, (socklen_t)record.nameData.length);
        if (nameAddress && copiedNameLength &&
            ![weakSelf.registry.memory writeBytes:record.nameData.bytes address:nameAddress
                                           length:copiedNameLength]) {
            [weakSelf fail:state error:EFAULT]; return YES;
        }
        uint32_t copiedControlLength = (uint32_t)MIN(record->_message.msg_controllen, record.controlData.length);
        if (controlAddress && copiedControlLength) {
            NSMutableData *guestControl = [weakSelf guestControlFromHostBytes:record.controlData.bytes
                length:copiedControlLength];
            if (!guestControl || ![weakSelf.registry.memory writeBytes:guestControl.bytes address:controlAddress
                                                               length:guestControl.length]) {
                [weakSelf fail:state error:EFAULT]; return YES;
            }
        }
        if (![weakSelf.registry.memory writeUInt32:record->_message.msg_namelen address:messageAddress + 4] ||
            ![weakSelf.registry.memory writeUInt32:(uint32_t)record->_message.msg_controllen address:messageAddress + 20] ||
            ![weakSelf.registry.memory writeUInt32:(uint32_t)record->_message.msg_flags address:messageAddress + 24]) {
            [weakSelf fail:state error:EFAULT]; return YES;
        }
        NetworkFinish(state, (uint32_t)result); return YES;
    }];

    [registry registerSymbol:@"_setsockopt" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[7];
        if (length > (1u << 20)) { [weakSelf fail:state error:EOVERFLOW]; return YES; }
        NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![weakSelf.registry.memory readBytes:data.mutableBytes address:state->gpr[6] length:length])
            { [weakSelf fail:state error:EFAULT]; return YES; }
        int integer = 0; const void *value = data.bytes;
        if (length == 4) { uint32_t word = 0; [weakSelf.registry.memory readUInt32:&word address:state->gpr[6]]; integer = (int32_t)word; value = &integer; }
        int result = setsockopt((int)state->gpr[3], (int)state->gpr[4], (int)state->gpr[5], value, length);
        if (result < 0) [weakSelf fail:state error:errno]; else NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_getsockopt" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t capacity = 0;
        if (![weakSelf.registry.memory readUInt32:&capacity address:state->gpr[7]] || capacity > (1u << 20))
            { [weakSelf fail:state error:EFAULT]; return YES; }
        NSMutableData *data = [NSMutableData dataWithLength:capacity]; socklen_t length = capacity;
        int result = getsockopt((int)state->gpr[3], (int)state->gpr[4], (int)state->gpr[5], data.mutableBytes, &length);
        if (result < 0) [weakSelf fail:state error:errno];
        else if ((length == 4
                    ? ![weakSelf.registry.memory writeUInt32:*(uint32_t *)data.bytes address:state->gpr[6]]
                    : ![weakSelf.registry.memory writeBytes:data.bytes address:state->gpr[6] length:length]) ||
                 ![weakSelf.registry.memory writeUInt32:length address:state->gpr[7]])
            [weakSelf fail:state error:EFAULT];
        else NetworkFinish(state, 0); return YES;
    }];

    for (NSString *symbol in @[@"_htonl", @"_ntohl"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NetworkFinish(state, state->gpr[3]); return YES;
        }];
    }
    for (NSString *symbol in @[@"_htons", @"_ntohs"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NetworkFinish(state, state->gpr[3] & UINT16_MAX); return YES;
        }];
    }

    [registry registerSymbol:@"_select" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int count = (int)state->gpr[3]; fd_set readSet, writeSet, exceptSet;
        if (count < 0 || count > FD_SETSIZE ||
            ![weakSelf readGuestFDSet:&readSet address:state->gpr[4] count:count] ||
            ![weakSelf readGuestFDSet:&writeSet address:state->gpr[5] count:count] ||
            ![weakSelf readGuestFDSet:&exceptSet address:state->gpr[6] count:count])
            { [weakSelf fail:state error:EINVAL]; return YES; }
        struct timeval timeout, *timeoutPointer = NULL;
        if (state->gpr[7]) {
            uint32_t seconds = 0, microseconds = 0;
            if (![weakSelf.registry.memory readUInt32:&seconds address:state->gpr[7]] ||
                ![weakSelf.registry.memory readUInt32:&microseconds address:state->gpr[7] + 4])
                { [weakSelf fail:state error:EFAULT]; return YES; }
            timeout.tv_sec = (int32_t)seconds; timeout.tv_usec = (int32_t)microseconds; timeoutPointer = &timeout;
        }
        int result = select(count, state->gpr[4] ? &readSet : NULL, state->gpr[5] ? &writeSet : NULL,
                            state->gpr[6] ? &exceptSet : NULL, timeoutPointer);
        if (getenv("BISMUTH_NETWORK_TRACE"))
            fprintf(stderr, "network select count=%d timeout=%ld.%06d result=%d errno=%d\n",
                    count, timeoutPointer ? timeout.tv_sec : -1L,
                    timeoutPointer ? (int)timeout.tv_usec : 0, result, result < 0 ? errno : 0);
        if (result < 0) [weakSelf fail:state error:errno];
        else if (![weakSelf writeGuestFDSet:&readSet address:state->gpr[4] count:count] ||
                 ![weakSelf writeGuestFDSet:&writeSet address:state->gpr[5] count:count] ||
                 ![weakSelf writeGuestFDSet:&exceptSet address:state->gpr[6] count:count])
            [weakSelf fail:state error:EFAULT];
        else NetworkFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_poll" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[4];
        if (count > (1u << 20)) { [weakSelf fail:state error:EOVERFLOW]; return YES; }
        struct pollfd *descriptors = calloc(count ?: 1, sizeof(*descriptors));
        if (!descriptors) { [weakSelf fail:state error:ENOMEM]; return YES; }
        BOOL valid = YES;
        for (uint32_t i = 0; i < count; i++) {
            uint32_t descriptor = 0; uint8_t events[2];
            if (![weakSelf.registry.memory readUInt32:&descriptor address:state->gpr[3] + i * 8] ||
                ![weakSelf.registry.memory readBytes:events address:state->gpr[3] + i * 8 + 4 length:2]) { valid = NO; break; }
            descriptors[i].fd = (int32_t)descriptor; descriptors[i].events = (short)((uint16_t)events[0] << 8 | events[1]);
        }
        int result = valid ? poll(descriptors, count, (int32_t)state->gpr[5]) : -1;
        if (valid && result >= 0) for (uint32_t i = 0; i < count; i++) {
            uint8_t value[] = {(uint8_t)((uint16_t)descriptors[i].revents >> 8), (uint8_t)descriptors[i].revents};
            if (![weakSelf.registry.memory writeBytes:value address:state->gpr[3] + i * 8 + 6 length:2]) { valid = NO; break; }
        }
        free(descriptors);
        if (!valid) [weakSelf fail:state error:EFAULT]; else if (result < 0) [weakSelf fail:state error:errno];
        else NetworkFinish(state, (uint32_t)result); return YES;
    }];

    [registry registerSymbol:@"_inet_pton" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *text = [weakSelf stringAtAddress:state->gpr[4]];
        uint8_t bytes[16]; int result = text ? inet_pton((int)state->gpr[3], text.UTF8String, bytes) : -1;
        size_t length = state->gpr[3] == AF_INET ? 4 : state->gpr[3] == AF_INET6 ? 16 : 0;
        if (!text || (result == 1 && (!length || ![weakSelf.registry.memory writeBytes:bytes address:state->gpr[5] length:length])))
            [weakSelf fail:state error:EFAULT];
        else NetworkFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_inet_ntop" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; size_t sourceLength = state->gpr[3] == AF_INET ? 4 : state->gpr[3] == AF_INET6 ? 16 : 0;
        uint8_t source[16]; NSMutableData *destination = [NSMutableData dataWithLength:state->gpr[6]];
        if (!sourceLength || ![weakSelf.registry.memory readBytes:source address:state->gpr[4] length:sourceLength])
            { [weakSelf fail:state error:EFAULT]; return YES; }
        const char *result = inet_ntop((int)state->gpr[3], source, destination.mutableBytes,
                                       (socklen_t)destination.length);
        if (!result) [weakSelf fail:state error:errno];
        else if (![weakSelf.registry.memory writeBytes:destination.bytes address:state->gpr[5] length:strlen(result) + 1])
            [weakSelf fail:state error:EFAULT]; else NetworkFinish(state, state->gpr[5]); return YES;
    }];
    [registry registerSymbol:@"_inet_addr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *text = [weakSelf stringAtAddress:state->gpr[3]]; uint8_t bytes[4];
        if (!text || inet_pton(AF_INET, text.UTF8String, bytes) != 1) NetworkFinish(state, UINT32_MAX);
        else {
            NetworkFinish(state, (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 |
                                 (uint32_t)bytes[2] << 8 | bytes[3]);
        }
        return YES;
    }];
    [registry registerSymbol:@"_inet_ntoa" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t value = state->gpr[3]; uint8_t bytes[] = {value >> 24, value >> 16, value >> 8, value};
        char text[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, bytes, text, sizeof(text))) [weakSelf fail:state error:errno];
        else { uint32_t address = [weakSelf copyCStringToGuest:text allocations:nil];
               if (!address) [weakSelf fail:state error:ENOMEM]; else NetworkFinish(state, address); }
        return YES;
    }];

    [registry registerSymbol:@"_getaddrinfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *node = [weakSelf stringAtAddress:state->gpr[3]];
        NSString *service = [weakSelf stringAtAddress:state->gpr[4]];
        struct addrinfo hints, *hintsPointer = NULL, *results = NULL;
        memset(&hints, 0, sizeof(hints));
        if (state->gpr[5]) {
            uint32_t values[4];
            for (NSUInteger i = 0; i < 4; i++) if (![weakSelf.registry.memory readUInt32:&values[i]
                address:state->gpr[5] + (uint32_t)i * 4]) { [weakSelf fail:state error:EFAULT]; return YES; }
            hints.ai_flags = (int)values[0]; hints.ai_family = (int)values[1];
            hints.ai_socktype = (int)values[2]; hints.ai_protocol = (int)values[3]; hintsPointer = &hints;
        }
        int result = getaddrinfo(node.UTF8String, service.UTF8String, hintsPointer, &results);
        if (getenv("BISMUTH_NETWORK_TRACE"))
            fprintf(stderr, "network getaddrinfo node=%s service=%s result=%d\n",
                    node.UTF8String ?: "(null)", service.UTF8String ?: "(null)", result);
        if (result) { NetworkFinish(state, (uint32_t)result); return YES; }
        NSMutableArray<NSNumber *> *allocations = [NSMutableArray array]; uint32_t root = 0, previous = 0;
        for (struct addrinfo *item = results; item; item = item->ai_next) {
            uint32_t record = registry.guestAllocator ? registry.guestAllocator(32, YES) : 0;
            uint32_t socketAddress = item->ai_addrlen && registry.guestAllocator
                ? registry.guestAllocator((uint32_t)item->ai_addrlen, NO) : 0;
            uint32_t canonical = [weakSelf copyCStringToGuest:item->ai_canonname allocations:allocations];
            if (!record || (item->ai_addrlen && (!socketAddress ||
                ![registry.memory writeBytes:item->ai_addr address:socketAddress length:item->ai_addrlen]))) {
                result = EAI_MEMORY; break;
            }
            [allocations addObject:@(record)]; if (socketAddress) [allocations addObject:@(socketAddress)];
            BOOL wrote = [registry.memory writeUInt32:(uint32_t)item->ai_flags address:record] &&
                [registry.memory writeUInt32:(uint32_t)item->ai_family address:record + 4] &&
                [registry.memory writeUInt32:(uint32_t)item->ai_socktype address:record + 8] &&
                [registry.memory writeUInt32:(uint32_t)item->ai_protocol address:record + 12] &&
                [registry.memory writeUInt32:(uint32_t)item->ai_addrlen address:record + 16] &&
                [registry.memory writeUInt32:canonical address:record + 20] &&
                [registry.memory writeUInt32:socketAddress address:record + 24];
            if (!wrote) { result = EAI_MEMORY; break; }
            if (!root) root = record; if (previous) [registry.memory writeUInt32:record address:previous + 28];
            previous = record;
        }
        freeaddrinfo(results);
        if (result) {
            for (NSNumber *address in allocations) if (registry.guestDeallocator) registry.guestDeallocator(address.unsignedIntValue);
            NetworkFinish(state, (uint32_t)result); return YES;
        }
        weakSelf.addressInfoAllocations[@(root)] = allocations;
        if (![registry.memory writeUInt32:root address:state->gpr[6]]) { NetworkFinish(state, EAI_MEMORY); return YES; }
        NetworkFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_gethostbyname", @"_gethostbyname2"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *name = [weakSelf stringAtAddress:state->gpr[3]];
            int family = [symbol hasSuffix:@"2"] ? (int)state->gpr[4] : AF_INET;
            if (family != AF_INET && family != AF_INET6 && family != AF_UNSPEC) {
                [weakSelf setGuestHerrno:NO_RECOVERY]; NetworkFinish(state, 0); return YES;
            }
            NetworkFinish(state, [weakSelf resolveLegacyHostName:name family:family]); return YES;
        }];
    }
    [registry registerSymbol:@"_gethostbyaddr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[4]; int family = (int)state->gpr[5];
        if ((family != AF_INET || length != 4) && (family != AF_INET6 || length != 16)) {
            [weakSelf setGuestHerrno:NO_RECOVERY]; NetworkFinish(state, 0); return YES;
        }
        NSMutableData *addressData = [NSMutableData dataWithLength:length];
        if (![weakSelf.registry.memory readBytes:addressData.mutableBytes address:state->gpr[3] length:length]) {
            [weakSelf setGuestHerrno:NO_RECOVERY]; NetworkFinish(state, 0); return YES;
        }
        struct sockaddr_storage storage = {0}; socklen_t socketLength;
        if (family == AF_INET) {
            struct sockaddr_in *address = (struct sockaddr_in *)&storage;
            address->sin_len = sizeof(*address); address->sin_family = AF_INET;
            memcpy(&address->sin_addr, addressData.bytes, 4); socketLength = sizeof(*address);
        } else {
            struct sockaddr_in6 *address = (struct sockaddr_in6 *)&storage;
            address->sin6_len = sizeof(*address); address->sin6_family = AF_INET6;
            memcpy(&address->sin6_addr, addressData.bytes, 16); socketLength = sizeof(*address);
        }
        char name[NI_MAXHOST];
        int result = getnameinfo((struct sockaddr *)&storage, socketLength, name, sizeof(name), NULL, 0, NI_NAMEREQD);
        if (result) { [weakSelf setGuestHerrno:HOST_NOT_FOUND]; NetworkFinish(state, 0); return YES; }
        NetworkFinish(state, [weakSelf hostEntryWithName:[NSString stringWithUTF8String:name]
                                               addresses:@[addressData] family:family]); return YES;
    }];
    [registry registerSymbol:@"_hstrerror" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *key = @((int32_t)state->gpr[3]); uint32_t address = weakSelf.errorStrings[key].unsignedIntValue;
        if (!address) {
            address = [weakSelf copyCStringToGuest:hstrerror((int32_t)state->gpr[3]) allocations:nil];
            if (address) weakSelf.errorStrings[key] = @(address);
        }
        NetworkFinish(state, address); return YES;
    }];
    [registry registerSymbol:@"_getservbyname" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = [weakSelf stringAtAddress:state->gpr[3]];
        NSString *protocol = [weakSelf stringAtAddress:state->gpr[4]];
        struct servent *entry = name ? getservbyname(name.UTF8String, protocol.UTF8String) : NULL;
        NetworkFinish(state, [weakSelf guestServiceEntry:entry]); return YES;
    }];
    [registry registerSymbol:@"_getservbyport" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *protocol = [weakSelf stringAtAddress:state->gpr[4]];
        struct servent *entry = getservbyport(htons((uint16_t)state->gpr[3]), protocol.UTF8String);
        NetworkFinish(state, [weakSelf guestServiceEntry:entry]); return YES;
    }];
    [registry registerSymbol:@"_getservent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NetworkFinish(state, [weakSelf guestServiceEntry:getservent()]); return YES;
    }];
    [registry registerSymbol:@"_setservent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; setservent((int)state->gpr[3]); NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_endservent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; endservent(); NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_getprotobyname" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = [weakSelf stringAtAddress:state->gpr[3]];
        NetworkFinish(state, [weakSelf guestProtocolEntry:name ? getprotobyname(name.UTF8String) : NULL]); return YES;
    }];
    [registry registerSymbol:@"_getprotobynumber" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NetworkFinish(state, [weakSelf guestProtocolEntry:getprotobynumber((int)state->gpr[3])]); return YES;
    }];
    [registry registerSymbol:@"_getprotoent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NetworkFinish(state, [weakSelf guestProtocolEntry:getprotoent()]); return YES;
    }];
    [registry registerSymbol:@"_setprotoent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; setprotoent((int)state->gpr[3]); NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_endprotoent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; endprotoent(); NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_freeaddrinfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSArray<NSNumber *> *allocations = weakSelf.addressInfoAllocations[@(state->gpr[3])];
        for (NSNumber *address in allocations) if (registry.guestDeallocator) registry.guestDeallocator(address.unsignedIntValue);
        [weakSelf.addressInfoAllocations removeObjectForKey:@(state->gpr[3])]; NetworkFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_gai_strerror" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *key = @((int32_t)state->gpr[3]); uint32_t address = weakSelf.errorStrings[key].unsignedIntValue;
        if (!address) { address = [weakSelf copyCStringToGuest:gai_strerror((int32_t)state->gpr[3]) allocations:nil];
                        if (address) weakSelf.errorStrings[key] = @(address); }
        if (!address) [weakSelf fail:state error:ENOMEM]; else NetworkFinish(state, address); return YES;
    }];
    [registry registerSymbol:@"_getnameinfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; struct sockaddr_storage address;
        if (![weakSelf readSocketAddress:&address address:state->gpr[3] length:(socklen_t)state->gpr[4]])
            { NetworkFinish(state, EAI_FAIL); return YES; }
        NSMutableData *host = [NSMutableData dataWithLength:state->gpr[6] ?: 1];
        NSMutableData *service = [NSMutableData dataWithLength:state->gpr[8] ?: 1];
        int result = getnameinfo((struct sockaddr *)&address, (socklen_t)state->gpr[4],
            state->gpr[5] ? host.mutableBytes : NULL, state->gpr[6],
            state->gpr[7] ? service.mutableBytes : NULL, state->gpr[8], (int)state->gpr[9]);
        if (!result && ((state->gpr[5] && ![registry.memory writeBytes:host.bytes address:state->gpr[5]
                                                               length:strnlen(host.bytes, host.length) + 1]) ||
                        (state->gpr[7] && ![registry.memory writeBytes:service.bytes address:state->gpr[7]
                                                               length:strnlen(service.bytes, service.length) + 1])))
            result = EAI_FAIL;
        NetworkFinish(state, (uint32_t)result); return YES;
    }];
    return YES;
}

@end
