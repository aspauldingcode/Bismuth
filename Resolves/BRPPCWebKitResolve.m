#import "BRPPCWebKitResolve.h"

@implementation BRPPCWebKitResolve
- (instancetype)init { return [super initWithFrameworkName:@"WebKit"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    return YES;
}
@end
