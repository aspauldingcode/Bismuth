#import "BRPPCCarbonResolve.h"
#import "BRPPCAddressSpace.h"
#import <CoreServices/CoreServices.h>
#import <AppKit/AppKit.h>

@interface BRPPCCarbonResolve ()
@property(nonatomic) int16_t resourceError;
@property(nonatomic, strong) NSDictionary<NSString *, NSData *> *indexedStrings;
@property(nonatomic, strong) NSDictionary<NSString *, NSData *> *indexedResources;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSPasteboard *> *pasteboards;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *syntheticPasteboards;
@property(nonatomic) uint32_t nextPasteboard;
@end

static uint16_t BRCarbon16(const uint8_t *p) { return ((uint16_t)p[0] << 8) | p[1]; }
static uint32_t BRCarbon32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static BOOL BRCarbonIsFindPasteboardName(NSString *name) {
    return [name isEqualToString:NSPasteboardNameFind] || [name isEqualToString:@"com.apple.pasteboard.find"];
}
static void BRCarbonReadResources(NSData *file, NSMutableDictionary<NSString *, NSData *> *resources,
                                  NSMutableDictionary<NSString *, NSData *> *strings) {
    const uint8_t *p = file.bytes; NSUInteger n = file.length;
    if (n < 16) return;
    uint32_t dataOffset = BRCarbon32(p), mapOffset = BRCarbon32(p + 4);
    uint32_t dataLength = BRCarbon32(p + 8), mapLength = BRCarbon32(p + 12);
    if ((uint64_t)dataOffset + dataLength > n || (uint64_t)mapOffset + mapLength > n || mapLength < 30) return;
    const uint8_t *map = p + mapOffset; uint16_t typeOffset = BRCarbon16(map + 24);
    if ((uint32_t)typeOffset + 2 > mapLength) return;
    const uint8_t *types = map + typeOffset; uint32_t typeCount = (uint32_t)BRCarbon16(types) + 1;
    if ((uint64_t)typeOffset + 2 + (uint64_t)typeCount * 8 > mapLength) return;
    for (uint32_t t = 0; t < typeCount; t++) {
        const uint8_t *type = types + 2 + t * 8;
        uint32_t resourceType = BRCarbon32(type);
        uint32_t count = (uint32_t)BRCarbon16(type + 4) + 1, refsOffset = BRCarbon16(type + 6);
        if ((uint64_t)typeOffset + refsOffset + (uint64_t)count * 12 > mapLength) return;
        for (uint32_t r = 0; r < count; r++) {
            const uint8_t *ref = types + refsOffset + r * 12; int16_t resourceID = (int16_t)BRCarbon16(ref);
            uint32_t offset = BRCarbon32(ref + 4) & 0x00ffffff;
            if ((uint64_t)offset + 4 > dataLength) continue;
            const uint8_t *body = p + dataOffset + offset; uint32_t length = BRCarbon32(body);
            if ((uint64_t)offset + 4 + length > dataLength || length < 2) continue;
            resources[[NSString stringWithFormat:@"%08x:%u", resourceType, r + 1]] =
                [NSData dataWithBytes:body + 4 length:length];
            if (resourceType != 'STR#') continue;
            const uint8_t *s = body + 4; uint32_t stringCount = BRCarbon16(s), pos = 2;
            for (uint32_t i = 1; i <= stringCount && pos < length; i++) {
                uint32_t size = s[pos++]; if ((uint64_t)pos + size > length) break;
                strings[[NSString stringWithFormat:@"%d:%u", resourceID, i]] = [NSData dataWithBytes:s + pos length:size];
                pos += size;
            }
        }
    }
}

