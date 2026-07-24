#import "BRPPCCoreServicesResolve.h"
#import "BRPPCAddressSpace.h"
#import <CoreServices/CoreServices.h>
#import <dlfcn.h>
#include <time.h>

static const uint32_t BRPPCGuestSystemVersion = 0x1068;
static const uint32_t BRPPCGuestSystemVersionMajor = 10;
static const uint32_t BRPPCGuestSystemVersionMinor = 6;
static const uint32_t BRPPCGuestSystemVersionBugFix = 8;
static const uint32_t BRPPCGuestQuickTimeVersion = 0x07668000u;
static const uint32_t BRPPCGuestComponentVersion = 0x01000000u;
static const uint32_t BRPPCGestaltSystemVersionSelector = 'sysv';
static const uint32_t BRPPCGestaltSystemVersionMajorSelector = 'sys1';
static const uint32_t BRPPCGestaltSystemVersionMinorSelector = 'sys2';
static const uint32_t BRPPCGestaltSystemVersionBugFixSelector = 'sys3';
static const uint32_t BRPPCGestaltQuickTimeVersionSelector = 'qtim';
static const uint32_t BRPPCGestaltTSMVersionSelector = 'tsmv';

static void BRPPCFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

@class BRCSComponent;

@interface BRPPCCoreServicesResolve ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *handleSizes;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *referencePaths;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSFileHandle *> *openForks;
@property(nonatomic, strong) NSMutableArray<BRCSComponent *> *components;
@property(nonatomic) uint32_t nextReferenceToken;
@property(nonatomic) uint16_t nextForkNumber;
@property(nonatomic) int32_t memoryError;
@end

static NSString *BRCSGuestPath(BRPPCResolveRegistry *registry, uint32_t address) {
    if (!address) return nil;
    NSMutableData *bytes = [NSMutableData data];
    for (NSUInteger i = 0; i < PATH_MAX; i++) {
        uint8_t byte = 0;
        if (![registry.memory readBytes:&byte address:address + (uint32_t)i length:1]) return nil;
        if (!byte) break;
        [bytes appendBytes:&byte length:1];
    }
    return [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
}

static BOOL BRCSWriteUInt16(BRPPCResolveRegistry *registry, uint32_t address, uint16_t value) {
    uint8_t bytes[] = {(uint8_t)(value >> 8), (uint8_t)value};
    return [registry.memory writeBytes:bytes address:address length:2];
}

static BOOL BRCSWriteHFSName(BRPPCResolveRegistry *registry, uint32_t address, NSString *name) {
    if (!address || name.length > 255 || !BRCSWriteUInt16(registry, address, (uint16_t)name.length)) return NO;
    for (NSUInteger i = 0; i < name.length; i++)
        if (!BRCSWriteUInt16(registry, address + 2 + (uint32_t)i * 2, [name characterAtIndex:i])) return NO;
    return YES;
}

static NSString *BRCSReadHFSName(BRPPCResolveRegistry *registry, uint32_t address) {
    uint8_t countBytes[2];
    if (!address || ![registry.memory readBytes:countBytes address:address length:2]) return nil;
    uint16_t count = (uint16_t)countBytes[0] << 8 | countBytes[1];
    NSMutableString *name = [NSMutableString stringWithCapacity:count];
    for (uint16_t i = 0; i < count; i++) {
        uint8_t bytes[2];
        if (![registry.memory readBytes:bytes address:address + 2 + 2 * i length:2]) return nil;
        [name appendFormat:@"%C", (unichar)((uint16_t)bytes[0] << 8 | bytes[1])];
    }
    return name;
}

static NSString *BRCSReadUnicode(BRPPCResolveRegistry *registry, uint32_t address, uint32_t count) {
    if (count > 255) return nil;
    NSMutableString *name = [NSMutableString stringWithCapacity:count];
    for (uint32_t i = 0; i < count; i++) {
        uint8_t bytes[2];
        if (![registry.memory readBytes:bytes address:address + 2 * i length:2]) return nil;
        [name appendFormat:@"%C", (unichar)((uint16_t)bytes[0] << 8 | bytes[1])];
    }
    return name;
}

static NSString *BRCSFolderPath(uint32_t type) {
    NSSearchPathDirectory directory = NSLibraryDirectory;
    switch (type) {
        case 'pref': return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
        case 'asup': directory = NSApplicationSupportDirectory; break;
        case 'cach': directory = NSCachesDirectory; break;
        case 'desk': directory = NSDesktopDirectory; break;
        case 'docs': directory = NSDocumentDirectory; break;
        case 'apps': directory = NSApplicationDirectory; break;
        case 'temp': return NSTemporaryDirectory();
        case 'lib ': directory = NSLibraryDirectory; break;
        default: return nil;
    }
    return NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES).firstObject;
}

@interface BRCSComponent : NSObject
@property(nonatomic) uint32_t type;
@property(nonatomic) uint32_t subtype;
@property(nonatomic) uint32_t manufacturer;
@property(nonatomic) uint32_t flags;
@property(nonatomic) uint32_t mask;
@property(nonatomic) uint32_t routine;
@end
@implementation BRCSComponent @end

@interface BRCSComponentInstance : NSObject
@property(nonatomic, strong) BRCSComponent *component;
@property(nonatomic) uint32_t storage;
@property(nonatomic) uint32_t target;
@end
@implementation BRCSComponentInstance @end

