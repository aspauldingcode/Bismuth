#import <Foundation/Foundation.h>
#import "BRPPCResolveRegistry.h"

NS_ASSUME_NONNULL_BEGIN


@interface BRPPCObjectiveCResolve : NSObject <BRPPCResolveExtension>
- (instancetype)initWithApplicationBundleURL:(nullable NSURL *)bundleURL;
- (void)attachCPU:(BRPowerPC32 *)cpu;
- (BOOL)performHostCallbackScopeWithState:(BRPPCState *)state
                                    block:(BOOL (^)(NSError **error))block
                                    error:(NSError **)error;
- (NSArray *)hostObjectsSnapshot;
@end

NS_ASSUME_NONNULL_END
