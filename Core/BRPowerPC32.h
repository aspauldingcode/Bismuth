#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint8_t, BRPPCStopReason) {
    BRPPCStopNone,
    BRPPCStopHalt,
    BRPPCStopTrap,
    BRPPCStopSystemCall,
  BRPPCStopFault,
  BRPPCStopIllegalInstruction,
  BRPPCStopPrivilegedInstruction,
  BRPPCStopFloatingPointException,
};

typedef NS_ENUM(uint8_t, BRPPCCPUModel) {
    BRPPCCPUCommon,
    BRPPCCPU601,
    BRPPCCPUG4,
};

typedef struct __attribute__((aligned(16))) { uint8_t byte[16]; } BRPPCVector;

typedef struct {
    uint32_t gpr[32];
    double fpr[32];
    BRPPCVector vr[32];
    uint32_t pc, lr, ctr, cr, xer, mq, fpscr, vscr, vrsave, msr;
    uint32_t srr0, srr1;
    uint64_t timeBase;
    BOOL reservationValid;
    uint32_t reservationAddress;
} BRPPCState;

typedef void (^BRPPCInstructionCacheInvalidationHandler)(uint32_t address, size_t length);

@protocol BRPPCMemory <NSObject>
- (BOOL)readBytes:(void *)destination address:(uint32_t)address length:(size_t)length;
- (BOOL)writeBytes:(const void *)source address:(uint32_t)address length:(size_t)length;
@optional
- (void)synchronizeInstructionCacheAtAddress:(uint32_t)address;
- (void)setInstructionCacheInvalidationHandler:
    (nullable BRPPCInstructionCacheInvalidationHandler)handler;
@end

@interface BRPPCLinearMemory : NSObject <BRPPCMemory>
@property(nonatomic, readonly) uint32_t baseAddress;
@property(nonatomic, readonly) NSMutableData *data;
- (instancetype)initWithBaseAddress:(uint32_t)baseAddress size:(NSUInteger)size;
@end

typedef void (^BRPPCSystemCallHandler)(BRPPCState *state, BRPPCStopReason *stop);
typedef void (^BRPPCSupervisorHandler)(uint32_t instruction, BRPPCState *state,
                                      id<BRPPCMemory> memory, BRPPCStopReason *stop);

@protocol BRPPCPrivilegeAuthorizing <NSObject>

- (BOOL)authorizeInstruction:(uint32_t)instruction
                 description:(NSString *)description
                       error:(NSError * _Nullable * _Nullable)error;
@end


@interface BRPPCSecurityAuthorizer : NSObject <BRPPCPrivilegeAuthorizing>
@end


@interface BRPowerPC32 : NSObject
@property(nonatomic) BRPPCCPUModel model;
@property(nonatomic) BRPPCState state;
@property(nonatomic, readonly) uint32_t programCounter;


@property(nonatomic, readonly) BRPPCState *mutableState;
@property(nonatomic, readonly) BRPPCStopReason stopReason;
@property(nonatomic, copy, nullable) BRPPCSystemCallHandler systemCallHandler;
@property(nonatomic, copy, nullable) BRPPCSupervisorHandler supervisorHandler;
@property(nonatomic, strong, nullable) id<BRPPCPrivilegeAuthorizing> privilegeAuthorizer;
- (instancetype)initWithMemory:(id<BRPPCMemory>)memory;
- (BRPPCStopReason)step;
- (BRPPCStopReason)runWithInstructionLimit:(uint64_t)limit;
- (BRPPCStopReason)runWithInstructionLimit:(uint64_t)limit
          stoppingBeforeProgramCounterFrom:(uint32_t)firstAddress
                                    through:(uint32_t)lastAddress;
- (BRPPCStopReason)runWithInstructionLimit:(uint64_t)limit
          stoppingBeforeProgramCounterFrom:(uint32_t)firstAddress
                                    through:(uint32_t)lastAddress
                   executedInstructionCount:(nullable uint64_t *)executedInstructionCount;
- (void)resetAtProgramCounter:(uint32_t)pc;
- (void)invalidateTranslationCache;
@end

NS_ASSUME_NONNULL_END
