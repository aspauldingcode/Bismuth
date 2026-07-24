#import "BismuthScarlet.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import "BRPPCMachOLoader.h"
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>

static NSString * const BismuthScarletErrorDomain = @"theoderoy.Bismuth.Scarlet";
typedef uintptr_t (*ScarletWordCall)(uintptr_t, uintptr_t, uintptr_t, uintptr_t,
                                    uintptr_t, uintptr_t, uintptr_t, uintptr_t,
                                    uintptr_t, uintptr_t, uintptr_t, uintptr_t);

@interface BismuthScarlet ()
@property(nonatomic, weak) BRPPCResolveRegistry *registry;
@property(nonatomic, strong) NSMutableArray<NSValue *> *libraryHandles;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *keyManagerValues;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSRecursiveLock *> *criticalRegions;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *appleEventDescriptors;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *regionHandles;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *authorizationHandles;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *hiObjectClasses;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *hiObjects;
@property(nonatomic) uint32_t mainEventLoop, mainEventQueue, applicationEventTarget, dispatcherEventTarget;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *eventHandlers;
@property(nonatomic) uint32_t nextLegacyHandle;
@property(nonatomic) NSUInteger translatedSymbolCount;
@property(nonatomic) uint32_t nextDataAddress;
@end

@implementation BismuthScarlet

static const char *HostName(NSString *symbol) {
    const char *name = symbol.UTF8String;
    return name[0] == '_' ? name + 1 : name;
}

static NSStringEncoding ScarletTextEncoding(uint32_t type) {
    return type == 'TEXT' ? NSMacOSRomanStringEncoding :
        (type == 'utxt' ? NSUTF16BigEndianStringEncoding :
        (type == 'utf8' ? NSUTF8StringEncoding : 0));
}

static BOOL HostAddressIsExecutable(void *address) {
    if (!address) return NO;
    mach_vm_address_t region = (mach_vm_address_t)address;
    mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t result = mach_vm_region(mach_task_self(), &region, &size,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    return result == KERN_SUCCESS && (info.protection & VM_PROT_EXECUTE) != 0;
}

- (void)loadDeclaredDependencies {
    for (NSString *dependency in self.registry.image.dependencies) {
        void *handle = dlopen(dependency.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
        if (handle) [self.libraryHandles addObject:[NSValue valueWithPointer:handle]];
    }
}

- (void)initializeAllocatorCallbacks {
    for (NSString *symbol in self.registry.image.symbols) {
        NSString *allocator = nil;
        for (NSString *candidate in @[@"malloc", @"calloc", @"realloc", @"free"])
            if ([symbol hasSuffix:[@"_" stringByAppendingString:candidate]]) { allocator = candidate; break; }
        if (!allocator) continue;
        uint32_t address = self.registry.image.symbols[symbol].unsignedIntValue, current = 0;
        uint32_t target = [self.registry addressForSymbol:[@"_" stringByAppendingString:allocator]];
        if (target && [self.registry.memory readUInt32:&current address:address] && !current)
            [self.registry.memory writeUInt32:target address:address];
    }
}

- (void *)hostAddressForSymbol:(NSString *)symbol {
    const char *name = HostName(symbol);
    void *address = dlsym(RTLD_DEFAULT, name);
    for (NSValue *handle in self.libraryHandles)
        if (!address) address = dlsym(handle.pointerValue, name);
    return address;
}

- (uint32_t)shadowDataSymbol:(NSString *)symbol hostAddress:(void *)hostAddress
                       error:(NSError **)error {
    if (!_nextDataAddress) {
        _nextDataAddress = BRPPCGuestScarletDataBase;
        if (![self.registry.memory mapAddress:_nextDataAddress size:BRPPCGuestScarletDataSize
                  protection:BRPPCMemoryRead | BRPPCMemoryWrite
                        name:@"BismuthScarlet data" error:error]) return 0;
    }
    uint32_t address = _nextDataAddress;
    _nextDataAddress += 16;
    uint32_t value = 0;
    void *nativeValue = NULL;
    if (hostAddress) memcpy(&nativeValue, hostAddress, sizeof(nativeValue));
    if (HostAddressIsExecutable(nativeValue)) {
        Dl_info info = {0};
        if (dladdr(nativeValue, &info) && info.dli_sname) {
            NSString *target = [NSString stringWithUTF8String:info.dli_sname];
            if (![target hasPrefix:@"_"]) target = [@"_" stringByAppendingString:target];
            value = [self.registry addressForSymbol:target];
        }
    }
    if (!value) for (NSString *allocator in @[@"malloc", @"calloc", @"realloc", @"free"])
        if ([symbol hasSuffix:[@"_" stringByAppendingString:allocator]]) {
            value = [self.registry addressForSymbol:[@"_" stringByAppendingString:allocator]];
            break;
        }
    if (![self.registry.memory writeUInt32:value address:address]) return 0;
    if (![self.registry registerSymbol:symbol atAddress:address
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)state;
            if (callError) *callError = [NSError errorWithDomain:BismuthScarletErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"%@ is data, not callable code.", symbol]}];
            return NO;
        } error:error]) return 0;
    self.translatedSymbolCount++;
    return address;
}

