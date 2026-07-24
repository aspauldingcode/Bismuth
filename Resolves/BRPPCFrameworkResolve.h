#import "BRPPCResolveRegistry.h"

NS_ASSUME_NONNULL_BEGIN



@interface BRPPCFrameworkResolve : NSObject <BRPPCResolveExtension>
@property(nonatomic, readonly) NSString *frameworkName;
- (instancetype)initWithFrameworkName:(NSString *)frameworkName NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry
                                    error:(NSError **)error;
- (nullable void *)openFramework;
- (void)registerZeroFunction:(NSString *)symbol registry:(BRPPCResolveRegistry *)registry;
- (void)registerZeroFunctions:(NSArray<NSString *> *)symbols
                     registry:(BRPPCResolveRegistry *)registry;
- (BOOL)registerStringConstant:(NSString *)symbol value:(NSString *)value
                       registry:(BRPPCResolveRegistry *)registry error:(NSError **)error;
- (BOOL)registerStringConstants:(NSArray<NSString *> *)symbols
                        registry:(BRPPCResolveRegistry *)registry error:(NSError **)error;
- (BOOL)registerWordConstant:(NSString *)symbol value:(uint32_t)value
                     registry:(BRPPCResolveRegistry *)registry error:(NSError **)error;
- (BOOL)registerDataConstant:(NSString *)symbol data:(NSData *)data alignment:(uint32_t)alignment
                     registry:(BRPPCResolveRegistry *)registry error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
