#import <Foundation/Foundation.h>
#import "BRPPCResolveRegistry.h"

NS_ASSUME_NONNULL_BEGIN


@interface BRPPCDarwinResolve : NSObject <BRPPCResolveExtension>
@property(nonatomic, readonly) BOOL exitRequested;
@property(nonatomic, readonly) int exitStatus;
@property(nonatomic, readonly) BOOL lastGuestThreadSliceExecuted;
@property(nonatomic, copy, nullable) NSString *executablePath;
@property(nonatomic, copy, nullable) NSString *launcherPath;
- (BOOL)hasPendingSignals;
- (BOOL)deliverPendingSignalsToState:(BRPPCState *)state error:(NSError **)error;
- (BOOL)isMainThreadWaiting;
- (BOOL)serviceMainThreadWaitWithWorkerInstructionLimit:(uint64_t)instructionLimit
                                                   error:(NSError **)error;
- (BOOL)runGuestThreadSliceWithInstructionLimit:(uint64_t)instructionLimit
                                          error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