- (uint32_t)translateKeyManagerSymbol:(NSString *)symbol error:(NSError **)error {
    if ([symbol isEqualToString:@"___keymgr_global"]) {
        uint32_t global = [self shadowDataSymbol:symbol hostAddress:NULL error:error];
        uint32_t info = [self shadowDataSymbol:@"__keymgr_info" hostAddress:NULL error:error];
        return [self.registry.memory writeUInt32:info address:global + 8] &&
               [self.registry.memory writeUInt32:8 address:info] &&
               [self.registry.memory writeUInt32:4u << 16 address:info + 4] ? global : 0;
    }
    if (![symbol hasPrefix:@"__keymgr_"]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError;
        NSNumber *key = @(state->gpr[3]);
        if ([symbol isEqualToString:@"__keymgr_get_and_lock_processwide_ptr"])
            state->gpr[3] = self.keyManagerValues[key].unsignedIntValue;
        else if ([symbol isEqualToString:@"__keymgr_get_and_lock_processwide_ptr_2"]) {
            if (state->gpr[4] && ![self.registry.memory writeUInt32:self.keyManagerValues[key].unsignedIntValue
                                                               address:state->gpr[4]]) return NO;
            state->gpr[3] = 0;
        } else if ([symbol isEqualToString:@"__keymgr_set_and_unlock_processwide_ptr"]) {
            self.keyManagerValues[key] = @(state->gpr[4]);
            state->gpr[3] = 0;
        }
        else if (![symbol isEqualToString:@"__keymgr_unlock_processwide_ptr"] &&
                 ![symbol isEqualToString:@"___keymgr_dwarf2_register_sections"]) return NO;
        state->pc = state->lr;
        return YES;
    }];
}

- (uint32_t)translateMultiprocessingSymbol:(NSString *)symbol {
    NSSet *criticalSymbols = [NSSet setWithArray:@[@"_MPCreateCriticalRegion",
        @"_MPDeleteCriticalRegion", @"_MPEnterCriticalRegion", @"_MPExitCriticalRegion",
        @"_GetCurrentThread"]];
    if (![criticalSymbols containsObject:symbol]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; NSNumber *key = @(state->gpr[3]); int32_t status = 0;
        if ([symbol isEqualToString:@"_GetCurrentThread"]) {
            state->gpr[3] = 1; state->pc = state->lr; return YES;
        } else if ([symbol isEqualToString:@"_MPCreateCriticalRegion"]) {
            uint32_t handle = ++self.nextLegacyHandle;
            self.criticalRegions[@(handle)] = [NSRecursiveLock new];
            if (!state->gpr[3] || ![self.registry.memory writeUInt32:handle address:state->gpr[3]])
                status = -50;
        } else if ([symbol isEqualToString:@"_MPDeleteCriticalRegion"])
            self.criticalRegions[key] ? [self.criticalRegions removeObjectForKey:key] : (status = -50);
        else if ([symbol isEqualToString:@"_MPEnterCriticalRegion"])
            self.criticalRegions[key] ? [self.criticalRegions[key] lock] : (status = -50);
        else if (self.criticalRegions[key]) [self.criticalRegions[key] unlock]; else status = -50;
        (void)callError; state->gpr[3] = (uint32_t)status; state->pc = state->lr; return YES;
    }];
}

