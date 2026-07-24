#import "BRPPCResolveRegistry.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import "BRPPCMachOLoader.h"

static NSString * const BRPPCResolveErrorDomain = @"theoderoy.Bismuth.resolve";

@interface BRPPCResolveRegistry ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *addresses;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCResolvedCall> *handlers;
@property(nonatomic, strong) NSMutableArray *syntheticHandlers;
@property(nonatomic) void **syntheticHandlerPointers;
@property(nonatomic) NSUInteger syntheticHandlerCapacity;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *namesByAddress;
@property(nonatomic) uint32_t nextAddress;
@property(nonatomic) uint32_t minimumHandlerAddress;
@property(nonatomic) uint32_t maximumHandlerAddress;
@property(nonatomic) BOOL resolveTraceEnabled;
@property(nonatomic) uint32_t cachedHandlerAddress;
@property(nonatomic, copy, nullable) BRPPCResolvedCall cachedHandler;
@property(nonatomic, weak) BRPowerPC32 *cpu;
@property(nonatomic, strong) NSArray<NSNumber *> *callbackReturnAddresses;
@property(nonatomic) NSUInteger callbackDepth;
@property(nonatomic) uint64_t returnedCallbackMask;
@property(nonatomic) uint32_t guestThreadReturnAddress;
@property(nonatomic) BOOL guestThreadReturned;
@end

@implementation BRPPCResolveRegistry
- (void)dealloc {
    free(_syntheticHandlerPointers);
}

- (instancetype)initWithMemory:(BRPPCAddressSpace *)memory image:(BRPPCMachOImage *)image {
    if ((self = [super init])) {
        _memory = memory;
        _image = image;
        _addresses = [NSMutableDictionary dictionary];
        _handlers = [NSMutableDictionary dictionary];
        _syntheticHandlers = [NSMutableArray array];
        _namesByAddress = [NSMutableDictionary dictionary];
        _nextAddress = BRPPCGuestSyntheticHandlerBase;
        _minimumHandlerAddress = UINT32_MAX;
        _maximumHandlerAddress = 0;
        _resolveTraceEnabled = getenv("BISMUTH_RESOLVE_TRACE") != NULL;



        __unsafe_unretained typeof(self) unownedSelf = self;
        NSMutableArray<NSNumber *> *returnAddresses = [NSMutableArray arrayWithObject:@0];
        for (NSUInteger depth = 1; depth <= BRPPCGuestCallbackSlotCount; depth++) {
            NSString *symbol = [NSString stringWithFormat:@"_bismuth_guest_callback_return_%lu",
                                (unsigned long)depth];
            uint32_t address = [self registerSymbol:symbol handler:^BOOL(BRPPCState *state,
                                                                         NSError **error) {
                (void)state; (void)error;
                unownedSelf->_returnedCallbackMask |= UINT64_C(1) << (depth - 1);
                return YES;
            }];
            [returnAddresses addObject:@(address)];
        }
        _callbackReturnAddresses = returnAddresses.copy;
        _guestThreadReturnAddress = [self registerSymbol:@"_bismuth_guest_thread_return"
            handler:^BOOL(BRPPCState *state, NSError **error) {
                (void)state; (void)error;
                unownedSelf->_guestThreadReturned = YES;
                return YES;
            }];
    }
    return self;
}

