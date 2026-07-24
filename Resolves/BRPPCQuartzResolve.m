#import "BRPPCQuartzResolve.h"
#import "BRPPCAddressSpace.h"

@implementation BRPPCQuartzResolve
- (instancetype)init { return [super initWithFrameworkName:@"Quartz"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if (![self registerStringConstant:@"_QCCompositionAttributeNameKey"
        value:@"QCCompositionAttributeNameKey" registry:registry error:error]) return NO;
    [self registerZeroFunction:@"_QCRendererRelease" registry:registry];
    [registry registerSymbol:@"_QCCompositionFromFile" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *path = [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:PATH_MAX];
        NSData *composition = path.length ? [NSData dataWithContentsOfFile:path] : nil;
        state->gpr[3] = composition && registry.guestObjectEncoder ? registry.guestObjectEncoder(composition) : 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_QCPatchFromComposition" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id composition = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        state->gpr[3] = composition && registry.guestObjectEncoder ? registry.guestObjectEncoder(composition) : 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_QCGLExtensionSupported" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:1024];
        NSSet *baseline = [NSSet setWithArray:@[@"GL_ARB_multitexture", @"GL_ARB_texture_rectangle",
            @"GL_EXT_framebuffer_object", @"GL_EXT_texture_rectangle", @"GL_APPLE_client_storage",
            @"GL_APPLE_ycbcr_422"]];
        state->gpr[3] = [baseline containsObject:name]; state->pc = state->lr; return YES;
    }];
    return YES;
}
@end
