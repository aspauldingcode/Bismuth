#import "BRPPCDiscRecordingResolve.h"

@implementation BRPPCDiscRecordingResolve
- (instancetype)init { return [super initWithFrameworkName:@"DiscRecording"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    [registry registerSymbol:@"_DRDeviceCopyDeviceForBSDName"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"__DRDeviceReadDVDLayerDescriptor"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; state->gpr[3] = UINT32_MAX; state->pc = state->lr; return YES;
        }];
    return YES;
}
@end
