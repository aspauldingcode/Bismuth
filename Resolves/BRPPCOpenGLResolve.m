#import "BRPPCOpenGLResolve.h"
#import "BRPPCAddressSpace.h"
#import <OpenGL/gl.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@interface BRPPCOpenGLResolve ()
@property(nonatomic) void *openGLHandle;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *guestStrings;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *clientArrays;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *bufferArrays;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *arrayFunctions;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableData *> *clientArrayData;
@property(nonatomic, strong) NSMutableData *clientIndexData;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableData *> *bufferData;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *bufferUsage;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *dirtyBuffers;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableData *> *translatedBufferData;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *translatedBufferLayoutGenerations;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *elementBufferTypes;
@property(nonatomic) NSUInteger bufferLayoutGeneration;
@property(nonatomic) uint32_t boundArrayBuffer;
@property(nonatomic) uint32_t boundElementArrayBuffer;
@property(nonatomic) uint32_t packAlignment;
@property(nonatomic) uint32_t unpackAlignment;
@end

static void BRGLReturn(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value; state->pc = state->lr;
}

static void *BRGLSymbol(void *handle, NSString *symbol) {
    const char *name = symbol.UTF8String;
    return dlsym(handle ?: RTLD_DEFAULT, name[0] == '_' ? name + 1 : name);
}

static uint32_t BRGLComponentCount(uint32_t format) {
    switch (format) {
        case GL_RED: case GL_ALPHA: case GL_LUMINANCE: return 1;
        case GL_LUMINANCE_ALPHA: return 2;
        case GL_RGB: case GL_BGR: return 3;
        case GL_RGBA: case GL_BGRA: return 4;
        default: return 4;
    }
}

static uint32_t BRGLTypeSize(uint32_t type) {
    switch (type) {
        case GL_BYTE: case GL_UNSIGNED_BYTE: case GL_UNSIGNED_BYTE_3_3_2: case GL_UNSIGNED_BYTE_2_3_3_REV: return 1;
        case GL_SHORT: case GL_UNSIGNED_SHORT: case GL_HALF_FLOAT:
        case GL_UNSIGNED_SHORT_4_4_4_4: case GL_UNSIGNED_SHORT_5_5_5_1: case GL_UNSIGNED_SHORT_5_6_5: case GL_UNSIGNED_SHORT_5_6_5_REV:
        case GL_UNSIGNED_SHORT_4_4_4_4_REV: case GL_UNSIGNED_SHORT_1_5_5_5_REV: return 2;
        case GL_INT: case GL_UNSIGNED_INT: case GL_FLOAT:
        case GL_UNSIGNED_INT_8_8_8_8: case GL_UNSIGNED_INT_10_10_10_2: case GL_UNSIGNED_INT_8_8_8_8_REV: case GL_UNSIGNED_INT_2_10_10_10_REV: return 4;
        case GL_DOUBLE: return 8;
        default: return 1;
    }
}

static BOOL BRGLTypeIsPackedPixel(uint32_t type) {
    switch (type) {
        case GL_UNSIGNED_BYTE_3_3_2: case GL_UNSIGNED_SHORT_4_4_4_4: case GL_UNSIGNED_SHORT_5_5_5_1: case GL_UNSIGNED_INT_8_8_8_8: case GL_UNSIGNED_INT_10_10_10_2:
        case GL_UNSIGNED_BYTE_2_3_3_REV: case GL_UNSIGNED_SHORT_5_6_5: case GL_UNSIGNED_SHORT_5_6_5_REV: case GL_UNSIGNED_SHORT_4_4_4_4_REV: case GL_UNSIGNED_SHORT_1_5_5_5_REV:
        case GL_UNSIGNED_INT_8_8_8_8_REV: case GL_UNSIGNED_INT_2_10_10_10_REV: return YES;
        default: return NO;
    }
}

static BOOL BRGLPixelLayout(uint32_t width, uint32_t height, uint32_t format,
                            uint32_t type, uint32_t alignment, uint64_t *rowBytes,
                            uint64_t *stride, uint64_t *length) {
    uint64_t pixelSize = BRGLTypeSize(type);
    if (!BRGLTypeIsPackedPixel(type)) pixelSize *= BRGLComponentCount(format);
    uint64_t row = (uint64_t)width * pixelSize;
    uint64_t effectiveAlignment = alignment == 1 || alignment == 2 || alignment == 4 || alignment == 8
        ? alignment : 4;
    uint64_t padded = (row + effectiveAlignment - 1) & ~(effectiveAlignment - 1);
    if (width && row / width != pixelSize) return NO;
    if (height && padded > UINT64_MAX / height) return NO;
    if (rowBytes) *rowBytes = row;
    if (stride) *stride = padded;
    if (length) *length = padded * height;
    return padded * height <= UINT32_MAX;
}

typedef struct __attribute__((packed, may_alias)) { uint16_t value; } BRGLUnaligned16;
typedef struct __attribute__((packed, may_alias)) { uint32_t value; } BRGLUnaligned32;
typedef struct __attribute__((packed, may_alias)) { uint64_t value; } BRGLUnaligned64;

static void BRGLSwapElements(void *bytes, NSUInteger length, uint32_t elementSize) {
    if (elementSize <= 1) return;
    uint8_t *cursor = bytes;
    if (elementSize == 2) {
        for (NSUInteger offset = 0; offset + 2 <= length; offset += 2) {
            BRGLUnaligned16 *element = (BRGLUnaligned16 *)(cursor + offset);
            element->value = __builtin_bswap16(element->value);
        }
        return;
    }
    if (elementSize == 4) {
        for (NSUInteger offset = 0; offset + 4 <= length; offset += 4) {
            BRGLUnaligned32 *element = (BRGLUnaligned32 *)(cursor + offset);
            element->value = __builtin_bswap32(element->value);
        }
        return;
    }
    if (elementSize == 8) {
        for (NSUInteger offset = 0; offset + 8 <= length; offset += 8) {
            BRGLUnaligned64 *element = (BRGLUnaligned64 *)(cursor + offset);
            element->value = __builtin_bswap64(element->value);
        }
        return;
    }
    for (NSUInteger offset = 0; offset + elementSize <= length; offset += elementSize)
        for (uint32_t left = 0, right = elementSize - 1; left < right; left++, right--) {
            uint8_t temporary = cursor[offset + left];
            cursor[offset + left] = cursor[offset + right];
            cursor[offset + right] = temporary;
        }
}