- (BOOL)executeGuestThreadState:(BRPPCState *)state
               instructionLimit:(uint64_t)instructionLimit
                       completed:(BOOL *)completed
                           error:(NSError **)error {
    if (!_cpu || !state || !state->pc) {
        if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Guest thread has no attached CPU or entry point."}];
        return NO;
    }
    BRPPCState savedCPUState = _cpu.state;
    _guestThreadReturned = NO;
    _cpu.state = *state;
    BRPPCState *current = _cpu.mutableState;
    uint64_t remaining = instructionLimit;
    BOOL succeeded = YES;
    while (!_guestThreadReturned) {
        uint32_t previousPC = current->pc;
        if (previousPC == _guestThreadReturnAddress) {
            _guestThreadReturned = YES;
            break;
        }
        if (previousPC >= _minimumHandlerAddress && previousPC <= _maximumHandlerAddress) {
            BOOL handled = NO;
            if (![self dispatchState:current handled:&handled error:error]) {
                succeeded = NO;
                break;
            }
            if (handled) continue;
        }
        if (!remaining) break;
        BRPPCStopReason stop;
        if (previousPC >= _minimumHandlerAddress && previousPC <= _maximumHandlerAddress) {


            stop = [_cpu step];
            remaining--;
        } else {
            uint64_t executed = 0;
            stop = [_cpu runWithInstructionLimit:remaining
                stoppingBeforeProgramCounterFrom:_minimumHandlerAddress
                                          through:_maximumHandlerAddress
                         executedInstructionCount:&executed];
            remaining -= executed;
        }
        if (stop != BRPPCStopNone) {
            uint32_t instruction = 0;
            [self.memory readUInt32:&instruction address:previousPC];
            if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Guest pthread stopped at 0x%08x (instruction 0x%08x, reason %u; r1=0x%08x r2=0x%08x r3=0x%08x r4=0x%08x r5=0x%08x r6=0x%08x r7=0x%08x r8=0x%08x r9=0x%08x r10=0x%08x r11=0x%08x r27=0x%08x r28=0x%08x r29=0x%08x r30=0x%08x).",
                                               previousPC, instruction, stop, current->gpr[1],
                                               current->gpr[2], current->gpr[3], current->gpr[4],
                                               current->gpr[5], current->gpr[6], current->gpr[7],
                                               current->gpr[8], current->gpr[9], current->gpr[10],
                                               current->gpr[11], current->gpr[27], current->gpr[28],
                                               current->gpr[29], current->gpr[30]]}];
            succeeded = NO;
            break;
        }
    }
    *state = *current;
    if (completed) *completed = _guestThreadReturned;
    _cpu.state = savedCPUState;
    return succeeded;
}

- (void)attachCPU:(BRPowerPC32 *)cpu {
    _cpu = cpu;
}

- (BOOL)executeGuestCallbackState:(BRPPCState *)state
                 instructionLimit:(uint64_t)instructionLimit
                            label:(NSString *)label
                            error:(NSError **)error {
    if (!_cpu || !state || !state->pc) {
        if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Guest callback has no attached CPU or entry point."}];
        return NO;
    }
    BRPPCState savedCPUState = _cpu.state;
    NSUInteger depth = ++_callbackDepth;
    if (depth >= _callbackReturnAddresses.count) {
        _callbackDepth--;
        if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:6
            userInfo:@{NSLocalizedDescriptionKey: @"Guest callback nesting limit reached."}];
        return NO;
    }
    uint64_t returnBit = UINT64_C(1) << (depth - 1);
    uint32_t returnAddress = _callbackReturnAddresses[depth].unsignedIntValue;
    _returnedCallbackMask &= ~returnBit;
    state->lr = returnAddress;
    state->gpr[1] = BRPPCGuestCallbackStackBase + (uint32_t)depth *
        BRPPCGuestCallbackSlotSize - BRPPCGuestStackFrameReserve;
    _cpu.state = *state;
    BRPPCState *current = _cpu.mutableState;
    uint64_t remaining = instructionLimit;
    BOOL succeeded = YES;
    while (!(_returnedCallbackMask & returnBit)) {
        uint32_t previousPC = current->pc;
        if (previousPC == returnAddress) {
            _returnedCallbackMask |= returnBit;
            break;
        }
        if (previousPC >= _minimumHandlerAddress && previousPC <= _maximumHandlerAddress) {
            BOOL handled = NO;
            if (![self dispatchState:current handled:&handled error:error]) {
                succeeded = NO;
                break;
            }
            if (handled) continue;
        }
        if (!remaining) break;
        BRPPCStopReason stop;
        if (previousPC >= _minimumHandlerAddress && previousPC <= _maximumHandlerAddress) {
            stop = [_cpu step];
            remaining--;
        } else {
            uint64_t executed = 0;
            stop = [_cpu runWithInstructionLimit:remaining
                stoppingBeforeProgramCounterFrom:_minimumHandlerAddress
                                          through:_maximumHandlerAddress
                         executedInstructionCount:&executed];
            remaining -= executed;
        }
        if (stop != BRPPCStopNone) {
            uint8_t previousInstructionBytes[4] = {0};
            [_memory readBytes:previousInstructionBytes address:previousPC
                        length:sizeof(previousInstructionBytes)];
            uint32_t previousInstruction = (uint32_t)previousInstructionBytes[0] << 24 |
                                           (uint32_t)previousInstructionBytes[1] << 16 |
                                           (uint32_t)previousInstructionBytes[2] << 8 |
                                           previousInstructionBytes[3];
            uint8_t instructionBytes[4] = {0};
            [_memory readBytes:instructionBytes address:current->pc length:sizeof(instructionBytes)];
            uint32_t instruction = (uint32_t)instructionBytes[0] << 24 |
                                   (uint32_t)instructionBytes[1] << 16 |
                                   (uint32_t)instructionBytes[2] << 8 |
                                   instructionBytes[3];
            if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Guest %@ callback stopped at 0x%08x "
                                               "(instruction 0x%08x, from 0x%08x/0x%08x, "
                                               "LR 0x%08x, reason %u).",
                                               label, current->pc, instruction,
                                               previousPC, previousInstruction,
                                               current->lr, stop]}];
            succeeded = NO;
            break;
        }
    }
    *state = *current;
    if (succeeded && !remaining && !(_returnedCallbackMask & returnBit)) {
        if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Guest %@ callback instruction limit reached.", label]}];
        succeeded = NO;
    }
    _returnedCallbackMask &= ~returnBit;
    _callbackDepth--;
    _cpu.state = savedCPUState;
    return succeeded;
}

