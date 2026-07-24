#import "BRPPCAccelerateResolve.h"
#import "BRPPCAddressSpace.h"
#import <Accelerate/Accelerate.h>

static BOOL BRVReadFloat(BRPPCAddressSpace *memory, uint32_t address, float *value) {
    uint32_t bits = 0;
    if (![memory readUInt32:&bits address:address]) return NO;
    memcpy(value, &bits, sizeof(bits));
    return YES;
}

static BOOL BRVWriteFloat(BRPPCAddressSpace *memory, uint32_t address, float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    return [memory writeUInt32:bits address:address];
}

static BOOL BRVAddress(uint32_t base, int32_t stride, uint32_t index, uint32_t *address) {
    int64_t offset = (int64_t)stride * index * sizeof(float);
    int64_t result = (int64_t)base + offset;
    if (result < 0 || result > UINT32_MAX) return NO;
    *address = (uint32_t)result;
    return YES;
}

static void BRVReturn(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

typedef struct {
    uint32_t data;
    uint32_t width;
    uint32_t height;
    uint32_t rowBytes;
} BRVImageBuffer;

static BOOL BRVReadImageBuffer(BRPPCAddressSpace *memory, uint32_t address,
                               BRVImageBuffer *buffer) {
    return address && [memory readUInt32:&buffer->data address:address] &&
        [memory readUInt32:&buffer->height address:address + 4] &&
        [memory readUInt32:&buffer->width address:address + 8] &&
        [memory readUInt32:&buffer->rowBytes address:address + 12] &&
        buffer->rowBytes >= buffer->width * 4;
}

static BOOL BRVReadInt16(BRPPCAddressSpace *memory, uint32_t address, int16_t *value) {
    uint8_t bytes[2];
    if (![memory readBytes:bytes address:address length:2]) return NO;
    *value = (int16_t)((uint16_t)bytes[0] << 8 | bytes[1]);
    return YES;
}

@implementation BRPPCAccelerateResolve
- (instancetype)init { return [super initWithFrameworkName:@"Accelerate"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    [registry registerSymbol:@"_vDSP_vclr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        int32_t stride = (int32_t)state->gpr[4];
        for (uint32_t i = 0; i < state->gpr[5]; i++) {
            uint32_t address = 0;
            if (!BRVAddress(state->gpr[3], stride, i, &address) ||
                !BRVWriteFloat(registry.memory, address, 0)) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_vDSP_vfill" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float value = 0;
        if (!BRVReadFloat(registry.memory, state->gpr[3], &value)) return NO;
        int32_t stride = (int32_t)state->gpr[5];
        for (uint32_t i = 0; i < state->gpr[6]; i++) {
            uint32_t address = 0;
            if (!BRVAddress(state->gpr[4], stride, i, &address) ||
                !BRVWriteFloat(registry.memory, address, value)) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    void (^registerScalarMultiply)(NSString *) = ^(NSString *symbol) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; float scalar = 0;
            if (!BRVReadFloat(registry.memory, state->gpr[5], &scalar)) return NO;
            for (uint32_t i = 0; i < state->gpr[8]; i++) {
                uint32_t input = 0, output = 0; float value = 0;
                if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &input) ||
                    !BRVAddress(state->gpr[6], (int32_t)state->gpr[7], i, &output) ||
                    !BRVReadFloat(registry.memory, input, &value) ||
                    !BRVWriteFloat(registry.memory, output, value * scalar)) return NO;
            }
            BRVReturn(state, 0); return YES;
        }];
    };
    registerScalarMultiply(@"_vDSP_vsmul");
    registerScalarMultiply(@"_vsmul");
    void (^registerBinary)(NSString *, BOOL) = ^(NSString *symbol, BOOL multiply) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            for (uint32_t i = 0; i < state->gpr[9]; i++) {
                uint32_t leftAddress = 0, rightAddress = 0, outputAddress = 0;
                float left = 0, right = 0;
                if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &leftAddress) ||
                    !BRVAddress(state->gpr[5], (int32_t)state->gpr[6], i, &rightAddress) ||
                    !BRVAddress(state->gpr[7], (int32_t)state->gpr[8], i, &outputAddress) ||
                    !BRVReadFloat(registry.memory, leftAddress, &left) ||
                    !BRVReadFloat(registry.memory, rightAddress, &right) ||
                    !BRVWriteFloat(registry.memory, outputAddress,
                                   multiply ? left * right : left + right)) return NO;
            }
            BRVReturn(state, 0); return YES;
        }];
    };
    registerBinary(@"_vadd", NO);
    registerBinary(@"_vmul", YES);
    [registry registerSymbol:@"_vDSP_vabs" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        for (uint32_t i = 0; i < state->gpr[7]; i++) { uint32_t input = 0, output = 0; float value = 0;
            if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &input) ||
                !BRVAddress(state->gpr[5], (int32_t)state->gpr[6], i, &output) ||
                !BRVReadFloat(registry.memory, input, &value) || !BRVWriteFloat(registry.memory, output, fabsf(value))) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_vDSP_vmax" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        for (uint32_t i = 0; i < state->gpr[9]; i++) { uint32_t a = 0, b = 0, output = 0; float av = 0, bv = 0;
            if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &a) ||
                !BRVAddress(state->gpr[5], (int32_t)state->gpr[6], i, &b) ||
                !BRVAddress(state->gpr[7], (int32_t)state->gpr[8], i, &output) ||
                !BRVReadFloat(registry.memory, a, &av) || !BRVReadFloat(registry.memory, b, &bv) ||
                !BRVWriteFloat(registry.memory, output, MAX(av, bv))) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_vDSP_maxmgv" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float maximum = 0;
        for (uint32_t i = 0; i < state->gpr[5]; i++) { uint32_t address = 0; float value = 0;
            if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &address) || !BRVReadFloat(registry.memory, address, &value)) return NO;
            maximum = MAX(maximum, fabsf(value));
        }
        if (!BRVWriteFloat(registry.memory, state->gpr[6], maximum)) return NO; BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_vDSP_vsma" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float scalar = 0;
        if (!BRVReadFloat(registry.memory, state->gpr[5], &scalar)) return NO;
        uint32_t count = state->gpr[10];
        for (uint32_t i = 0; i < count; i++) { uint32_t a = 0, c = 0, output = 0; float av = 0, cv = 0;
            if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &a) ||
                !BRVAddress(state->gpr[6], (int32_t)state->gpr[7], i, &c) ||
                !BRVAddress(state->gpr[8], (int32_t)state->gpr[9], i, &output) ||
                !BRVReadFloat(registry.memory, a, &av) || !BRVReadFloat(registry.memory, c, &cv) ||
                !BRVWriteFloat(registry.memory, output, av * scalar + cv)) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_vDSP_vma" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = 0;
        if (![registry.memory readUInt32:&count address:state->gpr[1] + 56]) return NO;
        for (uint32_t i = 0; i < count; i++) { uint32_t a = 0, b = 0, c = 0, output = 0; float av = 0, bv = 0, cv = 0;
            if (!BRVAddress(state->gpr[3], (int32_t)state->gpr[4], i, &a) || !BRVAddress(state->gpr[5], (int32_t)state->gpr[6], i, &b) ||
                !BRVAddress(state->gpr[7], (int32_t)state->gpr[8], i, &c) || !BRVAddress(state->gpr[9], (int32_t)state->gpr[10], i, &output) ||
                !BRVReadFloat(registry.memory, a, &av) || !BRVReadFloat(registry.memory, b, &bv) || !BRVReadFloat(registry.memory, c, &cv) ||
                !BRVWriteFloat(registry.memory, output, av * bv + cv)) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_create_fftsetup" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t setup = registry.guestAllocator ? registry.guestAllocator(8, YES) : 0;
        if (setup) { [registry.memory writeUInt32:state->gpr[3] address:setup]; [registry.memory writeUInt32:state->gpr[4] address:setup + 4]; }
        BRVReturn(state, setup); return YES;
    }];
    [registry registerSymbol:@"_destroy_fftsetup" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; if (state->gpr[3] && registry.guestDeallocator) registry.guestDeallocator(state->gpr[3]); BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_fft_zip" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t realAddress = 0, imaginaryAddress = 0;
        if (!state->gpr[4] || ![registry.memory readUInt32:&realAddress address:state->gpr[4]] ||
            ![registry.memory readUInt32:&imaginaryAddress address:state->gpr[4] + 4]) return NO;
        uint32_t log2Count = state->gpr[6];
        if (log2Count >= 31 || !realAddress || !imaginaryAddress) { BRVReturn(state, 0); return YES; }
        uint32_t count = 1u << log2Count; int32_t stride = (int32_t)state->gpr[5];
        NSMutableData *realData = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(float)];
        NSMutableData *imaginaryData = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(float)];
        float *real = realData.mutableBytes, *imaginary = imaginaryData.mutableBytes;
        for (uint32_t i = 0; i < count; i++) { uint32_t r = 0, im = 0;
            if (!BRVAddress(realAddress, stride, i, &r) || !BRVAddress(imaginaryAddress, stride, i, &im) ||
                !BRVReadFloat(registry.memory, r, &real[i]) || !BRVReadFloat(registry.memory, im, &imaginary[i])) return NO;
        }
        for (uint32_t i = 1, j = 0; i < count; i++) { uint32_t bit = count >> 1;
            while (j & bit) { j ^= bit; bit >>= 1; } j ^= bit;
            if (i < j) { float swap = real[i]; real[i] = real[j]; real[j] = swap;
                swap = imaginary[i]; imaginary[i] = imaginary[j]; imaginary[j] = swap; }
        }
        float direction = (int32_t)state->gpr[7] < 0 ? -1.0f : 1.0f;
        for (uint32_t length = 2; length <= count; length <<= 1) {
            float angle = direction * 2.0f * (float)M_PI / length;
            float stepReal = cosf(angle), stepImaginary = sinf(angle);
            for (uint32_t start = 0; start < count; start += length) {
                float twiddleReal = 1, twiddleImaginary = 0;
                for (uint32_t offset = 0; offset < length / 2; offset++) {
                    uint32_t even = start + offset, odd = even + length / 2;
                    float oddReal = real[odd] * twiddleReal - imaginary[odd] * twiddleImaginary;
                    float oddImaginary = real[odd] * twiddleImaginary + imaginary[odd] * twiddleReal;
                    real[odd] = real[even] - oddReal; imaginary[odd] = imaginary[even] - oddImaginary;
                    real[even] += oddReal; imaginary[even] += oddImaginary;
                    float nextReal = twiddleReal * stepReal - twiddleImaginary * stepImaginary;
                    twiddleImaginary = twiddleReal * stepImaginary + twiddleImaginary * stepReal;
                    twiddleReal = nextReal;
                }
            }
            if (length == count) break;
        }
        for (uint32_t i = 0; i < count; i++) { uint32_t r = 0, im = 0;
            if (!BRVAddress(realAddress, stride, i, &r) || !BRVAddress(imaginaryAddress, stride, i, &im) ||
                !BRVWriteFloat(registry.memory, r, real[i]) || !BRVWriteFloat(registry.memory, im, imaginary[i])) return NO;
        }
        BRVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_vImageHistogramCalculation_ARGB8888"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRVImageBuffer source;
            if (!BRVReadImageBuffer(registry.memory, state->gpr[3], &source)) {
                BRVReturn(state, (uint32_t)kvImageRoiLargerThanInputBuffer); return YES;
            }
            uint32_t histogramAddresses[4];
            for (NSUInteger channel = 0; channel < 4; channel++)
                if (![registry.memory readUInt32:&histogramAddresses[channel]
                    address:state->gpr[4] + (uint32_t)channel * 4] || !histogramAddresses[channel]) {
                    BRVReturn(state, (uint32_t)kvImageNullPointerArgument); return YES;
                }
            uint32_t counts[4][256] = {{0}};
            NSMutableData *row = [NSMutableData dataWithLength:source.width * 4];
            for (uint32_t y = 0; y < source.height; y++) {
                if (![registry.memory readBytes:row.mutableBytes
                    address:source.data + y * source.rowBytes length:row.length]) return NO;
                const uint8_t *pixels = row.bytes;
                for (uint32_t x = 0; x < source.width; x++)
                    for (NSUInteger channel = 0; channel < 4; channel++)
                        counts[channel][pixels[x * 4 + channel]]++;
            }
            for (NSUInteger channel = 0; channel < 4; channel++)
                for (NSUInteger bin = 0; bin < 256; bin++)
                    if (![registry.memory writeUInt32:counts[channel][bin]
                        address:histogramAddresses[channel] + (uint32_t)bin * 4]) return NO;
            BRVReturn(state, 0); return YES;
        }];
    [registry registerSymbol:@"_vImageMatrixMultiply_ARGB8888"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRVImageBuffer source, destination;
            if (!BRVReadImageBuffer(registry.memory, state->gpr[3], &source) ||
                !BRVReadImageBuffer(registry.memory, state->gpr[4], &destination) ||
                source.width != destination.width || source.height != destination.height) {
                BRVReturn(state, (uint32_t)kvImageRoiLargerThanInputBuffer); return YES;
            }
            int16_t matrix[16], preBias[4] = {0}; int32_t postBias[4] = {0};
            for (NSUInteger i = 0; i < 16; i++)
                if (!BRVReadInt16(registry.memory, state->gpr[5] + (uint32_t)i * 2, &matrix[i])) return NO;
            if (state->gpr[7]) for (NSUInteger i = 0; i < 4; i++)
                if (!BRVReadInt16(registry.memory, state->gpr[7] + (uint32_t)i * 2, &preBias[i])) return NO;
            if (state->gpr[8]) for (NSUInteger i = 0; i < 4; i++) {
                uint32_t value = 0;
                if (![registry.memory readUInt32:&value
                    address:state->gpr[8] + (uint32_t)i * 4]) return NO;
                postBias[i] = (int32_t)value;
            }
            int32_t divisor = (int32_t)state->gpr[6]; if (!divisor) divisor = 1;
            NSMutableData *input = [NSMutableData dataWithLength:source.width * 4];
            NSMutableData *output = [NSMutableData dataWithLength:destination.width * 4];
            for (uint32_t y = 0; y < source.height; y++) {
                if (![registry.memory readBytes:input.mutableBytes
                    address:source.data + y * source.rowBytes length:input.length]) return NO;
                const uint8_t *sourcePixels = input.bytes; uint8_t *destinationPixels = output.mutableBytes;
                for (uint32_t x = 0; x < source.width; x++) for (NSUInteger rowIndex = 0; rowIndex < 4; rowIndex++) {
                    int64_t sum = postBias[rowIndex];
                    for (NSUInteger column = 0; column < 4; column++)
                        sum += matrix[rowIndex * 4 + column] *
                               ((int32_t)sourcePixels[x * 4 + column] + preBias[column]);
                    int64_t value = sum / divisor; destinationPixels[x * 4 + rowIndex] =
                        (uint8_t)MAX(0, MIN(255, value));
                }
                if (![registry.memory writeBytes:output.bytes
                    address:destination.data + y * destination.rowBytes length:output.length]) return NO;
            }
            BRVReturn(state, 0); return YES;
        }];
    return YES;
}
@end
