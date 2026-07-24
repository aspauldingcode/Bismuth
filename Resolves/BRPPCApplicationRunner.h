#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BRPPCApplicationRunner : NSObject
@property(nonatomic, copy) NSArray<id> *additionalExtensions;
- (BOOL)runApplicationAtURL:(NSURL *)targetURL
                  arguments:(NSArray<NSString *> *)arguments
                 exitStatus:(int * _Nullable)exitStatus
                      error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
