#import "BRPPCMathResolve.h"
#import "BRPPCAddressSpace.h"
#include <errno.h>
#include <math.h>

@interface BRPPCMathResolve ()
@property(nonatomic, weak) BRPPCResolveRegistry *registry;
@end

@implementation BRPPCMathResolve

static void FinishFP(BRPPCState *state, double value) {
    state->fpr[1] = value;
    state->pc = state->lr;
}

static void FinishWord(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

static void FinishLongLong(BRPPCState *state, uint64_t value) {
    state->gpr[3] = (uint32_t)(value >> 32);
    state->gpr[4] = (uint32_t)value;
    state->pc = state->lr;
}

- (BOOL)writeDouble:(double)value address:(uint32_t)address {
    uint64_t bits = 0; memcpy(&bits, &value, 8);
    return [_registry.memory writeUInt32:(uint32_t)(bits >> 32) address:address] &&
           [_registry.memory writeUInt32:(uint32_t)bits address:address + 4];
}

- (BOOL)writeFloat:(float)value address:(uint32_t)address {
    uint32_t bits = 0; memcpy(&bits, &value, 4);
    return [_registry.memory writeUInt32:bits address:address];
}

- (void)copyErrno {
    if (errno && _registry.guestErrnoAddress)
        [_registry.memory writeUInt32:(uint32_t)errno address:_registry.guestErrnoAddress];
}

- (void)registerUnaryDouble:(NSString *)name function:(double (*)(double))function {
    __weak typeof(self) weakSelf = self;
    [_registry registerSymbol:[@"_" stringByAppendingString:name]
        handler:^BOOL(BRPPCState *state, NSError **error) {
            (void)error; errno = 0; double value = function(state->fpr[1]);
            [weakSelf copyErrno]; FinishFP(state, value); return YES;
        }];
}

- (void)registerUnaryFloat:(NSString *)name function:(float (*)(float))function {
    __weak typeof(self) weakSelf = self;
    [_registry registerSymbol:[@"_" stringByAppendingString:name]
        handler:^BOOL(BRPPCState *state, NSError **error) {
            (void)error; errno = 0; float value = function((float)state->fpr[1]);
            [weakSelf copyErrno]; FinishFP(state, value); return YES;
        }];
}

- (void)registerBinaryDouble:(NSString *)name function:(double (*)(double, double))function {
    __weak typeof(self) weakSelf = self;
    [_registry registerSymbol:[@"_" stringByAppendingString:name]
        handler:^BOOL(BRPPCState *state, NSError **error) {
            (void)error; errno = 0; double value = function(state->fpr[1], state->fpr[2]);
            [weakSelf copyErrno]; FinishFP(state, value); return YES;
        }];
}

- (void)registerBinaryFloat:(NSString *)name function:(float (*)(float, float))function {
    __weak typeof(self) weakSelf = self;
    [_registry registerSymbol:[@"_" stringByAppendingString:name]
        handler:^BOOL(BRPPCState *state, NSError **error) {
            (void)error; errno = 0;
            float value = function((float)state->fpr[1], (float)state->fpr[2]);
            [weakSelf copyErrno]; FinishFP(state, value); return YES;
        }];
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    self.registry = registry;
#define UNARY(name) [self registerUnaryDouble:@#name function:name]; [self registerUnaryFloat:@#name "f" function:name##f]
#define BINARY(name) [self registerBinaryDouble:@#name function:name]; [self registerBinaryFloat:@#name "f" function:name##f]
    UNARY(acos); UNARY(acosh); UNARY(asin); UNARY(asinh); UNARY(atan); UNARY(atanh);
    UNARY(cbrt); UNARY(ceil); UNARY(cos); UNARY(cosh); UNARY(erf); UNARY(erfc);
    UNARY(exp); UNARY(exp2); UNARY(expm1); UNARY(fabs); UNARY(floor); UNARY(lgamma);
    UNARY(log); UNARY(log10); UNARY(log1p); UNARY(log2); UNARY(logb); UNARY(nearbyint);
    UNARY(rint); UNARY(round); UNARY(sin); UNARY(sinh); UNARY(sqrt); UNARY(tan);
    UNARY(tanh); UNARY(tgamma); UNARY(trunc);
    [self registerUnaryDouble:@"j0" function:j0];
    [self registerUnaryDouble:@"j1" function:j1];
    [self registerUnaryDouble:@"y0" function:y0];
    [self registerUnaryDouble:@"y1" function:y1];
    BINARY(atan2); BINARY(copysign); BINARY(fdim); BINARY(fmax); BINARY(fmin);
    BINARY(fmod); BINARY(hypot); BINARY(nextafter); BINARY(pow); BINARY(remainder);
#undef UNARY
#undef BINARY
    __weak typeof(self) weakSelf = self;
    [registry registerSymbol:@"_fma" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; double value = fma(state->fpr[1], state->fpr[2], state->fpr[3]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_fmaf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0;
        float value = fmaf((float)state->fpr[1], (float)state->fpr[2], (float)state->fpr[3]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_ldexp" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; double value = ldexp(state->fpr[1], (int)state->gpr[5]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_ldexpf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; float value = ldexpf((float)state->fpr[1], (int)state->gpr[4]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_scalbn" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; double value = scalbn(state->fpr[1], (int)state->gpr[5]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_scalbnf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; float value = scalbnf((float)state->fpr[1], (int)state->gpr[4]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_scalbln" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; double value = scalbln(state->fpr[1], (long)(int32_t)state->gpr[5]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_scalblnf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; errno = 0; float value = scalblnf((float)state->fpr[1], (long)(int32_t)state->gpr[4]);
        [weakSelf copyErrno]; FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_frexp" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int exponent = 0; double value = frexp(state->fpr[1], &exponent);
        if (![weakSelf.registry.memory writeUInt32:(uint32_t)exponent address:state->gpr[5]]) return NO;
        FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_frexpf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int exponent = 0; float value = frexpf((float)state->fpr[1], &exponent);
        if (![weakSelf.registry.memory writeUInt32:(uint32_t)exponent address:state->gpr[4]]) return NO;
        FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_modf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; double integral = 0, value = modf(state->fpr[1], &integral);
        if (![weakSelf writeDouble:integral address:state->gpr[5]]) return NO;
        FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_modff" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float integral = 0, value = modff((float)state->fpr[1], &integral);
        if (![weakSelf writeFloat:integral address:state->gpr[4]]) return NO;
        FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_remquo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int quotient = 0; double value = remquo(state->fpr[1], state->fpr[2], &quotient);
        if (![weakSelf.registry.memory writeUInt32:(uint32_t)quotient address:state->gpr[7]]) return NO;
        FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_remquof" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int quotient = 0;
        float value = remquof((float)state->fpr[1], (float)state->fpr[2], &quotient);
        if (![weakSelf.registry.memory writeUInt32:(uint32_t)quotient address:state->gpr[5]]) return NO;
        FinishFP(state, value); return YES;
    }];
    [registry registerSymbol:@"_jn" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishFP(state, jn((int)state->gpr[3], state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_yn" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishFP(state, yn((int)state->gpr[3], state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_ilogb" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishWord(state, (uint32_t)ilogb(state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_ilogbf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishWord(state, (uint32_t)ilogbf((float)state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_lround" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishWord(state, (uint32_t)lround(state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_lroundf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishWord(state, (uint32_t)lroundf((float)state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_lrint" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishWord(state, (uint32_t)lrint(state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_lrintf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishWord(state, (uint32_t)lrintf((float)state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_llround" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishLongLong(state, (uint64_t)llround(state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_llroundf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishLongLong(state, (uint64_t)llroundf((float)state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_llrint" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishLongLong(state, (uint64_t)llrint(state->fpr[1])); return YES;
    }];
    [registry registerSymbol:@"_llrintf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; FinishLongLong(state, (uint64_t)llrintf((float)state->fpr[1])); return YES;
    }];
    return YES;
}

@end