- (uint32_t)registerSymbol:(NSString *)symbol handler:(BRPPCResolvedCall)handler {
    NSNumber *existing = _addresses[symbol];
    if (existing) {
        BRPPCResolvedCall copiedHandler = [handler copy];
        _handlers[existing] = copiedHandler;
        uint32_t address = existing.unsignedIntValue;
        if (address >= BRPPCGuestSyntheticHandlerBase && address < _nextAddress &&
            !(address & 3)) {
            NSUInteger index = (address - BRPPCGuestSyntheticHandlerBase) >> 2;
            _syntheticHandlers[index] = copiedHandler;
            if (index < _syntheticHandlerCapacity)
                _syntheticHandlerPointers[index] = (__bridge void *)copiedHandler;
        }
        _cachedHandler = nil;
        return existing.unsignedIntValue;
    }
    uint32_t address = _nextAddress;
    _nextAddress += 4;
    NSNumber *key = @(address);
    _addresses[symbol] = key;
    BRPPCResolvedCall copiedHandler = [handler copy];
    _handlers[key] = copiedHandler;
    NSUInteger handlerIndex = _syntheticHandlers.count;
    if (handlerIndex >= _syntheticHandlerCapacity) {
        NSUInteger capacity = MAX((NSUInteger)256, _syntheticHandlerCapacity * 2);
        void **pointers = realloc(_syntheticHandlerPointers, capacity * sizeof(*pointers));
        if (pointers) {
            memset(pointers + _syntheticHandlerCapacity, 0,
                   (capacity - _syntheticHandlerCapacity) * sizeof(*pointers));
            _syntheticHandlerPointers = pointers;
            _syntheticHandlerCapacity = capacity;
        }
    }
    [_syntheticHandlers addObject:copiedHandler];
    if (handlerIndex < _syntheticHandlerCapacity)
        _syntheticHandlerPointers[handlerIndex] = (__bridge void *)copiedHandler;
    _cachedHandler = nil;
    _namesByAddress[key] = symbol;
    _minimumHandlerAddress = MIN(_minimumHandlerAddress, address);
    _maximumHandlerAddress = MAX(_maximumHandlerAddress, address);
    return address;
}

- (BOOL)registerSymbol:(NSString *)symbol atAddress:(uint32_t)address
               handler:(BRPPCResolvedCall)handler error:(NSError **)error {
    NSNumber *key = @(address);
    if ((_handlers[key] && ![_addresses[symbol] isEqual:key]) ||
        (_addresses[symbol] && ![_addresses[symbol] isEqual:key])) {
        NSString *existingSymbol = [_addresses allKeysForObject:key].firstObject;
        if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:2
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Resolver address 0x%08x conflicts with %@.",
                                           address, existingSymbol ?: symbol]}];
        return NO;
    }
    _addresses[symbol] = key;
    _handlers[key] = [handler copy];
    _cachedHandler = nil;
    _namesByAddress[key] = symbol;
    _minimumHandlerAddress = MIN(_minimumHandlerAddress, address);
    _maximumHandlerAddress = MAX(_maximumHandlerAddress, address);
    return YES;
}