@implementation BRPPCCarbonResolve
- (instancetype)init { return [super initWithFrameworkName:@"Carbon"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    self.resourceError = 0;
    self.pasteboards = [NSMutableDictionary dictionary]; self.syntheticPasteboards = [NSMutableSet set];
    self.nextPasteboard = 0xb2000000;
    __weak typeof(self) weakSelf = self;
    NSMutableDictionary *resources = [NSMutableDictionary dictionary], *strings = [NSMutableDictionary dictionary];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:NSBundle.mainBundle.resourcePath error:nil])
        if ([name.pathExtension caseInsensitiveCompare:@"rsrc"] == NSOrderedSame)
            BRCarbonReadResources([NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:name]], resources, strings);
    self.indexedResources = resources; self.indexedStrings = strings;
    [self registerZeroFunctions:@[@"_RunApplicationEventLoop", @"_QuitApplicationEventLoop",
        @"_GetCurrentEventTime", @"_FlushEvents"] registry:registry];
    [registry registerSymbol:@"_AcquireRootMenu" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMenu *menu = NSApp.mainMenu ?: [NSMenu new];
        state->gpr[3] = registry.guestObjectEncoder ? registry.guestObjectEncoder(menu) : 0;
        state->pc = state->lr; return YES;
    }];
    [self registerZeroFunction:@"_ReleaseRootMenu" registry:registry];
    [registry registerSymbol:@"_RegisterIconRefFromFSRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSImage *icon = NSApplication.sharedApplication.applicationIconImage ?: [NSImage new];
        uint32_t handle = registry.guestObjectEncoder ? registry.guestObjectEncoder(icon) : 0;
        if (!state->gpr[6] || !handle || ![registry.memory writeUInt32:handle address:state->gpr[6]]) return NO;
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [self registerZeroFunctions:@[@"_AcquireIconRef", @"_ReleaseIconRef"] registry:registry];
    [registry registerSymbol:@"_NumToString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; char text[32]; int length = snprintf(text, sizeof(text), "%d", (int32_t)state->gpr[3]);
        uint8_t count = (uint8_t)MAX(0, MIN(length, 31));
        if (!state->gpr[4] || ![registry.memory writeBytes:&count address:state->gpr[4] length:1] ||
            (count && ![registry.memory writeBytes:text address:state->gpr[4] + 1 length:count])) return NO;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_StringToNum" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint8_t count = 0; char text[256] = {0};
        if (!state->gpr[3] || !state->gpr[4] || ![registry.memory readBytes:&count address:state->gpr[3] length:1] ||
            (count && ![registry.memory readBytes:text address:state->gpr[3] + 1 length:count]) ||
            ![registry.memory writeUInt32:(uint32_t)strtol(text, NULL, 10) address:state->gpr[4]]) return NO;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PasteboardCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        NSPasteboard *pasteboard = name.length ? [NSPasteboard pasteboardWithName:name] : NSPasteboard.generalPasteboard;
        uint32_t handle = ++weakSelf.nextPasteboard; weakSelf.pasteboards[@(handle)] = pasteboard;
        if (BRCarbonIsFindPasteboardName(name) && !pasteboard.pasteboardItems.count)
            [weakSelf.syntheticPasteboards addObject:@(handle)];
        if (!state->gpr[4] || !handle || ![registry.memory writeUInt32:handle address:state->gpr[4]]) return NO;
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PasteboardClear" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSPasteboard *pasteboard = weakSelf.pasteboards[@(state->gpr[3])]; [pasteboard clearContents];
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [self registerZeroFunction:@"_PasteboardSynchronize" registry:registry];
    [registry registerSymbol:@"_PasteboardCopyName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSPasteboard *pasteboard = weakSelf.pasteboards[@(state->gpr[3])];
        state->gpr[3] = registry.guestObjectEncoder ? registry.guestObjectEncoder(pasteboard.name ?: @"") : 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PasteboardGetItemCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSPasteboard *pasteboard = weakSelf.pasteboards[@(state->gpr[3])];
        uint32_t count = [weakSelf.syntheticPasteboards containsObject:@(state->gpr[3])] ? 1 : (uint32_t)pasteboard.pasteboardItems.count;
        if (!state->gpr[4] || ![registry.memory writeUInt32:count address:state->gpr[4]]) return NO;
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PasteboardGetItemIdentifier" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSPasteboard *pasteboard = weakSelf.pasteboards[@(state->gpr[3])];
        NSUInteger index = state->gpr[4] ? state->gpr[4] - 1 : NSNotFound;
        BOOL synthetic = [weakSelf.syntheticPasteboards containsObject:@(state->gpr[3])];
        if ((!synthetic && index >= pasteboard.pasteboardItems.count) || (synthetic && index != 0)) state->gpr[3] = (uint32_t)(int32_t)badPasteboardIndexErr;
        else if (!state->gpr[5] || ![registry.memory writeUInt32:state->gpr[4] address:state->gpr[5]]) return NO;
        else state->gpr[3] = 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PasteboardCopyItemFlavors" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSPasteboard *pasteboard = weakSelf.pasteboards[@(state->gpr[3])];
        NSUInteger index = state->gpr[4] ? state->gpr[4] - 1 : NSNotFound;
        BOOL synthetic = [weakSelf.syntheticPasteboards containsObject:@(state->gpr[3])];
        NSArray *flavors = synthetic && index == 0 ? @[@"com.apple.traditional-mac-plain-text",
            @"public.utf8-plain-text", @"public.utf16-external-plain-text", @"public.plain-text"] :
            (index < pasteboard.pasteboardItems.count ? pasteboard.pasteboardItems[index].types : nil);
        uint32_t value = flavors && registry.guestObjectEncoder ? registry.guestObjectEncoder(flavors) : 0;
        if (!flavors) { state->gpr[3] = (uint32_t)(int32_t)badPasteboardItemErr; state->pc = state->lr; return YES; }
        if (!state->gpr[5] || !value || ![registry.memory writeUInt32:value address:state->gpr[5]]) return NO;
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PasteboardCopyItemFlavorData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSPasteboard *pasteboard = weakSelf.pasteboards[@(state->gpr[3])];
        NSUInteger index = state->gpr[4] ? state->gpr[4] - 1 : NSNotFound;
        NSString *flavor = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[5]) : nil;
        BOOL synthetic = [weakSelf.syntheticPasteboards containsObject:@(state->gpr[3])];
        NSData *data = synthetic && index == 0 ? NSData.data :
            (flavor && index < pasteboard.pasteboardItems.count ? [pasteboard.pasteboardItems[index] dataForType:flavor] : nil);
        uint32_t value = data && registry.guestObjectEncoder ? registry.guestObjectEncoder(data) : 0;
        if (!data) { state->gpr[3] = (uint32_t)(int32_t)badPasteboardFlavorErr; state->pc = state->lr; return YES; }
        if (!state->gpr[6] || !value || ![registry.memory writeUInt32:value address:state->gpr[6]]) return NO;
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [self registerZeroFunctions:@[@"_PasteboardPutItemFlavor", @"_TransformProcessType"]
                         registry:registry];
    for (NSString *symbol in @[@"_AHLookupAnchor", @"_AHRegisterHelpBook",
                               @"_HIViewDrawCGImage"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_GetApplicationTextEncoding"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_GetCurrentEventKeyModifiers"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_GetKeys" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint8_t keys[16] = {0};
        if (!state->gpr[3] || ![registry.memory writeBytes:keys address:state->gpr[3] length:sizeof(keys)])
            return NO;
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_GetCurrentProcess", @"_GetFrontProcess"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (!state->gpr[3] || ![registry.memory writeUInt32:0 address:state->gpr[3]] ||
                ![registry.memory writeUInt32:2 address:state->gpr[3] + 4]) return NO;
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_GetIndString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *value = weakSelf.indexedStrings[[NSString stringWithFormat:@"%d:%u",
            (int16_t)state->gpr[4], (uint16_t)state->gpr[5]]];
        uint8_t length = (uint8_t)MIN(value.length, 255), empty = 0;
        if (!state->gpr[3] || ![registry.memory writeBytes:value ? &length : &empty address:state->gpr[3] length:1] ||
            (value && length && ![registry.memory writeBytes:value.bytes address:state->gpr[3] + 1 length:length])) return NO;
        weakSelf.resourceError = value ? 0 : resNotFound; state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_SetFrontProcess", @"_SetFrontProcessWithOptions", @"_WakeUpProcess"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_FSOpenResourceFile" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        weakSelf.resourceError = fnfErr;
        uint16_t invalidReference = UINT16_MAX;
        if (state->gpr[7]) [registry.memory writeBytes:&invalidReference
                                             address:state->gpr[7] length:sizeof(invalidReference)];
        state->gpr[3] = (uint32_t)(int32_t)weakSelf.resourceError; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_FSOpenResFile" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; weakSelf.resourceError = fnfErr;
        state->gpr[3] = UINT32_MAX; state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_GetIndResource", @"_Get1IndResource"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *data = weakSelf.indexedResources[
                [NSString stringWithFormat:@"%08x:%u", state->gpr[3], state->gpr[4]]];
            uint32_t bytes = data.length && registry.guestAllocator ? registry.guestAllocator((uint32_t)data.length, NO) : 0;
            uint32_t handle = data && registry.guestAllocator ? registry.guestAllocator(4, YES) : 0;
            if ((data.length && (!bytes || ![registry.memory writeBytes:data.bytes address:bytes length:data.length])) ||
                (data && (!handle || ![registry.memory writeUInt32:bytes address:handle]))) return NO;
            if (data && registry.guestHandleRegistrar) registry.guestHandleRegistrar(handle, (uint32_t)data.length);
            weakSelf.resourceError = data ? 0 : resNotFound; state->gpr[3] = handle; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_GetResource" handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; weakSelf.resourceError = resNotFound;
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_GetResInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; weakSelf.resourceError = resNotFound;
        state->gpr[3] = (uint32_t)(int32_t)weakSelf.resourceError; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_ResError" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->gpr[3] = (uint32_t)(int32_t)weakSelf.resourceError;
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_CloseResFile", @"_UseResFile", @"_ReleaseResource"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; weakSelf.resourceError = 0;
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    return YES;
}
@end