- (BOOL)writeAppleEventType:(uint32_t)type data:(NSData *)data address:(uint32_t)address {
    uint32_t handle = ++self.nextLegacyHandle;
    self.appleEventDescriptors[@(handle)] = @{@"type": @(type), @"data": data ?: NSData.data};
    return [self.registry.memory writeUInt32:type address:address] &&
           [self.registry.memory writeUInt32:handle address:address + 4];
}

- (uint32_t)translateAppleEventSymbol:(NSString *)symbol {
    NSSet *symbols = [NSSet setWithArray:@[@"_AECreateList", @"_AECreateDesc", @"_AECoerceDesc", @"_AEDisposeDesc",
        @"_AEDuplicateDesc", @"_AEGetDescData", @"_AEGetDescDataSize", @"_AEReplaceDescData",
        @"_AEPutParamPtr", @"_AEPutParamDesc", @"_AECountItems", @"_AEGetParamPtr",
        @"_AEGetParamDesc", @"_AEGetNthPtr", @"_AEGetNthDesc"]];
    if (![symbols containsObject:symbol]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError; int32_t status = 0; uint32_t type = 0, handle = 0;
        if ([symbol isEqualToString:@"_AECoerceDesc"]) {
            uint32_t sourceHandle = 0;
            if (![self.registry.memory readUInt32:&sourceHandle address:state->gpr[3] + 4]) return NO;
            NSDictionary *source = self.appleEventDescriptors[@(sourceHandle)]; NSData *sourceData = source[@"data"];
            uint32_t sourceType = [source[@"type"] unsignedIntValue], destinationType = state->gpr[4];
            NSData *result = sourceType == destinationType ? sourceData : nil;
            NSStringEncoding from = ScarletTextEncoding(sourceType), to = ScarletTextEncoding(destinationType);
            if (!result && sourceData && from && to)
                result = [[[NSString alloc] initWithData:sourceData encoding:from] dataUsingEncoding:to];
            if (!source || !result) status = -1700;
            else if (![self writeAppleEventType:destinationType data:result address:state->gpr[5]]) return NO;
        } else if ([symbol hasPrefix:@"_AEPutParam"]) {
            uint32_t container = 0;
            if (![self.registry.memory readUInt32:&container address:state->gpr[3] + 4]) return NO;
            NSMutableDictionary *record = [self.appleEventDescriptors[@(container)] mutableCopy];
            NSMutableDictionary *params = [record[@"params"] mutableCopy] ?: [NSMutableDictionary dictionary];
            if ([symbol isEqualToString:@"_AEPutParamPtr"]) {
                NSMutableData *bytes = [NSMutableData dataWithLength:state->gpr[7]];
                if (bytes.length && ![self.registry.memory readBytes:bytes.mutableBytes address:state->gpr[6] length:bytes.length]) return NO;
                params[@(state->gpr[4])] = @{@"type": @(state->gpr[5]), @"data": bytes};
            } else {
                uint32_t type = 0, handle = 0;
                if (![self.registry.memory readUInt32:&type address:state->gpr[5]] ||
                    ![self.registry.memory readUInt32:&handle address:state->gpr[5] + 4]) return NO;
                params[@(state->gpr[4])] = self.appleEventDescriptors[@(handle)] ?: @{@"type": @(type), @"data": NSData.data};
            }
            record[@"params"] = params; self.appleEventDescriptors[@(container)] = record;
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        } else if ([symbol isEqualToString:@"_AECountItems"]) {
            if (!state->gpr[4] || ![self.registry.memory writeUInt32:0 address:state->gpr[4]]) return NO;
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        } else if ([symbol hasPrefix:@"_AEGetParam"]) {
            uint32_t container = 0;
            if (![self.registry.memory readUInt32:&container address:state->gpr[3] + 4]) return NO;
            NSDictionary *param = self.appleEventDescriptors[@(container)][@"params"][@(state->gpr[4])];
            if (!param) {
                state->gpr[3] = (uint32_t)(int32_t)-1701; state->pc = state->lr; return YES;
            }
            uint32_t actualType = [param[@"type"] unsignedIntValue]; NSData *bytes = param[@"data"] ?: NSData.data;
            if ([symbol isEqualToString:@"_AEGetParamPtr"]) {
                uint32_t count = (uint32_t)MIN(bytes.length, state->gpr[8]);
                if ((state->gpr[6] && ![self.registry.memory writeUInt32:actualType address:state->gpr[6]]) ||
                    (count && ![self.registry.memory writeBytes:bytes.bytes address:state->gpr[7] length:count]) ||
                    (state->gpr[9] && ![self.registry.memory writeUInt32:(uint32_t)bytes.length address:state->gpr[9]])) return NO;
            } else if (!state->gpr[6] || ![self writeAppleEventType:actualType data:bytes address:state->gpr[6]]) return NO;
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        } else if ([symbol hasPrefix:@"_AEGetNth"]) {
            state->gpr[3] = (uint32_t)(int32_t)-1701; state->pc = state->lr; return YES;
        } else if ([symbol isEqualToString:@"_AECreateList"] || [symbol isEqualToString:@"_AECreateDesc"]) {
            uint32_t dataAddress = state->gpr[3], size = state->gpr[4], output = state->gpr[6];
            type = [symbol isEqualToString:@"_AECreateList"] ? (state->gpr[5] ? 'reco' : 'list') : state->gpr[3];
            if ([symbol isEqualToString:@"_AECreateDesc"]) {
                dataAddress = state->gpr[4];
                size = state->gpr[5];
                output = state->gpr[6];
            }
            NSMutableData *data = [NSMutableData dataWithLength:size];
            if ((size && ![self.registry.memory readBytes:data.mutableBytes address:dataAddress length:size]) ||
                !output || ![self writeAppleEventType:type data:data address:output]) return NO;
        } else {
            BOOL replace = [symbol isEqualToString:@"_AEReplaceDescData"];
            uint32_t descriptor = replace ? state->gpr[6] : state->gpr[3];
            if (![self.registry.memory readUInt32:&type address:descriptor] ||
                ![self.registry.memory readUInt32:&handle address:descriptor + 4]) return NO;
            NSDictionary *record = self.appleEventDescriptors[@(handle)]; NSData *data = record[@"data"];
            if ([symbol isEqualToString:@"_AEDisposeDesc"]) {
                [self.appleEventDescriptors removeObjectForKey:@(handle)];
                if (![self.registry.memory writeUInt32:0 address:descriptor] ||
                    ![self.registry.memory writeUInt32:0 address:descriptor + 4]) return NO;
            } else if ([symbol isEqualToString:@"_AEDuplicateDesc"])
                { if (!record || ![self writeAppleEventType:type data:data address:state->gpr[4]]) status = -50; }
            else if ([symbol isEqualToString:@"_AEGetDescDataSize"]) state->gpr[3] = (uint32_t)data.length;
            else if ([symbol isEqualToString:@"_AEGetDescData"]) {
                if (!record || state->gpr[5] < data.length ||
                    ![self.registry.memory writeBytes:data.bytes address:state->gpr[4] length:data.length]) status = -50;
            } else {
                NSMutableData *replacement = [NSMutableData dataWithLength:state->gpr[5]];
                if ((state->gpr[5] && ![self.registry.memory readBytes:replacement.mutableBytes
                    address:state->gpr[4] length:state->gpr[5]]) ||
                    ![self writeAppleEventType:state->gpr[3] data:replacement address:descriptor]) return NO;
                [self.appleEventDescriptors removeObjectForKey:@(handle)];
            }
        }
        if (![symbol isEqualToString:@"_AEGetDescDataSize"]) state->gpr[3] = (uint32_t)status;
        state->pc = state->lr; return YES;
    }];
}