@implementation BRPPCCoreServicesResolve
- (instancetype)init { return [super initWithFrameworkName:@"CoreServices"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    self.handleSizes = [NSMutableDictionary dictionary];
    self.referencePaths = [NSMutableDictionary dictionary];
    self.openForks = [NSMutableDictionary dictionary];
    self.components = [NSMutableArray array];
    self.nextReferenceToken = 1;
    self.nextForkNumber = 1;
    __weak typeof(self) weakSelf = self;
    __weak BRPPCResolveRegistry *weakRegistry = registry;
    registry.guestHandleRegistrar = ^(uint32_t handle, uint32_t size) {
        weakSelf.handleSizes[@(handle)] = @(size);
    };
    registry.guestFSRefWriter = ^BOOL(NSURL *URL, uint32_t address) {
        uint32_t token = weakSelf.nextReferenceToken++; uint8_t clear[80] = {0};
        weakSelf.referencePaths[@(token)] = URL.path;
        return URL.isFileURL && address && [weakRegistry.memory writeBytes:clear address:address length:sizeof(clear)] &&
            [weakRegistry.memory writeUInt32:token address:address];
    };
    registry.guestFSRefDecoder = ^NSURL *(uint32_t address) {
        uint32_t token = 0; [weakRegistry.memory readUInt32:&token address:address];
        NSString *path = weakSelf.referencePaths[@(token)]; return path ? [NSURL fileURLWithPath:path] : nil;
    };
    [registry registerSymbol:@"_Gestalt" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (getenv("BISMUTH_FRAMEWORK_TRACE"))
            fprintf(stderr, "Gestalt selector=0x%08x\n", state->gpr[3]);
        uint32_t value = 0;
        switch (state->gpr[3]) {
            case BRPPCGestaltSystemVersionSelector: value = BRPPCGuestSystemVersion; break;
            case BRPPCGestaltSystemVersionMajorSelector: value = BRPPCGuestSystemVersionMajor; break;
            case BRPPCGestaltSystemVersionMinorSelector: value = BRPPCGuestSystemVersionMinor; break;
            case BRPPCGestaltSystemVersionBugFixSelector: value = BRPPCGuestSystemVersionBugFix; break;
            case BRPPCGestaltQuickTimeVersionSelector: value = BRPPCGuestQuickTimeVersion; break;
            case BRPPCGestaltTSMVersionSelector: value = 0x0240; break;
            default: BRPPCFinish(state, (uint32_t)gestaltUndefSelectorErr); return YES;
        }
        if (!state->gpr[4] || ![registry.memory writeUInt32:value address:state->gpr[4]]) {
            BRPPCFinish(state, (uint32_t)paramErr);
            return YES;
        }
        BRPPCFinish(state, 0);
        return YES;
    }];
    [self registerZeroFunctions:@[@"_LSCopyApplicationURLsForURL", @"_LSOpenCFURLRef",
        @"_FSPathMakeRef", @"_FSRefMakePath"] registry:registry];
    void (^registerNewHandle)(NSString *, BOOL) = ^(NSString *symbol, BOOL clear) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCCoreServicesResolve *self = weakSelf;
            uint32_t size = state->gpr[3];
            uint32_t data = registry.guestAllocator ? registry.guestAllocator(size, clear) : 0;
            uint32_t handle = data && registry.guestAllocator ? registry.guestAllocator(4, YES) : 0;
            if (!handle || ![registry.memory writeUInt32:data address:handle]) {
                if (data && registry.guestDeallocator) registry.guestDeallocator(data);
                if (handle && registry.guestDeallocator) registry.guestDeallocator(handle);
                self.memoryError = memFullErr; BRPPCFinish(state, 0); return YES;
            }
            self.handleSizes[@(handle)] = @(size); self.memoryError = 0;
            BRPPCFinish(state, handle); return YES;
        }];
    };
    registerNewHandle(@"_NewHandle", NO);
    registerNewHandle(@"_NewHandleClear", YES);
    void (^registerNewPtr)(NSString *, BOOL) = ^(NSString *symbol, BOOL clear) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCCoreServicesResolve *self = weakSelf;
            uint32_t pointer = registry.guestAllocator ? registry.guestAllocator(state->gpr[3], clear) : 0;
            self.memoryError = pointer ? 0 : memFullErr; BRPPCFinish(state, pointer); return YES;
        }];
    };
    registerNewPtr(@"_NewPtr", NO);
    registerNewPtr(@"_NewPtrClear", YES);
    [registry registerSymbol:@"_DisposePtr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; if (registry.guestDeallocator) registry.guestDeallocator(state->gpr[3]);
        weakSelf.memoryError = 0; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_DisposeHandle" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t pointer = 0;
        [registry.memory readUInt32:&pointer address:state->gpr[3]];
        if (pointer && registry.guestDeallocator) registry.guestDeallocator(pointer);
        if (registry.guestDeallocator) registry.guestDeallocator(state->gpr[3]);
        [weakSelf.handleSizes removeObjectForKey:@(state->gpr[3])];
        weakSelf.memoryError = 0; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetHandleSize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *size = weakSelf.handleSizes[@(state->gpr[3])];
        weakSelf.memoryError = size ? 0 : nilHandleErr; BRPPCFinish(state, size.unsignedIntValue); return YES;
    }];
    [registry registerSymbol:@"_SetHandleSize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t handle = state->gpr[3], oldPointer = 0;
        NSNumber *oldSize = weakSelf.handleSizes[@(handle)]; uint32_t size = state->gpr[4];
        if (!oldSize || ![registry.memory readUInt32:&oldPointer address:handle]) {
            weakSelf.memoryError = nilHandleErr; BRPPCFinish(state, 0); return YES;
        }
        uint32_t replacement = registry.guestAllocator ? registry.guestAllocator(size, NO) : 0;
        NSMutableData *bytes = [NSMutableData dataWithLength:MIN(oldSize.unsignedIntValue, size)];
        if (!replacement || (bytes.length && ![registry.memory readBytes:bytes.mutableBytes
            address:oldPointer length:bytes.length]) || (bytes.length && ![registry.memory writeBytes:bytes.bytes
            address:replacement length:bytes.length]) || ![registry.memory writeUInt32:replacement address:handle]) {
            if (replacement && registry.guestDeallocator) registry.guestDeallocator(replacement);
            weakSelf.memoryError = memFullErr; BRPPCFinish(state, 0); return YES;
        }
        if (oldPointer && registry.guestDeallocator) registry.guestDeallocator(oldPointer);
        weakSelf.handleSizes[@(handle)] = @(size); weakSelf.memoryError = 0; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_PtrAndHand" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCCoreServicesResolve *self = weakSelf;
        uint32_t source = state->gpr[3], handle = state->gpr[4], appendSize = state->gpr[5];
        uint32_t oldPointer = 0, oldSize = self.handleSizes[@(handle)].unsignedIntValue;
        if (!handle || ![registry.memory readUInt32:&oldPointer address:handle]) {
            self.memoryError = nilHandleErr; BRPPCFinish(state, (uint32_t)nilHandleErr); return YES;
        }
        uint64_t combined = (uint64_t)oldSize + appendSize;
        uint32_t replacement = combined <= UINT32_MAX && registry.guestAllocator
            ? registry.guestAllocator((uint32_t)combined, NO) : 0;
        NSMutableData *bytes = replacement ? [NSMutableData dataWithLength:(NSUInteger)combined] : nil;
        if (!replacement || (oldSize && ![registry.memory readBytes:bytes.mutableBytes
            address:oldPointer length:oldSize]) || (appendSize && ![registry.memory readBytes:
            (uint8_t *)bytes.mutableBytes + oldSize address:source length:appendSize]) ||
            ![registry.memory writeBytes:bytes.bytes address:replacement length:bytes.length] ||
            ![registry.memory writeUInt32:replacement address:handle]) {
            if (replacement && registry.guestDeallocator) registry.guestDeallocator(replacement);
            self.memoryError = memFullErr; BRPPCFinish(state, (uint32_t)memFullErr); return YES;
        }
        if (oldPointer && registry.guestDeallocator) registry.guestDeallocator(oldPointer);
        self.handleSizes[@(handle)] = @((uint32_t)combined); self.memoryError = 0;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_BlockMoveData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *bytes = [NSMutableData dataWithLength:state->gpr[5]];
        if (![registry.memory readBytes:bytes.mutableBytes address:state->gpr[3] length:bytes.length] ||
            ![registry.memory writeBytes:bytes.bytes address:state->gpr[4] length:bytes.length]) return NO;
        BRPPCFinish(state, state->gpr[4]); return YES;
    }];
    [registry registerSymbol:@"_MemError" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCFinish(state, (uint32_t)weakSelf.memoryError); return YES;
    }];
    for (NSString *symbol in @[@"_HLock", @"_HUnlock"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_Long2Fix" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCFinish(state, state->gpr[3] << 16); return YES;
    }];
    [registry registerSymbol:@"_Fix2Long" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCFinish(state, (uint32_t)((int32_t)state->gpr[3] >> 16)); return YES;
    }];
    [registry registerSymbol:@"_TickCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t ticks = ((uint64_t)now.tv_sec * 1000000000ull + now.tv_nsec) * 60 / 1000000000ull;
        BRPPCFinish(state, (uint32_t)ticks); return YES;
    }];
    [registry registerSymbol:@"_Microseconds" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t value = (uint64_t)now.tv_sec * 1000000ull + now.tv_nsec / 1000;
        if (!state->gpr[3] || ![registry.memory writeUInt32:(uint32_t)(value >> 32) address:state->gpr[3]] ||
            ![registry.memory writeUInt32:(uint32_t)value address:state->gpr[3] + 4]) return NO;
        BRPPCFinish(state, state->gpr[3]); return YES;
    }];
    if (![self registerStringConstants:@[@"_kFSOperationBytesCompleteKey",
        @"_kFSOperationTotalBytesKey"] registry:registry error:error]) return NO;
    NSArray<NSString *> *componentManager = @[@"_FindNextComponent", @"_OpenComponent",
        @"_OpenAComponent", @"_OpenDefaultComponent", @"_CloseComponent",
        @"_GetComponentInfo", @"_GetComponentVersion", @"_GetComponentInstanceStorage",
        @"_SetComponentInstanceStorage", @"_GetComponentPublicResource",
        @"_ComponentSetTarget", @"_CallComponentCanDo",
        @"_CallComponentFunctionWithStorageProcInfo", @"_DelegateComponentCall",
        @"_RegisterComponent", @"_RegisterComponentFileRef",
        @"_RegisterComponentFileRefEntries", @"_UnregisterComponent",
        @"__CopyComponentBundleIdentifier", @"__GetComponentFSRef"];
    for (NSString *symbol in componentManager)
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_FindNextComponent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponent *previous = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        NSUInteger start = previous ? [weakSelf.components indexOfObjectIdenticalTo:previous] + 1 : 0;
        uint32_t values[5] = {0}; uint32_t description = state->gpr[4];
        if (description) for (NSUInteger i = 0; i < 5; i++) [registry.memory readUInt32:&values[i] address:description + (uint32_t)i * 4];
        BRCSComponent *match = nil;
        for (NSUInteger i = start; i < weakSelf.components.count; i++) { BRCSComponent *candidate = weakSelf.components[i];
            if ((!values[0] || candidate.type == values[0]) && (!values[1] || candidate.subtype == values[1]) &&
                (!values[2] || candidate.manufacturer == values[2]) &&
                ((candidate.flags & values[4]) == (values[3] & values[4]))) { match = candidate; break; }
        }
        BRPPCFinish(state, match && registry.guestObjectEncoder ? registry.guestObjectEncoder(match) : 0); return YES;
    }];
    [registry registerSymbol:@"_RegisterComponent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponent *component = [BRCSComponent new]; component.type = state->gpr[3];
        component.subtype = state->gpr[4]; component.manufacturer = state->gpr[5]; component.routine = state->gpr[6];
        component.flags = state->gpr[7]; [weakSelf.components addObject:component];
        BRPPCFinish(state, registry.guestObjectEncoder ? registry.guestObjectEncoder(component) : 0); return YES;
    }];
    for (NSString *symbol in @[@"_OpenComponent", @"_OpenDefaultComponent"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRCSComponent *component = nil;
            if ([symbol hasSuffix:@"DefaultComponent"]) {
                for (BRCSComponent *candidate in weakSelf.components)
                    if (candidate.type == state->gpr[3] && (!state->gpr[4] || candidate.subtype == state->gpr[4])) { component = candidate; break; }
            }
            else { id candidate = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
                if ([candidate isKindOfClass:[BRCSComponent class]]) component = candidate; }
            BRCSComponentInstance *instance = component ? [BRCSComponentInstance new] : nil; instance.component = component;
            BRPPCFinish(state, instance && registry.guestObjectEncoder ? registry.guestObjectEncoder(instance) : 0); return YES;
        }];
    [registry registerSymbol:@"_OpenAComponent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponent *component = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        if (![component isKindOfClass:[BRCSComponent class]] || !state->gpr[4]) { BRPPCFinish(state, (uint32_t)invalidComponentID); return YES; }
        BRCSComponentInstance *instance = [BRCSComponentInstance new]; instance.component = component;
        uint32_t handle = registry.guestObjectEncoder ? registry.guestObjectEncoder(instance) : 0;
        BRPPCFinish(state, handle && [registry.memory writeUInt32:handle address:state->gpr[4]] ? 0 : (uint32_t)invalidComponentID); return YES;
    }];
    [registry registerSymbol:@"_GetComponentInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponent *component = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        if (![component isKindOfClass:[BRCSComponent class]]) { BRPPCFinish(state, (uint32_t)invalidComponentID); return YES; }
        if (state->gpr[4]) { [registry.memory writeUInt32:component.type address:state->gpr[4]];
            [registry.memory writeUInt32:component.subtype address:state->gpr[4]+4];
            [registry.memory writeUInt32:component.manufacturer address:state->gpr[4]+8];
            [registry.memory writeUInt32:component.flags address:state->gpr[4]+12];
            [registry.memory writeUInt32:component.mask address:state->gpr[4]+16]; }
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetComponentVersion" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id instance = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        BRPPCFinish(state, [instance isKindOfClass:[BRCSComponentInstance class]]
            ? BRPPCGuestComponentVersion : (uint32_t)invalidComponentID); return YES;
    }];
    [registry registerSymbol:@"_GetComponentInstanceStorage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponentInstance *instance = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        BRPPCFinish(state, [instance isKindOfClass:[BRCSComponentInstance class]] ? instance.storage : 0); return YES;
    }];
    [registry registerSymbol:@"_SetComponentInstanceStorage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponentInstance *instance = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        uint32_t old = instance.storage; if ([instance isKindOfClass:[BRCSComponentInstance class]]) instance.storage = state->gpr[4];
        BRPPCFinish(state, old); return YES;
    }];
    [registry registerSymbol:@"_ComponentSetTarget" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRCSComponentInstance *instance = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        if ([instance isKindOfClass:[BRCSComponentInstance class]]) instance.target = state->gpr[4];
        BRPPCFinish(state, [instance isKindOfClass:[BRCSComponentInstance class]] ? 0 : (uint32_t)invalidComponentID); return YES;
    }];
    [registry registerSymbol:@"_CallComponentCanDo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id instance = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        BRPPCFinish(state, [instance isKindOfClass:[BRCSComponentInstance class]]); return YES;
    }];
    for (NSString *symbol in @[@"_CloseComponent", @"_UnregisterComponent", @"_RegisterComponentFileRef",
        @"_RegisterComponentFileRefEntries", @"_DelegateComponentCall", @"_CallComponentFunctionWithStorageProcInfo"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_OSASetSendProc", @"_OSASetActiveProc"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            BRPPCFinish(state, (uint32_t)badComponentInstance); return YES;
        }];
    [registry registerSymbol:@"_CompareAndSwap" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t current = 0; BOOL swapped = NO;
        if (state->gpr[5] && [registry.memory readUInt32:&current address:state->gpr[5]] && current == state->gpr[3])
            swapped = [registry.memory writeUInt32:state->gpr[4] address:state->gpr[5]];
        BRPPCFinish(state, swapped); return YES;
    }];
    [registry registerSymbol:@"_Fix2X" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->fpr[1] = (double)(int32_t)state->gpr[3] / 65536.0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_X2Fix" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; double scaled = state->fpr[1] * 65536.0;
        if (scaled > INT32_MAX) scaled = INT32_MAX; if (scaled < INT32_MIN) scaled = INT32_MIN;
        BRPPCFinish(state, (uint32_t)(int32_t)llround(scaled)); return YES;
    }];
    [registry registerSymbol:@"_UTTypeCreatePreferredIdentifierForTag" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *tagClass = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        NSString *tag = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil;
        NSString *conforming = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[5]) : nil;
        CFStringRef (*createType)(CFStringRef, CFStringRef, CFStringRef) =
            dlsym(RTLD_DEFAULT, "UTTypeCreatePreferredIdentifierForTag");
        CFStringRef value = createType && tagClass && tag ? createType(
            (__bridge CFStringRef)tagClass, (__bridge CFStringRef)tag,
            conforming ? (__bridge CFStringRef)conforming : NULL) : NULL;
        BRPPCFinish(state, value && registry.guestObjectEncoder ? registry.guestObjectEncoder(CFBridgingRelease(value)) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_UTTypeConformsTo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *first = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        NSString *second = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil;
        Boolean (*conforms)(CFStringRef, CFStringRef) = dlsym(RTLD_DEFAULT, "UTTypeConformsTo");
        BRPPCFinish(state, conforms && first && second && conforms((__bridge CFStringRef)first, (__bridge CFStringRef)second));
        return YES;
    }];
    [registry registerSymbol:@"_TECCountAvailableTextEncodings" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = 0; int32_t (*function)(uint32_t *) =
            dlsym(RTLD_DEFAULT, "TECCountAvailableTextEncodings");
        int32_t status = function && state->gpr[3] ? function(&count) : paramErr;
        if (!status && ![registry.memory writeUInt32:count address:state->gpr[3]]) return NO;
        BRPPCFinish(state, (uint32_t)status); return YES;
    }];
    [registry registerSymbol:@"_TECGetAvailableTextEncodings" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t maximum = state->gpr[4], actual = 0;
        NSMutableData *values = [NSMutableData dataWithLength:(NSUInteger)maximum * sizeof(uint32_t)];
        int32_t (*function)(uint32_t *, uint32_t, uint32_t *) =
            dlsym(RTLD_DEFAULT, "TECGetAvailableTextEncodings");
        int32_t status = function && state->gpr[3] && state->gpr[5] ?
            function(values.mutableBytes, maximum, &actual) : paramErr;
        for (uint32_t index = 0; !status && index < actual; index++)
            if (![registry.memory writeUInt32:((uint32_t *)values.bytes)[index]
                                      address:state->gpr[3] + index * 4]) return NO;
        if (!status && ![registry.memory writeUInt32:actual address:state->gpr[5]]) return NO;
        BRPPCFinish(state, (uint32_t)status); return YES;
    }];
    [registry registerSymbol:@"_TECCopyTextEncodingInternetNameAndMIB" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFStringRef name = NULL; int32_t mib = 0;
        int32_t (*function)(uint32_t, CFStringRef *, int32_t *) =
            dlsym(RTLD_DEFAULT, "TECCopyTextEncodingInternetNameAndMIB");
        int32_t status = function && state->gpr[4] && state->gpr[5] ? function(state->gpr[3], &name, &mib) : paramErr;
        uint32_t handle = name && registry.guestObjectEncoder ? registry.guestObjectEncoder(CFBridgingRelease(name)) : 0;
        if (!status && (!handle || ![registry.memory writeUInt32:handle address:state->gpr[4]] ||
                        ![registry.memory writeUInt32:(uint32_t)mib address:state->gpr[5]])) return NO;
        BRPPCFinish(state, (uint32_t)status); return YES;
    }];
    [registry registerSymbol:@"_TECGetTextEncodingFromInternetNameOrMIB" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        uint32_t encoding = 0; int32_t (*function)(CFStringRef, int32_t, uint32_t *) =
            dlsym(RTLD_DEFAULT, "TECGetTextEncodingFromInternetNameOrMIB");
        int32_t status = function && state->gpr[5] ? function((__bridge CFStringRef)name, (int32_t)state->gpr[4], &encoding) : paramErr;
        if (!status && ![registry.memory writeUInt32:encoding address:state->gpr[5]]) return NO;
        BRPPCFinish(state, (uint32_t)status); return YES;
    }];
    [registry registerSymbol:@"_TECCountSubTextEncodings" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[4] || ![registry.memory writeUInt32:0 address:state->gpr[4]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_TECGetSubTextEncodings" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[6] || ![registry.memory writeUInt32:0 address:state->gpr[6]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_TECCreateConverter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[3] || !registry.guestObjectEncoder) { BRPPCFinish(state, (uint32_t)paramErr); return YES; }
        uint32_t handle = registry.guestObjectEncoder(@[@(state->gpr[4]), @(state->gpr[5])]);
        if (!handle || ![registry.memory writeUInt32:handle address:state->gpr[3]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_UpgradeScriptInfoToTextEncoding" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t encoding = ((state->gpr[5] & 0xff) << 24) |
            ((state->gpr[4] & 0xff) << 16) | (state->gpr[3] & 0xffff);
        if (!state->gpr[7] || ![registry.memory writeUInt32:encoding address:state->gpr[7]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CreateTextToUnicodeInfo", @"_CreateTextToUnicodeInfoByEncoding",
                               @"_CreateUnicodeToTextInfo"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = state->gpr[4];
            if (!output || !registry.guestObjectEncoder) { BRPPCFinish(state, (uint32_t)paramErr); return YES; }
            uint32_t handle = registry.guestObjectEncoder(@(state->gpr[3]));
            if (!handle || ![registry.memory writeUInt32:handle address:output]) return NO;
            BRPPCFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_DisposeTextToUnicodeInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[3] || ![registry.memory writeUInt32:0 address:state->gpr[3]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_DisposeUnicodeToTextInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[3] || ![registry.memory writeUInt32:0 address:state->gpr[3]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_ConvertFromTextToUnicode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t outputSize = 0, sourceRead = 0, unicodeLength = 0, output = 0;
        if (!state->gpr[1] || ![registry.memory readUInt32:&outputSize address:state->gpr[1] + 56] ||
            ![registry.memory readUInt32:&sourceRead address:state->gpr[1] + 60] ||
            ![registry.memory readUInt32:&unicodeLength address:state->gpr[1] + 64] ||
            ![registry.memory readUInt32:&output address:state->gpr[1] + 68]) return NO;
        NSMutableData *source = [NSMutableData dataWithLength:state->gpr[4]];
        if (source.length && ![registry.memory readBytes:source.mutableBytes address:state->gpr[5] length:source.length]) return NO;
        NSString *text = [[NSString alloc] initWithData:source encoding:NSMacOSRomanStringEncoding] ?: @"";
        NSData *converted = [text dataUsingEncoding:NSUTF16BigEndianStringEncoding];
        uint32_t count = (uint32_t)MIN(converted.length, outputSize) & ~1u;
        if ((count && ![registry.memory writeBytes:converted.bytes address:output length:count]) ||
            ![registry.memory writeUInt32:(uint32_t)source.length address:sourceRead] ||
            ![registry.memory writeUInt32:count address:unicodeLength] ||
            (state->gpr[9] && ![registry.memory writeUInt32:0 address:state->gpr[9]])) return NO;
        BRPPCFinish(state, count < converted.length ? (uint32_t)kTECOutputBufferFullStatus : 0); return YES;
    }];
    [registry registerSymbol:@"_ConvertFromUnicodeToText" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t outputSize = 0, sourceRead = 0, outputLength = 0, output = 0;
        if (!state->gpr[1] || ![registry.memory readUInt32:&outputSize address:state->gpr[1] + 56] ||
            ![registry.memory readUInt32:&sourceRead address:state->gpr[1] + 60] ||
            ![registry.memory readUInt32:&outputLength address:state->gpr[1] + 64] ||
            ![registry.memory readUInt32:&output address:state->gpr[1] + 68]) return NO;
        NSMutableData *source = [NSMutableData dataWithLength:state->gpr[4]];
        if (source.length && ![registry.memory readBytes:source.mutableBytes address:state->gpr[5] length:source.length]) return NO;
        NSString *text = [[NSString alloc] initWithData:source encoding:NSUTF16BigEndianStringEncoding] ?: @"";
        NSData *converted = [text dataUsingEncoding:NSMacOSRomanStringEncoding allowLossyConversion:YES];
        uint32_t count = (uint32_t)MIN(converted.length, outputSize);
        if ((count && ![registry.memory writeBytes:converted.bytes address:output length:count]) ||
            ![registry.memory writeUInt32:(uint32_t)source.length address:sourceRead] ||
            ![registry.memory writeUInt32:count address:outputLength] ||
            (state->gpr[9] && ![registry.memory writeUInt32:0 address:state->gpr[9]])) return NO;
        BRPPCFinish(state, count < converted.length ? (uint32_t)kTECOutputBufferFullStatus : 0); return YES;
    }];
    [registry registerSymbol:@"_TECConvertText" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id converter = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        uint32_t count = MIN(state->gpr[5], state->gpr[8]);
        if (![converter isKindOfClass:NSArray.class] || !state->gpr[6] || !state->gpr[7] || !state->gpr[9]) {
            BRPPCFinish(state, (uint32_t)paramErr); return YES;
        }
        NSMutableData *bytes = [NSMutableData dataWithLength:count];
        if ((count && (![registry.memory readBytes:bytes.mutableBytes address:state->gpr[4] length:count] ||
                       ![registry.memory writeBytes:bytes.bytes address:state->gpr[7] length:count])) ||
            ![registry.memory writeUInt32:count address:state->gpr[6]] ||
            ![registry.memory writeUInt32:count address:state->gpr[9]]) return NO;
        BRPPCFinish(state, state->gpr[5] > state->gpr[8] ? (uint32_t)kTECOutputBufferFullStatus : 0); return YES;
    }];
    [registry registerSymbol:@"_TECFlushText" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (state->gpr[6] && ![registry.memory writeUInt32:0 address:state->gpr[6]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_TECDisposeConverter", @"_TECClearConverterContextInfo"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_FSPathMakeRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *path = BRCSGuestPath(registry, state->gpr[3]);
        if (!path || !state->gpr[4]) { BRPPCFinish(state, (uint32_t)paramErr); return YES; }
        BOOL directory = NO, exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory];
        if (!exists) { BRPPCFinish(state, (uint32_t)fnfErr); return YES; }
        uint32_t token = weakSelf.nextReferenceToken++; weakSelf.referencePaths[@(token)] = path;
        uint8_t clear[80] = {0};
        if (![registry.memory writeBytes:clear address:state->gpr[4] length:sizeof(clear)] ||
            ![registry.memory writeUInt32:token address:state->gpr[4]]) return NO;
        if (state->gpr[5]) { uint8_t value = directory; if (![registry.memory writeBytes:&value address:state->gpr[5] length:1]) return NO; }
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FindFolder" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if ((state->gpr[6] && !BRCSWriteUInt16(registry, state->gpr[6], 0)) ||
            (state->gpr[7] && ![registry.memory writeUInt32:fsRtDirID address:state->gpr[7]])) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSFindFolder" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *path = BRCSFolderPath(state->gpr[4]);
        if (!path || !state->gpr[6]) { BRPPCFinish(state, (uint32_t)fnfErr); return YES; }
        if (state->gpr[5]) [[NSFileManager defaultManager] createDirectoryAtPath:path
            withIntermediateDirectories:YES attributes:nil error:nil];
        uint32_t token = weakSelf.nextReferenceToken++; weakSelf.referencePaths[@(token)] = path;
        uint8_t clear[80] = {0};
        if (![registry.memory writeBytes:clear address:state->gpr[6] length:sizeof(clear)] ||
            ![registry.memory writeUInt32:token address:state->gpr[6]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSRefMakePath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t token = 0;
        if (![registry.memory readUInt32:&token address:state->gpr[3]]) { BRPPCFinish(state, (uint32_t)paramErr); return YES; }
        NSData *bytes = [weakSelf.referencePaths[@(token)] dataUsingEncoding:NSUTF8StringEncoding];
        if (!bytes || !state->gpr[4] || bytes.length + 1 > state->gpr[5]) { BRPPCFinish(state, (uint32_t)paramErr); return YES; }
        uint8_t zero = 0;
        if (![registry.memory writeBytes:bytes.bytes address:state->gpr[4] length:bytes.length] ||
            ![registry.memory writeBytes:&zero address:state->gpr[4] + (uint32_t)bytes.length length:1]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSMakeFSRefUnicode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t token = 0;
        if (![registry.memory readUInt32:&token address:state->gpr[3]]) return NO;
        NSString *parent = weakSelf.referencePaths[@(token)] ?: @"/";
        NSString *name = BRCSReadUnicode(registry, state->gpr[5], state->gpr[4]);
        if (!name || !state->gpr[7]) { BRPPCFinish(state, (uint32_t)paramErr); return YES; }
        uint32_t newToken = weakSelf.nextReferenceToken++;
        weakSelf.referencePaths[@(newToken)] = [parent stringByAppendingPathComponent:name];
        uint8_t clear[80] = {0};
        if (![registry.memory writeBytes:clear address:state->gpr[7] length:sizeof(clear)] ||
            ![registry.memory writeUInt32:newToken address:state->gpr[7]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSResolveAliasFile" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint8_t directory = 1, aliased = 0;
        if ((state->gpr[5] && ![registry.memory writeBytes:&directory address:state->gpr[5] length:1]) ||
            (state->gpr[6] && ![registry.memory writeBytes:&aliased address:state->gpr[6] length:1])) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSGetCatalogInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t token = 0;
        if (![registry.memory readUInt32:&token address:state->gpr[3]]) return NO;
        if (state->gpr[5]) {
            uint8_t clear[144] = {0};
            if (![registry.memory writeBytes:clear address:state->gpr[5] length:sizeof(clear)] ||
                !BRCSWriteUInt16(registry, state->gpr[5], kFSNodeIsDirectoryMask) ||
                ![registry.memory writeUInt32:token address:state->gpr[5] + 8]) return NO;
        }
        if (state->gpr[6]) {
            NSString *name = weakSelf.referencePaths[@(token)].lastPathComponent ?: @"";
            if (!BRCSWriteHFSName(registry, state->gpr[6], name)) return NO;
        }
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_PBGetCatInfoSync" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint8_t indexBytes[2] = {0}; uint32_t directoryID = 0;
        if (!state->gpr[3] || ![registry.memory readBytes:indexBytes address:state->gpr[3] + 28 length:2] ||
            ![registry.memory readUInt32:&directoryID address:state->gpr[3] + 48]) return NO;
        int16_t index = (int16_t)((indexBytes[0] << 8) | indexBytes[1]);
        int16_t result = index == -1 ? 0 : fnfErr;
        if (!BRCSWriteUInt16(registry, state->gpr[3] + 16, (uint16_t)result)) return NO;
        if (!result) {
            uint8_t directory = 0x10;
            if (![registry.memory writeBytes:&directory address:state->gpr[3] + 30 length:1] ||
                ![registry.memory writeUInt32:directoryID ?: fsRtDirID address:state->gpr[3] + 48] ||
                !BRCSWriteUInt16(registry, state->gpr[3] + 52, 0)) return NO;
        }
        BRPPCFinish(state, (uint32_t)(int32_t)result); return YES;
    }];
    for (NSString *symbol in @[@"_FSNewAlias", @"_FSNewAliasMinimal"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = [symbol hasSuffix:@"Minimal"] ? state->gpr[4] : state->gpr[5];
            uint32_t data = registry.guestAllocator ? registry.guestAllocator(4, YES) : 0;
            uint32_t handle = data && registry.guestAllocator ? registry.guestAllocator(4, YES) : 0;
            if (!output || !handle || ![registry.memory writeUInt32:data address:handle] ||
                ![registry.memory writeUInt32:handle address:output]) {
                if (data && registry.guestDeallocator) registry.guestDeallocator(data);
                if (handle && registry.guestDeallocator) registry.guestDeallocator(handle);
                BRPPCFinish(state, (uint32_t)memFullErr); return YES;
            }
            weakSelf.handleSizes[@(handle)] = @4; BRPPCFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_FSGetDataForkName", @"_FSGetResourceForkName"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *name = [symbol containsString:@"Resource"] ? @"RESOURCE_FORK" : @"";
            if (!BRCSWriteHFSName(registry, state->gpr[3], name)) return NO;
            BRPPCFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_FSGetHFSUniStrFromString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        if (![name isKindOfClass:NSString.class] || !BRCSWriteHFSName(registry, state->gpr[4], name)) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSCreateStringFromHFSUniStr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = BRCSReadHFSName(registry, state->gpr[4]);
        BRPPCFinish(state, name && registry.guestObjectEncoder ? registry.guestObjectEncoder(name) : 0); return YES;
    }];
    [registry registerSymbol:@"_FSOpenFork" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t token = 0;
        if (![registry.memory readUInt32:&token address:state->gpr[3]] || !state->gpr[7]) {
            BRPPCFinish(state, (uint32_t)paramErr); return YES;
        }
        NSString *path = weakSelf.referencePaths[@(token)]; NSFileHandle *file = nil;
        if (state->gpr[6] & 2) file = [NSFileHandle fileHandleForWritingAtPath:path];
        else file = [NSFileHandle fileHandleForReadingAtPath:path];
        if (!file) { BRPPCFinish(state, (uint32_t)fnfErr); return YES; }
        uint16_t number = weakSelf.nextForkNumber++; if (!number) number = weakSelf.nextForkNumber++;
        weakSelf.openForks[@(number)] = file;
        if (!BRCSWriteUInt16(registry, state->gpr[7], number)) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSCloseFork" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint16_t number = (uint16_t)state->gpr[3]; NSFileHandle *file = weakSelf.openForks[@(number)];
        if (!file) { BRPPCFinish(state, (uint32_t)fnOpnErr); return YES; }
        [file closeFile]; [weakSelf.openForks removeObjectForKey:@(number)]; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetEOF" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSFileHandle *file = weakSelf.openForks[@((uint16_t)state->gpr[3])];
        if (!file || !state->gpr[4]) { BRPPCFinish(state, (uint32_t)fnOpnErr); return YES; }
        unsigned long long position = file.offsetInFile, length = [file seekToEndOfFile];
        [file seekToFileOffset:position];
        if (length > UINT32_MAX || ![registry.memory writeUInt32:(uint32_t)length address:state->gpr[4]]) return NO;
        BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSRead" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSFileHandle *file = weakSelf.openForks[@((uint16_t)state->gpr[3])]; uint32_t count = 0;
        if (!file || !state->gpr[4] || ![registry.memory readUInt32:&count address:state->gpr[4]]) {
            BRPPCFinish(state, (uint32_t)fnOpnErr); return YES;
        }
        NSData *data = [file readDataOfLength:count];
        if ((data.length && ![registry.memory writeBytes:data.bytes address:state->gpr[5] length:data.length]) ||
            ![registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[4]]) return NO;
        BRPPCFinish(state, data.length < count ? (uint32_t)eofErr : 0); return YES;
    }];
    [registry registerSymbol:@"_FSWrite" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSFileHandle *file = weakSelf.openForks[@((uint16_t)state->gpr[3])]; uint32_t count = 0;
        if (!file || !state->gpr[4] || ![registry.memory readUInt32:&count address:state->gpr[4]]) {
            BRPPCFinish(state, (uint32_t)fnOpnErr); return YES;
        }
        NSMutableData *data = [NSMutableData dataWithLength:count];
        if ((count && ![registry.memory readBytes:data.mutableBytes address:state->gpr[5] length:count])) return NO;
        [file writeData:data]; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_SetEOF" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSFileHandle *file = weakSelf.openForks[@((uint16_t)state->gpr[3])];
        if (!file) { BRPPCFinish(state, (uint32_t)fnOpnErr); return YES; }
        [file truncateFileAtOffset:state->gpr[4]]; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_SetFPos" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSFileHandle *file = weakSelf.openForks[@((uint16_t)state->gpr[3])];
        if (!file) { BRPPCFinish(state, (uint32_t)fnOpnErr); return YES; }
        int32_t offset = (int32_t)state->gpr[5]; unsigned long long base = 0;
        if (state->gpr[4] == fsFromLEOF) base = [file seekToEndOfFile];
        else if (state->gpr[4] == fsFromMark || state->gpr[4] == fsAtMark) base = file.offsetInFile;
        [file seekToFileOffset:(unsigned long long)((int64_t)base + offset)]; BRPPCFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_FSClose" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint16_t number = (uint16_t)state->gpr[3]; NSFileHandle *file = weakSelf.openForks[@(number)];
        if (!file) { BRPPCFinish(state, (uint32_t)fnOpnErr); return YES; }
        [file closeFile]; [weakSelf.openForks removeObjectForKey:@(number)]; BRPPCFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CaptureComponent", @"_FSEjectVolumeSync", @"_FSFileOperationCancel",
        @"_FSFileOperationScheduleWithRunLoop", @"_FSGetVolumeInfo",
        @"_FSIsAliasFile", @"_FSPathCopyObjectAsync", @"_FSPathMoveObjectAsync",
        @"_FSResolveAlias", @"_FSSetCatalogInfo", @"_FSSpecToNativePathName",
        @"_PBReadForkSync"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_FSFileOperationCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCFinish(state, registry.guestObjectEncoder ? registry.guestObjectEncoder([NSObject new]) : 0); return YES;
    }];
    return YES;
}
@end
