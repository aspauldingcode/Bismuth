#import <Foundation/Foundation.h>
#import "../Core/BRPowerPC32.h"

@class BRPPCAddressSpace;
@class BRPPCMachOImage;
@class BRPowerPC32;

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^BRPPCResolvedCall)(BRPPCState *state, NSError **error);
typedef uint32_t (^BRPPCMissingSymbolResolver)(NSString *symbol, BOOL lazy,
                                               NSError **error);
typedef uint32_t (^BRPPCGuestAllocator)(uint32_t size, BOOL clear);
typedef void (^BRPPCGuestDeallocator)(uint32_t address);
typedef void (^BRPPCGuestHandleRegistrar)(uint32_t handle, uint32_t size);
typedef BOOL (^BRPPCGuestFSRefWriter)(NSURL *URL, uint32_t address);
typedef NSURL * _Nullable (^BRPPCGuestFSRefDecoder)(uint32_t address);
typedef id _Nullable (^BRPPCGuestObjectDecoder)(uint32_t address);
typedef uint32_t (^BRPPCGuestObjectEncoder)(id _Nullable object);
typedef NSData * _Nullable (^BRPPCGuestFormatRenderer)(uint32_t formatAddress,
    BRPPCState *state, NSUInteger firstArgumentGPR, NSError **error);
typedef NSData * _Nullable (^BRPPCGuestVAFormatRenderer)(uint32_t formatAddress,
    uint32_t argumentsAddress, NSError **error);

@protocol BRPPCResolveExtension <NSObject>
- (BOOL)installInRegistry:(id)registry error:(NSError **)error;
@end


@interface BRPPCResolveRegistry : NSObject
@property(nonatomic, readonly) BRPPCAddressSpace *memory;
@property(nonatomic, readonly) BRPPCMachOImage *image;
@property(nonatomic, copy, nullable) BRPPCMissingSymbolResolver missingSymbolResolver;
@property(nonatomic) uint32_t guestErrnoAddress;
@property(nonatomic, copy, nullable) BRPPCGuestAllocator guestAllocator;
@property(nonatomic, copy, nullable) BRPPCGuestDeallocator guestDeallocator;
@property(nonatomic, copy, nullable) BRPPCGuestHandleRegistrar guestHandleRegistrar;
@property(nonatomic, copy, nullable) BRPPCGuestFSRefWriter guestFSRefWriter;
@property(nonatomic, copy, nullable) BRPPCGuestFSRefDecoder guestFSRefDecoder;
@property(nonatomic, copy, nullable) BRPPCGuestObjectDecoder guestObjectDecoder;
@property(nonatomic, copy, nullable) BRPPCGuestObjectEncoder guestObjectEncoder;
@property(nonatomic, copy, nullable) BRPPCGuestFormatRenderer guestFormatRenderer;
@property(nonatomic, copy, nullable) BRPPCGuestVAFormatRenderer guestVAFormatRenderer;
@property(nonatomic, readonly) NSUInteger callbackDepth;
@property(nonatomic, readonly) uint32_t guestThreadReturnAddress;
- (instancetype)initWithMemory:(BRPPCAddressSpace *)memory image:(BRPPCMachOImage *)image;
- (uint32_t)registerSymbol:(NSString *)symbol handler:(BRPPCResolvedCall)handler;
- (BOOL)registerSymbol:(NSString *)symbol
             atAddress:(uint32_t)address
               handler:(BRPPCResolvedCall)handler
                 error:(NSError **)error;
- (uint32_t)addressForSymbol:(NSString *)symbol;
- (uint32_t)addressForSymbol:(NSString *)symbol lazy:(BOOL)lazy error:(NSError **)error;
- (BOOL)dispatchState:(BRPPCState *)state handled:(BOOL *)handled error:(NSError **)error;
- (BRPPCStopReason)runAttachedCPUWithInstructionLimit:(uint64_t)instructionLimit;
- (BRPPCStopReason)runAttachedCPUWithInstructionLimit:(uint64_t)instructionLimit
                              executedInstructionCount:(nullable uint64_t *)executedInstructionCount;
- (BOOL)installExtension:(id<BRPPCResolveExtension>)extension error:(NSError **)error;
- (void)attachCPU:(BRPowerPC32 *)cpu;
- (BOOL)executeGuestCallbackState:(BRPPCState *)state
                 instructionLimit:(uint64_t)instructionLimit
                            label:(NSString *)label
                            error:(NSError **)error;
- (BOOL)executeGuestThreadState:(BRPPCState *)state
               instructionLimit:(uint64_t)instructionLimit
                       completed:(BOOL *)completed
                           error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