static void BRGLSwapStridedElements(void *bytes, NSUInteger length, NSUInteger stride,
                                    NSUInteger componentLength, uint32_t elementSize) {
    if (elementSize <= 1 || !stride || !componentLength) return;
    uint8_t *cursor = bytes;
    if (elementSize == 2) {
        for (NSUInteger vertex = 0; vertex + componentLength <= length; vertex += stride)
            for (NSUInteger component = 0; component + 2 <= componentLength; component += 2) {
                BRGLUnaligned16 *element = (BRGLUnaligned16 *)(cursor + vertex + component);
                element->value = __builtin_bswap16(element->value);
            }
        return;
    }
    if (elementSize == 4) {
        for (NSUInteger vertex = 0; vertex + componentLength <= length; vertex += stride)
            for (NSUInteger component = 0; component + 4 <= componentLength; component += 4) {
                BRGLUnaligned32 *element = (BRGLUnaligned32 *)(cursor + vertex + component);
                element->value = __builtin_bswap32(element->value);
            }
        return;
    }
    if (elementSize == 8) {
        for (NSUInteger vertex = 0; vertex + componentLength <= length; vertex += stride)
            for (NSUInteger component = 0; component + 8 <= componentLength; component += 8) {
                BRGLUnaligned64 *element = (BRGLUnaligned64 *)(cursor + vertex + component);
                element->value = __builtin_bswap64(element->value);
            }
        return;
    }
    for (NSUInteger vertex = 0; vertex + componentLength <= length; vertex += stride)
        BRGLSwapElements(cursor + vertex, componentLength, elementSize);
}

static uint32_t BRGLIntegerResultCount(uint32_t parameter) {
    switch (parameter) {
        case GL_VIEWPORT:
        case GL_SCISSOR_BOX:
        case GL_COLOR_WRITEMASK:
            return 4;
        case GL_POLYGON_MODE:
        case GL_ALIASED_POINT_SIZE_RANGE:
        case GL_ALIASED_LINE_WIDTH_RANGE:
            return 2;
        default:
            return 1;
    }
}

static void *BRGLDecodedPointer(BRPPCResolveRegistry *registry, uint32_t handle) {
    id object = registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
    return [object isKindOfClass:[NSValue class]] ? [object pointerValue] : NULL;
}

static uint32_t BRGLEncodePointer(BRPPCResolveRegistry *registry, void *pointer) {
    return pointer && registry.guestObjectEncoder
        ? registry.guestObjectEncoder([NSValue valueWithPointer:pointer]) : 0;
}