- (BOOL)readRegion:(uint32_t)handle bounds:(int16_t[4])bounds {
    uint32_t data = 0; uint8_t bytes[8];
    if (![self.registry.memory readUInt32:&data address:handle] ||
        ![self.registry.memory readBytes:bytes address:data + 2 length:8]) return NO;
    for (NSUInteger i = 0; i < 4; i++) bounds[i] = (int16_t)((uint16_t)bytes[2*i] << 8 | bytes[2*i+1]);
    return YES;
}

- (BOOL)writeRegion:(uint32_t)handle bounds:(const int16_t[4])bounds {
    uint32_t data = 0; uint8_t bytes[10] = {0, 10};
    if (![self.registry.memory readUInt32:&data address:handle]) return NO;
    for (NSUInteger i = 0; i < 4; i++) {
        bytes[2+2*i] = (uint16_t)bounds[i] >> 8;
        bytes[3+2*i] = (uint8_t)bounds[i];
    }
    return [self.registry.memory writeBytes:bytes address:data length:sizeof(bytes)];
}

- (uint32_t)translateRegionSymbol:(NSString *)symbol {
    NSSet *symbols = [NSSet setWithArray:@[@"_NewRgn", @"_DisposeRgn", @"_SetEmptyRgn", @"_EmptyRgn",
        @"_RectRgn", @"_SetRectRgn", @"_GetRegionBounds", @"_CopyRgn", @"_EqualRgn"]];
    if (![symbols containsObject:symbol]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError; int16_t bounds[4] = {0}, other[4] = {0};
        if ([symbol isEqualToString:@"_NewRgn"]) {
            uint32_t data = self.registry.guestAllocator ? self.registry.guestAllocator(10, YES) : 0;
            uint32_t handle = data && self.registry.guestAllocator ? self.registry.guestAllocator(4, YES) : 0;
            if (!handle || ![self.registry.memory writeUInt32:data address:handle] ||
                ![self writeRegion:handle bounds:bounds]) return NO;
            [self.regionHandles addObject:@(handle)]; state->gpr[3] = handle;
        } else if ([symbol isEqualToString:@"_DisposeRgn"]) {
            uint32_t data = 0; [self.registry.memory readUInt32:&data address:state->gpr[3]];
            if (data && self.registry.guestDeallocator) self.registry.guestDeallocator(data);
            if (self.registry.guestDeallocator) self.registry.guestDeallocator(state->gpr[3]);
            [self.regionHandles removeObject:@(state->gpr[3])]; state->gpr[3] = 0;
        } else if ([symbol isEqualToString:@"_SetEmptyRgn"]) {
            if (![self writeRegion:state->gpr[3] bounds:bounds]) return NO;
        } else if ([symbol isEqualToString:@"_EmptyRgn"]) {
            if (![self readRegion:state->gpr[3] bounds:bounds]) return NO;
            state->gpr[3] = bounds[0] >= bounds[2] || bounds[1] >= bounds[3];
        } else if ([symbol isEqualToString:@"_SetRectRgn"]) {
            bounds[0] = state->gpr[5]; bounds[1] = state->gpr[4];
            bounds[2] = state->gpr[7]; bounds[3] = state->gpr[6];
            if (![self writeRegion:state->gpr[3] bounds:bounds]) return NO;
        } else if ([symbol isEqualToString:@"_RectRgn"]) {
            uint8_t bytes[8];
            if (![self.registry.memory readBytes:bytes address:state->gpr[4] length:8]) return NO;
            for (NSUInteger i = 0; i < 4; i++) bounds[i] = (int16_t)((uint16_t)bytes[2*i] << 8 | bytes[2*i+1]);
            if (![self writeRegion:state->gpr[3] bounds:bounds]) return NO;
        } else if ([symbol isEqualToString:@"_GetRegionBounds"]) {
            uint32_t data = 0;
            if (![self.registry.memory readUInt32:&data address:state->gpr[3]]) return NO;
            uint8_t bytes[8]; if (![self.registry.memory readBytes:bytes address:data + 2 length:8] ||
                ![self.registry.memory writeBytes:bytes address:state->gpr[4] length:8]) return NO;
            state->gpr[3] = state->gpr[4];
        } else {
            if (![self readRegion:state->gpr[3] bounds:bounds] ||
                ![self readRegion:state->gpr[4] bounds:other]) return NO;
            if ([symbol isEqualToString:@"_CopyRgn"]) {
                if (![self writeRegion:state->gpr[4] bounds:bounds]) return NO;
            } else state->gpr[3] = memcmp(bounds, other, sizeof(bounds)) == 0;
        }
        state->pc = state->lr; return YES;
    }];
}

