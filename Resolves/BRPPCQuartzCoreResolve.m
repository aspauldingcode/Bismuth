#import "BRPPCQuartzCoreResolve.h"
#import "BRPPCAddressSpace.h"
#include <time.h>

static void BRQCReturn(BRPPCState *state, uint32_t value) { state->gpr[3] = value; state->pc = state->lr; }

static BOOL BRQCWriteTransform(BRPPCResolveRegistry *registry, uint32_t address, const float *values) {
    for (NSUInteger i = 0; i < 16; i++) { uint32_t bits = 0; memcpy(&bits, values + i, 4);
        if (![registry.memory writeUInt32:bits address:address + (uint32_t)i * 4]) return NO; }
    return YES;
}

@implementation BRPPCQuartzCoreResolve
- (instancetype)init { return [super initWithFrameworkName:@"QuartzCore"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if (![self registerStringConstants:@[@"_kCIAttributeDisplayName",
        @"_kCIAttributeFilterDisplayName", @"_kCIContextOutputColorSpace",
        @"_kCIContextParametricColorMatching", @"_kCIContextWorkingFormat"]
        registry:registry error:error]) return NO;
    if (![self registerWordConstant:@"_kCIFormatARGB8" value:0 registry:registry error:error] ||
        ![self registerWordConstant:@"_kCIFormatRGBA8" value:1 registry:registry error:error]) return NO;
    if (![self registerStringConstants:@[@"_kCAAlignmentCenter", @"_kCAFillModeBoth",
        @"_kCATransactionDisableActions"] registry:registry error:error]) return NO;
    float identity[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
    uint8_t identityBytes[64];
    for (NSUInteger i = 0; i < 16; i++) { uint32_t bits = 0; memcpy(&bits, identity + i, 4);
        identityBytes[i * 4] = bits >> 24; identityBytes[i * 4 + 1] = bits >> 16;
        identityBytes[i * 4 + 2] = bits >> 8; identityBytes[i * 4 + 3] = bits; }
    if (![self registerDataConstant:@"_CATransform3DIdentity"
        data:[NSData dataWithBytes:identityBytes length:sizeof(identityBytes)] alignment:4
        registry:registry error:error]) return NO;
    [self registerZeroFunctions:@[@"_CATransactionFlush", @"_CATransactionBegin",
        @"_CATransactionCommit", @"_CATransactionLock", @"_CATransactionUnlock"] registry:registry];
    [registry registerSymbol:@"_CACurrentMediaTime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        state->fpr[1] = now.tv_sec + now.tv_nsec / 1000000000.0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CATransform3DMakeScale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float result[16] = {0}; result[0] = state->fpr[1]; result[5] = state->fpr[2];
        result[10] = state->fpr[3]; result[15] = 1;
        if (!BRQCWriteTransform(registry, state->gpr[3], result)) return NO;
        BRQCReturn(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_CATransform3DMakeRotation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float angle = state->fpr[1], x = state->fpr[2], y = state->fpr[3], z = state->fpr[4];
        float length = sqrtf(x*x + y*y + z*z); if (!length) { x = 0; y = 0; z = 1; } else { x /= length; y /= length; z /= length; }
        float c = cosf(angle), s = sinf(angle), t = 1-c;
        float result[16] = {t*x*x+c, t*x*y+s*z, t*x*z-s*y, 0,
            t*x*y-s*z, t*y*y+c, t*y*z+s*x, 0, t*x*z+s*y, t*y*z-s*x, t*z*z+c, 0, 0, 0, 0, 1};
        if (!BRQCWriteTransform(registry, state->gpr[3], result)) return NO;
        BRQCReturn(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_CATransform3DRotate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQCReturn(state, state->gpr[3]); return YES;
    }];
    return YES;
}
@end
