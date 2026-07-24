#import <AppKit/AppKit.h>
#import "BRPPCResolveRegistry.h"

NS_ASSUME_NONNULL_BEGIN

@class BRPPCObjectiveCResolve;


@interface BRPPCCocoaResolve : NSObject <BRPPCResolveExtension>
- (instancetype)initWithApplicationBundleURL:(nullable NSURL *)bundleURL;
@property(nonatomic, weak, nullable) BRPPCObjectiveCResolve *objectiveCBridge;
@end

NS_ASSUME_NONNULL_END