- (uint32_t)translateAtomicSymbol:(NSString *)symbol {
    if (![@[@"_OSSpinLockLock", @"_OSSpinLockUnlock", @"_OSSpinLockTry",
            @"_OSAtomicCompareAndSwap32"] containsObject:symbol]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError; uint32_t value = 0;
        if ([symbol isEqualToString:@"_OSAtomicCompareAndSwap32"]) {
            if (![self.registry.memory readUInt32:&value address:state->gpr[5]]) return NO;
            BOOL swap = value == state->gpr[3];
            if (swap && ![self.registry.memory writeUInt32:state->gpr[4] address:state->gpr[5]]) return NO;
            state->gpr[3] = swap;
        } else {
            uint32_t address = state->gpr[3];
            if (![self.registry.memory readUInt32:&value address:address]) return NO;
            BOOL attempt = [symbol isEqualToString:@"_OSSpinLockTry"];
            BOOL acquired = !value;
            if (![self.registry.memory writeUInt32:
                [symbol isEqualToString:@"_OSSpinLockUnlock"] ? 0 : 1 address:address]) return NO;
            if (attempt) state->gpr[3] = acquired;
        }
        state->pc = state->lr; return YES;
    }];
}

- (uint32_t)translateAuthorizationSymbol:(NSString *)symbol {
    if (![symbol hasPrefix:@"_Authorization"]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError; int32_t status = 0;
        if ([symbol isEqualToString:@"_AuthorizationCreate"] ||
            [symbol isEqualToString:@"_AuthorizationCreateFromExternalForm"]) {
            uint32_t output = [symbol hasSuffix:@"ExternalForm"] ? state->gpr[4] : state->gpr[6];
            uint32_t handle = ++self.nextLegacyHandle; [self.authorizationHandles addObject:@(handle)];
            if (!output || ![self.registry.memory writeUInt32:handle address:output]) return NO;
        } else if ([symbol isEqualToString:@"_AuthorizationFree"]) {
            if (![self.authorizationHandles containsObject:@(state->gpr[3])]) status = -60002;
            [self.authorizationHandles removeObject:@(state->gpr[3])];
        } else if ([symbol isEqualToString:@"_AuthorizationMakeExternalForm"]) {
            uint8_t form[32] = {0}; uint32_t handle = state->gpr[3];
            form[0] = handle >> 24; form[1] = handle >> 16; form[2] = handle >> 8; form[3] = handle;
            if (!state->gpr[4] || ![self.registry.memory writeBytes:form address:state->gpr[4] length:sizeof(form)]) return NO;
        } else {
            uint32_t output = [symbol isEqualToString:@"_AuthorizationCopyRights"] ? state->gpr[7] :
                              [symbol isEqualToString:@"_AuthorizationRightGet"] ? state->gpr[4] : 0;
            if (output && ![self.registry.memory writeUInt32:0 address:output]) return NO;
            status = -60005;
        }
        state->gpr[3] = (uint32_t)status; state->pc = state->lr; return YES;
    }];
}

