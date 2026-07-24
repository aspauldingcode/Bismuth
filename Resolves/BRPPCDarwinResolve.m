#import "BRPPCDarwinResolve.h"
#import <AppKit/AppKit.h>
#import <mach/mach_time.h>
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import "BRPPCMachOLoader.h"
#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <time.h>
#include <utime.h>
#include <unistd.h>

extern char **environ;

static NSString * const BRPPCDarwinErrorDomain = @"theoderoy.Bismuth.darwin";
static const uint32_t BRPPCGuestErrnoAddress = BRPPCGuestDarwinDataBase;
static const uint32_t BRPPCGuestStdinAddress = BRPPCGuestDarwinDataBase + 0x10;
static const uint32_t BRPPCGuestStdoutAddress = BRPPCGuestDarwinDataBase + 0x14;
static const uint32_t BRPPCGuestStderrAddress = BRPPCGuestDarwinDataBase + 0x18;
static const uint16_t BRPPCGuestDirent32Size = 264;
static const uint16_t BRPPCGuestDirent64Size = 1048;
static const size_t BRPPCGuestDirent32NameCapacity = 255;
static volatile sig_atomic_t BRPPCPendingSignals[NSIG];
static volatile sig_atomic_t BRPPCHasPendingSignals;

static FILE *BRPPCIOTraceStream(void) {
    static FILE *stream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *path = getenv("BISMUTH_IO_TRACE_FILE");
        if (path && *path) stream = fopen(path, "a");
        if (stream) setvbuf(stream, NULL, _IOLBF, 0);
    });
    return stream;
}

static void BRPPCDeferredSignalHandler(int signalNumber) {
    if (signalNumber > 0 && signalNumber < NSIG) {
        BRPPCPendingSignals[signalNumber] = 1;
        BRPPCHasPendingSignals = 1;
    }
}

static BOOL ConfigureHostSignal(int signalNumber, uint32_t guestHandler) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    sigemptyset(&action.sa_mask);
    action.sa_handler = guestHandler == 1 ? SIG_IGN : BRPPCDeferredSignalHandler;
    return sigaction(signalNumber, &action, NULL) == 0;
}

@interface BRPPCGuestDirectory : NSObject
@property(nonatomic) DIR *directory;
@property(nonatomic) uint32_t guestEntryAddress;
@end
@implementation BRPPCGuestDirectory
@end

@interface BRPPCDarwinResolve ()
@property(nonatomic) BOOL exitRequested;
@property(nonatomic) int exitStatus;
@property(nonatomic) BOOL lastGuestThreadSliceExecuted;
@property(nonatomic, weak) BRPPCResolveRegistry *registry;
@property(nonatomic) uint32_t heapBase;
@property(nonatomic) uint32_t heapNext;
@property(nonatomic) uint32_t heapEnd;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *allocations;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *freeBlocks;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *streams;
@property(nonatomic) uint32_t nextStreamHandle;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestDirectory *> *directories;
@property(nonatomic) uint32_t nextDirectoryHandle;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *signalHandlers;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *signalFlags;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *signalMasks;
@property(nonatomic) uint32_t blockedSignals;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *exitCallbacks;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *jumpContexts;
@property(nonatomic, strong) NSMutableArray<NSValue *> *dynamicImageHandles;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *threadResults;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *threadStates;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *threadStacks;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *threadOrder;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *blockedThreadStates;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *conditionWaiters;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *threadWaitDeadlines;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *threadWaitResults;
@property(nonatomic) NSUInteger nextThreadIndex;
@property(nonatomic) uint32_t nextThreadHandle;
@property(nonatomic, strong) NSNumber *currentThreadHandle;
@property(nonatomic) BOOL mainThreadWaiting;
@property(nonatomic) NSTimeInterval mainThreadWaitDeadline;
- (BOOL)writeUInt16:(uint16_t)value address:(uint32_t)address;
@end

@implementation BRPPCDarwinResolve

static const uint32_t BRPPCGuestThreadStackSize = 1024 * 1024;

static void Finish(BRPPCState *state, uint32_t result) {
    state->gpr[3] = result;
    state->pc = state->lr;
}

static void Finish64(BRPPCState *state, uint64_t result) {
    state->gpr[3] = (uint32_t)(result >> 32);
    state->gpr[4] = (uint32_t)result;
    state->pc = state->lr;
}

- (void)setGuestErrno:(int)value {
    [_registry.memory writeUInt32:(uint32_t)value address:BRPPCGuestErrnoAddress];
}

- (void)failState:(BRPPCState *)state errorNumber:(int)value {
    [self setGuestErrno:value];
    Finish(state, UINT32_MAX);
}

static BOOL SignalDefaultsToIgnore(int signalNumber) {
    return signalNumber == SIGCHLD || signalNumber == SIGURG || signalNumber == SIGWINCH ||
           signalNumber == SIGCONT || signalNumber == SIGIO;
}

- (BOOL)hasPendingSignals {
    return BRPPCHasPendingSignals != 0;
}

- (BOOL)deliverPendingSignalsToState:(BRPPCState *)state error:(NSError **)error {
    BRPPCHasPendingSignals = 0;
    for (int signalNumber = 1; signalNumber < NSIG; signalNumber++) {
        uint32_t bit = signalNumber <= 32 ? 1u << (signalNumber - 1) : 0;
        if (!BRPPCPendingSignals[signalNumber] || (bit && (_blockedSignals & bit))) continue;
        BRPPCPendingSignals[signalNumber] = 0;
        uint32_t handler = _signalHandlers[signalNumber].unsignedIntValue;
        if (handler == 1 || (!handler && SignalDefaultsToIgnore(signalNumber))) continue;
        if (!handler) {
            self.exitRequested = YES;
            self.exitStatus = 128 + signalNumber;
            return YES;
        }
        uint32_t flags = _signalFlags[signalNumber].unsignedIntValue;
        uint32_t savedMask = _blockedSignals;
        _blockedSignals |= _signalMasks[signalNumber].unsignedIntValue;
        if (!(flags & SA_NODEFER) && bit) _blockedSignals |= bit;
        BRPPCState callback = *state;
        callback.pc = handler; callback.gpr[12] = handler; callback.gpr[3] = (uint32_t)signalNumber;
        BOOL succeeded = [_registry executeGuestCallbackState:&callback instructionLimit:10000000
                                                        label:@"signal" error:error];
        _blockedSignals = savedMask;
        if (!succeeded) return NO;
        if (flags & SA_RESETHAND) {
            _signalHandlers[signalNumber] = @0; _signalFlags[signalNumber] = @0;
            _signalMasks[signalNumber] = @0;
        }
    }
    for (int signalNumber = 1; signalNumber < NSIG; signalNumber++)
        if (BRPPCPendingSignals[signalNumber]) {
            BRPPCHasPendingSignals = 1;
            break;
        }
    return YES;
}

- (BOOL)suspendCurrentGuestThreadState:(BRPPCState *)state
                         untilDeadline:(NSTimeInterval)deadline
                                result:(uint32_t)result {
    NSNumber *handle = self.currentThreadHandle;
    if (!handle) return NO;
    Finish(state, result);
    _blockedThreadStates[handle] = [NSValue valueWithBytes:state objCType:@encode(BRPPCState)];
    _threadWaitDeadlines[handle] = @(deadline);
    _threadWaitResults[handle] = @(result);
    state->pc = _registry.guestThreadReturnAddress;
    return YES;
}

- (void)suspendMainGuestThreadState:(BRPPCState *)state
                      untilDeadline:(NSTimeInterval)deadline
                             result:(uint32_t)result {
    Finish(state, result);
    self.mainThreadWaitDeadline = deadline;
    self.mainThreadWaiting = YES;
}

- (BOOL)isMainThreadWaiting {
    if (_mainThreadWaiting && [NSDate date].timeIntervalSince1970 >= _mainThreadWaitDeadline)
        _mainThreadWaiting = NO;
    return _mainThreadWaiting;
}

- (BOOL)serviceMainThreadWaitWithWorkerInstructionLimit:(uint64_t)instructionLimit
                                                   error:(NSError **)error {
    if (![self isMainThreadWaiting]) return YES;
    if (![self runGuestThreadSliceWithInstructionLimit:instructionLimit error:error]) return NO;
    NSTimeInterval remaining = _mainThreadWaitDeadline - [NSDate date].timeIntervalSince1970;
    if (remaining > 0) {


        uint64_t nanoseconds = (uint64_t)(MIN(remaining, 0.001) * 1000000000.0);
        struct timespec interval = {(time_t)(nanoseconds / 1000000000u),
                                    (long)(nanoseconds % 1000000000u)};
        nanosleep(&interval, NULL);
    }
    [self isMainThreadWaiting];
    return YES;
}

- (BOOL)runGuestThreadSliceWithInstructionLimit:(uint64_t)instructionLimit
                                          error:(NSError **)error {
    self.lastGuestThreadSliceExecuted = NO;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    for (NSNumber *handle in _threadWaitDeadlines.allKeys.copy) {
        if (_threadWaitDeadlines[handle].doubleValue > now) continue;
        NSValue *stored = _blockedThreadStates[handle];
        if (!stored) continue;
        BRPPCState resumed; [stored getValue:&resumed];
        resumed.gpr[3] = _threadWaitResults[handle].unsignedIntValue;
        _threadStates[handle] = [NSValue valueWithBytes:&resumed objCType:@encode(BRPPCState)];
        [_blockedThreadStates removeObjectForKey:handle];
        [_threadWaitDeadlines removeObjectForKey:handle];
        [_threadWaitResults removeObjectForKey:handle];
        for (NSMutableArray<NSNumber *> *waiters in _conditionWaiters.allValues)
            [waiters removeObject:handle];
        [_threadOrder addObject:handle];
    }
    if (!_threadOrder.count) return YES;
    if (_nextThreadIndex >= _threadOrder.count) _nextThreadIndex = 0;
    NSNumber *handle = _threadOrder[_nextThreadIndex];
    NSValue *stored = _threadStates[handle];
    if (!stored) {
        [_threadOrder removeObjectAtIndex:_nextThreadIndex];
        return YES;
    }
    BRPPCState threadState;
    [stored getValue:&threadState];
    BOOL completed = NO;
    self.lastGuestThreadSliceExecuted = YES;
    self.currentThreadHandle = handle;
    if (![_registry executeGuestThreadState:&threadState instructionLimit:instructionLimit
                                  completed:&completed error:error]) {
        self.currentThreadHandle = nil;
        return NO;
    }
    self.currentThreadHandle = nil;
    if (completed) {
        NSValue *blocked = _blockedThreadStates[handle];
        if (blocked) {
            [_threadStates removeObjectForKey:handle];
            [_threadOrder removeObjectAtIndex:_nextThreadIndex];
            return YES;
        }
        _threadResults[handle] = @(threadState.gpr[3]);
        [_threadStates removeObjectForKey:handle];
        NSNumber *stack = _threadStacks[handle];
        if (stack) [self freeAddress:stack.unsignedIntValue];
        [_threadStacks removeObjectForKey:handle];
        [_threadOrder removeObjectAtIndex:_nextThreadIndex];
    } else {
        _threadStates[handle] = [NSValue valueWithBytes:&threadState objCType:@encode(BRPPCState)];
        _nextThreadIndex = (_nextThreadIndex + 1) % _threadOrder.count;
    }
    return YES;
}

- (BOOL)runExitCallbacksForDSO:(uint32_t)dso state:(BRPPCState)outer error:(NSError **)error {
    for (NSInteger index = (NSInteger)_exitCallbacks.count - 1; index >= 0; index--) {
        NSDictionary<NSString *, NSNumber *> *record = _exitCallbacks[(NSUInteger)index];
        uint32_t recordDSO = record[@"dso"].unsignedIntValue;
        if (dso && recordDSO != dso) continue;
        [_exitCallbacks removeObjectAtIndex:(NSUInteger)index];
        BRPPCState callback = outer;
        callback.pc = record[@"function"].unsignedIntValue;
        callback.gpr[12] = callback.pc;
        callback.gpr[3] = record[@"argument"].unsignedIntValue;
        if (![_registry executeGuestCallbackState:&callback instructionLimit:10000000
                                             label:@"exit" error:error]) return NO;
    }
    return YES;
}

- (NSString *)stringAtAddress:(uint32_t)address errorNumber:(int *)errorNumber {
    if (!address) {
        if (errorNumber) *errorNumber = EFAULT;
        return nil;
    }
    NSString *string = [_registry.memory readCStringAtAddress:address maximumLength:PATH_MAX * 4];
    if (!string && errorNumber) *errorNumber = EFAULT;
    return string;
}

- (BOOL)readVariadicWord:(uint32_t *)value state:(BRPPCState *)state cursor:(NSUInteger *)cursor {
    NSUInteger position = (*cursor)++;
    if (position <= 10) { *value = state->gpr[position]; return YES; }
    return [_registry.memory readUInt32:value
                                 address:state->gpr[1] + 24 + (uint32_t)(position - 3) * 4];
}

static BOOL AppendPrintfBytes(NSMutableData *output, const char *format,
                              uint64_t integer, double floating, const char *string,
                              void *pointer, char conversion) {
    int length;
    if (strchr("di", conversion)) length = snprintf(NULL, 0, format, (long long)integer);
    else if (strchr("uoxX", conversion)) length = snprintf(NULL, 0, format, (unsigned long long)integer);
    else if (strchr("fFeEgGaA", conversion)) length = snprintf(NULL, 0, format, floating);
    else if (conversion == 's') length = snprintf(NULL, 0, format, string);
    else if (conversion == 'c') length = snprintf(NULL, 0, format, (int)integer);
    else if (conversion == 'p') length = snprintf(NULL, 0, format, pointer);
    else return NO;
    if (length < 0 || length > (1 << 24)) return NO;
    NSMutableData *piece = [NSMutableData dataWithLength:(NSUInteger)length + 1];
    if (strchr("di", conversion)) snprintf(piece.mutableBytes, piece.length, format, (long long)integer);
    else if (strchr("uoxX", conversion)) snprintf(piece.mutableBytes, piece.length, format, (unsigned long long)integer);
    else if (strchr("fFeEgGaA", conversion)) snprintf(piece.mutableBytes, piece.length, format, floating);
    else if (conversion == 's') snprintf(piece.mutableBytes, piece.length, format, string);
    else if (conversion == 'c') snprintf(piece.mutableBytes, piece.length, format, (int)integer);
    else snprintf(piece.mutableBytes, piece.length, format, pointer);
    [output appendBytes:piece.bytes length:(NSUInteger)length];
    return YES;
}