@implementation BRPPCOpenGLResolve
- (instancetype)init { return [super initWithFrameworkName:@"OpenGL"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    self.openGLHandle = [self openFramework];
    self.guestStrings = [NSMutableDictionary dictionary];
    self.clientArrays = [NSMutableDictionary dictionary];
    self.bufferArrays = [NSMutableDictionary dictionary];
    self.arrayFunctions = [NSMutableDictionary dictionary];
    self.clientArrayData = [NSMutableDictionary dictionary];
    self.clientIndexData = [NSMutableData data];
    self.bufferData = [NSMutableDictionary dictionary];
    self.bufferUsage = [NSMutableDictionary dictionary];
    self.dirtyBuffers = [NSMutableSet set];
    self.translatedBufferData = [NSMutableDictionary dictionary];
    self.translatedBufferLayoutGenerations = [NSMutableDictionary dictionary];
    self.elementBufferTypes = [NSMutableDictionary dictionary];
    self.bufferLayoutGeneration = 1;
    self.packAlignment = 4;
    self.unpackAlignment = 4;
    __weak typeof(self) weakSelf = self;
    void (^invalidateBufferLayouts)(void) = ^{
        if (++weakSelf.bufferLayoutGeneration == 0) {
            weakSelf.bufferLayoutGeneration = 1;
            [weakSelf.translatedBufferLayoutGenerations removeAllObjects];
        }
    };
    NSArray<NSString *> *void0 = @[@"_glFlush", @"_glFinish", @"_glLoadIdentity",
        @"_glPopMatrix", @"_glPushMatrix", @"_glEnd", @"_glPopClientAttrib"];
    for (NSString *symbol in void0) {
        void (*function)(void) = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (function) function(); BRGLReturn(state, 0); return YES;
        }];
    }
    NSArray<NSString *> *void1 = @[@"_glClear", @"_glDisable", @"_glEnable", @"_glBegin",
        @"_glDepthMask", @"_glDrawBuffer", @"_glMatrixMode",
        @"_glPushClientAttrib", @"_glStencilMask", @"_glDepthFunc",
        @"_glDisableClientState", @"_glEnableClientState"];
    for (NSString *symbol in void1) {
        void (*function)(uint32_t) = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (function) function(state->gpr[3]); BRGLReturn(state, 0); return YES;
        }];
    }
    NSArray<NSString *> *void2 = @[@"_glTexCoord2i", @"_glBlendFunc"];
    for (NSString *symbol in void2) {
        void (*function)(int32_t, int32_t) = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (function) function((int32_t)state->gpr[3], (int32_t)state->gpr[4]);
            BRGLReturn(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_glBindTexture", @"_glHint"]) {
        void (*function)(uint32_t, uint32_t) = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (function) function(state->gpr[3], state->gpr[4]);
            BRGLReturn(state, 0); return YES;
        }];
    }
    void (*pixelStorei)(uint32_t, int32_t) = BRGLSymbol(self.openGLHandle, @"_glPixelStorei");
    [registry registerSymbol:@"_glPixelStorei" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t parameter = state->gpr[3];
        uint32_t value = state->gpr[4];
        if (parameter == GL_PACK_ALIGNMENT) weakSelf.packAlignment = value;
        else if (parameter == GL_UNPACK_ALIGNMENT) weakSelf.unpackAlignment = value;
        if (pixelStorei) pixelStorei(parameter, (int32_t)value);
        BRGLReturn(state, 0); return YES;
    }];
    void (*bindBuffer)(uint32_t, uint32_t) = BRGLSymbol(self.openGLHandle, @"_glBindBuffer");
    [registry registerSymbol:@"_glBindBuffer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (state->gpr[3] == GL_ARRAY_BUFFER) weakSelf.boundArrayBuffer = state->gpr[4];
        else if (state->gpr[3] == GL_ELEMENT_ARRAY_BUFFER) weakSelf.boundElementArrayBuffer = state->gpr[4];
        if (bindBuffer) bindBuffer(state->gpr[3], state->gpr[4]); BRGLReturn(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_glTexParameteri", @"_glTexEnvi"]) {
        void (*function)(uint32_t, uint32_t, int32_t) = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (function) function(state->gpr[3], state->gpr[4], (int32_t)state->gpr[5]);
            BRGLReturn(state, 0); return YES;
        }];
    }
    void (*clearColor)(float, float, float, float) =
        BRGLSymbol(self.openGLHandle, @"_glClearColor");
    [registry registerSymbol:@"_glClearColor" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (clearColor) clearColor((float)state->fpr[1], (float)state->fpr[2],
                                   (float)state->fpr[3], (float)state->fpr[4]);
        BRGLReturn(state, 0); return YES;
    }];
    void (*color4f)(float, float, float, float) = BRGLSymbol(self.openGLHandle, @"_glColor4f");
    [registry registerSymbol:@"_glColor4f" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (color4f) color4f((float)state->fpr[1], (float)state->fpr[2],
                             (float)state->fpr[3], (float)state->fpr[4]);
        BRGLReturn(state, 0); return YES;
    }];
    void (*vertex2f)(float, float) = BRGLSymbol(self.openGLHandle, @"_glVertex2f");
    [registry registerSymbol:@"_glVertex2f" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (vertex2f) vertex2f((float)state->fpr[1], (float)state->fpr[2]);
        BRGLReturn(state, 0); return YES;
    }];
    void (*colorMask)(uint8_t, uint8_t, uint8_t, uint8_t) =
        BRGLSymbol(self.openGLHandle, @"_glColorMask");
    [registry registerSymbol:@"_glColorMask" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (colorMask) colorMask(state->gpr[3] != 0, state->gpr[4] != 0,
                                 state->gpr[5] != 0, state->gpr[6] != 0);
        BRGLReturn(state, 0); return YES;
    }];
    void (*alphaFunc)(uint32_t, float) = BRGLSymbol(self.openGLHandle, @"_glAlphaFunc");
    [registry registerSymbol:@"_glAlphaFunc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (alphaFunc) alphaFunc(state->gpr[3], (float)state->fpr[1]); BRGLReturn(state, 0); return YES;
    }];
    void (*fogf)(uint32_t, float) = BRGLSymbol(self.openGLHandle, @"_glFogf");
    [registry registerSymbol:@"_glFogf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (fogf) fogf(state->gpr[3], (float)state->fpr[1]); BRGLReturn(state, 0); return YES;
    }];
    void (*fogi)(uint32_t, int32_t) = BRGLSymbol(self.openGLHandle, @"_glFogi");
    [registry registerSymbol:@"_glFogi" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (fogi) fogi(state->gpr[3], (int32_t)state->gpr[4]); BRGLReturn(state, 0); return YES;
    }];
    void (*fogfv)(uint32_t, const float *) = BRGLSymbol(self.openGLHandle, @"_glFogfv");
    [registry registerSymbol:@"_glFogfv" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float values[4] = {0};
        for (NSUInteger index = 0; index < 4; index++) {
            uint32_t bits = 0;
            if (![registry.memory readUInt32:&bits address:state->gpr[4] + (uint32_t)index * 4]) return NO;
            memcpy(values + index, &bits, sizeof(bits));
        }
        if (fogfv) fogfv(state->gpr[3], values); BRGLReturn(state, 0); return YES;
    }];
    void (*loadMatrixf)(const float *) = BRGLSymbol(self.openGLHandle, @"_glLoadMatrixf");
    [registry registerSymbol:@"_glLoadMatrixf" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float matrix[16];
        for (NSUInteger index = 0; index < 16; index++) {
            uint32_t bits = 0;
            if (![registry.memory readUInt32:&bits address:state->gpr[3] + (uint32_t)index * 4]) return NO;
            memcpy(matrix + index, &bits, sizeof(bits));
        }
        if (loadMatrixf) loadMatrixf(matrix); BRGLReturn(state, 0); return YES;
    }];
    void (*getIntegerv)(uint32_t, int32_t *) = BRGLSymbol(self.openGLHandle, @"_glGetIntegerv");
    [registry registerSymbol:@"_glGetIntegerv" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t values[16] = {0};
        if (getIntegerv) getIntegerv(state->gpr[3], values);
        uint32_t count = BRGLIntegerResultCount(state->gpr[3]);
        if (!state->gpr[4]) return NO;
        for (uint32_t index = 0; index < count; index++)
            if (![registry.memory writeUInt32:(uint32_t)values[index]
                                      address:state->gpr[4] + index * 4]) return NO;
        BRGLReturn(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_glColorPointer", @"_glTexCoordPointer", @"_glVertexPointer"]) {
        void (*function)(int32_t, uint32_t, int32_t, const void *) =
            BRGLSymbol(self.openGLHandle, symbol);
        self.arrayFunctions[symbol] = [NSValue valueWithPointer:function];
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (weakSelf.boundArrayBuffer) {
                NSDictionary *descriptor = @{ @"buffer": @(weakSelf.boundArrayBuffer),
                    @"size": @(state->gpr[3]), @"type": @(state->gpr[4]),
                    @"stride": @(state->gpr[5]), @"address": @(state->gpr[6]) };
                if (![weakSelf.bufferArrays[symbol] isEqual:descriptor]) {
                    weakSelf.bufferArrays[symbol] = descriptor;
                    invalidateBufferLayouts();
                }
                [weakSelf.clientArrays removeObjectForKey:symbol];
                if (function) function((int32_t)state->gpr[3], state->gpr[4],
                    (int32_t)state->gpr[5], (const void *)(uintptr_t)state->gpr[6]);
                BRGLReturn(state, 0); return YES;
            }
            if (weakSelf.bufferArrays[symbol]) {
                [weakSelf.bufferArrays removeObjectForKey:symbol];
                invalidateBufferLayouts();
            }
            weakSelf.clientArrays[symbol] = @{@"size": @(state->gpr[3]), @"type": @(state->gpr[4]),
                @"stride": @(state->gpr[5]), @"address": @(state->gpr[6])};
            BRGLReturn(state, 0); return YES;
        }];
    }
    BOOL (^prepareClientArrays)(uint32_t) = ^BOOL(uint32_t vertexCount) {
        for (NSString *symbol in weakSelf.clientArrays) {
            NSDictionary<NSString *, NSNumber *> *descriptor = weakSelf.clientArrays[symbol];
            uint32_t size = descriptor[@"size"].unsignedIntValue;
            uint32_t type = descriptor[@"type"].unsignedIntValue;
            uint32_t elementSize = BRGLTypeSize(type);
            uint32_t stride = descriptor[@"stride"].unsignedIntValue ?: size * elementSize;
            uint64_t length = (uint64_t)stride * vertexCount;
            if (length > UINT32_MAX) return NO;
            NSMutableData *data = weakSelf.clientArrayData[symbol];
            if (!data) {
                data = [NSMutableData dataWithLength:(NSUInteger)length];
                weakSelf.clientArrayData[symbol] = data;
            } else {
                data.length = (NSUInteger)length;
            }
            if (length && ![registry.memory readBytes:data.mutableBytes
                address:descriptor[@"address"].unsignedIntValue length:data.length]) return NO;
            if (elementSize > 1) {
                uint8_t *bytes = data.mutableBytes;
                BRGLSwapStridedElements(bytes, data.length, stride,
                                        (NSUInteger)size * elementSize, elementSize);
            }
            void (*function)(int32_t, uint32_t, int32_t, const void *) =
                [weakSelf.arrayFunctions[symbol] pointerValue];
            if (function) function((int32_t)size, type, (int32_t)stride, data.bytes);
            objc_setAssociatedObject(weakSelf, (__bridge const void *)symbol, data,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return YES;
    };
    void (*bindArrayBuffer)(uint32_t, uint32_t) =
        BRGLSymbol(self.openGLHandle, @"_glBindBuffer");
    void (*uploadArrayBuffer)(uint32_t, intptr_t, const void *, uint32_t) =
        BRGLSymbol(self.openGLHandle, @"_glBufferData");
    void (^prepareArrayBuffers)(void) = ^{
        NSUInteger generation = weakSelf.bufferLayoutGeneration;
        BOOL requiresTranslation = NO;
        for (NSDictionary<NSString *, NSNumber *> *descriptor in weakSelf.bufferArrays.allValues) {
            NSNumber *key = descriptor[@"buffer"];
            if ([weakSelf.dirtyBuffers containsObject:key] ||
                weakSelf.translatedBufferLayoutGenerations[key].unsignedIntegerValue != generation) {
                requiresTranslation = YES;
                break;
            }
        }
        if (!requiresTranslation) return;
        NSMutableSet<NSNumber *> *buffers = [NSMutableSet set];
        for (NSDictionary<NSString *, NSNumber *> *descriptor in weakSelf.bufferArrays.allValues)
            [buffers addObject:descriptor[@"buffer"]];
        for (NSNumber *key in buffers) {
            if (![weakSelf.dirtyBuffers containsObject:key] &&
                weakSelf.translatedBufferLayoutGenerations[key].unsignedIntegerValue == generation) continue;
            NSMutableData *original = weakSelf.bufferData[key];
            if (!original) {
                [weakSelf.translatedBufferData removeObjectForKey:key];
                weakSelf.translatedBufferLayoutGenerations[key] = @(generation);
                continue;
            }
            NSMutableData *translated = [original mutableCopy];
            for (NSString *symbol in weakSelf.bufferArrays) {
                NSDictionary<NSString *, NSNumber *> *descriptor = weakSelf.bufferArrays[symbol];
                if (![descriptor[@"buffer"] isEqual:key]) continue;
                uint32_t size = descriptor[@"size"].unsignedIntValue;
                uint32_t type = descriptor[@"type"].unsignedIntValue;
                uint32_t elementSize = BRGLTypeSize(type);
                uint32_t stride = descriptor[@"stride"].unsignedIntValue ?: size * elementSize;
                uint32_t offset = descriptor[@"address"].unsignedIntValue;
                if (elementSize <= 1 || !stride || offset >= translated.length) continue;
                BRGLSwapStridedElements((uint8_t *)translated.mutableBytes + offset,
                    translated.length - offset, stride, (NSUInteger)size * elementSize,
                    elementSize);
            }
            if (bindArrayBuffer) bindArrayBuffer(GL_ARRAY_BUFFER, key.unsignedIntValue);
            if (uploadArrayBuffer) uploadArrayBuffer(GL_ARRAY_BUFFER, translated.length,
                translated.bytes, weakSelf.bufferUsage[key].unsignedIntValue ?: GL_STATIC_DRAW);
            weakSelf.translatedBufferData[key] = translated;
            [weakSelf.dirtyBuffers removeObject:key];
            weakSelf.translatedBufferLayoutGenerations[key] = @(generation);
        }
        if (bindArrayBuffer) bindArrayBuffer(GL_ARRAY_BUFFER, weakSelf.boundArrayBuffer);
    };
    void (*uploadElementBuffer)(uint32_t, intptr_t, const void *, uint32_t) =
        BRGLSymbol(self.openGLHandle, @"_glBufferData");
    void (^prepareElementBuffer)(uint32_t) = ^(uint32_t type) {
        NSNumber *key = @(weakSelf.boundElementArrayBuffer);
        NSMutableData *original = weakSelf.bufferData[key];
        if (!original) return;
        if (![weakSelf.dirtyBuffers containsObject:key] &&
            weakSelf.elementBufferTypes[key].unsignedIntValue == type) return;
        NSMutableData *translated = [original mutableCopy];
        BRGLSwapElements(translated.mutableBytes, translated.length, BRGLTypeSize(type));
        if (uploadElementBuffer) uploadElementBuffer(GL_ELEMENT_ARRAY_BUFFER, translated.length,
            translated.bytes, weakSelf.bufferUsage[key].unsignedIntValue ?: GL_STATIC_DRAW);
        [weakSelf.dirtyBuffers removeObject:key];
        weakSelf.elementBufferTypes[key] = @(type);
    };
    void (*drawArrays)(uint32_t, int32_t, int32_t) =
        BRGLSymbol(self.openGLHandle, @"_glDrawArrays");
    [registry registerSymbol:@"_glDrawArrays" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint64_t end = (uint64_t)state->gpr[4] + state->gpr[5];
        if (end > UINT32_MAX) return NO;
        if (weakSelf.bufferArrays.count) prepareArrayBuffers();
        if (weakSelf.clientArrays.count && !prepareClientArrays((uint32_t)end)) return NO;
        if (drawArrays) drawArrays(state->gpr[3], (int32_t)state->gpr[4],
                                   (int32_t)state->gpr[5]);
        BRGLReturn(state, 0); return YES;
    }];
    void (*drawElements)(uint32_t, int32_t, uint32_t, const void *) =
        BRGLSymbol(self.openGLHandle, @"_glDrawElements");
    [registry registerSymbol:@"_glDrawElements" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[4], type = state->gpr[5];
        if (weakSelf.boundElementArrayBuffer) {
            if (weakSelf.bufferArrays.count) prepareArrayBuffers();
            prepareElementBuffer(type);
            if (drawElements) drawElements(state->gpr[3], (int32_t)count, type,
                                           (const void *)(uintptr_t)state->gpr[6]);
            BRGLReturn(state, 0); return YES;
        }
        uint32_t elementSize = BRGLTypeSize(type);
        if (elementSize != 1 && elementSize != 2 && elementSize != 4) return NO;
        uint64_t length = (uint64_t)count * elementSize;
        if (length > UINT32_MAX) return NO;
        NSMutableData *indices = weakSelf.clientIndexData;
        indices.length = (NSUInteger)length;
        if (length && ![registry.memory readBytes:indices.mutableBytes address:state->gpr[6]
                                             length:indices.length]) return NO;
        BRGLSwapElements(indices.mutableBytes, indices.length, elementSize);
        uint32_t maximum = 0;
        for (uint32_t index = 0; index < count; index++) {
            uint32_t value = 0;
            if (elementSize == 1) value = ((uint8_t *)indices.mutableBytes)[index];
            else if (elementSize == 2) value = ((uint16_t *)indices.mutableBytes)[index];
            else value = ((uint32_t *)indices.mutableBytes)[index];
            maximum = MAX(maximum, value);
        }
        if (weakSelf.bufferArrays.count) prepareArrayBuffers();
        if (count && weakSelf.clientArrays.count && !prepareClientArrays(maximum + 1)) return NO;
        if (drawElements) drawElements(state->gpr[3], (int32_t)count, type, indices.bytes);
        BRGLReturn(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_glViewport", @"_glScissor"]) {
        void (*function)(int32_t, int32_t, int32_t, int32_t) =
            BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (function) function((int32_t)state->gpr[3], (int32_t)state->gpr[4],
                                   (int32_t)state->gpr[5], (int32_t)state->gpr[6]);
            BRGLReturn(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_glOrtho", @"_gluOrtho2D"]) {
        BOOL isGLOrtho = [symbol isEqualToString:@"_glOrtho"];
        void *rawFunction = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if (isGLOrtho) {
                void (*function)(double, double, double, double, double, double) = rawFunction;
                if (function) function(state->fpr[1], state->fpr[2], state->fpr[3],
                                       state->fpr[4], state->fpr[5], state->fpr[6]);
            } else {
                void (*function)(double, double, double, double) = rawFunction;
                if (function) function(state->fpr[1], state->fpr[2], state->fpr[3], state->fpr[4]);
            }
            BRGLReturn(state, 0); return YES;
        }];
    }
    uint32_t (*getError)(void) = BRGLSymbol(self.openGLHandle, @"_glGetError");
    [registry registerSymbol:@"_glGetError" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        BRGLReturn(state, getError ? getError() : 0); return YES;
    }];
    void (^registerStringGetter)(NSString *) = ^(NSString *symbol) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCOpenGLResolve *self = weakSelf; uint32_t key = state->gpr[3];
            NSString *cacheKey = [NSString stringWithFormat:@"%@:%u", symbol, key];
            NSNumber *cached = self.guestStrings[cacheKey];
            if (!cached) {
                const uint8_t *(*function)(uint32_t) = BRGLSymbol(self.openGLHandle, symbol);
                const uint8_t *host = function ? function(key) : NULL;
                if (host && registry.guestAllocator) {
                    size_t length = strlen((const char *)host) + 1;
                    uint32_t address = length <= UINT32_MAX ? registry.guestAllocator((uint32_t)length, NO) : 0;
                    if (address && [registry.memory writeBytes:host address:address length:length]) {
                        cached = @(address); self.guestStrings[cacheKey] = cached;
                    }
                }
            }
            BRGLReturn(state, cached.unsignedIntValue); return YES;
        }];
    };
    registerStringGetter(@"_glGetString");
    registerStringGetter(@"_gluErrorString");
    [registry registerSymbol:@"_glGenTextures" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[3];
        NSMutableData *textures = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(uint32_t)];
        void (*function)(int32_t, uint32_t *) = BRGLSymbol(weakSelf.openGLHandle, @"_glGenTextures");
        if (function) function((int32_t)count, textures.mutableBytes);
        uint32_t *values = textures.mutableBytes;
        for (uint32_t i = 0; i < count; i++)
            if (![registry.memory writeUInt32:values[i] address:state->gpr[4] + i * 4]) return NO;
        BRGLReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_glGenBuffers" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[3];
        NSMutableData *buffers = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(uint32_t)];
        void (*function)(int32_t, uint32_t *) = BRGLSymbol(weakSelf.openGLHandle, @"_glGenBuffers");
        if (function) function((int32_t)count, buffers.mutableBytes);
        uint32_t *values = buffers.mutableBytes;
        for (uint32_t index = 0; index < count; index++)
            if (![registry.memory writeUInt32:values[index] address:state->gpr[4] + index * 4]) return NO;
        BRGLReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_glDeleteTextures" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[3];
        NSMutableData *textures = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(uint32_t)];
        uint32_t *values = textures.mutableBytes;
        for (uint32_t i = 0; i < count; i++)
            if (![registry.memory readUInt32:&values[i] address:state->gpr[4] + i * 4]) return NO;
        void (*function)(int32_t, const uint32_t *) = BRGLSymbol(weakSelf.openGLHandle, @"_glDeleteTextures");
        if (function) function((int32_t)count, values); BRGLReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_glDeleteBuffers" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[3];
        NSMutableData *buffers = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(uint32_t)];
        uint32_t *values = buffers.mutableBytes;
        for (uint32_t index = 0; index < count; index++)
            if (![registry.memory readUInt32:&values[index] address:state->gpr[4] + index * 4]) return NO;
        void (*function)(int32_t, const uint32_t *) = BRGLSymbol(weakSelf.openGLHandle, @"_glDeleteBuffers");
        if (function) function((int32_t)count, values);
        for (uint32_t index = 0; index < count; index++) {
            NSNumber *key = @(values[index]);
            [weakSelf.bufferData removeObjectForKey:key];
            [weakSelf.bufferUsage removeObjectForKey:key];
            [weakSelf.dirtyBuffers removeObject:key];
            [weakSelf.translatedBufferData removeObjectForKey:key];
            [weakSelf.translatedBufferLayoutGenerations removeObjectForKey:key];
            [weakSelf.elementBufferTypes removeObjectForKey:key];
            if (weakSelf.boundArrayBuffer == values[index]) weakSelf.boundArrayBuffer = 0;
            if (weakSelf.boundElementArrayBuffer == values[index]) weakSelf.boundElementArrayBuffer = 0;
            NSArray<NSString *> *arrayKeys = [weakSelf.bufferArrays keysOfEntriesPassingTest:
                ^BOOL(NSString *symbol, NSDictionary<NSString *, NSNumber *> *descriptor, BOOL *stop) {
                    (void)symbol; (void)stop;
                    return [descriptor[@"buffer"] isEqual:key];
                }].allObjects;
            if (arrayKeys.count) {
                [weakSelf.bufferArrays removeObjectsForKeys:arrayKeys];
                invalidateBufferLayouts();
            }
        }
        BRGLReturn(state, 0); return YES;
    }];
    void (*bufferDataFunction)(uint32_t, intptr_t, const void *, uint32_t) =
        BRGLSymbol(self.openGLHandle, @"_glBufferData");
    [registry registerSymbol:@"_glBufferData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[4];
        NSMutableData *data = state->gpr[5] ? [NSMutableData dataWithLength:length] : nil;
        if (data && ![registry.memory readBytes:data.mutableBytes address:state->gpr[5] length:data.length]) return NO;
        uint32_t buffer = state->gpr[3] == GL_ARRAY_BUFFER ? weakSelf.boundArrayBuffer :
            state->gpr[3] == GL_ELEMENT_ARRAY_BUFFER ? weakSelf.boundElementArrayBuffer : 0;
        NSNumber *bufferKey = buffer ? @(buffer) : nil;
        NSMutableData *previous = bufferKey ? weakSelf.bufferData[bufferKey] : nil;
        NSMutableData *previousTranslation = bufferKey
            ? weakSelf.translatedBufferData[bufferKey] : nil;
        BOOL reusesTranslation = data && state->gpr[3] == GL_ARRAY_BUFFER &&
            previousTranslation.length == data.length &&
            weakSelf.translatedBufferLayoutGenerations[bufferKey].unsignedIntegerValue ==
                weakSelf.bufferLayoutGeneration &&
            [previous isEqualToData:data];
        if (reusesTranslation) {
            weakSelf.bufferUsage[bufferKey] = @(state->gpr[6]);
            if (bufferDataFunction)
                bufferDataFunction(state->gpr[3], length, previousTranslation.bytes, state->gpr[6]);
            BRGLReturn(state, 0);
            return YES;
        }
        if (buffer) {
            weakSelf.bufferData[bufferKey] = data ?: [NSMutableData dataWithLength:length];
            weakSelf.bufferUsage[bufferKey] = @(state->gpr[6]);
            [weakSelf.dirtyBuffers addObject:bufferKey];
            [weakSelf.translatedBufferData removeObjectForKey:bufferKey];
            [weakSelf.translatedBufferLayoutGenerations removeObjectForKey:bufferKey];
        }
        BOOL translatedByPreparation = NO;
        if (buffer && state->gpr[3] == GL_ARRAY_BUFFER) {
            NSNumber *key = @(buffer);
            for (NSDictionary<NSString *, NSNumber *> *descriptor in weakSelf.bufferArrays.allValues)
                if ([descriptor[@"buffer"] isEqual:key]) {
                    translatedByPreparation = YES;
                    break;
                }
        }
        if (translatedByPreparation) prepareArrayBuffers();
        if (bufferDataFunction && !translatedByPreparation)
            bufferDataFunction(state->gpr[3], length, data.bytes, state->gpr[6]);
        BRGLReturn(state, 0); return YES;
    }];
    void (*bufferSubDataFunction)(uint32_t, intptr_t, intptr_t, const void *) =
        BRGLSymbol(self.openGLHandle, @"_glBufferSubData");
    [registry registerSymbol:@"_glBufferSubData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5];
        NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[6] length:data.length]) return NO;
        uint32_t buffer = state->gpr[3] == GL_ARRAY_BUFFER ? weakSelf.boundArrayBuffer :
            state->gpr[3] == GL_ELEMENT_ARRAY_BUFFER ? weakSelf.boundElementArrayBuffer : 0;
        NSMutableData *original = buffer ? weakSelf.bufferData[@(buffer)] : nil;
        uint64_t end = (uint64_t)state->gpr[4] + length;
        if (original && end <= original.length)
            [original replaceBytesInRange:NSMakeRange(state->gpr[4], length) withBytes:data.bytes];
        NSNumber *key = buffer ? @(buffer) : nil;
        NSMutableData *translated = key ? weakSelf.translatedBufferData[key] : nil;
        BOOL patchesTranslatedArrayBuffer = state->gpr[3] == GL_ARRAY_BUFFER && original &&
            end <= original.length && translated.length == original.length &&
            weakSelf.translatedBufferLayoutGenerations[key].unsignedIntegerValue ==
                weakSelf.bufferLayoutGeneration;
        NSUInteger uploadStart = state->gpr[4], uploadEnd = (NSUInteger)end;
        if (patchesTranslatedArrayBuffer) {
            if (length)
                [translated replaceBytesInRange:NSMakeRange(uploadStart, length)
                                       withBytes:data.bytes];
            for (NSString *symbol in weakSelf.bufferArrays) {
                NSDictionary<NSString *, NSNumber *> *descriptor = weakSelf.bufferArrays[symbol];
                if (![descriptor[@"buffer"] isEqual:key]) continue;
                NSUInteger size = descriptor[@"size"].unsignedIntegerValue;
                uint32_t type = descriptor[@"type"].unsignedIntValue;
                uint32_t elementSize = BRGLTypeSize(type);
                NSUInteger componentLength = size * elementSize;
                NSUInteger stride = descriptor[@"stride"].unsignedIntegerValue ?:
                    componentLength;
                NSUInteger offset = descriptor[@"address"].unsignedIntegerValue;
                if (elementSize <= 1 || !componentLength || !stride || offset >= original.length)
                    continue;
                NSUInteger vertex = uploadStart > offset
                    ? (uploadStart - offset) / stride : 0;
                if (vertex) vertex--;
                for (;; vertex++) {
                    uint64_t componentStart64 = (uint64_t)offset + (uint64_t)vertex * stride;
                    uint64_t componentEnd64 = componentStart64 + componentLength;
                    if (componentStart64 >= uploadEnd || componentStart64 >= original.length) break;
                    if (componentEnd64 <= uploadStart) continue;
                    if (componentEnd64 > original.length) break;
                    NSUInteger componentStart = (NSUInteger)componentStart64;
                    memcpy((uint8_t *)translated.mutableBytes + componentStart,
                           (const uint8_t *)original.bytes + componentStart, componentLength);
                    BRGLSwapElements((uint8_t *)translated.mutableBytes + componentStart,
                                     componentLength, elementSize);
                    uploadStart = MIN(uploadStart, componentStart);
                    uploadEnd = MAX(uploadEnd, (NSUInteger)componentEnd64);
                }
            }
            [weakSelf.dirtyBuffers removeObject:key];
        } else if (buffer) {
            [weakSelf.dirtyBuffers addObject:key];
        }
        if (bufferSubDataFunction) {
            const void *uploadBytes = patchesTranslatedArrayBuffer
                ? (const uint8_t *)translated.bytes + uploadStart : data.bytes;
            NSUInteger uploadLength = patchesTranslatedArrayBuffer
                ? uploadEnd - uploadStart : length;
            bufferSubDataFunction(state->gpr[3], uploadStart, uploadLength, uploadBytes);
        }
        BRGLReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_glReadPixels" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t width = state->gpr[5], height = state->gpr[6];
        uint64_t rowBytes = 0, stride = 0, size = 0;
        if (!BRGLPixelLayout(width, height, state->gpr[7], state->gpr[8],
                             weakSelf.packAlignment, &rowBytes, &stride, &size)) return NO;
        NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)size];
        void (*function)(int32_t, int32_t, int32_t, int32_t, uint32_t, uint32_t, void *) =
            BRGLSymbol(weakSelf.openGLHandle, @"_glReadPixels");
        if (function) function((int32_t)state->gpr[3], (int32_t)state->gpr[4],
            (int32_t)width, (int32_t)height, state->gpr[7], state->gpr[8], pixels.mutableBytes);
        uint32_t elementSize = BRGLTypeSize(state->gpr[8]);
        for (uint32_t row = 0; row < height; row++)
            BRGLSwapElements((uint8_t *)pixels.mutableBytes + row * stride,
                             (NSUInteger)rowBytes, elementSize);
        if (size && ![registry.memory writeBytes:pixels.bytes address:state->gpr[9] length:(NSUInteger)size]) return NO;
        BRGLReturn(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_glTexImage2D", @"_glTexSubImage2D"]) {
        void *rawFunction = BRGLSymbol(self.openGLHandle, symbol);
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t pixelsAddress = 0;
            if (![registry.memory readUInt32:&pixelsAddress address:state->gpr[1] + 56]) return NO;
            uint32_t width = state->gpr[6], height = state->gpr[7];
            uint32_t format = state->gpr[9], type = state->gpr[10];
            if ([symbol isEqualToString:@"_glTexSubImage2D"]) {
                width = state->gpr[7]; height = state->gpr[8]; format = state->gpr[9]; type = state->gpr[10];
            }
            uint32_t elementSize = BRGLTypeSize(type);
            uint64_t rowBytes = 0, stride = 0, size = 0;
            if (!BRGLPixelLayout(width, height, format, type, weakSelf.unpackAlignment,
                                 &rowBytes, &stride, &size)) return NO;
            NSMutableData *pixels = pixelsAddress ? [NSMutableData dataWithLength:(NSUInteger)size] : nil;
            if (pixels && ![registry.memory readBytes:pixels.mutableBytes
                address:pixelsAddress length:pixels.length]) return NO;
            if (pixels)
                for (uint32_t row = 0; row < height; row++)
                    BRGLSwapElements((uint8_t *)pixels.mutableBytes + row * stride,
                                     (NSUInteger)rowBytes, elementSize);
            if ([symbol isEqualToString:@"_glTexImage2D"]) {
                void (*function)(uint32_t, int32_t, int32_t, int32_t, int32_t, int32_t,
                    uint32_t, uint32_t, const void *) = rawFunction;
                if (function) function(state->gpr[3], (int32_t)state->gpr[4], (int32_t)state->gpr[5],
                    (int32_t)state->gpr[6], (int32_t)state->gpr[7], (int32_t)state->gpr[8],
                    state->gpr[9], state->gpr[10], pixels.bytes);
            } else {
                void (*function)(uint32_t, int32_t, int32_t, int32_t, int32_t, int32_t,
                    uint32_t, uint32_t, const void *) = rawFunction;
                if (function) function(state->gpr[3], (int32_t)state->gpr[4], (int32_t)state->gpr[5],
                    (int32_t)state->gpr[6], (int32_t)state->gpr[7], (int32_t)state->gpr[8],
                    state->gpr[9], state->gpr[10], pixels.bytes);
            }
            BRGLReturn(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CGLChoosePixelFormat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *attributes = [NSMutableData dataWithLength:256 * sizeof(int32_t)];
        int32_t *values = attributes.mutableBytes; NSUInteger count = 0;
        for (; count < 255; count++) {
            uint32_t value = 0;
            if (![registry.memory readUInt32:&value address:state->gpr[3] + (uint32_t)count * 4]) return NO;
            values[count] = (int32_t)value;
            if (!value) break;
        }
        if (count == 255) { BRGLReturn(state, 10000); return YES; }
        void *pixelFormat = NULL; int32_t formats = 0;
        int32_t (*function)(const int32_t *, void **, int32_t *) =
            BRGLSymbol(weakSelf.openGLHandle, @"_CGLChoosePixelFormat");
        int32_t result = function ? function(values, &pixelFormat, &formats) : 10000;
        uint32_t handle = BRGLEncodePointer(registry, pixelFormat);
        if ((!state->gpr[4] || ![registry.memory writeUInt32:handle address:state->gpr[4]]) ||
            (state->gpr[5] && ![registry.memory writeUInt32:(uint32_t)formats address:state->gpr[5]]))
            result = 10000;
        BRGLReturn(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CGLCreateContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; void *context = NULL;
        int32_t (*function)(void *, void *, void **) = BRGLSymbol(weakSelf.openGLHandle, @"_CGLCreateContext");
        int32_t result = function ? function(BRGLDecodedPointer(registry, state->gpr[3]),
            BRGLDecodedPointer(registry, state->gpr[4]), &context) : 10000;
        uint32_t handle = BRGLEncodePointer(registry, context);
        if (!state->gpr[5] || ![registry.memory writeUInt32:handle address:state->gpr[5]]) result = 10000;
        BRGLReturn(state, (uint32_t)result); return YES;
    }];
    for (NSString *symbol in @[@"_CGLDestroyContext", @"_CGLDestroyPixelFormat"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; int32_t (*function)(void *) = BRGLSymbol(weakSelf.openGLHandle, symbol);
            BRGLReturn(state, function ? (uint32_t)function(BRGLDecodedPointer(registry, state->gpr[3])) : 0);
            return YES;
        }];
    [registry registerSymbol:@"_CGLGetCurrentContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; void *(*function)(void) = BRGLSymbol(weakSelf.openGLHandle, @"_CGLGetCurrentContext");
        BRGLReturn(state, BRGLEncodePointer(registry, function ? function() : NULL)); return YES;
    }];
    [registry registerSymbol:@"_CGLSetCurrentContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t (*function)(void *) = BRGLSymbol(weakSelf.openGLHandle, @"_CGLSetCurrentContext");
        BRGLReturn(state, function ? (uint32_t)function(BRGLDecodedPointer(registry, state->gpr[3])) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_CGLQueryRendererInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; void *info = NULL; int32_t count = 0;
        int32_t (*function)(uint32_t, void **, int32_t *) =
            BRGLSymbol(weakSelf.openGLHandle, @"_CGLQueryRendererInfo");
        int32_t result = function ? function(state->gpr[3], &info, &count) : 10000;
        if ((state->gpr[4] && ![registry.memory writeUInt32:BRGLEncodePointer(registry, info)
                                                        address:state->gpr[4]]) ||
            (state->gpr[5] && ![registry.memory writeUInt32:(uint32_t)count address:state->gpr[5]]))
            result = 10000;
        BRGLReturn(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CGLDescribeRenderer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t value = 0;
        int32_t (*function)(void *, int32_t, int32_t, int32_t *) =
            BRGLSymbol(weakSelf.openGLHandle, @"_CGLDescribeRenderer");
        int32_t result = function ? function(BRGLDecodedPointer(registry, state->gpr[3]),
            (int32_t)state->gpr[4], (int32_t)state->gpr[5], &value) : 10000;
        if (state->gpr[6] && ![registry.memory writeUInt32:(uint32_t)value address:state->gpr[6]]) result = 10000;
        BRGLReturn(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CGLGetParameter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t value = 0;
        int32_t (*function)(void *, int32_t, int32_t *) =
            BRGLSymbol(weakSelf.openGLHandle, @"_CGLGetParameter");
        int32_t result = function ? function(BRGLDecodedPointer(registry, state->gpr[3]),
            (int32_t)state->gpr[4], &value) : 10000;
        if (state->gpr[5] && ![registry.memory writeUInt32:(uint32_t)value address:state->gpr[5]]) result = 10000;
        BRGLReturn(state, (uint32_t)result); return YES;
    }];
    for (NSString *symbol in @[@"_CGLDestroyRendererInfo", @"_CGLSetFullScreen"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; int32_t (*function)(void *) = BRGLSymbol(weakSelf.openGLHandle, symbol);
            BRGLReturn(state, function ? (uint32_t)function(BRGLDecodedPointer(registry, state->gpr[3])) : 0);
            return YES;
        }];
    [registry registerSymbol:@"_gluCheckExtension" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSString *extension = [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:4096];
        NSString *extensions = [registry.memory readCStringAtAddress:state->gpr[4] maximumLength:1u << 20];
        BOOL found = NO;
        if (extension.length && extensions.length &&
            [extension rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location == NSNotFound)
            found = [[extensions componentsSeparatedByCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]] containsObject:extension];
        BRGLReturn(state, found); return YES;
    }];
    return YES;
}
- (void)dealloc { if (_openGLHandle) dlclose(_openGLHandle); }
@end