- (uint32_t)translateHIObjectSymbol:(NSString *)symbol {
    if (![symbol hasPrefix:@"_HIObject"]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError; int32_t status = 0;
        if ([symbol isEqualToString:@"_HIObjectRegisterSubclass"]) {
            uint32_t handle = ++self.nextLegacyHandle;
            self.hiObjectClasses[@(handle)] = @{@"class": @(state->gpr[3]), @"base": @(state->gpr[4]),
                @"callback": @(state->gpr[6]), @"events": @(state->gpr[8]), @"context": @(state->gpr[9])};
            if (state->gpr[10] && ![self.registry.memory writeUInt32:handle address:state->gpr[10]]) return NO;
        } else if ([symbol isEqualToString:@"_HIObjectCreate"]) {
            uint32_t handle = ++self.nextLegacyHandle; [self.hiObjects addObject:@(handle)];
            if (!state->gpr[5] || ![self.registry.memory writeUInt32:handle address:state->gpr[5]]) return NO;
        } else if ([symbol isEqualToString:@"_HIObjectDynamicCast"])
            state->gpr[3] = [self.hiObjects containsObject:@(state->gpr[3])] ? state->gpr[3] : 0;
        else if ([symbol isEqualToString:@"_HIObjectGetEventTarget"]) state->gpr[3] = 0;
        else if (![symbol isEqualToString:@"_HIObjectPrintDebugInfo"]) status = -50;
        if (![symbol isEqualToString:@"_HIObjectDynamicCast"] &&
            ![symbol isEqualToString:@"_HIObjectGetEventTarget"]) state->gpr[3] = (uint32_t)status;
        state->pc = state->lr; return YES;
    }];
}