- (NSMutableData *)renderFormatAtAddress:(uint32_t)formatAddress state:(BRPPCState *)state
                                  cursor:(NSUInteger)cursor error:(NSError **)error {
    NSMutableData *output = [NSMutableData data];
    NSString *formatString = [_registry.memory readCStringAtAddress:formatAddress maximumLength:1u << 20];
    if (!formatString) goto badPointer;
    const char *format = formatString.UTF8String;
    for (NSUInteger i = 0; format[i];) {
        if (format[i] != '%') { [output appendBytes:&format[i] length:1]; i++; continue; }
        i++;
        if (format[i] == '%') { uint8_t percent = '%'; [output appendBytes:&percent length:1]; i++; continue; }
        NSMutableString *spec = [NSMutableString stringWithString:@"%"];
        BOOL left = NO;
        while (strchr("-+ #0'", format[i])) { if (format[i] == '-') left = YES; [spec appendFormat:@"%c", format[i++]]; }
        if (format[i] == '*') {
            uint32_t word = 0; if (![self readVariadicWord:&word state:state cursor:&cursor]) goto badPointer;
            int width = (int32_t)word;
            if (width < 0) { if (!left) [spec appendString:@"-"]; width = -width; }
            [spec appendFormat:@"%d", width]; i++;
        } else while (isdigit(format[i])) [spec appendFormat:@"%c", format[i++]];
        if (format[i] == '.') {
            i++;
            if (format[i] == '*') {
                uint32_t word = 0; if (![self readVariadicWord:&word state:state cursor:&cursor]) goto badPointer;
                int precision = (int32_t)word; i++;
                if (precision >= 0) [spec appendFormat:@".%d", precision];
            } else {
                [spec appendString:@"."];
                while (isdigit(format[i])) [spec appendFormat:@"%c", format[i++]];
            }
        }
        NSString *lengthType = @"";
        if (format[i] == 'h' && format[i + 1] == 'h') { lengthType = @"hh"; i += 2; }
        else if (format[i] == 'l' && format[i + 1] == 'l') { lengthType = @"ll"; i += 2; }
        else if (strchr("hljztL", format[i])) { lengthType = [NSString stringWithFormat:@"%c", format[i++]]; }
        char conversion = format[i++];
        if (!conversion || !strchr("diuoxXfFeEgGaAcspn@", conversion)) goto badFormat;
        if (conversion == 'n') {
            uint32_t address = 0; if (![self readVariadicWord:&address state:state cursor:&cursor]) goto badPointer;
            uint64_t count = output.length;
            if ([lengthType isEqualToString:@"ll"] || [lengthType isEqualToString:@"j"])
                { if (![self writeUInt64:count address:address]) goto badPointer; }
            else if ([lengthType isEqualToString:@"h"] || [lengthType isEqualToString:@"hh"]) {
                uint8_t bytes[2] = {(uint8_t)(count >> 8), (uint8_t)count};
                size_t size = [lengthType isEqualToString:@"hh"] ? 1 : 2;
                if (![_registry.memory writeBytes:size == 1 ? &bytes[1] : bytes address:address length:size]) goto badPointer;
            } else if (![_registry.memory writeUInt32:(uint32_t)count address:address]) goto badPointer;
            continue;
        }
        uint64_t integer = 0; double floating = 0; const char *string = NULL; void *pointer = NULL;
        NSString *objectString = nil; char renderedConversion = conversion;
        if (strchr("diuoxX", conversion)) {
            uint32_t high = 0, low = 0;
            BOOL wide = [lengthType isEqualToString:@"ll"] || [lengthType isEqualToString:@"j"];
            if (wide) {
                if (((cursor - 3) & 1) != 0) cursor++;
                if (![self readVariadicWord:&high state:state cursor:&cursor] ||
                    ![self readVariadicWord:&low state:state cursor:&cursor]) goto badPointer;
                integer = (uint64_t)high << 32 | low;
            } else {
                if (![self readVariadicWord:&low state:state cursor:&cursor]) goto badPointer;
                integer = low;
                if ([lengthType isEqualToString:@"hh"])
                    integer = strchr("di", conversion) ? (uint64_t)(int64_t)(int8_t)low : (uint8_t)low;
                else if ([lengthType isEqualToString:@"h"])
                    integer = strchr("di", conversion) ? (uint64_t)(int64_t)(int16_t)low : (uint16_t)low;
                else if (strchr("di", conversion)) integer = (uint64_t)(int64_t)(int32_t)low;
            }
            [spec appendFormat:@"ll%c", conversion];
        } else if (strchr("fFeEgGaA", conversion)) {
            if ([lengthType isEqualToString:@"L"]) goto badFormat;
            if (((cursor - 3) & 1) != 0) cursor++;
            uint32_t high = 0, low = 0;
            if (![self readVariadicWord:&high state:state cursor:&cursor] ||
                ![self readVariadicWord:&low state:state cursor:&cursor]) goto badPointer;
            uint64_t bits = (uint64_t)high << 32 | low; memcpy(&floating, &bits, 8);
            [spec appendFormat:@"%c", conversion];
        } else {
            uint32_t word = 0; if (![self readVariadicWord:&word state:state cursor:&cursor]) goto badPointer;
            if (conversion == 's') {
                NSString *value = [_registry.memory readCStringAtAddress:word maximumLength:1u << 20];
                if (!value) goto badPointer; string = value.UTF8String;
            } else if (conversion == '@') {
                id object = _registry.guestObjectDecoder ? _registry.guestObjectDecoder(word) : nil;
                objectString = object ? [object description] : @"(null)"; string = objectString.UTF8String;
                renderedConversion = 's';
            } else if (conversion == 'p') pointer = (void *)(uintptr_t)word;
            else integer = word;
            [spec appendFormat:@"%c", renderedConversion];
        }
        if (!AppendPrintfBytes(output, spec.UTF8String, integer, floating, string, pointer,
                               renderedConversion)) goto badFormat;
    }
    return output;
badPointer:
    if (error) *error = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:3
        userInfo:@{NSLocalizedDescriptionKey: @"Formatted output references invalid guest memory."}];
    return nil;
badFormat:
    if (error) *error = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:4
        userInfo:@{NSLocalizedDescriptionKey: @"Formatted output contains unsupported conversion."}];
    return nil;
}

- (BOOL)mapHeap:(NSError **)error {
    for (uint32_t candidate = BRPPCGuestHeapSearchStart;;
         candidate -= BRPPCGuestHeapSearchStride) {
        NSError *mappingError = nil;
        if ([_registry.memory mapAddress:candidate size:BRPPCGuestHeapSize
                              protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                    name:@"Darwin guest heap" error:&mappingError]) {
            _heapBase = candidate;
            _heapNext = candidate;
            _heapEnd = candidate + BRPPCGuestHeapSize;
            return YES;
        }
        if (candidate == BRPPCGuestHeapSearchEnd) break;
    }
    NSError *mappingError = nil;
    if ([_registry.memory mapAddress:BRPPCGuestHeapFallback size:BRPPCGuestHeapSize
                          protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                name:@"Darwin guest heap" error:&mappingError]) {
        _heapBase = BRPPCGuestHeapFallback;
        _heapNext = BRPPCGuestHeapFallback;
        _heapEnd = BRPPCGuestHeapFallback + BRPPCGuestHeapSize;
        return YES;
    }
    if (error) *error = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Cannot reserve a guest heap range."}];
    return NO;
}

- (uint32_t)allocateSize:(uint32_t)requested clear:(BOOL)clear {
    uint32_t size = MAX(requested, 1u);
    if (size > UINT32_MAX - 15) return 0;
    size = (size + 15) & ~15u;
    for (NSUInteger i = 0; i < _freeBlocks.count; i++) {
        NSDictionary *block = _freeBlocks[i];
        uint32_t blockSize = [block[@"size"] unsignedIntValue];
        if (blockSize < size) continue;
        uint32_t address = [block[@"address"] unsignedIntValue];
        [_freeBlocks removeObjectAtIndex:i];
        if (blockSize > size)
            [_freeBlocks addObject:@{@"address": @(address + size), @"size": @(blockSize - size)}];
        _allocations[@(address)] = @(size);
        if (clear) {
            NSMutableData *zeros = [NSMutableData dataWithLength:size];
            if (![_registry.memory writeBytes:zeros.bytes address:address length:size]) return 0;
        }
        return address;
    }
    if (_heapNext > _heapEnd || size > _heapEnd - _heapNext) return 0;
    uint32_t address = _heapNext;
    _heapNext += size;
    _allocations[@(address)] = @(size);
    if (clear) {
        NSMutableData *zeros = [NSMutableData dataWithLength:size];
        if (![_registry.memory writeBytes:zeros.bytes address:address length:size]) return 0;
    }
    return address;
}

- (void)freeAddress:(uint32_t)address {
    if (!address) return;
    NSNumber *size = _allocations[@(address)];
    if (!size) return;
    [_allocations removeObjectForKey:@(address)];
    [_freeBlocks addObject:@{@"address": @(address), @"size": size}];
}

- (BOOL)copyGuestAddress:(uint32_t)source toAddress:(uint32_t)destination length:(uint32_t)length {
    const uint32_t chunkSize = 1u << 20;
    NSMutableData *buffer = [NSMutableData dataWithLength:MIN(length, chunkSize)];
    if (destination > source && (uint64_t)destination < (uint64_t)source + length) {
        uint32_t remaining = length;
        while (remaining) {
            uint32_t chunk = MIN(remaining, chunkSize);
            uint32_t offset = remaining - chunk;
            if (![_registry.memory readBytes:buffer.mutableBytes address:source + offset length:chunk] ||
                ![_registry.memory writeBytes:buffer.bytes address:destination + offset length:chunk]) return NO;
            remaining = offset;
        }
        return YES;
    }
    uint32_t copied = 0;
    while (copied < length) {
        uint32_t chunk = MIN(length - copied, chunkSize);
        if (![_registry.memory readBytes:buffer.mutableBytes address:source + copied length:chunk] ||
            ![_registry.memory writeBytes:buffer.bytes address:destination + copied length:chunk]) return NO;
        copied += chunk;
    }
    return YES;
}

- (uint32_t)cStringLength:(uint32_t)address valid:(BOOL *)valid {
    uint32_t length = 0;
    uint8_t byte = 0;
    while ([_registry.memory readBytes:&byte address:address + length length:1]) {
        if (!byte) { if (valid) *valid = YES; return length; }
        if (length == UINT32_MAX) break;
        length++;
    }
    if (valid) *valid = NO;
    return 0;
}

- (void)registerAliases:(NSArray<NSString *> *)names handler:(BRPPCResolvedCall)handler {
    for (NSString *name in names) [_registry registerSymbol:name handler:handler];
}

- (BOOL)compareGuestFunction:(uint32_t)function
                       state:(BRPPCState)outerState
                     context:(uint32_t)context
                  contextual:(BOOL)contextual
                       first:(uint32_t)first
                      second:(uint32_t)second
                      result:(int32_t *)result
                       error:(NSError **)error {
    BRPPCState callback = outerState;
    callback.pc = function;
    callback.gpr[12] = function;
    if (contextual) {
        callback.gpr[3] = context;
        callback.gpr[4] = first;
        callback.gpr[5] = second;
    } else {
        callback.gpr[3] = first;
        callback.gpr[4] = second;
    }
    if (![_registry executeGuestCallbackState:&callback instructionLimit:10000000
                                         label:@"comparison" error:error]) return NO;
    *result = (int32_t)callback.gpr[3];
    return YES;
}

- (BOOL)swapGuestElement:(uint32_t)first second:(uint32_t)second size:(uint32_t)size {
    if (first == second || !size) return YES;
    NSMutableData *left = [NSMutableData dataWithLength:size];
    NSMutableData *right = [NSMutableData dataWithLength:size];
    return [_registry.memory readBytes:left.mutableBytes address:first length:size] &&
           [_registry.memory readBytes:right.mutableBytes address:second length:size] &&
           [_registry.memory writeBytes:right.bytes address:first length:size] &&
           [_registry.memory writeBytes:left.bytes address:second length:size];
}

- (BOOL)sortGuestBase:(uint32_t)base count:(uint32_t)count size:(uint32_t)size
              context:(uint32_t)context contextual:(BOOL)contextual comparator:(uint32_t)comparator
                 state:(BRPPCState)outerState error:(NSError **)error {
    if (!comparator || (!base && count) || (!size && count)) goto invalid;
    if ((uint64_t)base + (uint64_t)count * size > UINT32_MAX + 1ull) goto invalid;
    if (count < 2) return YES;
    uint8_t byte = 0;
    if (![_registry.memory readBytes:&byte address:base length:1] ||
        ![_registry.memory readBytes:&byte address:base + (count - 1) * size + size - 1 length:1])
        goto invalid;
    for (uint32_t gap = count / 2; gap; gap /= 2) {
        for (uint32_t i = gap; i < count; i++) {
            for (uint32_t j = i; j >= gap; j -= gap) {
                uint32_t left = base + (j - gap) * size;
                uint32_t right = base + j * size;
                int32_t comparison = 0;
                if (![self compareGuestFunction:comparator state:outerState context:context contextual:contextual
                                           first:left second:right result:&comparison error:error]) return NO;
                if (comparison <= 0) break;
                if (![self swapGuestElement:left second:right size:size]) goto invalid;
            }
        }
    }
    return YES;
invalid:
    if (error) *error = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:EFAULT
        userInfo:@{NSLocalizedDescriptionKey: @"Guest sort range or comparator is invalid."}];
    return NO;
}

- (uint32_t)registerStream:(FILE *)stream {
    if (!stream) return 0;
    for (NSNumber *key in _streams)
        if (_streams[key].pointerValue == stream) return key.unsignedIntValue;
    uint32_t handle = _nextStreamHandle;
    _nextStreamHandle += 4;
    _streams[@(handle)] = [NSValue valueWithPointer:stream];
    return handle;
}

- (FILE *)streamForHandle:(uint32_t)handle {
    return _streams[@(handle)].pointerValue;
}

