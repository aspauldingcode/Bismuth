#import "BRPPCApplicationRunner.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import "BRPPCCocoaResolve.h"
#import "BRPPCCoreFoundationResolve.h"
#import "BRPPCDarwinResolve.h"
#import "BRPPCMachOLoader.h"
#import "BRPPCMathResolve.h"
#import "BRPPCNetworkResolve.h"
#import "BRPPCObjectiveCResolve.h"
#import "BRPPCResolveRegistry.h"
#import "BismuthScarlet.h"
#import "BRPPCAccelerateResolve.h"
#import "BRPPCAddressBookResolve.h"
#import "BRPPCAppKitResolve.h"
#import "BRPPCApplicationServicesResolve.h"
#import "BRPPCAudioResolve.h"
#import "BRPPCCarbonResolve.h"
#import "BRPPCCoreServicesResolve.h"
#import "BRPPCCoreVideoResolve.h"
#import "BRPPCDiscRecordingResolve.h"
#import "BRPPCFoundationResolve.h"
#import "BRPPCIOKitResolve.h"
#import "BRPPCOpenGLResolve.h"
#import "BRPPCOpenALResolve.h"
#import "BRPPCQTKitResolve.h"
#import "BRPPCQuartzCoreResolve.h"
#import "BRPPCQuartzResolve.h"
#import "BRPPCQuickTimeResolve.h"
#import "BRPPCSystemConfigurationResolve.h"
#import "BRPPCSecurityResolve.h"
#import "BRPPCWebKitResolve.h"
#import "../Core/BRPowerPC32.h"
#include <mach/mach_time.h>

static NSString * const BRPPCRunnerErrorDomain = @"theoderoy.Bismuth.Runner";