- (uint32_t)addressForSymbol:(NSString *)symbol {
    return _addresses[symbol].unsignedIntValue;
}

- (uint32_t)addressForSymbol:(NSString *)symbol lazy:(BOOL)lazy error:(NSError **)error {
    uint32_t address = [self addressForSymbol:symbol];
    if (!address && self.missingSymbolResolver)
        address = self.missingSymbolResolver(symbol, lazy, error);
    return address;
}

- (BOOL)dispatchState:(BRPPCState *)state handled:(BOOL *)handled error:(NSError **)error {
    if (state->pc < _minimumHandlerAddress || state->pc > _maximumHandlerAddress) {
        *handled = NO;
        return YES;
    }
    BRPPCResolvedCall __unsafe_unretained call = nil;
    BOOL synthetic = state->pc >= BRPPCGuestSyntheticHandlerBase && state->pc < _nextAddress &&
        !(state->pc & 3);
    if (_cachedHandler && _cachedHandlerAddress == state->pc) {
        call = _cachedHandler;
    } else if (synthetic) {
        NSUInteger index = (state->pc - BRPPCGuestSyntheticHandlerBase) >> 2;
        if (index < _syntheticHandlerCapacity && _syntheticHandlerPointers[index])
            call = (__bridge BRPPCResolvedCall)_syntheticHandlerPointers[index];
        else
            call = _syntheticHandlers[index];
    } else {
        call = _handlers[@(state->pc)];
    }
    if (call && !synthetic && (!_cachedHandler || _cachedHandlerAddress != state->pc)) {
        _cachedHandlerAddress = state->pc;
        _cachedHandler = call;
    }
    *handled = call != nil;
    if (call && _resolveTraceEnabled)
        fprintf(stderr, "resolve %s pc=0x%08x\n",
                _namesByAddress[@(state->pc)].UTF8String, state->pc);
    if (!call) return YES;





    uint32_t callerLinkRegister = state->lr;
    BOOL succeeded = call(state, error);
    if (_callbackDepth) {
        uint32_t firstReturn = BRPPCGuestSyntheticHandlerBase;
        uint32_t lastReturn = BRPPCGuestSyntheticHandlerBase +
            (BRPPCGuestCallbackSlotCount - 1u) * 4u;
        uint32_t expectedReturn = BRPPCGuestSyntheticHandlerBase + (uint32_t)(_callbackDepth - 1) * 4u;
        BOOL leakedNestedReturn = state->lr >= firstReturn && state->lr <= lastReturn &&
            !(state->lr & 3) && state->lr != expectedReturn;
        if (leakedNestedReturn) {
            uint32_t leakedAddress = state->lr;
            state->lr = callerLinkRegister;
            if (state->pc == leakedAddress) state->pc = callerLinkRegister;
        }
    }
    return succeeded;
}

- (BRPPCStopReason)runAttachedCPUWithInstructionLimit:(uint64_t)instructionLimit {
    return [self runAttachedCPUWithInstructionLimit:instructionLimit
                           executedInstructionCount:NULL];
}

- (BRPPCStopReason)runAttachedCPUWithInstructionLimit:(uint64_t)instructionLimit
                              executedInstructionCount:(uint64_t *)executedInstructionCount {
    return [_cpu runWithInstructionLimit:instructionLimit
        stoppingBeforeProgramCounterFrom:_minimumHandlerAddress
                                  through:_maximumHandlerAddress
                 executedInstructionCount:executedInstructionCount];
}

- (BOOL)installExtension:(id<BRPPCResolveExtension>)extension error:(NSError **)error {
    if (![extension conformsToProtocol:@protocol(BRPPCResolveExtension)]) {
        if (error) *error = [NSError errorWithDomain:BRPPCResolveErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Resolve extension does not implement BRPPCResolveExtension."}];
        return NO;
    }
    return [extension installInRegistry:self error:error];
}
@end