- (uint32_t)registerDirectory:(DIR *)directory {
    if (!directory) return 0;
    uint32_t handle = _nextDirectoryHandle;
    _nextDirectoryHandle += 4;
    BRPPCGuestDirectory *record = [BRPPCGuestDirectory new];
    record.directory = directory;
    record.guestEntryAddress = [self allocateSize:BRPPCGuestDirent64Size clear:YES];
    if (!record.guestEntryAddress) { closedir(directory); return 0; }
    _directories[@(handle)] = record;
    return handle;
}

- (BOOL)writeDirectoryEntry:(const struct dirent *)entry record:(BRPPCGuestDirectory *)record
                     inode64:(BOOL)inode64 {
    uint32_t address = record.guestEntryAddress;
    size_t nameLength = strnlen(entry->d_name, sizeof(entry->d_name));
    if (inode64) {
        NSMutableData *zeros = [NSMutableData dataWithLength:BRPPCGuestDirent64Size];
        uint8_t type = entry->d_type;
        return [_registry.memory writeBytes:zeros.bytes address:address length:zeros.length] &&
               [self writeUInt64:(uint64_t)entry->d_ino address:address] &&
               [self writeUInt64:(uint64_t)entry->d_seekoff address:address + 8] &&
               [self writeUInt16:BRPPCGuestDirent64Size address:address + 16] &&
               [self writeUInt16:(uint16_t)nameLength address:address + 18] &&
               [_registry.memory writeBytes:&type address:address + 20 length:1] &&
               [_registry.memory writeBytes:entry->d_name address:address + 21 length:nameLength + 1];
    }
    NSMutableData *zeros = [NSMutableData dataWithLength:BRPPCGuestDirent32Size];
    uint8_t metadata[] = {entry->d_type, (uint8_t)MIN(nameLength, UINT8_MAX)};
    return [_registry.memory writeBytes:zeros.bytes address:address length:zeros.length] &&
           [_registry.memory writeUInt32:(uint32_t)entry->d_ino address:address] &&
           [self writeUInt16:BRPPCGuestDirent32Size address:address + 4] &&
           [_registry.memory writeBytes:metadata address:address + 6 length:sizeof(metadata)] &&
           [_registry.memory writeBytes:entry->d_name address:address + 8
                                  length:MIN(nameLength, BRPPCGuestDirent32NameCapacity) + 1];
}

- (BOOL)registerDataSymbol:(NSString *)symbol address:(uint32_t)address error:(NSError **)error {
    return [_registry registerSymbol:symbol atAddress:address
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)state;
            if (callError) *callError = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"%@ is data, not callable code.", symbol]}];
            return NO;
        } error:error];
}

- (BOOL)writeUInt64:(uint64_t)value address:(uint32_t)address {
    return [_registry.memory writeUInt32:(uint32_t)(value >> 32) address:address] &&
           [_registry.memory writeUInt32:(uint32_t)value address:address + 4];
}

- (BOOL)writeUInt16:(uint16_t)value address:(uint32_t)address {
    uint8_t bytes[] = {(uint8_t)(value >> 8), (uint8_t)value};
    return [_registry.memory writeBytes:bytes address:address length:sizeof(bytes)];
}

- (BOOL)writeTimespec:(struct timespec)value address:(uint32_t)address {
    return [_registry.memory writeUInt32:(uint32_t)value.tv_sec address:address] &&
           [_registry.memory writeUInt32:(uint32_t)value.tv_nsec address:address + 4];
}