static void BRReturn(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

@implementation BRPPCApplicationRunner
- (BOOL)prepareArguments:(NSArray<NSString *> *)arguments forProcessEntry:(BOOL)processEntry
                  memory:(BRPPCAddressSpace *)memory state:(BRPPCState *)state
                   error:(NSError **)error {
    if (![memory mapAddress:BRPPCGuestProcessStackBase size:BRPPCGuestProcessStackSize
                 protection:BRPPCMemoryRead | BRPPCMemoryWrite
                       name:@"guest stack" error:error]) return NO;
    uint32_t cursor = BRPPCGuestProcessStackBase + BRPPCGuestProcessStackSize;
    NSMutableArray<NSNumber *> *addresses = [NSMutableArray array];
    for (NSString *argument in [arguments reverseObjectEnumerator]) {
        NSData *string = [argument dataUsingEncoding:NSUTF8StringEncoding];
        if (string.length + 1 > cursor - BRPPCGuestProcessStackBase) return NO;
        cursor -= (uint32_t)string.length + 1;
        uint8_t zero = 0;
        if (![memory writeBytes:string.bytes address:cursor length:string.length] ||
            ![memory writeBytes:&zero address:cursor + (uint32_t)string.length length:1]) return NO;
        [addresses addObject:@(cursor)];
    }
    cursor &= ~15u;
    uint32_t processWords = (uint32_t)addresses.count + 4;
    cursor -= (processEntry ? processWords : (uint32_t)addresses.count + 1) * 4;
    uint32_t argv = cursor + (processEntry ? 4 : 0);
    if (processEntry && ![memory writeUInt32:(uint32_t)addresses.count address:cursor]) return NO;
    NSUInteger argumentIndex = 0;
    for (NSNumber *argumentAddress in addresses.reverseObjectEnumerator) {
        if (![memory writeUInt32:argumentAddress.unsignedIntValue
                         address:argv + (uint32_t)argumentIndex * 4]) return NO;
        argumentIndex++;
    }
    if (![memory writeUInt32:0 address:argv + (uint32_t)addresses.count * 4]) return NO;
    if (processEntry) {
        uint32_t terminators = argv + ((uint32_t)addresses.count + 1) * 4;
        if (![memory writeUInt32:0 address:terminators] ||
            ![memory writeUInt32:0 address:terminators + 4]) return NO;
    } else {
        cursor = (cursor - 224) & ~15u;
    }
    state->gpr[1] = cursor;
    state->gpr[3] = (uint32_t)addresses.count;
    state->gpr[4] = argv;
    return YES;
}

- (BOOL)runApplicationAtURL:(NSURL *)targetURL arguments:(NSArray<NSString *> *)arguments
                  exitStatus:(int * _Nullable)exitStatus error:(NSError **)error {
    targetURL = targetURL.URLByStandardizingPath;
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:targetURL.path
                                              isDirectory:&isDirectory]) {
        if (error) *error = [NSError errorWithDomain:BRPPCRunnerErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Target does not exist: %@", targetURL.path]}];
        return NO;
    }
    NSURL *bundleURL = nil;
    NSURL *executableURL = targetURL;
    if (isDirectory) {
        NSBundle *bundle = [NSBundle bundleWithURL:targetURL];
        NSString *executablePath = bundle.executablePath;
        if (!executablePath.length) {
            if (error) *error = [NSError errorWithDomain:BRPPCRunnerErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey: @"Application bundle has no executable."}];
            return NO;
        }
        bundleURL = targetURL;
        executableURL = [NSURL fileURLWithPath:executablePath];
    }
    BRPPCAddressSpace *memory = [BRPPCAddressSpace new];
    BRPPCMachOLoader *loader = [BRPPCMachOLoader new];
    BRPPCMachOImage *image = [loader loadURL:executableURL intoMemory:memory error:error];
    if (!image) return NO;
    uint32_t launchAddress = image.mainAddress ?: image.entryPoint;
    if (!launchAddress) {
        if (error) *error = [NSError errorWithDomain:BRPPCRunnerErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey:
                @"PowerPC executable has neither a _main symbol nor a Mach-O entry point."}];
        return NO;
    }

    BRPPCResolveRegistry *registry = [[BRPPCResolveRegistry alloc] initWithMemory:memory image:image];
    BRPPCDarwinResolve *darwin = [BRPPCDarwinResolve new];
    darwin.executablePath = executableURL.path;
    darwin.launcherPath = [NSProcessInfo.processInfo.arguments.firstObject
        stringByStandardizingPath];
    BRPPCObjectiveCResolve *objectiveC =
        [[BRPPCObjectiveCResolve alloc] initWithApplicationBundleURL:bundleURL];
    BRPPCCocoaResolve *cocoa = [[BRPPCCocoaResolve alloc] initWithApplicationBundleURL:bundleURL];
    cocoa.objectiveCBridge = objectiveC;
    BRPPCCoreFoundationResolve *coreFoundation = [BRPPCCoreFoundationResolve new];
    BRPPCMathResolve *math = [BRPPCMathResolve new];
    BRPPCNetworkResolve *network = [BRPPCNetworkResolve new];
    BismuthScarlet *scarlet = [BismuthScarlet new];
    NSArray<id<BRPPCResolveExtension>> *builtins = @[
        darwin, objectiveC, coreFoundation, math, network,
        [BRPPCFoundationResolve new], [BRPPCAppKitResolve new],
        [BRPPCCoreServicesResolve new], [BRPPCApplicationServicesResolve new],
        [BRPPCCarbonResolve new], [BRPPCQuickTimeResolve new], [BRPPCQTKitResolve new],
        [BRPPCCoreVideoResolve new], [BRPPCAudioResolve new],
        [BRPPCQuartzCoreResolve new], [BRPPCQuartzResolve new],
        [BRPPCOpenGLResolve new], [BRPPCOpenALResolve new], [BRPPCAccelerateResolve new], [BRPPCIOKitResolve new],
        [BRPPCWebKitResolve new], [BRPPCDiscRecordingResolve new],
        [BRPPCAddressBookResolve new], [BRPPCSystemConfigurationResolve new],
        [BRPPCSecurityResolve new],
        cocoa, scarlet
    ];
    for (id<BRPPCResolveExtension> extension in builtins)
        if (![registry installExtension:extension error:error]) return NO;
    for (id extension in self.additionalExtensions)
        if (![registry installExtension:extension error:error]) return NO;
    BRPPCMachOSection *dyld = [image sectionInSegment:@"__DATA" name:@"__dyld"];
    if (dyld && dyld.size >= 8) {
        uint32_t binder = [registry registerSymbol:@"__dyld_stub_binding_helper"
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                if (callError) *callError = [NSError errorWithDomain:BRPPCRunnerErrorDomain code:6
                    userInfo:@{NSLocalizedDescriptionKey:
                        @"A lazy Mach-O import reached the dyld binding helper after eager binding."}];
                (void)state;
                return NO;
            }];
        uint32_t noOp = [registry registerSymbol:@"__dyld_noop"
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                (void)callError;
                BRReturn(state, 0);
                return YES;
            }];
        __weak BRPPCResolveRegistry *weakRegistry = registry;
        uint32_t lookup = [registry registerSymbol:@"__dyld_func_lookup"
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                BRPPCResolveRegistry *strongRegistry = weakRegistry;
                NSString *name = [strongRegistry.memory readCStringAtAddress:state->gpr[3]
                                                               maximumLength:1024];
                if (!name.length || !state->gpr[4]) {
                    BRReturn(state, 0);
                    return YES;
                }
                uint32_t address = [strongRegistry addressForSymbol:name];
                if (!address) address = [strongRegistry addressForSymbol:
                    [name hasPrefix:@"_"] ? name : [@"_" stringByAppendingString:name]];
                if (!address && ([name containsString:@"initializer"] ||
                                 [name containsString:@"terminator"])) address = noOp;
                if (address && ![strongRegistry.memory writeUInt32:address address:state->gpr[4]]) {
                    if (callError) *callError = [NSError errorWithDomain:BRPPCRunnerErrorDomain code:7
                        userInfo:@{NSLocalizedDescriptionKey:
                            @"dyld function lookup received an invalid result pointer."}];
                    return NO;
                }
                BRReturn(state, address != 0);
                return YES;
            }];
        if (![memory writeUInt32:binder address:dyld.address] ||
            ![memory writeUInt32:lookup address:dyld.address + 4]) return NO;
    }
    if (![loader bindImage:image registry:registry error:error]) return NO;

    BRPowerPC32 *cpu = [[BRPowerPC32 alloc] initWithMemory:memory];
    cpu.model = BRPPCCPUG4;
    [objectiveC attachCPU:cpu];
    BOOL processEntry = !image.mainAddress;
    [cpu resetAtProgramCounter:launchAddress];
    BRPPCState state = cpu.state;
    NSArray *guestArguments = arguments.count ? arguments : @[targetURL.path];
    if (![self prepareArguments:guestArguments forProcessEntry:processEntry
                         memory:memory state:&state error:error]) return NO;
    if (!processEntry) state.lr = [registry addressForSymbol:@"_exit"];
    cpu.state = state;
    BRPPCState *cpuState = cpu.mutableState;

    uint64_t workerInstructionQuantum = 16384;
    mach_timebase_info_data_t workerTimebase;
    mach_timebase_info(&workerTimebase);
    const double workerTargetNanoseconds = 1000000.0;

    while (!darwin.exitRequested) {
      __strong NSError *iterationError = nil;
      BOOL iterationSucceeded = YES;
      BOOL mainWaitServiced = NO;
      @autoreleasepool {
        do {
            if ([darwin hasPendingSignals] &&
                ![darwin deliverPendingSignalsToState:cpuState error:&iterationError]) {
                iterationSucceeded = NO;
                break;
            }
            if (darwin.exitRequested) break;
            if ([darwin isMainThreadWaiting]) {
                uint64_t workerStart = mach_absolute_time();
                iterationSucceeded = [darwin
                    serviceMainThreadWaitWithWorkerInstructionLimit:workerInstructionQuantum
                    error:&iterationError];
                uint64_t workerEnd = mach_absolute_time();
                if (iterationSucceeded && darwin.lastGuestThreadSliceExecuted) {
                    double elapsedNanoseconds = (double)(workerEnd - workerStart) *
                        workerTimebase.numer / workerTimebase.denom;
                    if (elapsedNanoseconds > 0.0) {
                        double desired = workerInstructionQuantum *
                            workerTargetNanoseconds / elapsedNanoseconds;
                        desired = MIN(MAX(desired, workerInstructionQuantum * 0.5),
                                      workerInstructionQuantum * 2.0);
                        desired = MIN(MAX(desired, 256.0), 1048576.0);
                        workerInstructionQuantum = (uint64_t)(workerInstructionQuantum * 0.75 +
                                                              desired * 0.25);
                    }
                }
                mainWaitServiced = YES;
                break;
            }
            BOOL handled = NO;
            if (![registry dispatchState:cpuState handled:&handled error:&iterationError]) {
                iterationSucceeded = NO;
                break;
            }
            uint64_t mainProgress = workerInstructionQuantum;
            if (!handled) {
                mainProgress = 0;
                BRPPCStopReason stop = [registry runAttachedCPUWithInstructionLimit:4096
                                                          executedInstructionCount:&mainProgress];
                if (stop != BRPPCStopNone) {
                    uint32_t instruction = 0;
                    [memory readUInt32:&instruction address:cpuState->pc];
                    iterationError = [NSError errorWithDomain:BRPPCRunnerErrorDomain code:4
                        userInfo:@{NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:@"PowerPC execution stopped at 0x%08x (instruction 0x%08x, reason %u; lr=0x%08x r1=0x%08x r2=0x%08x r3=0x%08x r4=0x%08x r5=0x%08x r6=0x%08x).",
                                                       cpuState->pc, instruction, stop, cpuState->lr, cpuState->gpr[1],
                                                       cpuState->gpr[2], cpuState->gpr[3], cpuState->gpr[4],
                                                       cpuState->gpr[5], cpuState->gpr[6]]}];
                    iterationSucceeded = NO;
                    break;
                }
            }



            uint64_t workerStart = mach_absolute_time();
            iterationSucceeded = [darwin
                runGuestThreadSliceWithInstructionLimit:MAX(mainProgress, UINT64_C(1))
                error:&iterationError];
            uint64_t workerEnd = mach_absolute_time();
            if (iterationSucceeded && darwin.lastGuestThreadSliceExecuted && handled) {
                double elapsedNanoseconds = (double)(workerEnd - workerStart) *
                    workerTimebase.numer / workerTimebase.denom;
                if (elapsedNanoseconds > 0.0) {
                    double desired = workerInstructionQuantum *
                        workerTargetNanoseconds / elapsedNanoseconds;
                    double lower = workerInstructionQuantum * 0.5;
                    double upper = workerInstructionQuantum * 2.0;
                    desired = MIN(MAX(desired, lower), upper);
                    desired = MIN(MAX(desired, 256.0), 1048576.0);
                    workerInstructionQuantum = (uint64_t)(workerInstructionQuantum * 0.75 +
                                                          desired * 0.25);
                }
            }
        } while (NO);
      }
      if (!iterationSucceeded) {
          if (error) *error = iterationError;
          return NO;
      }
      if (mainWaitServiced) continue;
    }
    if (getenv("BISMUTH_RUNNER_TRACE"))
        fprintf(stderr, "guest stopped status=%d pc=0x%08x\n",
                darwin.exitStatus, cpuState->pc);
    if (exitStatus) *exitStatus = darwin.exitStatus;
    return YES;
}
@end
