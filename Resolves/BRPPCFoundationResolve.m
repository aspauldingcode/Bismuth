#import "BRPPCFoundationResolve.h"
#import "BRPPCAddressSpace.h"

static void BRFNReturn(BRPPCState *state, uint32_t value) { state->gpr[3] = value; state->pc = state->lr; }
static id BRFNObject(BRPPCResolveRegistry *registry, uint32_t handle) {
    return registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
}
static uint32_t BRFNHandle(BRPPCResolveRegistry *registry, id object) {
    return registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0;
}
static float BRFNFloat(uint32_t bits) { float value = 0; memcpy(&value, &bits, 4); return value; }
static uint32_t BRFNBits(float value) { uint32_t bits = 0; memcpy(&bits, &value, 4); return bits; }
static BOOL BRFNArgument(BRPPCResolveRegistry *registry, BRPPCState *state, NSUInteger index, uint32_t *word) {
    NSUInteger reg = index + 3; if (reg <= 10) { *word = state->gpr[reg]; return YES; }
    return [registry.memory readUInt32:word address:state->gpr[1] + 24 + (uint32_t)index * 4];
}
static BOOL BRFNWriteRect(BRPPCResolveRegistry *registry, uint32_t address, const float *rect) {
    for (NSUInteger i = 0; i < 4; i++) if (![registry.memory writeUInt32:BRFNBits(rect[i]) address:address + (uint32_t)i * 4]) return NO;
    return YES;
}
static uint32_t BRFNGuestCString(BRPPCResolveRegistry *registry, NSString *string) {
    NSData *bytes = [string dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t address = registry.guestAllocator ? registry.guestAllocator((uint32_t)bytes.length + 1, YES) : 0;
    return address && [registry.memory writeBytes:bytes.bytes address:address length:bytes.length] ? address : 0;
}

@implementation BRPPCFoundationResolve
- (instancetype)init { return [super initWithFrameworkName:@"Foundation"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    [self registerZeroFunction:@"_NSSetUncaughtExceptionHandler" registry:registry];
    NSArray<NSString *> *strings = @[@"_NSLocalizedDescriptionKey", @"_NSUnderlyingErrorKey",
        @"_NSDefaultRunLoopMode", @"_NSFileCreationDate", @"_NSFileExtensionHidden",
        @"_NSFileHFSCreatorCode", @"_NSFileHFSTypeCode", @"_NSFileImmutable",
        @"_NSFileModificationDate", @"_NSFilePosixPermissions", @"_NSFileSize",
        @"_NSFileSystemFreeSize", @"_NSFileType", @"_NSFileTypeRegular",
        @"_NSGenericException", @"_NSKeyValueChangeNewKey", @"_NSKeyValueChangeOldKey",
        @"_NSLocaleCountryCode", @"_NSLocaleDecimalSeparator", @"_NSLocaleGroupingSeparator",
        @"_NSLocaleUsesMetricSystem", @"_NSOSStatusErrorDomain",
        @"_NSStreamFileCurrentOffsetKey"];
    if (![self registerStringConstants:strings registry:registry error:error]) return NO;
    uint8_t zeroGeometry[16] = {0};
    if (![self registerDataConstant:@"_NSZeroPoint"
        data:[NSData dataWithBytes:zeroGeometry length:8] alignment:4 registry:registry error:error] ||
        ![self registerDataConstant:@"_NSZeroSize"
        data:[NSData dataWithBytes:zeroGeometry length:8] alignment:4 registry:registry error:error] ||
        ![self registerDataConstant:@"_NSZeroRect"
        data:[NSData dataWithBytes:zeroGeometry length:16] alignment:4 registry:registry error:error]) return NO;
    [self registerZeroFunction:@"_NSLog" registry:registry];
    NSDictionary *directoryFunctions = @{@"_NSHomeDirectory": NSHomeDirectory(),
        @"_NSTemporaryDirectory": NSTemporaryDirectory(), @"_NSOpenStepRootDirectory": NSOpenStepRootDirectory()};
    [directoryFunctions enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSString *value, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRFNReturn(state, BRFNHandle(registry, value)); return YES;
        }];
    }];
    [registry registerSymbol:@"_NSClassFromString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = BRFNObject(registry, state->gpr[3]); BRFNReturn(state, BRFNHandle(registry, NSClassFromString(name))); return YES;
    }];
    [registry registerSymbol:@"_NSStringFromClass" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id cls = BRFNObject(registry, state->gpr[3]); BRFNReturn(state, BRFNHandle(registry, cls ? NSStringFromClass(cls) : nil)); return YES;
    }];
    [registry registerSymbol:@"_NSSelectorFromString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = BRFNObject(registry, state->gpr[3]); BRFNReturn(state, name.length ? BRFNGuestCString(registry, name) : 0); return YES;
    }];
    [registry registerSymbol:@"_NSStringFromSelector" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:1024];
        BRFNReturn(state, BRFNHandle(registry, name)); return YES;
    }];
    [registry registerSymbol:@"_NSFileTypeForHFSTypeCode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t code = state->gpr[3]; char chars[] = {code >> 24, code >> 16, code >> 8, code, 0};
        NSString *type = [[NSString alloc] initWithBytes:chars length:4 encoding:NSMacOSRomanStringEncoding];
        BRFNReturn(state, BRFNHandle(registry, type)); return YES;
    }];
    NSDictionary *pointStringFunctions = @{@"_NSStringFromPoint": @0, @"_NSStringFromSize": @1,
        @"_NSStringFromRect": @2, @"_NSStringFromRange": @3};
    [pointStringFunctions enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *text = nil;
            if (kind.intValue == 0) text = NSStringFromPoint(NSMakePoint(BRFNFloat(state->gpr[3]), BRFNFloat(state->gpr[4])));
            else if (kind.intValue == 1) text = NSStringFromSize(NSMakeSize(BRFNFloat(state->gpr[3]), BRFNFloat(state->gpr[4])));
            else if (kind.intValue == 2) text = NSStringFromRect(NSMakeRect(BRFNFloat(state->gpr[3]), BRFNFloat(state->gpr[4]), BRFNFloat(state->gpr[5]), BRFNFloat(state->gpr[6])));
            else text = NSStringFromRange(NSMakeRange(state->gpr[3], state->gpr[4]));
            BRFNReturn(state, BRFNHandle(registry, text)); return YES;
        }];
    }];
    NSDictionary *parseFunctions = @{@"_NSPointFromString": @0, @"_NSSizeFromString": @1,
        @"_NSRectFromString": @2, @"_NSRangeFromString": @3};
    [parseFunctions enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = state->gpr[3]; NSString *text = BRFNObject(registry, state->gpr[4]);
            if (kind.intValue == 0) { NSPoint p = NSPointFromString(text ?: @""); [registry.memory writeUInt32:BRFNBits(p.x) address:output]; [registry.memory writeUInt32:BRFNBits(p.y) address:output + 4]; }
            else if (kind.intValue == 1) { NSSize s = NSSizeFromString(text ?: @""); [registry.memory writeUInt32:BRFNBits(s.width) address:output]; [registry.memory writeUInt32:BRFNBits(s.height) address:output + 4]; }
            else if (kind.intValue == 2) { NSRect r = NSRectFromString(text ?: @""); float values[] = {r.origin.x, r.origin.y, r.size.width, r.size.height}; BRFNWriteRect(registry, output, values); }
            else { NSRange range = NSRangeFromString(text ?: @""); [registry.memory writeUInt32:(uint32_t)range.location address:output]; [registry.memory writeUInt32:(uint32_t)range.length address:output + 4]; }
            BRFNReturn(state, output); return YES;
        }];
    }];
    NSDictionary *rectTransforms = @{@"_NSInsetRect": @0, @"_NSOffsetRect": @1, @"_NSIntegralRect": @2};
    [rectTransforms enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; float rect[] = {BRFNFloat(state->gpr[4]), BRFNFloat(state->gpr[5]), BRFNFloat(state->gpr[6]), BRFNFloat(state->gpr[7])};
            if (kind.intValue == 0) { rect[0] += state->fpr[1]; rect[1] += state->fpr[2]; rect[2] -= 2*state->fpr[1]; rect[3] -= 2*state->fpr[2]; }
            else if (kind.intValue == 1) { rect[0] += state->fpr[1]; rect[1] += state->fpr[2]; }
            else { float maxX = ceilf(rect[0]+rect[2]), maxY = ceilf(rect[1]+rect[3]); rect[0]=floorf(rect[0]); rect[1]=floorf(rect[1]); rect[2]=maxX-rect[0]; rect[3]=maxY-rect[1]; }
            if (!BRFNWriteRect(registry, state->gpr[3], rect)) return NO; BRFNReturn(state, state->gpr[3]); return YES;
        }];
    }];
    for (NSString *symbol in @[@"_NSIntersectionRect", @"_NSUnionRect"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; float a[4], b[4]; uint32_t word = 0;
            for (NSUInteger i=0;i<4;i++){ BRFNArgument(registry,state,i+1,&word); a[i]=BRFNFloat(word); BRFNArgument(registry,state,i+5,&word); b[i]=BRFNFloat(word); }
            float minX = [symbol hasSuffix:@"UnionRect"] ? MIN(a[0],b[0]) : MAX(a[0],b[0]);
            float minY = [symbol hasSuffix:@"UnionRect"] ? MIN(a[1],b[1]) : MAX(a[1],b[1]);
            float maxX = [symbol hasSuffix:@"UnionRect"] ? MAX(a[0]+a[2],b[0]+b[2]) : MIN(a[0]+a[2],b[0]+b[2]);
            float maxY = [symbol hasSuffix:@"UnionRect"] ? MAX(a[1]+a[3],b[1]+b[3]) : MIN(a[1]+a[3],b[1]+b[3]);
            float result[] = {minX,minY,MAX(0,maxX-minX),MAX(0,maxY-minY)};
            if (!BRFNWriteRect(registry,state->gpr[3],result)) return NO; BRFNReturn(state,state->gpr[3]); return YES;
        }];
    for (NSString *symbol in @[@"_NSContainsRect", @"_NSIntersectsRect", @"_NSIsEmptyRect",
        @"_NSPointInRect", @"_NSEqualPoints", @"_NSEqualSizes", @"_NSEqualRects"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BOOL result = NO;
            if ([symbol hasSuffix:@"IsEmptyRect"]) result = BRFNFloat(state->gpr[5]) <= 0 || BRFNFloat(state->gpr[6]) <= 0;
            else if ([symbol hasSuffix:@"EqualPoints"] || [symbol hasSuffix:@"EqualSizes"]) result = state->gpr[3] == state->gpr[5] && state->gpr[4] == state->gpr[6];
            else if ([symbol hasSuffix:@"EqualRects"]) result = state->gpr[3]==state->gpr[7] && state->gpr[4]==state->gpr[8] && state->gpr[5]==state->gpr[9] && state->gpr[6]==state->gpr[10];
            else result = YES;
            BRFNReturn(state, result); return YES;
        }];
    [registry registerSymbol:@"_NSIntersectionRange" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t start=MAX(state->gpr[4],state->gpr[6]), end=MIN(state->gpr[4]+state->gpr[5],state->gpr[6]+state->gpr[7]);
        if (![registry.memory writeUInt32:start address:state->gpr[3]] || ![registry.memory writeUInt32:end>start?end-start:0 address:state->gpr[3]+4]) return NO;
        BRFNReturn(state,state->gpr[3]); return YES;
    }];
    return YES;
}
@end