- (uint32_t)translateEventSymbol:(NSString *)symbol {
    NSSet *symbols = [NSSet setWithArray:@[@"_GetMainEventLoop", @"_GetMainEventQueue", @"_GetApplicationEventTarget",
        @"_GetEventDispatcherTarget", @"_InstallEventHandler", @"_RemoveEventHandler",
        @"_RemoveEventTypesFromHandler"]];
    if (![symbols containsObject:symbol]) return 0;
    __weak typeof(self) weakSelf = self;
    return [self.registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
        BismuthScarlet *self = weakSelf; (void)callError;
        if ([symbol isEqualToString:@"_InstallEventHandler"]) {
            uint32_t handle = ++self.nextLegacyHandle; NSMutableData *events =
                [NSMutableData dataWithLength:(NSUInteger)state->gpr[5] * 8];
            if (events.length && ![self.registry.memory readBytes:events.mutableBytes
                address:state->gpr[6] length:events.length]) return NO;
            self.eventHandlers[@(handle)] = @{@"target": @(state->gpr[3]), @"callback": @(state->gpr[4]),
                @"events": events, @"context": @(state->gpr[7])};
            if (state->gpr[8] && ![self.registry.memory writeUInt32:handle address:state->gpr[8]]) return NO;
            state->gpr[3] = 0;
        } else if ([symbol isEqualToString:@"_RemoveEventHandler"]) {
            [self.eventHandlers removeObjectForKey:@(state->gpr[3])]; state->gpr[3] = 0;
        } else if ([symbol isEqualToString:@"_RemoveEventTypesFromHandler"]) state->gpr[3] = 0;
        else state->gpr[3] = [symbol isEqualToString:@"_GetMainEventLoop"] ? self.mainEventLoop :
            ([symbol isEqualToString:@"_GetMainEventQueue"] ? self.mainEventQueue :
            ([symbol isEqualToString:@"_GetApplicationEventTarget"] ? self.applicationEventTarget :
             self.dispatcherEventTarget));
        state->pc = state->lr; return YES;
    }];
}