- (BOOL)writeStat:(const struct stat *)status address:(uint32_t)address inode64:(BOOL)inode64 {
    NSMutableData *zeros = [NSMutableData dataWithLength:inode64 ? 112 : 96];
    if (![_registry.memory writeBytes:zeros.bytes address:address length:zeros.length]) return NO;
    uint32_t modeAndLinks = (uint32_t)(status->st_mode & UINT16_MAX) << 16 |
                            (uint32_t)(status->st_nlink & UINT16_MAX);
    if (!inode64) {
        return [_registry.memory writeUInt32:(uint32_t)status->st_dev address:address] &&
               [_registry.memory writeUInt32:(uint32_t)status->st_ino address:address + 4] &&
               [_registry.memory writeUInt32:modeAndLinks address:address + 8] &&
               [_registry.memory writeUInt32:status->st_uid address:address + 12] &&
               [_registry.memory writeUInt32:status->st_gid address:address + 16] &&
               [_registry.memory writeUInt32:(uint32_t)status->st_rdev address:address + 20] &&
               [self writeTimespec:status->st_atimespec address:address + 24] &&
               [self writeTimespec:status->st_mtimespec address:address + 32] &&
               [self writeTimespec:status->st_ctimespec address:address + 40] &&
               [self writeUInt64:(uint64_t)status->st_size address:address + 48] &&
               [self writeUInt64:(uint64_t)status->st_blocks address:address + 56] &&
               [_registry.memory writeUInt32:(uint32_t)status->st_blksize address:address + 64] &&
               [_registry.memory writeUInt32:status->st_flags address:address + 68] &&
               [_registry.memory writeUInt32:status->st_gen address:address + 72];
    }
    return [_registry.memory writeUInt32:(uint32_t)status->st_dev address:address] &&
           [_registry.memory writeUInt32:modeAndLinks address:address + 4] &&
           [self writeUInt64:status->st_ino address:address + 8] &&
           [_registry.memory writeUInt32:status->st_uid address:address + 16] &&
           [_registry.memory writeUInt32:status->st_gid address:address + 20] &&
           [_registry.memory writeUInt32:(uint32_t)status->st_rdev address:address + 24] &&
           [self writeTimespec:status->st_atimespec address:address + 28] &&
           [self writeTimespec:status->st_mtimespec address:address + 36] &&
           [self writeTimespec:status->st_ctimespec address:address + 44] &&
           [self writeTimespec:status->st_birthtimespec address:address + 52] &&
           [self writeUInt64:(uint64_t)status->st_size address:address + 64] &&
           [self writeUInt64:(uint64_t)status->st_blocks address:address + 72] &&
           [_registry.memory writeUInt32:(uint32_t)status->st_blksize address:address + 80] &&
           [_registry.memory writeUInt32:status->st_flags address:address + 84] &&
           [_registry.memory writeUInt32:status->st_gen address:address + 88];
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    self.registry = registry;
    registry.guestErrnoAddress = BRPPCGuestErrnoAddress;
    __weak typeof(self) allocatorSelf = self;
    registry.guestAllocator = ^uint32_t(uint32_t size, BOOL clear) {
        return [allocatorSelf allocateSize:size clear:clear];
    };
    registry.guestDeallocator = ^(uint32_t address) {
        [allocatorSelf freeAddress:address];
    };
    registry.guestFormatRenderer = ^NSData *(uint32_t formatAddress, BRPPCState *state,
                                              NSUInteger firstArgumentGPR, NSError **renderError) {
        return [allocatorSelf renderFormatAtAddress:formatAddress state:state
                                             cursor:firstArgumentGPR error:renderError];
    };
    registry.guestVAFormatRenderer = ^NSData *(uint32_t formatAddress, uint32_t argumentsAddress,
                                                NSError **renderError) {
        BRPPCState argumentsState = {0};
        NSUInteger cursor = (argumentsAddress & 7u) ? 12u : 11u;
        uint32_t stackOffset = 24u + (uint32_t)(cursor - 3u) * 4u;
        if (argumentsAddress < stackOffset) return nil;
        argumentsState.gpr[1] = argumentsAddress - stackOffset;
        return [allocatorSelf renderFormatAtAddress:formatAddress state:&argumentsState
                                             cursor:cursor error:renderError];
    };
    self.allocations = [NSMutableDictionary dictionary];
    self.freeBlocks = [NSMutableArray array];
    self.streams = [NSMutableDictionary dictionary];
    self.nextStreamHandle = BRPPCGuestStreamHandleBase;
    self.directories = [NSMutableDictionary dictionary];
    self.nextDirectoryHandle = BRPPCGuestDirectoryHandleBase;
    self.signalHandlers = [NSMutableArray arrayWithCapacity:NSIG];
    self.signalFlags = [NSMutableArray arrayWithCapacity:NSIG];
    self.signalMasks = [NSMutableArray arrayWithCapacity:NSIG];
    for (int signalNumber = 0; signalNumber < NSIG; signalNumber++) {
        [self.signalHandlers addObject:@0];
        [self.signalFlags addObject:@0];
        [self.signalMasks addObject:@0];
        BRPPCPendingSignals[signalNumber] = 0;
    }
    BRPPCHasPendingSignals = 0;
    self.blockedSignals = 0;
    self.exitCallbacks = [NSMutableArray array];
    self.jumpContexts = [NSMutableDictionary dictionary];
    self.dynamicImageHandles = [NSMutableArray array];
    self.threadResults = [NSMutableDictionary dictionary];
    self.threadStates = [NSMutableDictionary dictionary];
    self.threadStacks = [NSMutableDictionary dictionary];
    self.threadOrder = [NSMutableArray array];
    self.blockedThreadStates = [NSMutableDictionary dictionary];
    self.conditionWaiters = [NSMutableDictionary dictionary];
    self.threadWaitDeadlines = [NSMutableDictionary dictionary];
    self.threadWaitResults = [NSMutableDictionary dictionary];
    self.nextThreadIndex = 0;
    self.nextThreadHandle = 1;
    if (![registry.memory mapAddress:BRPPCGuestDarwinDataBase size:BRPPCGuestDarwinDataSize
                          protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                name:@"Darwin globals" error:error] ||
        ![self mapHeap:error]) return NO;
    uint32_t stdinHandle = [self registerStream:stdin];
    uint32_t stdoutHandle = [self registerStream:stdout];
    uint32_t stderrHandle = [self registerStream:stderr];
    if (![registry.memory writeUInt32:stdinHandle address:BRPPCGuestStdinAddress] ||
        ![registry.memory writeUInt32:stdoutHandle address:BRPPCGuestStdoutAddress] ||
        ![registry.memory writeUInt32:stderrHandle address:BRPPCGuestStderrAddress] ||
        ![self registerDataSymbol:@"___stdinp" address:BRPPCGuestStdinAddress error:error] ||
        ![self registerDataSymbol:@"___stdoutp" address:BRPPCGuestStdoutAddress error:error] ||
        ![self registerDataSymbol:@"___stderrp" address:BRPPCGuestStderrAddress error:error]) return NO;
    __weak typeof(self) weakSelf = self;

    [registry registerSymbol:@"___keymgr_dwarf2_register_sections"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; Finish(state, 0); return YES;
        }];

    for (NSString *symbol in @[@"_setjmp", @"__setjmp", @"_sigsetjmp"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            BRPPCState saved = *state;
            @synchronized (weakSelf) {
                weakSelf.jumpContexts[@(state->gpr[3])] =
                    [NSValue valueWithBytes:&saved objCType:@encode(BRPPCState)];
            }
            Finish(state, 0);
            return YES;
        }];
    for (NSString *symbol in @[@"_longjmp", @"__longjmp", @"_siglongjmp"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            NSValue *context = nil;
            @synchronized (weakSelf) {
                context = weakSelf.jumpContexts[@(state->gpr[3])];
            }
            if (!context) {
                if (callError) *callError = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:9
                    userInfo:@{NSLocalizedDescriptionKey: @"longjmp used an unknown guest context."}];
                return NO;
            }
            uint32_t result = state->gpr[4] ?: 1;
            BRPPCState restored;
            [context getValue:&restored];
            *state = restored;
            state->gpr[3] = result;
            state->pc = state->lr;
            return YES;
        }];

    [registry registerSymbol:@"___error" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, BRPPCGuestErrnoAddress); return YES;
    }];
    [registry registerSymbol:@"_mach_absolute_time" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish64(state, mach_absolute_time()); return YES;
    }];
    [registry registerSymbol:@"__dyld_image_count" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, (uint32_t)weakSelf.registry.image.dependencies.count); return YES;
    }];
    [registry registerSymbol:@"__dyld_get_image_name" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t index = state->gpr[3];
        if (index >= weakSelf.registry.image.dependencies.count || !weakSelf.registry.guestAllocator) {
            Finish(state, 0); return YES;
        }
        NSData *bytes = [weakSelf.registry.image.dependencies[index] dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t address = weakSelf.registry.guestAllocator((uint32_t)bytes.length + 1, NO);
        uint8_t zero = 0;
        if (!address || ![weakSelf.registry.memory writeBytes:bytes.bytes address:address length:bytes.length] ||
            ![weakSelf.registry.memory writeBytes:&zero address:address + (uint32_t)bytes.length length:1]) {
            Finish(state, 0); return YES;
        }
        Finish(state, address); return YES;
    }];
    [registry registerSymbol:@"_NSAddImage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *path = [weakSelf.registry.memory readCStringAtAddress:state->gpr[3]
                                                                    maximumLength:PATH_MAX * 4];
        void *handle = path.length ? dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL) : NULL;
        if (!handle) { Finish(state, 0); return YES; }
        [weakSelf.dynamicImageHandles addObject:[NSValue valueWithPointer:handle]];
        Finish(state, (uint32_t)weakSelf.dynamicImageHandles.count); return YES;
    }];
    [registry registerSymbol:@"_dlopen" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSString *path = state->gpr[3]
            ? [weakSelf.registry.memory readCStringAtAddress:state->gpr[3] maximumLength:PATH_MAX * 4]
            : nil;
        void *handle = path.length ? dlopen(path.fileSystemRepresentation, (int)state->gpr[4])
                                   : dlopen(NULL, (int)state->gpr[4]);
        if (!handle) { Finish(state, 0); return YES; }
        [weakSelf.dynamicImageHandles addObject:[NSValue valueWithPointer:handle]];
        Finish(state, (uint32_t)weakSelf.dynamicImageHandles.count);
        return YES;
    }];
    [registry registerSymbol:@"_dlsym" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSString *name = [weakSelf.registry.memory readCStringAtAddress:state->gpr[4]
                                                          maximumLength:4096];
        if (!name.length) { Finish(state, 0); return YES; }
        NSString *guestName = [name hasPrefix:@"_"] ? name : [@"_" stringByAppendingString:name];
        uint32_t address = [weakSelf.registry addressForSymbol:guestName lazy:YES error:callError];
        Finish(state, address);
        return !callError || !*callError;
    }];
    [registry registerSymbol:@"_dlclose" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_dlerror" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_NSLookupSymbolInImage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSString *name = [weakSelf.registry.memory readCStringAtAddress:state->gpr[4] maximumLength:4096];
        uint32_t address = name.length ? [weakSelf.registry addressForSymbol:name lazy:YES error:callError] : 0;
        Finish(state, address); return !callError || !*callError;
    }];
    [registry registerSymbol:@"_NSAddressOfSymbol" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_NSLinkEditError" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        for (NSUInteger index = 3; index <= 6; index++)
            if (state->gpr[index]) [weakSelf.registry.memory writeUInt32:0 address:state->gpr[index]];
        Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"__NSGetExecutablePath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t capacity = 0;
        NSData *path = [(weakSelf.executablePath ?: NSProcessInfo.processInfo.arguments.firstObject)
            dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t required = (uint32_t)path.length + 1;
        if (!state->gpr[4] ||
            ![weakSelf.registry.memory readUInt32:&capacity address:state->gpr[4]]) {
            [weakSelf failState:state errorNumber:EFAULT];
            return YES;
        }
        if (capacity < required || !state->gpr[3]) {
            if (![weakSelf.registry.memory writeUInt32:required address:state->gpr[4]]) {
                [weakSelf failState:state errorNumber:EFAULT];
                return YES;
            }
            Finish(state, UINT32_MAX);
            return YES;
        }
        uint8_t zero = 0;
        if (![weakSelf.registry.memory writeBytes:path.bytes address:state->gpr[3] length:path.length] ||
            ![weakSelf.registry.memory writeBytes:&zero address:state->gpr[3] + (uint32_t)path.length length:1]) {
            [weakSelf failState:state errorNumber:EFAULT];
            return YES;
        }
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_mach_timebase_info" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        mach_timebase_info_data_t info = {0};
        kern_return_t result = mach_timebase_info(&info);
        if (result == KERN_SUCCESS &&
            (![weakSelf.registry.memory writeUInt32:info.numer address:state->gpr[3]] ||
             ![weakSelf.registry.memory writeUInt32:info.denom address:state->gpr[3] + 4])) {
            [weakSelf failState:state errorNumber:EFAULT];
            return YES;
        }
        Finish(state, (uint32_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_getrlimit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        struct rlimit limit = {0};
        int result = getrlimit((int)state->gpr[3], &limit);
        if (!result && (!state->gpr[4] ||
            ![weakSelf writeUInt64:limit.rlim_cur address:state->gpr[4]] ||
            ![weakSelf writeUInt64:limit.rlim_max address:state->gpr[4] + 8])) {
            [weakSelf setGuestErrno:EFAULT]; result = -1;
        } else if (result) [weakSelf setGuestErrno:errno];
        Finish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_setrlimit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t curHigh = 0, curLow = 0, maxHigh = 0, maxLow = 0;
        if (!state->gpr[4] ||
            ![registry.memory readUInt32:&curHigh address:state->gpr[4]] ||
            ![registry.memory readUInt32:&curLow address:state->gpr[4] + 4] ||
            ![registry.memory readUInt32:&maxHigh address:state->gpr[4] + 8] ||
            ![registry.memory readUInt32:&maxLow address:state->gpr[4] + 12]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, UINT32_MAX); return YES;
        }
        struct rlimit limit = {
            .rlim_cur = (rlim_t)((uint64_t)curHigh << 32 | curLow),
            .rlim_max = (rlim_t)((uint64_t)maxHigh << 32 | maxLow)
        };
        int result = setrlimit((int)state->gpr[3], &limit);
        if (result) [weakSelf setGuestErrno:errno];
        Finish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_exit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        if (getenv("BISMUTH_EXIT_TRACE"))
            fprintf(stderr, "guest exit status=%d lr=0x%08x\n", (int)state->gpr[3], state->lr);
        BRPPCState outer = *state;
        if (![weakSelf runExitCallbacksForDSO:0 state:outer error:callError]) return NO;
        weakSelf.exitStatus = (int)state->gpr[3];
        weakSelf.exitRequested = YES;
        return YES;
    }];
    [registry registerSymbol:@"__exit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (getenv("BISMUTH_EXIT_TRACE"))
            fprintf(stderr, "guest _exit status=%d lr=0x%08x\n", (int)state->gpr[3], state->lr);
        weakSelf.exitStatus = (int)state->gpr[3];
        weakSelf.exitRequested = YES;
        return YES;
    }];
    [registry registerSymbol:@"_atexit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[3]) { [weakSelf failState:state errorNumber:EINVAL]; return YES; }
        [weakSelf.exitCallbacks addObject:@{@"function": @(state->gpr[3]), @"argument": @0, @"dso": @0}];
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"___cxa_atexit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[3]) { [weakSelf failState:state errorNumber:EINVAL]; return YES; }
        [weakSelf.exitCallbacks addObject:@{@"function": @(state->gpr[3]),
                                            @"argument": @(state->gpr[4]),
                                            @"dso": @(state->gpr[5])}];
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"___cxa_finalize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCState outer = *state;
        if (![weakSelf runExitCallbacksForDSO:state->gpr[3] state:outer error:callError]) return NO;
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_signal" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        int signalNumber = (int)state->gpr[3];
        uint32_t handler = state->gpr[4];
        if (signalNumber <= 0 || signalNumber >= NSIG || signalNumber == SIGKILL ||
            signalNumber == SIGSTOP || handler == UINT32_MAX) {
            [weakSelf failState:state errorNumber:EINVAL];
            return YES;
        }
        uint32_t previous = weakSelf.signalHandlers[signalNumber].unsignedIntValue;
        if (!ConfigureHostSignal(signalNumber, handler)) {
            [weakSelf failState:state errorNumber:errno];
            return YES;
        }
        weakSelf.signalHandlers[signalNumber] = @(handler);
        weakSelf.signalFlags[signalNumber] = @0;
        weakSelf.signalMasks[signalNumber] = @0;
        Finish(state, previous);
        return YES;
    }];
    [registry registerSymbol:@"_sigaction" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        int signalNumber = (int)state->gpr[3];
        uint32_t actionAddress = state->gpr[4], oldAddress = state->gpr[5];
        if (signalNumber <= 0 || signalNumber >= NSIG || signalNumber == SIGKILL ||
            signalNumber == SIGSTOP) {
            [weakSelf failState:state errorNumber:EINVAL];
            return YES;
        }
        if (oldAddress &&
            (![weakSelf.registry.memory writeUInt32:weakSelf.signalHandlers[signalNumber].unsignedIntValue
                                             address:oldAddress] ||
             ![weakSelf.registry.memory writeUInt32:weakSelf.signalMasks[signalNumber].unsignedIntValue
                                             address:oldAddress + 4] ||
             ![weakSelf.registry.memory writeUInt32:weakSelf.signalFlags[signalNumber].unsignedIntValue
                                             address:oldAddress + 8])) {
            [weakSelf failState:state errorNumber:EFAULT];
            return YES;
        }
        if (actionAddress) {
            uint32_t handler = 0, mask = 0, flags = 0;
            if (![weakSelf.registry.memory readUInt32:&handler address:actionAddress] ||
                ![weakSelf.registry.memory readUInt32:&mask address:actionAddress + 4] ||
                ![weakSelf.registry.memory readUInt32:&flags address:actionAddress + 8]) {
                [weakSelf failState:state errorNumber:EFAULT];
                return YES;
            }
            if (flags & SA_SIGINFO) {
                [weakSelf failState:state errorNumber:ENOTSUP];
                return YES;
            }
            if (!ConfigureHostSignal(signalNumber, handler)) {
                [weakSelf failState:state errorNumber:errno];
                return YES;
            }
            weakSelf.signalHandlers[signalNumber] = @(handler);
            weakSelf.signalMasks[signalNumber] = @(mask);
            weakSelf.signalFlags[signalNumber] = @(flags);
        }
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_raise" handler:^BOOL(BRPPCState *state, NSError **callError) {
        int signalNumber = (int)state->gpr[3];
        if (signalNumber <= 0 || signalNumber >= NSIG) {
            [weakSelf failState:state errorNumber:EINVAL];
            return YES;
        }
        BRPPCPendingSignals[signalNumber] = 1;
        BRPPCHasPendingSignals = 1;
        Finish(state, 0);
        return [weakSelf deliverPendingSignalsToState:state error:callError];
    }];
    [registry registerSymbol:@"_kill" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        pid_t process = (pid_t)state->gpr[3];
        int signalNumber = (int)state->gpr[4];
        if (process == getpid() && signalNumber > 0 && signalNumber < NSIG) {
            BRPPCPendingSignals[signalNumber] = 1;
            BRPPCHasPendingSignals = 1;
            Finish(state, 0);
            return YES;
        }
        int result = kill(process, signalNumber);
        if (result < 0) [weakSelf setGuestErrno:errno];
        Finish(state, (uint32_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_sigemptyset" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (![weakSelf.registry.memory writeUInt32:0 address:state->gpr[3]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_sigfillset" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (![weakSelf.registry.memory writeUInt32:UINT32_MAX address:state->gpr[3]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    BRPPCResolvedCall alterSignalSet = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t set = 0; int signalNumber = (int)state->gpr[4];
        if (signalNumber <= 0 || signalNumber > 32) {
            [weakSelf failState:state errorNumber:EINVAL]; return YES;
        }
        if (![weakSelf.registry.memory readUInt32:&set address:state->gpr[3]]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        uint32_t bit = 1u << (signalNumber - 1);
        if (state->pc == [weakSelf.registry addressForSymbol:@"_sigaddset"]) set |= bit;
        else set &= ~bit;
        if (![weakSelf.registry.memory writeUInt32:set address:state->gpr[3]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    };
    [registry registerSymbol:@"_sigaddset" handler:alterSignalSet];
    [registry registerSymbol:@"_sigdelset" handler:alterSignalSet];
    [registry registerSymbol:@"_sigismember" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t set = 0; int signalNumber = (int)state->gpr[4];
        if (signalNumber <= 0 || signalNumber > 32) {
            [weakSelf failState:state errorNumber:EINVAL]; return YES;
        }
        if (![weakSelf.registry.memory readUInt32:&set address:state->gpr[3]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, !!(set & (1u << (signalNumber - 1))));
        return YES;
    }];
    [registry registerSymbol:@"_sigprocmask" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t setAddress = state->gpr[4], oldAddress = state->gpr[5], set = 0;
        if (oldAddress && ![weakSelf.registry.memory writeUInt32:weakSelf.blockedSignals address:oldAddress]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        if (setAddress) {
            if (![weakSelf.registry.memory readUInt32:&set address:setAddress]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
            switch ((int)state->gpr[3]) {
                case SIG_BLOCK: weakSelf.blockedSignals |= set; break;
                case SIG_UNBLOCK: weakSelf.blockedSignals &= ~set; break;
                case SIG_SETMASK: weakSelf.blockedSignals = set; break;
                default: [weakSelf failState:state errorNumber:EINVAL]; return YES;
            }
            weakSelf.blockedSignals &= ~((1u << (SIGKILL - 1)) | (1u << (SIGSTOP - 1)));
        }
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_sigpending" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t pending = 0;
        for (int signalNumber = 1; signalNumber < NSIG && signalNumber <= 32; signalNumber++)
            if (BRPPCPendingSignals[signalNumber]) pending |= 1u << (signalNumber - 1);
        if (![weakSelf.registry.memory writeUInt32:pending address:state->gpr[3]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_alarm" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!ConfigureHostSignal(SIGALRM, weakSelf.signalHandlers[SIGALRM].unsignedIntValue)) {
            [weakSelf failState:state errorNumber:errno]; return YES;
        }
        Finish(state, alarm(state->gpr[3]));
        return YES;
    }];
    [registry registerSymbol:@"_pause" handler:^BOOL(BRPPCState *state, NSError **callError) {
        int result = pause();
        int savedErrno = errno;
        Finish(state, (uint32_t)result);
        if (result < 0) [weakSelf setGuestErrno:savedErrno];
        return [weakSelf deliverPendingSignalsToState:state error:callError];
    }];
    [registry registerSymbol:@"_sigsuspend" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t temporaryMask = 0;
        if (![weakSelf.registry.memory readUInt32:&temporaryMask address:state->gpr[3]]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        sigset_t hostMask;
        sigemptyset(&hostMask);
        for (int signalNumber = 1; signalNumber < NSIG && signalNumber <= 32; signalNumber++)
            if (temporaryMask & (1u << (signalNumber - 1))) sigaddset(&hostMask, signalNumber);
        uint32_t savedMask = weakSelf.blockedSignals;
        weakSelf.blockedSignals = temporaryMask;
        int result = sigsuspend(&hostMask);
        int savedErrno = errno;
        weakSelf.blockedSignals = savedMask;
        Finish(state, (uint32_t)result);
        if (result < 0) [weakSelf setGuestErrno:savedErrno];
        return [weakSelf deliverPendingSignalsToState:state error:callError];
    }];

    [registry registerSymbol:@"_malloc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t address = [weakSelf allocateSize:state->gpr[3] clear:NO];
        if (!address) [weakSelf setGuestErrno:ENOMEM];
        Finish(state, address); return YES;
    }];
    [registry registerSymbol:@"_calloc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint64_t size = (uint64_t)state->gpr[3] * state->gpr[4];
        uint32_t address = size <= UINT32_MAX ? [weakSelf allocateSize:(uint32_t)size clear:YES] : 0;
        if (!address) [weakSelf setGuestErrno:ENOMEM];
        Finish(state, address); return YES;
    }];
    [registry registerSymbol:@"_free" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf freeAddress:state->gpr[3]]; Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_realloc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t oldAddress = state->gpr[3], requested = state->gpr[4];
        if (!oldAddress) { Finish(state, [weakSelf allocateSize:requested clear:NO]); return YES; }
        if (!requested) { [weakSelf freeAddress:oldAddress]; Finish(state, 0); return YES; }
        NSNumber *oldSize = weakSelf.allocations[@(oldAddress)];
        if (!oldSize) { [weakSelf setGuestErrno:EINVAL]; Finish(state, 0); return YES; }
        uint32_t newAddress = [weakSelf allocateSize:requested clear:NO];
        if (!newAddress || ![weakSelf copyGuestAddress:oldAddress toAddress:newAddress
                                                   length:MIN(requested, oldSize.unsignedIntValue)]) {
            if (newAddress) [weakSelf freeAddress:newAddress];
            [weakSelf setGuestErrno:ENOMEM]; Finish(state, 0); return YES;
        }
        [weakSelf freeAddress:oldAddress]; Finish(state, newAddress); return YES;
    }];

    BRPPCResolvedCall memcpyCall = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t destination = state->gpr[3];
        if (![weakSelf copyGuestAddress:state->gpr[4] toAddress:destination length:state->gpr[5]]) {
            [weakSelf setGuestErrno:EFAULT];
            destination = 0;
        }
        Finish(state, destination); return YES;
    };
    [self registerAliases:@[@"_memcpy", @"_memmove"] handler:memcpyCall];
    [registry registerSymbol:@"_memset" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t destination = state->gpr[3], length = state->gpr[5];
        NSMutableData *bytes = [NSMutableData dataWithLength:length];
        memset(bytes.mutableBytes, (int)state->gpr[4], length);
        if (![weakSelf.registry.memory writeBytes:bytes.bytes address:destination length:length]) {
            [weakSelf setGuestErrno:EFAULT];
            destination = 0;
        }
        Finish(state, destination); return YES;
    }];
    [registry registerSymbol:@"_memcmp" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t length = state->gpr[5];
        NSMutableData *a = [NSMutableData dataWithLength:length];
        NSMutableData *b = [NSMutableData dataWithLength:length];
        if (![weakSelf.registry.memory readBytes:a.mutableBytes address:state->gpr[3] length:length] ||
            ![weakSelf.registry.memory readBytes:b.mutableBytes address:state->gpr[4] length:length]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        Finish(state, (uint32_t)memcmp(a.bytes, b.bytes, length)); return YES;
    }];
    [registry registerSymbol:@"_strlen" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = NO;
        uint32_t length = [weakSelf cStringLength:state->gpr[3] valid:&valid];
        if (!valid) [weakSelf failState:state errorNumber:EFAULT]; else Finish(state, length);
        return YES;
    }];
    [registry registerSymbol:@"_strnlen" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = 0, limit = state->gpr[4]; uint8_t byte = 0;
        while (length < limit && [weakSelf.registry.memory readBytes:&byte
                                                            address:state->gpr[3] + length length:1] && byte) length++;
        Finish(state, length); return YES;
    }];
    [self registerAliases:@[@"_strcmp", @"_strncmp"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t i = 0;
        uint32_t limit = state->pc == [weakSelf.registry addressForSymbol:@"_strncmp"] ? state->gpr[5] : UINT32_MAX;
        int result = 0;
        while (i < limit) {
            uint8_t a = 0, b = 0;
            if (![weakSelf.registry.memory readBytes:&a address:state->gpr[3] + i length:1] ||
                ![weakSelf.registry.memory readBytes:&b address:state->gpr[4] + i length:1]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
            if (a != b || !a) { result = (int)a - (int)b; break; }
            i++;
        }
        Finish(state, (uint32_t)result); return YES;
    }];

    [self registerAliases:@[@"_strcpy", @"_stpcpy", @"_strncpy"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t destination = state->gpr[3], i = 0;
        BOOL bounded = state->pc == [weakSelf.registry addressForSymbol:@"_strncpy"];
        uint32_t limit = bounded ? state->gpr[5] : UINT32_MAX;
        uint8_t byte = 0;
        for (; i < limit; i++) {
            if (![weakSelf.registry.memory readBytes:&byte address:state->gpr[4] + i length:1] ||
                ![weakSelf.registry.memory writeBytes:&byte address:destination + i length:1]) {
                [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
            }
            if (!byte) break;
        }
        if (bounded) {
            byte = 0;
            for (uint32_t j = i + (i < limit ? 1 : 0); j < limit; j++)
                if (![weakSelf.registry.memory writeBytes:&byte address:destination + j length:1]) break;
        }
        BOOL endPointer = state->pc == [weakSelf.registry addressForSymbol:@"_stpcpy"];
        Finish(state, endPointer ? destination + i : destination); return YES;
    }];
    [registry registerSymbol:@"_strdup" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = NO;
        uint32_t length = [weakSelf cStringLength:state->gpr[3] valid:&valid];
        uint32_t result = valid ? [weakSelf allocateSize:length + 1 clear:NO] : 0;
        if (!result || ![weakSelf copyGuestAddress:state->gpr[3] toAddress:result length:length + 1]) {
            if (result) [weakSelf freeAddress:result];
            [weakSelf setGuestErrno:valid ? ENOMEM : EFAULT]; result = 0;
        }
        Finish(state, result); return YES;
    }];
    [self registerAliases:@[@"_strchr", @"_strrchr"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t found = 0, i = 0; uint8_t byte = 0, wanted = (uint8_t)state->gpr[4];
        BOOL reverse = state->pc == [weakSelf.registry addressForSymbol:@"_strrchr"];
        while ([weakSelf.registry.memory readBytes:&byte address:state->gpr[3] + i length:1]) {
            if (byte == wanted) { found = state->gpr[3] + i; if (!reverse) break; }
            if (!byte) break;
            i++;
        }
        Finish(state, found); return YES;
    }];
    [self registerAliases:@[@"_strcat", @"_strncat"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL destinationValid = NO, sourceValid = NO;
        uint32_t destinationLength = [weakSelf cStringLength:state->gpr[3] valid:&destinationValid];
        uint32_t sourceLength = [weakSelf cStringLength:state->gpr[4] valid:&sourceValid];
        if (!destinationValid || !sourceValid) { [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES; }
        if (state->pc == [weakSelf.registry addressForSymbol:@"_strncat"])
            sourceLength = MIN(sourceLength, state->gpr[5]);
        if (![weakSelf copyGuestAddress:state->gpr[4]
                               toAddress:state->gpr[3] + destinationLength length:sourceLength]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
        }
        uint8_t zero = 0;
        if (![weakSelf.registry.memory writeBytes:&zero
                                           address:state->gpr[3] + destinationLength + sourceLength length:1]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
        }
        Finish(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_strstr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL haystackValid = NO, needleValid = NO;
        uint32_t haystackLength = [weakSelf cStringLength:state->gpr[3] valid:&haystackValid];
        uint32_t needleLength = [weakSelf cStringLength:state->gpr[4] valid:&needleValid];
        if (!haystackValid || !needleValid) { [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES; }
        if (!needleLength) { Finish(state, state->gpr[3]); return YES; }
        NSMutableData *haystack = [NSMutableData dataWithLength:haystackLength];
        NSMutableData *needle = [NSMutableData dataWithLength:needleLength];
        if (![weakSelf.registry.memory readBytes:haystack.mutableBytes address:state->gpr[3]
                                          length:haystackLength] ||
            ![weakSelf.registry.memory readBytes:needle.mutableBytes address:state->gpr[4]
                                          length:needleLength]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
        }
        NSRange range = [haystack rangeOfData:needle options:0 range:NSMakeRange(0, haystackLength)];
        Finish(state, range.location == NSNotFound ? 0 : state->gpr[3] + (uint32_t)range.location);
        return YES;
    }];
    [self registerAliases:@[@"_strcasecmp", @"_strncasecmp"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t i = 0;
        uint32_t limit = state->pc == [weakSelf.registry addressForSymbol:@"_strncasecmp"]
            ? state->gpr[5] : UINT32_MAX;
        int result = 0;
        while (i < limit) {
            uint8_t a = 0, b = 0;
            if (![weakSelf.registry.memory readBytes:&a address:state->gpr[3] + i length:1] ||
                ![weakSelf.registry.memory readBytes:&b address:state->gpr[4] + i length:1]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
            int lowerA = tolower(a), lowerB = tolower(b);
            if (lowerA != lowerB || !a || !b) { result = lowerA - lowerB; break; }
            i++;
        }
        Finish(state, (uint32_t)result); return YES;
    }];
    [self registerAliases:@[@"_atoi", @"_atol", @"_strtol", @"_strtoul"]
                    handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int stringError = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&stringError];
        if (!string) { [weakSelf failState:state errorNumber:stringError]; return YES; }
        BOOL unsignedCall = state->pc == [weakSelf.registry addressForSymbol:@"_strtoul"];
        BOOL endPointerCall = unsignedCall || state->pc == [weakSelf.registry addressForSymbol:@"_strtol"];
        int base = endPointerCall ? (int)state->gpr[5] : 10;
        const char *start = string.UTF8String;
        char *end = NULL;
        errno = 0;
        uint64_t parsed = unsignedCall ? strtoull(start, &end, base)
                                       : (uint64_t)strtoll(start, &end, base);
        if (endPointerCall && state->gpr[4])
            [weakSelf.registry.memory writeUInt32:state->gpr[3] + (uint32_t)(end - start)
                                           address:state->gpr[4]];
        if (unsignedCall && parsed > UINT32_MAX) { parsed = UINT32_MAX; errno = ERANGE; }
        if (!unsignedCall) {
            int64_t signedValue = (int64_t)parsed;
            if (signedValue > INT32_MAX) { parsed = INT32_MAX; errno = ERANGE; }
            else if (signedValue < INT32_MIN) { parsed = (uint32_t)INT32_MIN; errno = ERANGE; }
        }
        if (errno) [weakSelf setGuestErrno:errno];
        Finish(state, (uint32_t)parsed); return YES;
    }];

    BRPPCResolvedCall openCall = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        int descriptor = open(path.fileSystemRepresentation, (int)state->gpr[4], (mode_t)state->gpr[5]);
        if (BRPPCIOTraceStream()) fprintf(BRPPCIOTraceStream(), "open path=%s flags=0x%x fd=%d errno=%d\n",
                                          path.UTF8String, state->gpr[4], descriptor,
                                          descriptor < 0 ? errno : 0);
        if (descriptor < 0) [weakSelf failState:state errorNumber:errno];
        else Finish(state, (uint32_t)descriptor);
        return YES;
    };
    [self registerAliases:@[@"_open", @"_open$UNIX2003"] handler:openCall];
    [self registerAliases:@[@"_close", @"_close$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int result = close((int)state->gpr[3]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    BRPPCResolvedCall readCall = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5];
        NSMutableData *buffer = [NSMutableData dataWithLength:length];
        ssize_t result = read((int)state->gpr[3], buffer.mutableBytes, length);
        if (BRPPCIOTraceStream()) fprintf(BRPPCIOTraceStream(), "read fd=%d count=%u result=%lld errno=%d\n",
                                          (int)state->gpr[3], length, (long long)result,
                                          result < 0 ? errno : 0);
        if (result < 0) [weakSelf failState:state errorNumber:errno];
        else if (![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[4]
                                                   length:(size_t)result])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, (uint32_t)result);
        return YES;
    };
    [self registerAliases:@[@"_read", @"_read$UNIX2003"] handler:readCall];
    BRPPCResolvedCall writeCall = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5];
        NSMutableData *buffer = [NSMutableData dataWithLength:length];
        if (![weakSelf.registry.memory readBytes:buffer.mutableBytes address:state->gpr[4] length:length]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        ssize_t result = write((int)state->gpr[3], buffer.bytes, length);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result);
        return YES;
    };
    [self registerAliases:@[@"_write", @"_write$UNIX2003"] handler:writeCall];
    [registry registerSymbol:@"_lseek" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        int64_t offset = (int64_t)((uint64_t)state->gpr[4] << 32 | state->gpr[5]);
        off_t result = lseek((int)state->gpr[3], (off_t)offset, (int)state->gpr[6]);
        if (BRPPCIOTraceStream()) fprintf(BRPPCIOTraceStream(),
                                          "lseek fd=%d offset=%lld whence=%d result=%lld errno=%d\n",
                                          (int)state->gpr[3], (long long)offset, (int)state->gpr[6],
                                          (long long)result, result < 0 ? errno : 0);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish64(state, (uint64_t)result);
        return YES;
    }];
    BRPPCResolvedCall preadCall = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t length = state->gpr[5];
        int64_t offset = (int64_t)((uint64_t)state->gpr[6] << 32 | state->gpr[7]);
        NSMutableData *buffer = [NSMutableData dataWithLength:length];
        ssize_t result = pread((int)state->gpr[3], buffer.mutableBytes, length, (off_t)offset);
        if (result < 0) [weakSelf failState:state errorNumber:errno];
        else if (result && ![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[4]
                                                        length:(size_t)result])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, (uint32_t)result);
        return YES;
    };
    [self registerAliases:@[@"_pread", @"_pread$UNIX2003"] handler:preadCall];
    BRPPCResolvedCall pwriteCall = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t length = state->gpr[5];
        int64_t offset = (int64_t)((uint64_t)state->gpr[6] << 32 | state->gpr[7]);
        NSMutableData *buffer = [NSMutableData dataWithLength:length];
        if (length && ![weakSelf.registry.memory readBytes:buffer.mutableBytes address:state->gpr[4]
                                                       length:length]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        ssize_t result = pwrite((int)state->gpr[3], buffer.bytes, length, (off_t)offset);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result);
        return YES;
    };
    [self registerAliases:@[@"_pwrite", @"_pwrite$UNIX2003"] handler:pwriteCall];
    BRPPCResolvedCall vectorIO = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        int count = (int)state->gpr[5];
        if (count < 0 || count > IOV_MAX) { [weakSelf failState:state errorNumber:EINVAL]; return YES; }
        struct iovec *vectors = calloc((size_t)MAX(count, 1), sizeof(*vectors));
        NSMutableArray<NSMutableData *> *buffers = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
        BOOL reading = state->pc == [weakSelf.registry addressForSymbol:@"_readv"];
        BOOL valid = vectors != NULL;
        for (int index = 0; valid && index < count; index++) {
            uint32_t address = 0, length = 0;
            valid = [weakSelf.registry.memory readUInt32:&address
                address:state->gpr[4] + (uint32_t)index * 8] &&
                [weakSelf.registry.memory readUInt32:&length
                address:state->gpr[4] + (uint32_t)index * 8 + 4];
            if (!valid) break;
            NSMutableData *buffer = [NSMutableData dataWithLength:length];
            if (!reading && length)
                valid = [weakSelf.registry.memory readBytes:buffer.mutableBytes address:address length:length];
            [buffers addObject:buffer]; vectors[index].iov_base = buffer.mutableBytes;
            vectors[index].iov_len = length;
        }
        if (!valid) {
            free(vectors); [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        ssize_t result = reading ? readv((int)state->gpr[3], vectors, count)
                                 : writev((int)state->gpr[3], vectors, count);
        if (reading && result > 0) {
            size_t remainingBytes = (size_t)result;
            for (int index = 0; index < count && remainingBytes; index++) {
                uint32_t address = 0;
                [weakSelf.registry.memory readUInt32:&address address:state->gpr[4] + (uint32_t)index * 8];
                size_t copied = MIN(remainingBytes, vectors[index].iov_len);
                if (copied && ![weakSelf.registry.memory writeBytes:buffers[(NSUInteger)index].bytes
                                                       address:address length:copied]) {
                    free(vectors); [weakSelf failState:state errorNumber:EFAULT]; return YES;
                }
                remainingBytes -= copied;
            }
        }
        free(vectors);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result);
        return YES;
    };
    [registry registerSymbol:@"_readv" handler:vectorIO];
    [registry registerSymbol:@"_writev" handler:vectorIO];

    [registry registerSymbol:@"_fopen" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int pathError = 0, modeError = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&pathError];
        NSString *mode = [weakSelf stringAtAddress:state->gpr[4] errorNumber:&modeError];
        if (!path || !mode) { [weakSelf setGuestErrno:pathError ?: modeError]; Finish(state, 0); return YES; }
        FILE *stream = fopen(path.fileSystemRepresentation, mode.UTF8String);
        if (!stream) { [weakSelf setGuestErrno:errno]; Finish(state, 0); }
        else Finish(state, [weakSelf registerStream:stream]);
        return YES;
    }];
    [registry registerSymbol:@"_fdopen" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int modeError = 0;
        NSString *mode = [weakSelf stringAtAddress:state->gpr[4] errorNumber:&modeError];
        if (!mode) { [weakSelf setGuestErrno:modeError]; Finish(state, 0); return YES; }
        FILE *stream = fdopen((int)state->gpr[3], mode.UTF8String);
        if (!stream) { [weakSelf setGuestErrno:errno]; Finish(state, 0); }
        else Finish(state, [weakSelf registerStream:stream]);
        return YES;
    }];
    [registry registerSymbol:@"_fclose" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        int result = fclose(stream);
        [weakSelf.streams removeObjectForKey:@(state->gpr[3])];
        if (result == EOF) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_fread" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[6]];
        uint64_t byteCount = (uint64_t)state->gpr[4] * state->gpr[5];
        if (!stream || byteCount > UINT32_MAX) { [weakSelf setGuestErrno:stream ? EOVERFLOW : EBADF]; Finish(state, 0); return YES; }
        NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)byteCount];
        size_t items = fread(buffer.mutableBytes, state->gpr[4], state->gpr[5], stream);
        size_t bytesRead = items * state->gpr[4];
        if (bytesRead && ![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[3]
                                                       length:bytesRead]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
        }
        Finish(state, (uint32_t)items); return YES;
    }];
    [registry registerSymbol:@"_fwrite" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[6]];
        uint64_t byteCount = (uint64_t)state->gpr[4] * state->gpr[5];
        if (!stream || byteCount > UINT32_MAX) { [weakSelf setGuestErrno:stream ? EOVERFLOW : EBADF]; Finish(state, 0); return YES; }
        NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)byteCount];
        if (byteCount && ![weakSelf.registry.memory readBytes:buffer.mutableBytes address:state->gpr[3]
                                                      length:(size_t)byteCount]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
        }
        Finish(state, (uint32_t)fwrite(buffer.bytes, state->gpr[4], state->gpr[5], stream));
        return YES;
    }];
    [self registerAliases:@[@"_fseek", @"_fseeko"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        int result;
        if (state->pc == [weakSelf.registry addressForSymbol:@"_fseeko"]) {
            int64_t offset = (int64_t)((uint64_t)state->gpr[4] << 32 | state->gpr[5]);
            result = fseeko(stream, offset, (int)state->gpr[6]);
        } else result = fseek(stream, (int32_t)state->gpr[4], (int)state->gpr[5]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_ftell" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        long result = ftell(stream);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_ftello" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        off_t result = ftello(stream);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish64(state, (uint64_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_fflush" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = state->gpr[3] ? [weakSelf streamForHandle:state->gpr[3]] : NULL;
        if (state->gpr[3] && !stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        int result = fflush(stream);
        if (result == EOF) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_fgetc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) [weakSelf failState:state errorNumber:EBADF]; else Finish(state, (uint32_t)fgetc(stream));
        return YES;
    }];
    [registry registerSymbol:@"_fputc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[4]];
        if (!stream) [weakSelf failState:state errorNumber:EBADF]; else Finish(state, (uint32_t)fputc((int)state->gpr[3], stream));
        return YES;
    }];
    [registry registerSymbol:@"_fgets" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[5]];
        int size = (int)state->gpr[4];
        if (!stream || size <= 0) { [weakSelf setGuestErrno:stream ? EINVAL : EBADF]; Finish(state, 0); return YES; }
        NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)size];
        if (!fgets(buffer.mutableBytes, size, stream)) { Finish(state, 0); return YES; }
        size_t length = strlen(buffer.bytes) + 1;
        if (![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[3] length:length]) {
            [weakSelf setGuestErrno:EFAULT]; Finish(state, 0); return YES;
        }
        Finish(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_fputs" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int stringError = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&stringError];
        FILE *stream = [weakSelf streamForHandle:state->gpr[4]];
        if (!string || !stream) { [weakSelf failState:state errorNumber:string ? EBADF : stringError]; return YES; }
        int result = fputs(string.UTF8String, stream);
        if (result == EOF) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_puts" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int stringError = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&stringError];
        if (!string) [weakSelf failState:state errorNumber:stringError];
        else { int result = puts(string.UTF8String); if (result == EOF) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result); }
        return YES;
    }];

    [registry registerSymbol:@"_getcwd" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t guestAddress = state->gpr[3], size = state->gpr[4];
        if (!size) { [weakSelf setGuestErrno:EINVAL]; Finish(state, 0); return YES; }
        NSMutableData *buffer = [NSMutableData dataWithLength:size];
        if (!getcwd(buffer.mutableBytes, size)) { [weakSelf setGuestErrno:errno]; Finish(state, 0); return YES; }
        if (!guestAddress) guestAddress = [weakSelf allocateSize:size clear:NO];
        if (!guestAddress || ![weakSelf.registry.memory writeBytes:buffer.bytes address:guestAddress
                                                           length:strlen(buffer.bytes) + 1]) {
            [weakSelf setGuestErrno:ENOMEM]; Finish(state, 0); return YES;
        }
        Finish(state, guestAddress); return YES;
    }];
    [self registerAliases:@[@"_chdir", @"_unlink", @"_rmdir", @"_access"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        int result;
        if (state->pc == [weakSelf.registry addressForSymbol:@"_chdir"]) result = chdir(path.fileSystemRepresentation);
        else if (state->pc == [weakSelf.registry addressForSymbol:@"_unlink"]) result = unlink(path.fileSystemRepresentation);
        else if (state->pc == [weakSelf.registry addressForSymbol:@"_rmdir"]) result = rmdir(path.fileSystemRepresentation);
        else result = access(path.fileSystemRepresentation, (int)state->gpr[4]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_mkdir" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        int result = mkdir(path.fileSystemRepresentation, (mode_t)state->gpr[4]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];

    [self registerAliases:@[@"_stat", @"_stat$INODE64", @"_stat64",
                            @"_lstat", @"_lstat$INODE64", @"_lstat64"]
                    handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        NSString *symbol = nil;
        for (NSString *candidate in @[@"_stat", @"_stat$INODE64", @"_stat64",
                                      @"_lstat", @"_lstat$INODE64", @"_lstat64"])
            if (state->pc == [weakSelf.registry addressForSymbol:candidate]) { symbol = candidate; break; }
        struct stat status;
        int result = [symbol hasPrefix:@"_lstat"]
            ? lstat(path.fileSystemRepresentation, &status)
            : stat(path.fileSystemRepresentation, &status);
        BOOL inode64 = [symbol containsString:@"INODE64"] || [symbol hasSuffix:@"64"];
        if (result < 0) [weakSelf failState:state errorNumber:errno];
        else if (![weakSelf writeStat:&status address:state->gpr[4] inode64:inode64])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    [self registerAliases:@[@"_fstat", @"_fstat$INODE64", @"_fstat64"]
                    handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; struct stat status;
        NSString *symbol = state->pc == [weakSelf.registry addressForSymbol:@"_fstat"]
            ? @"_fstat" : (state->pc == [weakSelf.registry addressForSymbol:@"_fstat64"]
                ? @"_fstat64" : @"_fstat$INODE64");
        int result = fstat((int)state->gpr[3], &status);
        if (BRPPCIOTraceStream()) fprintf(BRPPCIOTraceStream(),
                                          "fstat fd=%d result=%d size=%lld inode64=%d errno=%d\n",
                                          (int)state->gpr[3], result, (long long)status.st_size,
                                          ![symbol isEqualToString:@"_fstat"], result < 0 ? errno : 0);
        BOOL inode64 = ![symbol isEqualToString:@"_fstat"];
        if (result < 0) [weakSelf failState:state errorNumber:errno];
        else if (![weakSelf writeStat:&status address:state->gpr[4] inode64:inode64])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];

    [registry registerSymbol:@"_getenv" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *name = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        const char *value = name ? getenv(name.UTF8String) : NULL;
        if (!value) { Finish(state, 0); return YES; }
        size_t length = strlen(value) + 1;
        uint32_t result = length <= UINT32_MAX ? [weakSelf allocateSize:(uint32_t)length clear:NO] : 0;
        if (!result || ![weakSelf.registry.memory writeBytes:value address:result length:length]) result = 0;
        Finish(state, result); return YES;
    }];
    [registry registerSymbol:@"_setenv" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int firstError = 0, secondError = 0;
        NSString *name = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&firstError];
        NSString *value = [weakSelf stringAtAddress:state->gpr[4] errorNumber:&secondError];
        if (!name || !value) { [weakSelf failState:state errorNumber:firstError ?: secondError]; return YES; }
        int result = setenv(name.UTF8String, value.UTF8String, (int)state->gpr[5]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_unsetenv" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *name = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!name) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        int result = unsetenv(name.UTF8String);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_time" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; time_t value = time(NULL);
        if (state->gpr[3] && ![weakSelf.registry.memory writeUInt32:(uint32_t)value address:state->gpr[3]]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        Finish(state, (uint32_t)value); return YES;
    }];
    [registry registerSymbol:@"_sleep" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSTimeInterval deadline = [NSDate date].timeIntervalSince1970 + state->gpr[3];
        if (![weakSelf suspendCurrentGuestThreadState:state untilDeadline:deadline result:0])
            [weakSelf suspendMainGuestThreadState:state untilDeadline:deadline result:0];
        return YES;
    }];
    [registry registerSymbol:@"_usleep" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSTimeInterval deadline = [NSDate date].timeIntervalSince1970 + state->gpr[3] / 1000000.0;
        if ([weakSelf suspendCurrentGuestThreadState:state untilDeadline:deadline result:0]) return YES;
        [weakSelf suspendMainGuestThreadState:state untilDeadline:deadline result:0];
        return YES;
    }];
    [registry registerSymbol:@"_getpid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, (uint32_t)getpid()); return YES;
    }];
    [registry registerSymbol:@"_getppid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, (uint32_t)getppid()); return YES;
    }];
    [registry registerSymbol:@"_getuid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, getuid()); return YES;
    }];
    [registry registerSymbol:@"_geteuid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, geteuid()); return YES;
    }];
    [registry registerSymbol:@"_getgid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, getgid()); return YES;
    }];
    [registry registerSymbol:@"_getegid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, getegid()); return YES;
    }];

    for (NSString *symbol in @[@"_isalnum", @"_isalpha", @"_isblank", @"_iscntrl",
                                @"_isdigit", @"_isgraph", @"_islower", @"_isprint",
                                @"_ispunct", @"_isspace", @"_isupper", @"_isxdigit",
                                @"_isascii", @"_toascii", @"_tolower", @"_toupper"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; int value = (int32_t)state->gpr[3];
            int character = value == EOF ? EOF : (unsigned char)value; int result = 0;
            if ([symbol isEqualToString:@"_isalnum"]) result = isalnum(character);
            else if ([symbol isEqualToString:@"_isalpha"]) result = isalpha(character);
            else if ([symbol isEqualToString:@"_isblank"]) result = isblank(character);
            else if ([symbol isEqualToString:@"_iscntrl"]) result = iscntrl(character);
            else if ([symbol isEqualToString:@"_isdigit"]) result = isdigit(character);
            else if ([symbol isEqualToString:@"_isgraph"]) result = isgraph(character);
            else if ([symbol isEqualToString:@"_islower"]) result = islower(character);
            else if ([symbol isEqualToString:@"_isprint"]) result = isprint(character);
            else if ([symbol isEqualToString:@"_ispunct"]) result = ispunct(character);
            else if ([symbol isEqualToString:@"_isspace"]) result = isspace(character);
            else if ([symbol isEqualToString:@"_isupper"]) result = isupper(character);
            else if ([symbol isEqualToString:@"_isxdigit"]) result = isxdigit(character);
            else if ([symbol isEqualToString:@"_isascii"]) result = isascii(value);
            else if ([symbol isEqualToString:@"_toascii"]) result = toascii(value);
            else if ([symbol isEqualToString:@"_tolower"]) result = tolower(character);
            else result = toupper(character);
            Finish(state, (uint32_t)result); return YES;
        }];
    }
    for (NSString *symbol in @[@"_abs", @"_labs"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; int32_t value = (int32_t)state->gpr[3];
            uint32_t result = value == INT32_MIN ? (uint32_t)INT32_MIN : (uint32_t)abs(value);
            Finish(state, result); return YES;
        }];
    }
    for (NSString *symbol in @[@"_rand", @"_random", @"_arc4random"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t value = [symbol isEqualToString:@"_rand"] ? (uint32_t)rand() :
                ([symbol isEqualToString:@"_random"] ? (uint32_t)random() : arc4random());
            Finish(state, value); return YES;
        }];
    }
    for (NSString *symbol in @[@"_srand", @"_srandom"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; if ([symbol isEqualToString:@"_srand"]) srand(state->gpr[3]);
            else srandom(state->gpr[3]); Finish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_arc4random_uniform" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, arc4random_uniform(state->gpr[3])); return YES;
    }];

    [registry registerSymbol:@"_memchr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t address = state->gpr[3], length = state->gpr[5];
        uint8_t byte = 0, wanted = (uint8_t)state->gpr[4];
        for (uint32_t i = 0; i < length; i++) {
            if (![weakSelf.registry.memory readBytes:&byte address:address + i length:1]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
            if (byte == wanted) { Finish(state, address + i); return YES; }
        }
        Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_bzero" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *zeros = [NSMutableData dataWithLength:state->gpr[4]];
        if (![weakSelf.registry.memory writeBytes:zeros.bytes address:state->gpr[3] length:zeros.length])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_bcopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (![weakSelf copyGuestAddress:state->gpr[3] toAddress:state->gpr[4] length:state->gpr[5]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    [self registerAliases:@[@"_strspn", @"_strcspn"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int firstError = 0, secondError = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&firstError];
        NSString *set = [weakSelf stringAtAddress:state->gpr[4] errorNumber:&secondError];
        if (!string || !set) { [weakSelf failState:state errorNumber:firstError ?: secondError]; return YES; }
        size_t result = state->pc == [weakSelf.registry addressForSymbol:@"_strspn"]
            ? strspn(string.UTF8String, set.UTF8String) : strcspn(string.UTF8String, set.UTF8String);
        Finish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_strpbrk" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int firstError = 0, secondError = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&firstError];
        NSString *set = [weakSelf stringAtAddress:state->gpr[4] errorNumber:&secondError];
        if (!string || !set) { [weakSelf failState:state errorNumber:firstError ?: secondError]; return YES; }
        const char *found = strpbrk(string.UTF8String, set.UTF8String);
        Finish(state, found ? state->gpr[3] + (uint32_t)(found - string.UTF8String) : 0); return YES;
    }];
    [registry registerSymbol:@"_strerror" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; const char *message = strerror((int)state->gpr[3]);
        size_t length = strlen(message) + 1;
        uint32_t address = length <= UINT32_MAX ? [weakSelf allocateSize:(uint32_t)length clear:NO] : 0;
        if (!address || ![weakSelf.registry.memory writeBytes:message address:address length:length])
            [weakSelf failState:state errorNumber:ENOMEM];
        else Finish(state, address);
        return YES;
    }];
    [registry registerSymbol:@"_strerror_r" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        const char *message = strerror((int)state->gpr[3]);
        size_t length = strlen(message) + 1;
        uint32_t capacity = state->gpr[5];
        if (!state->gpr[4] || !capacity) {
            [weakSelf failState:state errorNumber:ERANGE];
            return YES;
        }
        size_t copied = MIN(length, capacity);
        if (![weakSelf.registry.memory writeBytes:message address:state->gpr[4]
                                             length:copied > 0 ? copied - 1 : 0]) {
            [weakSelf failState:state errorNumber:EFAULT];
            return YES;
        }
        uint8_t zero = 0;
        if (![weakSelf.registry.memory writeBytes:&zero
                                           address:state->gpr[4] + (uint32_t)copied - 1 length:1]) {
            [weakSelf failState:state errorNumber:EFAULT];
            return YES;
        }
        Finish(state, length <= capacity ? 0 : ERANGE);
        return YES;
    }];
    [self registerAliases:@[@"_atoi", @"_atol"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!string) [weakSelf failState:state errorNumber:errorNumber];
        else Finish(state, (uint32_t)(int32_t)strtol(string.UTF8String, NULL, 10));
        return YES;
    }];
    [self registerAliases:@[@"_atof", @"_strtod", @"_strtof"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!string) { [weakSelf setGuestErrno:errorNumber]; Finish(state, 0); return YES; }
        char *end = NULL; errno = 0;
        double value = state->pc == [weakSelf.registry addressForSymbol:@"_strtof"]
            ? strtof(string.UTF8String, &end) : strtod(string.UTF8String, &end);
        if (state->pc != [weakSelf.registry addressForSymbol:@"_atof"] && state->gpr[4])
            [weakSelf.registry.memory writeUInt32:state->gpr[3] + (uint32_t)(end - string.UTF8String)
                                           address:state->gpr[4]];
        if (errno) [weakSelf setGuestErrno:errno];
        state->fpr[1] = value; state->pc = state->lr; return YES;
    }];
    [self registerAliases:@[@"_strtoll", @"_strtoull"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *string = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!string) { [weakSelf setGuestErrno:errorNumber]; Finish64(state, UINT64_MAX); return YES; }
        char *end = NULL; errno = 0;
        uint64_t value = state->pc == [weakSelf.registry addressForSymbol:@"_strtoull"]
            ? strtoull(string.UTF8String, &end, (int)state->gpr[5])
            : (uint64_t)strtoll(string.UTF8String, &end, (int)state->gpr[5]);
        if (state->gpr[4]) [weakSelf.registry.memory writeUInt32:state->gpr[3] + (uint32_t)(end - string.UTF8String)
                                                               address:state->gpr[4]];
        if (errno) [weakSelf setGuestErrno:errno]; Finish64(state, value); return YES;
    }];

    [self registerAliases:@[@"_feof", @"_ferror", @"_fileno"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        int value = state->pc == [weakSelf.registry addressForSymbol:@"_feof"] ? feof(stream)
            : state->pc == [weakSelf.registry addressForSymbol:@"_ferror"] ? ferror(stream) : fileno(stream);
        Finish(state, (uint32_t)value); return YES;
    }];
    [self registerAliases:@[@"_clearerr", @"_rewind"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        if (state->pc == [weakSelf.registry addressForSymbol:@"_clearerr"]) clearerr(stream); else rewind(stream);
        Finish(state, 0); return YES;
    }];
    [self registerAliases:@[@"_getc", @"_getchar"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = state->pc == [weakSelf.registry addressForSymbol:@"_getchar"]
            ? stdin : [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) [weakSelf failState:state errorNumber:EBADF]; else Finish(state, (uint32_t)getc(stream));
        return YES;
    }];
    [self registerAliases:@[@"_putc", @"_putchar"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = state->pc == [weakSelf.registry addressForSymbol:@"_putchar"]
            ? stdout : [weakSelf streamForHandle:state->gpr[4]];
        if (!stream) [weakSelf failState:state errorNumber:EBADF];
        else Finish(state, (uint32_t)putc((int)state->gpr[3], stream));
        return YES;
    }];
    [registry registerSymbol:@"_ungetc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = [weakSelf streamForHandle:state->gpr[4]];
        if (!stream) [weakSelf failState:state errorNumber:EBADF];
        else Finish(state, (uint32_t)ungetc((int)state->gpr[3], stream));
        return YES;
    }];
    [registry registerSymbol:@"_tmpfile" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FILE *stream = tmpfile();
        if (!stream) [weakSelf failState:state errorNumber:errno];
        else Finish(state, [weakSelf registerStream:stream]); return YES;
    }];
    [self registerAliases:@[@"_printf", @"_printf$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSMutableData *output = [weakSelf renderFormatAtAddress:state->gpr[3] state:state cursor:4 error:callError];
        if (!output) return NO;
        size_t written = fwrite(output.bytes, 1, output.length, stdout);
        if (written != output.length) [weakSelf failState:state errorNumber:errno];
        else Finish(state, (uint32_t)written); return YES;
    }];
    [self registerAliases:@[@"_fprintf", @"_fprintf$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        FILE *stream = [weakSelf streamForHandle:state->gpr[3]];
        if (!stream) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        NSMutableData *output = [weakSelf renderFormatAtAddress:state->gpr[4] state:state cursor:5 error:callError];
        if (!output) return NO;
        size_t written = fwrite(output.bytes, 1, output.length, stream);
        if (written != output.length) [weakSelf failState:state errorNumber:errno];
        else Finish(state, (uint32_t)written); return YES;
    }];
    [self registerAliases:@[@"_dprintf", @"_dprintf$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSMutableData *output = [weakSelf renderFormatAtAddress:state->gpr[4] state:state cursor:5 error:callError];
        if (!output) return NO;
        ssize_t written = write((int)state->gpr[3], output.bytes, output.length);
        if (written < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)written);
        return YES;
    }];
    [self registerAliases:@[@"_sprintf", @"_sprintf$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t destination = state->gpr[3];
        NSMutableData *output = [weakSelf renderFormatAtAddress:state->gpr[4] state:state cursor:5 error:callError];
        if (!output) return NO;
        uint8_t zero = 0;
        if (![weakSelf.registry.memory writeBytes:output.bytes address:destination length:output.length] ||
            ![weakSelf.registry.memory writeBytes:&zero address:destination + (uint32_t)output.length length:1])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, (uint32_t)output.length); return YES;
    }];
    [self registerAliases:@[@"_snprintf", @"_snprintf$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t destination = state->gpr[3], capacity = state->gpr[4];
        NSMutableData *output = [weakSelf renderFormatAtAddress:state->gpr[5] state:state cursor:6 error:callError];
        if (!output) return NO;
        if (capacity) {
            size_t copied = MIN(output.length, (NSUInteger)capacity - 1); uint8_t zero = 0;
            if (![weakSelf.registry.memory writeBytes:output.bytes address:destination length:copied] ||
                ![weakSelf.registry.memory writeBytes:&zero address:destination + (uint32_t)copied length:1]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
        }
        Finish(state, (uint32_t)output.length); return YES;
    }];
    [self registerAliases:@[@"_asprintf", @"_asprintf$UNIX2003"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t resultPointer = state->gpr[3];
        NSMutableData *output = [weakSelf renderFormatAtAddress:state->gpr[4] state:state cursor:5 error:callError];
        if (!output) return NO;
        uint32_t address = output.length < UINT32_MAX
            ? [weakSelf allocateSize:(uint32_t)output.length + 1 clear:NO] : 0;
        uint8_t zero = 0;
        if (!address || ![weakSelf.registry.memory writeBytes:output.bytes address:address length:output.length] ||
            ![weakSelf.registry.memory writeBytes:&zero address:address + (uint32_t)output.length length:1] ||
            ![weakSelf.registry.memory writeUInt32:address address:resultPointer])
            [weakSelf failState:state errorNumber:ENOMEM];
        else Finish(state, (uint32_t)output.length); return YES;
    }];

    [self registerAliases:@[@"_rename", @"_link", @"_symlink"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int firstError = 0, secondError = 0;
        NSString *first = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&firstError];
        NSString *second = [weakSelf stringAtAddress:state->gpr[4] errorNumber:&secondError];
        if (!first || !second) { [weakSelf failState:state errorNumber:firstError ?: secondError]; return YES; }
        int result = state->pc == [weakSelf.registry addressForSymbol:@"_rename"]
            ? rename(first.fileSystemRepresentation, second.fileSystemRepresentation)
            : state->pc == [weakSelf.registry addressForSymbol:@"_link"]
                ? link(first.fileSystemRepresentation, second.fileSystemRepresentation)
                : symlink(first.fileSystemRepresentation, second.fileSystemRepresentation);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_readlink" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        NSMutableData *buffer = [NSMutableData dataWithLength:state->gpr[5]];
        ssize_t result = readlink(path.fileSystemRepresentation, buffer.mutableBytes, buffer.length);
        if (result < 0) [weakSelf failState:state errorNumber:errno];
        else if (![weakSelf.registry.memory writeBytes:buffer.bytes address:state->gpr[4] length:(size_t)result])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, (uint32_t)result); return YES;
    }];
    [self registerAliases:@[@"_chmod", @"_chown", @"_lchown"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        int result = state->pc == [weakSelf.registry addressForSymbol:@"_chmod"]
            ? chmod(path.fileSystemRepresentation, (mode_t)state->gpr[4])
            : state->pc == [weakSelf.registry addressForSymbol:@"_chown"]
                ? chown(path.fileSystemRepresentation, state->gpr[4], state->gpr[5])
                : lchown(path.fileSystemRepresentation, state->gpr[4], state->gpr[5]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [self registerAliases:@[@"_fchmod", @"_fchown", @"_fsync", @"_dup"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int result;
        if (state->pc == [weakSelf.registry addressForSymbol:@"_fchmod"])
            result = fchmod((int)state->gpr[3], (mode_t)state->gpr[4]);
        else if (state->pc == [weakSelf.registry addressForSymbol:@"_fchown"])
            result = fchown((int)state->gpr[3], state->gpr[4], state->gpr[5]);
        else if (state->pc == [weakSelf.registry addressForSymbol:@"_fsync"])
            result = fsync((int)state->gpr[3]);
        else result = dup((int)state->gpr[3]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_dup2" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int result = dup2((int)state->gpr[3], (int)state->gpr[4]);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_pipe" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int descriptors[2];
        if (pipe(descriptors) < 0) [weakSelf failState:state errorNumber:errno];
        else if (![weakSelf.registry.memory writeUInt32:(uint32_t)descriptors[0] address:state->gpr[3]] ||
                 ![weakSelf.registry.memory writeUInt32:(uint32_t)descriptors[1] address:state->gpr[3] + 4]) {
            close(descriptors[0]); close(descriptors[1]); [weakSelf failState:state errorNumber:EFAULT];
        } else Finish(state, 0); return YES;
    }];
    [self registerAliases:@[@"_truncate", @"_ftruncate"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int64_t length = (int64_t)((uint64_t)state->gpr[5] << 32 | state->gpr[6]);
        int result;
        if (state->pc == [weakSelf.registry addressForSymbol:@"_truncate"]) {
            int errorNumber = 0; NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
            if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
            result = truncate(path.fileSystemRepresentation, length);
        } else result = ftruncate((int)state->gpr[3], length);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_opendir" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int errorNumber = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&errorNumber];
        if (!path) { [weakSelf failState:state errorNumber:errorNumber]; return YES; }
        DIR *directory = opendir(path.fileSystemRepresentation);
        if (!directory) [weakSelf failState:state errorNumber:errno];
        else { uint32_t handle = [weakSelf registerDirectory:directory]; if (!handle) [weakSelf failState:state errorNumber:ENOMEM]; else Finish(state, handle); }
        return YES;
    }];
    [registry registerSymbol:@"_fdopendir" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; DIR *directory = fdopendir((int)state->gpr[3]);
        if (!directory) [weakSelf failState:state errorNumber:errno];
        else { uint32_t handle = [weakSelf registerDirectory:directory]; if (!handle) [weakSelf failState:state errorNumber:ENOMEM]; else Finish(state, handle); }
        return YES;
    }];
    [registry registerSymbol:@"_closedir" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestDirectory *record = weakSelf.directories[@(state->gpr[3])];
        if (!record) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        int result = closedir(record.directory); [weakSelf.directories removeObjectForKey:@(state->gpr[3])];
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES;
    }];
    [self registerAliases:@[@"_readdir", @"_readdir$INODE64", @"_readdir64"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestDirectory *record = weakSelf.directories[@(state->gpr[3])];
        if (!record) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        errno = 0; struct dirent *entry = readdir(record.directory);
        if (!entry) { if (errno) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0); return YES; }
        BOOL inode64 = state->pc != [weakSelf.registry addressForSymbol:@"_readdir"];
        if (![weakSelf writeDirectoryEntry:entry record:record inode64:inode64])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, record.guestEntryAddress); return YES;
    }];
    [self registerAliases:@[@"_rewinddir", @"_seekdir"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestDirectory *record = weakSelf.directories[@(state->gpr[3])];
        if (!record) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        if (state->pc == [weakSelf.registry addressForSymbol:@"_rewinddir"]) rewinddir(record.directory);
        else seekdir(record.directory, (long)(int32_t)state->gpr[4]);
        Finish(state, 0); return YES;
    }];
    [self registerAliases:@[@"_telldir", @"_dirfd"] handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestDirectory *record = weakSelf.directories[@(state->gpr[3])];
        if (!record) { [weakSelf failState:state errorNumber:EBADF]; return YES; }
        long result = state->pc == [weakSelf.registry addressForSymbol:@"_telldir"]
            ? telldir(record.directory) : dirfd(record.directory);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, (uint32_t)result); return YES;
    }];

    [registry registerSymbol:@"_gettimeofday" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; struct timeval value; struct timezone zone;
        if (gettimeofday(&value, state->gpr[4] ? &zone : NULL) < 0) { [weakSelf failState:state errorNumber:errno]; return YES; }
        if (state->gpr[3] &&
            (! [weakSelf.registry.memory writeUInt32:(uint32_t)value.tv_sec address:state->gpr[3]] ||
             ! [weakSelf.registry.memory writeUInt32:(uint32_t)value.tv_usec address:state->gpr[3] + 4])) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        if (state->gpr[4] &&
            (! [weakSelf.registry.memory writeUInt32:(uint32_t)zone.tz_minuteswest address:state->gpr[4]] ||
             ! [weakSelf.registry.memory writeUInt32:(uint32_t)zone.tz_dsttime address:state->gpr[4] + 4])) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_localtime_r" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t seconds = 0;
        if (!state->gpr[3] || !state->gpr[4] ||
            ![weakSelf.registry.memory readUInt32:&seconds address:state->gpr[3]]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        time_t hostTime = (time_t)(int32_t)seconds; struct tm value;
        if (!localtime_r(&hostTime, &value)) { [weakSelf failState:state errorNumber:errno]; return YES; }
        int32_t fields[] = {value.tm_sec, value.tm_min, value.tm_hour, value.tm_mday,
            value.tm_mon, value.tm_year, value.tm_wday, value.tm_yday, value.tm_isdst,
            (int32_t)value.tm_gmtoff};
        for (NSUInteger index = 0; index < sizeof(fields) / sizeof(fields[0]); index++)
            if (![weakSelf.registry.memory writeUInt32:(uint32_t)fields[index]
                address:state->gpr[4] + (uint32_t)index * 4]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
        if (![weakSelf.registry.memory writeUInt32:0 address:state->gpr[4] + 40]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        Finish(state, state->gpr[4]); return YES;
    }];
    [registry registerSymbol:@"_utime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int stringError = 0;
        NSString *path = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&stringError];
        if (!path) { [weakSelf failState:state errorNumber:stringError]; return YES; }
        struct utimbuf times, *timesPointer = NULL;
        if (state->gpr[4]) {
            uint32_t access = 0, modification = 0;
            if (![weakSelf.registry.memory readUInt32:&access address:state->gpr[4]] ||
                ![weakSelf.registry.memory readUInt32:&modification address:state->gpr[4] + 4]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
            times.actime = (time_t)(int32_t)access; times.modtime = (time_t)(int32_t)modification;
            timesPointer = &times;
        }
        int result = utime(path.fileSystemRepresentation, timesPointer);
        if (result < 0) [weakSelf failState:state errorNumber:errno]; else Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_ioctl" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; unsigned long request = state->gpr[4];
        if (request != FIONBIO && request != FIONREAD) {
            [weakSelf failState:state errorNumber:ENOTSUP]; return YES;
        }
        int value = 0;
        if (!state->gpr[5] || ![weakSelf.registry.memory readUInt32:(uint32_t *)&value address:state->gpr[5]]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        int result = ioctl((int)state->gpr[3], request, &value);
        if (result < 0) [weakSelf failState:state errorNumber:errno];
        else if (![weakSelf.registry.memory writeUInt32:(uint32_t)value address:state->gpr[5]])
            [weakSelf failState:state errorNumber:EFAULT];
        else Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_clock" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, (uint32_t)clock()); return YES;
    }];
    [registry registerSymbol:@"_nanosleep" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t seconds = 0, nanoseconds = 0;
        if (![weakSelf.registry.memory readUInt32:&seconds address:state->gpr[3]] ||
            ![weakSelf.registry.memory readUInt32:&nanoseconds address:state->gpr[3] + 4]) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        if ((int32_t)seconds < 0 || (int32_t)nanoseconds < 0 || nanoseconds >= 1000000000u) {
            [weakSelf failState:state errorNumber:EINVAL]; return YES;
        }
        if (state->gpr[4] &&
            (![weakSelf.registry.memory writeUInt32:0 address:state->gpr[4]] ||
             ![weakSelf.registry.memory writeUInt32:0 address:state->gpr[4] + 4])) {
            [weakSelf failState:state errorNumber:EFAULT]; return YES;
        }
        NSTimeInterval deadline = [NSDate date].timeIntervalSince1970 +
            seconds + nanoseconds / 1000000000.0;
        if (weakSelf.currentThreadHandle) {
            [weakSelf suspendCurrentGuestThreadState:state untilDeadline:deadline result:0];
            return YES;
        }
        [weakSelf suspendMainGuestThreadState:state untilDeadline:deadline result:0];
        return YES;
    }];
    [registry registerSymbol:@"_qsort" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCState outer = *state;
        if (![weakSelf sortGuestBase:state->gpr[3] count:state->gpr[4] size:state->gpr[5]
                              context:0 contextual:NO comparator:state->gpr[6]
                                state:outer error:callError]) return NO;
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_qsort_r" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCState outer = *state;
        if (![weakSelf sortGuestBase:state->gpr[3] count:state->gpr[4] size:state->gpr[5]
                              context:state->gpr[6] contextual:YES comparator:state->gpr[7]
                                state:outer error:callError]) return NO;
        Finish(state, 0);
        return YES;
    }];
    [registry registerSymbol:@"_bsearch" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t key = state->gpr[3], base = state->gpr[4], count = state->gpr[5];
        uint32_t size = state->gpr[6], comparator = state->gpr[7];
        if (!comparator || (!base && count) || (!size && count) ||
            (uint64_t)base + (uint64_t)count * size > UINT32_MAX + 1ull) {
            if (callError) *callError = [NSError errorWithDomain:BRPPCDarwinErrorDomain code:EFAULT
                userInfo:@{NSLocalizedDescriptionKey: @"Guest bsearch range or comparator is invalid."}];
            return NO;
        }
        BRPPCState outer = *state;
        uint32_t low = 0, high = count;
        while (low < high) {
            uint32_t middle = low + (high - low) / 2;
            uint32_t element = base + middle * size;
            int32_t comparison = 0;
            if (![weakSelf compareGuestFunction:comparator state:outer context:0 contextual:NO
                                           first:key second:element result:&comparison error:callError]) return NO;
            if (!comparison) { Finish(state, element); return YES; }
            if (comparison < 0) high = middle; else low = middle + 1;
        }
        Finish(state, 0);
        return YES;
    }];
    for (NSString *symbol in @[@"_pthread_attr_init", @"_pthread_attr_destroy",
        @"_pthread_attr_setstacksize", @"_pthread_mutexattr_init", @"_pthread_mutexattr_destroy",
        @"_pthread_mutexattr_settype", @"_pthread_mutex_init", @"_pthread_mutex_destroy",
        @"_pthread_mutex_lock", @"_pthread_mutex_unlock", @"_pthread_cond_init",
        @"_pthread_cond_destroy", @"_pthread_detach"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; Finish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_pthread_cond_signal" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSMutableArray<NSNumber *> *waiters = weakSelf.conditionWaiters[@(state->gpr[3])];
        NSNumber *handle = waiters.firstObject;
        if (handle) {
            [waiters removeObjectAtIndex:0];
            NSValue *stored = weakSelf.blockedThreadStates[handle];
            if (stored) {
                weakSelf.threadStates[handle] = stored;
                [weakSelf.blockedThreadStates removeObjectForKey:handle];
                [weakSelf.threadWaitDeadlines removeObjectForKey:handle];
                [weakSelf.threadWaitResults removeObjectForKey:handle];
                [weakSelf.threadOrder addObject:handle];
            }
        }
        Finish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_pthread_cond_wait", @"_pthread_cond_timedwait"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            NSNumber *handle = weakSelf.currentThreadHandle;
            if (!handle) { Finish(state, EINVAL); return YES; }
            uint32_t condition = state->gpr[3];
            BOOL timed = [symbol isEqualToString:@"_pthread_cond_timedwait"];
            NSTimeInterval deadline = 0;
            if (timed) {
                uint32_t seconds = 0, nanoseconds = 0;
                if (!state->gpr[5] ||
                    ![weakSelf.registry.memory readUInt32:&seconds address:state->gpr[5]] ||
                    ![weakSelf.registry.memory readUInt32:&nanoseconds address:state->gpr[5] + 4]) {
                    Finish(state, EFAULT); return YES;
                }
                deadline = seconds + nanoseconds / 1000000000.0;
            }
            Finish(state, 0);
            weakSelf.blockedThreadStates[handle] =
                [NSValue valueWithBytes:state objCType:@encode(BRPPCState)];
            NSMutableArray<NSNumber *> *waiters = weakSelf.conditionWaiters[@(condition)];
            if (!waiters) weakSelf.conditionWaiters[@(condition)] = waiters = [NSMutableArray array];
            [waiters addObject:handle];
            if (timed) {
                weakSelf.threadWaitDeadlines[handle] = @(deadline);
                weakSelf.threadWaitResults[handle] = @(ETIMEDOUT);
            }
            state->pc = weakSelf.registry.guestThreadReturnAddress;
            return YES;
        }];
    [registry registerSymbol:@"_pthread_create" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[3] || !state->gpr[5]) { Finish(state, EINVAL); return YES; }
        uint32_t handle = weakSelf.nextThreadHandle++;
        uint32_t stack = [weakSelf allocateSize:BRPPCGuestThreadStackSize clear:NO];
        if (!stack) { Finish(state, EAGAIN); return YES; }
        BRPPCState callback = {0};
        callback.pc = state->gpr[5];
        callback.lr = weakSelf.registry.guestThreadReturnAddress;
        callback.gpr[12] = callback.pc;
        callback.gpr[3] = state->gpr[6];
        callback.gpr[1] = (stack + BRPPCGuestThreadStackSize - 32) & ~15u;
        if (![weakSelf.registry.memory writeUInt32:handle address:state->gpr[3]]) {
            [weakSelf freeAddress:stack];
            Finish(state, EFAULT); return YES;
        }
        NSNumber *key = @(handle);
        weakSelf.threadStates[key] = [NSValue valueWithBytes:&callback objCType:@encode(BRPPCState)];
        weakSelf.threadStacks[key] = @(stack);
        [weakSelf.threadOrder addObject:key];
        Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_pthread_join" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *result = weakSelf.threadResults[@(state->gpr[3])];
        if (!result) { Finish(state, ESRCH); return YES; }
        if (state->gpr[4] && ![weakSelf.registry.memory writeUInt32:result.unsignedIntValue
                                                        address:state->gpr[4]]) {
            Finish(state, EFAULT); return YES;
        }
        [weakSelf.threadResults removeObjectForKey:@(state->gpr[3])];
        Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_thread_stack_pcs" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_fork" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;



        Finish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_execvp" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int stringError = 0;
        NSString *file = [weakSelf stringAtAddress:state->gpr[3] errorNumber:&stringError];
        if (!file || !weakSelf.launcherPath.length || !state->gpr[4]) {
            [weakSelf failState:state errorNumber:file ? ENOENT : stringError]; return YES;
        }
        NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObjects:
            weakSelf.launcherPath, file, nil];
        for (uint32_t index = 1; index < 4096; index++) {
            uint32_t argumentAddress = 0;
            if (![weakSelf.registry.memory readUInt32:&argumentAddress
                address:state->gpr[4] + index * 4]) {
                [weakSelf failState:state errorNumber:EFAULT]; return YES;
            }
            if (!argumentAddress) break;
            NSString *argument = [weakSelf stringAtAddress:argumentAddress errorNumber:&stringError];
            if (!argument) { [weakSelf failState:state errorNumber:stringError]; return YES; }
            [arguments addObject:argument];
            if (index == 4095) { [weakSelf failState:state errorNumber:E2BIG]; return YES; }
        }
        char **hostArguments = calloc(arguments.count + 1, sizeof(char *));
        if (!hostArguments) { [weakSelf failState:state errorNumber:ENOMEM]; return YES; }
        for (NSUInteger index = 0; index < arguments.count; index++)
            hostArguments[index] = strdup(arguments[index].fileSystemRepresentation);
        const char *runnerPath = getenv("BISMUTH_RUNNER_PATH");
        if (!runnerPath || !*runnerPath) runnerPath = weakSelf.launcherPath.fileSystemRepresentation;
        free(hostArguments[0]);
        hostArguments[0] = strdup(runnerPath);
        for (NSWindow *window in NSApp.windows) {
            window.delegate = nil;
            [window orderOut:nil];
            [window close];
        }
        [NSApp updateWindows];
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        unsetenv("BISMUTH_APP_HOST");
        unsetenv("BISMUTH_GUEST_PATH");
        unsetenv("BISMUTH_GUEST_ARGUMENTS");
        execve(runnerPath, hostArguments, environ);
        int savedError = errno;
        for (NSUInteger index = 0; index < arguments.count; index++) free(hostArguments[index]);
        free(hostArguments);
        [weakSelf failState:state errorNumber:savedError]; return YES;
    }];
    return YES;
}

@end