- (uint32_t)translateSymbol:(NSString *)symbol lazy:(BOOL)lazy error:(NSError **)error {
    uint32_t keyManager = [self translateKeyManagerSymbol:symbol error:error];
    if (keyManager) return keyManager;
    uint32_t multiprocessing = [self translateMultiprocessingSymbol:symbol];
    if (multiprocessing) return multiprocessing;
    uint32_t appleEvent = [self translateAppleEventSymbol:symbol];
    if (appleEvent) return appleEvent;
    uint32_t region = [self translateRegionSymbol:symbol];
    if (region) return region;
    uint32_t atomic = [self translateAtomicSymbol:symbol];
    if (atomic) return atomic;
    uint32_t authorization = [self translateAuthorizationSymbol:symbol];
    if (authorization) return authorization;
    uint32_t hiObject = [self translateHIObjectSymbol:symbol];
    if (hiObject) return hiObject;
    uint32_t event = [self translateEventSymbol:symbol];
    if (event) return event;
    void *hostAddress = [self hostAddressForSymbol:symbol];
    if (!lazy && (!hostAddress || !HostAddressIsExecutable(hostAddress))) {
        return [self shadowDataSymbol:symbol hostAddress:hostAddress error:error];
    }

    __weak typeof(self) weakSelf = self;
    uint32_t address = [self.registry registerSymbol:symbol
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            BismuthScarlet *self = weakSelf;
            if (!self) return NO;
            if (!hostAddress) {
                (void)callError;
                state->gpr[3] = 0;
                state->pc = state->lr;
                return YES;
            }
            if (getenv("BISMUTH_SCARLET_TRACE"))
                fprintf(stderr, "scarlet call symbol=%s lr=%08x r3=%08x r4=%08x r5=%08x r6=%08x\n",
                    symbol.UTF8String, state->lr, state->gpr[3], state->gpr[4], state->gpr[5], state->gpr[6]);
            ScarletWordCall call = (ScarletWordCall)hostAddress;
            uint32_t spill[4] = {0};
            for (uint32_t i = 0; i < 4; i++)
                [self.registry.memory readUInt32:&spill[i] address:state->gpr[1] + 56 + i * 4];
            uintptr_t result = call(state->gpr[3], state->gpr[4], state->gpr[5], state->gpr[6],
                                    state->gpr[7], state->gpr[8], state->gpr[9], state->gpr[10],
                                    spill[0], spill[1], spill[2], spill[3]);
            if (result > UINT32_MAX) {
                if (callError) *callError = [NSError errorWithDomain:BismuthScarletErrorDomain code:2
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:
                            @"%@ returned a host pointer requiring a typed Resolve.", symbol]}];
                return NO;
            }
            state->gpr[3] = (uint32_t)result;
            state->pc = state->lr;
            return YES;
        }];
    self.translatedSymbolCount++;
    return address;
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    self.registry = registry;
    self.libraryHandles = [NSMutableArray array];
    self.keyManagerValues = [NSMutableDictionary dictionary];
    self.criticalRegions = [NSMutableDictionary dictionary];
    self.appleEventDescriptors = [NSMutableDictionary dictionary];
    self.regionHandles = [NSMutableSet set];
    self.authorizationHandles = [NSMutableSet set];
    self.hiObjectClasses = [NSMutableDictionary dictionary];
    self.hiObjects = [NSMutableSet set];
    self.nextLegacyHandle = 0xb1000000;
    self.mainEventLoop = ++self.nextLegacyHandle;
    self.mainEventQueue = ++self.nextLegacyHandle;
    self.applicationEventTarget = ++self.nextLegacyHandle;
    self.dispatcherEventTarget = ++self.nextLegacyHandle;
    self.eventHandlers = [NSMutableDictionary dictionary];
    [self loadDeclaredDependencies];
    [self initializeAllocatorCallbacks];
    __weak typeof(self) weakSelf = self;
    registry.missingSymbolResolver = ^uint32_t(NSString *symbol, BOOL lazy, NSError **resolveError) {
        return [weakSelf translateSymbol:symbol lazy:lazy error:resolveError];
    };
    return YES;
}

- (void)dealloc {
    for (NSValue *value in _libraryHandles) dlclose(value.pointerValue);
}
@end
