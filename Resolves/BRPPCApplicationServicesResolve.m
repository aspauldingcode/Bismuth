#import "BRPPCApplicationServicesResolve.h"
#import "BRPPCAddressSpace.h"
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static NSString * const BRPPCApplicationServicesErrorDomain = @"theoderoy.Bismuth.application-services";
static const void *BRASFullFramePresentationViewKey = &BRASFullFramePresentationViewKey;

@interface BRASPassthroughImageView : NSImageView
@end

@implementation BRASPassthroughImageView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end

@interface BRASColorSpace : NSObject
@property(nonatomic) uint32_t componentCount;
@property(nonatomic, readonly) CGColorSpaceRef nativeColorSpace;
- (void)adoptNativeColorSpace:(CGColorSpaceRef CF_CONSUMED)colorSpace;
- (void *)bismuthNativePointer;
@end
@implementation BRASColorSpace
- (void)adoptNativeColorSpace:(CGColorSpaceRef)colorSpace {
    if (_nativeColorSpace) CGColorSpaceRelease(_nativeColorSpace);
    _nativeColorSpace = colorSpace;
}
- (void *)bismuthNativePointer { return (void *)self.nativeColorSpace; }
- (void)dealloc { if (_nativeColorSpace) CGColorSpaceRelease(_nativeColorSpace); }
@end

@interface BRASDataProvider : NSObject
@property(nonatomic) uint32_t guestData;
@property(nonatomic) uint32_t size;
@end
@implementation BRASDataProvider @end

@interface BRASImage : NSObject
@property(nonatomic) uint32_t width;
@property(nonatomic) uint32_t height;
@property(nonatomic) uint32_t bitsPerComponent;
@property(nonatomic) uint32_t bitsPerPixel;
@property(nonatomic) uint32_t bytesPerRow;
@property(nonatomic) uint32_t bitmapInfo;
@property(nonatomic, strong) BRASColorSpace *colorSpace;
@property(nonatomic, strong) BRASDataProvider *provider;
@end
@implementation BRASImage @end

@interface BRASBitmapContext : NSObject {
@public
    float _transform[6];
}
@property(nonatomic) uint32_t guestData;
@property(nonatomic) uint32_t width;
@property(nonatomic) uint32_t height;
@property(nonatomic) uint32_t bitsPerComponent;
@property(nonatomic) uint32_t bytesPerRow;
@property(nonatomic, strong) BRASColorSpace *colorSpace;
@property(nonatomic) float alpha;
@end
@implementation BRASBitmapContext @end

@interface BRASImageSource : NSObject
@property(nonatomic, strong) NSData *data;
@end
@implementation BRASImageSource @end

@interface BRASImageDestination : NSObject
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, strong) NSMutableArray *images;
@end
@implementation BRASImageDestination @end

static void BRASFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value; state->pc = state->lr;
}

static id BRASObject(BRPPCResolveRegistry *registry, uint32_t handle) {
    return registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
}

static uint32_t BRASHandle(BRPPCResolveRegistry *registry, id object) {
    return registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0;
}

static BOOL BRASArgument(BRPPCResolveRegistry *registry, BRPPCState *state,
                         NSUInteger index, uint32_t *value) {
    NSUInteger reg = index + 3;
    if (reg <= 10) { *value = state->gpr[reg]; return YES; }
    return [registry.memory readUInt32:value address:state->gpr[1] + 24 + (uint32_t)index * 4];
}

static float BRASFloat(uint32_t bits) {
    float value = 0; memcpy(&value, &bits, sizeof(value)); return value;
}

static BOOL BRASWriteFloats(BRPPCResolveRegistry *registry, uint32_t address,
                            const float *values, NSUInteger count) {
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t bits = 0; memcpy(&bits, values + i, sizeof(bits));
        if (![registry.memory writeUInt32:bits address:address + (uint32_t)i * 4]) return NO;
    }
    return YES;
}

static void BRASConcat(float *left, const float *right) {
    float result[6] = {
        left[0] * right[0] + left[1] * right[2],
        left[0] * right[1] + left[1] * right[3],
        left[2] * right[0] + left[3] * right[2],
        left[2] * right[1] + left[3] * right[3],
        left[4] * right[0] + left[5] * right[2] + right[4],
        left[4] * right[1] + left[5] * right[3] + right[5]
    };
    memcpy(left, result, sizeof(result));
}

@implementation BRPPCApplicationServicesResolve
- (instancetype)init { return [super initWithFrameworkName:@"ApplicationServices"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if (![self registerStringConstants:@[@"_kCGColorSpaceGenericRGB",
        @"_kCGImageDestinationLossyCompressionQuality"] registry:registry error:error]) return NO;
    uint8_t zero[16] = {0};
    if (![self registerDataConstant:@"_CGPointZero" data:[NSData dataWithBytes:zero length:8]
        alignment:4 registry:registry error:error] ||
        ![self registerDataConstant:@"_CGSizeZero" data:[NSData dataWithBytes:zero length:8]
        alignment:4 registry:registry error:error] ||
        ![self registerDataConstant:@"_CGRectZero" data:[NSData dataWithBytes:zero length:16]
        alignment:4 registry:registry error:error]) return NO;
    float identityValues[] = {1, 0, 0, 1, 0, 0};
    uint8_t identityBytes[24];
    for (NSUInteger i = 0; i < 6; i++) {
        uint32_t bits = 0; memcpy(&bits, &identityValues[i], sizeof(bits));
        identityBytes[i * 4] = bits >> 24; identityBytes[i * 4 + 1] = bits >> 16;
        identityBytes[i * 4 + 2] = bits >> 8; identityBytes[i * 4 + 3] = bits;
    }
    if (![self registerDataConstant:@"_CGAffineTransformIdentity"
        data:[NSData dataWithBytes:identityBytes length:sizeof(identityBytes)] alignment:4
        registry:registry error:error]) return NO;
    [self registerZeroFunction:@"_CGContextSaveGState" registry:registry];
    [self registerZeroFunction:@"_CGContextRestoreGState" registry:registry];
    for (NSString *symbol in @[@"_CGContextFlush", @"_CGContextSynchronize"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            id object = BRASObject(registry, state->gpr[3]);
            CGContextRef context = [object isKindOfClass:[NSValue class]]
                ? [(NSValue *)object pointerValue] : NULL;
            if (!context) {
                if (callError) *callError = [NSError errorWithDomain:BRPPCApplicationServicesErrorDomain code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"CGContext flush received an invalid guest context."}];
                return NO;
            }
            CGContextFlush(context); BRASFinish(state, 0); return YES;
        }];
    [self registerZeroFunction:@"_CGImageRelease" registry:registry];
    [self registerZeroFunction:@"_CGColorSpaceRelease" registry:registry];
    [self registerZeroFunction:@"_CGPathRelease" registry:registry];
    NSArray *colorSpaceSymbols = @[@"_CGColorSpaceCreateDeviceRGB", @"_CGColorSpaceCreateWithName",
        @"_CGColorSpaceCreateWithPlatformColorSpace", @"_CGColorSpaceCreateICCBased"];
    for (NSString *symbol in colorSpaceSymbols)
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASColorSpace *space = [BRASColorSpace new];
            space.componentCount = [symbol hasSuffix:@"ICCBased"] ? state->gpr[3] : 3;
            if ([symbol isEqualToString:@"_CGColorSpaceCreateWithName"] && registry.guestObjectDecoder) {
                id name = registry.guestObjectDecoder(state->gpr[3]);
                if ([name isKindOfClass:[NSString class]])
                    [space adoptNativeColorSpace:
                        CGColorSpaceCreateWithName((__bridge CFStringRef)name)];
            }
            if (!space.nativeColorSpace)
                [space adoptNativeColorSpace:CGColorSpaceCreateDeviceRGB()];
            BRASFinish(state, BRASHandle(registry, space)); return YES;
        }];
    [registry registerSymbol:@"_CGColorSpaceRetain" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, state->gpr[3]); return YES;
    }];
    for (NSString *symbol in @[@"_CGColorCreateGenericGray", @"_CGColorCreateGenericRGB"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASFinish(state, BRASHandle(registry, [NSObject new])); return YES;
        }];
    [registry registerSymbol:@"_CGDataProviderCreateWithData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASDataProvider *provider = [BRASDataProvider new];
        provider.guestData = state->gpr[4]; provider.size = state->gpr[5];
        BRASFinish(state, BRASHandle(registry, provider)); return YES;
    }];
    [self registerZeroFunction:@"_CGDataProviderRelease" registry:registry];
    [registry registerSymbol:@"_CGImageCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASImage *image = [BRASImage new]; uint32_t word = 0;
        image.width = state->gpr[3]; image.height = state->gpr[4];
        image.bitsPerComponent = state->gpr[5]; image.bitsPerPixel = state->gpr[6];
        image.bytesPerRow = state->gpr[7]; image.colorSpace = BRASObject(registry, state->gpr[8]);
        image.bitmapInfo = state->gpr[9];
        if (BRASArgument(registry, state, 7, &word)) image.provider = BRASObject(registry, word);
        BRASFinish(state, BRASHandle(registry, image)); return YES;
    }];
    [registry registerSymbol:@"_CGImageCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASImage *source = BRASObject(registry, state->gpr[3]);
        if (![source isKindOfClass:[BRASImage class]]) { BRASFinish(state, 0); return YES; }
        BRASImage *copy = [BRASImage new]; copy.width = source.width; copy.height = source.height;
        copy.bitsPerComponent = source.bitsPerComponent; copy.bitsPerPixel = source.bitsPerPixel;
        copy.bytesPerRow = source.bytesPerRow; copy.bitmapInfo = source.bitmapInfo;
        copy.colorSpace = source.colorSpace; copy.provider = source.provider;
        BRASFinish(state, BRASHandle(registry, copy)); return YES;
    }];
    NSDictionary *imageGetters = @{@"_CGImageGetWidth": @0, @"_CGImageGetHeight": @1};
    [imageGetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASImage *image = BRASObject(registry, state->gpr[3]);
            BRASFinish(state, kind.boolValue ? image.height : image.width); return YES;
        }];
    }];
    [registry registerSymbol:@"_CGBitmapContextCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASBitmapContext *context = [BRASBitmapContext new];
        context.guestData = state->gpr[3]; context.width = state->gpr[4]; context.height = state->gpr[5];
        context.bitsPerComponent = state->gpr[6]; context.bytesPerRow = state->gpr[7];
        context.colorSpace = BRASObject(registry, state->gpr[8]); context.alpha = 1;
        float identity[] = {1, 0, 0, 1, 0, 0}; memcpy(context->_transform, identity, sizeof(identity));
        BRASFinish(state, BRASHandle(registry, context)); return YES;
    }];
    [registry registerSymbol:@"_CGBitmapContextCreateImage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASBitmapContext *context = BRASObject(registry, state->gpr[3]);
        if (![context isKindOfClass:[BRASBitmapContext class]]) { BRASFinish(state, 0); return YES; }
        BRASImage *image = [BRASImage new]; image.width = context.width; image.height = context.height;
        image.bitsPerComponent = context.bitsPerComponent; image.bitsPerPixel = context.colorSpace.componentCount * context.bitsPerComponent;
        image.bytesPerRow = context.bytesPerRow; image.colorSpace = context.colorSpace;
        BRASDataProvider *provider = [BRASDataProvider new]; provider.guestData = context.guestData;
        provider.size = context.bytesPerRow * context.height; image.provider = provider;
        BRASFinish(state, BRASHandle(registry, image)); return YES;
    }];
    [registry registerSymbol:@"_CGContextDrawImage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id contextObject = BRASObject(registry, state->gpr[3]);
        BRASImage *image = BRASObject(registry, state->gpr[8]);
        CGContextRef context = [contextObject isKindOfClass:[NSValue class]]
            ? [(NSValue *)contextObject pointerValue] : NULL;
        CGContextRef currentContext = NSGraphicsContext.currentContext.CGContext;
        if (!context || ![image isKindOfClass:[BRASImage class]] || !image.provider ||
            !image.width || !image.height || !image.bytesPerRow || image.provider.size < 4) {
            if (callError) *callError = [NSError errorWithDomain:BRPPCApplicationServicesErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey: @"CGContextDrawImage received an invalid guest context or image."}];
            return NO;
        }
        NSMutableData *pixels = [NSMutableData dataWithLength:image.provider.size];
        if (![registry.memory readBytes:pixels.mutableBytes address:image.provider.guestData
                                  length:pixels.length]) {
            if (callError) *callError = [NSError errorWithDomain:BRPPCApplicationServicesErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey: @"CGContextDrawImage cannot read guest image pixels."}];
            return NO;
        }
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
        CGColorSpaceRef colorSpace = image.colorSpace.nativeColorSpace ?: CGColorSpaceCreateDeviceRGB();
        CGImageRef nativeImage = provider ? CGImageCreate(image.width, image.height,
            image.bitsPerComponent, image.bitsPerPixel, image.bytesPerRow, colorSpace,
            (CGBitmapInfo)image.bitmapInfo, provider, NULL, false, kCGRenderingIntentDefault) : NULL;
        if (!image.colorSpace.nativeColorSpace && colorSpace) CGColorSpaceRelease(colorSpace);
        if (!nativeImage) {
            if (provider) CGDataProviderRelease(provider);
            if (callError) *callError = [NSError errorWithDomain:BRPPCApplicationServicesErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey: @"CGContextDrawImage cannot create a native image."}];
            return NO;
        }
        uint32_t words[4] = {state->gpr[4], state->gpr[5], state->gpr[6], state->gpr[7]};
        float values[4];
        for (NSUInteger i = 0; i < 4; i++) values[i] = BRASFloat(words[i]);
        if (getenv("BISMUTH_CG_TRACE"))
        {
            CGRect clip = CGContextGetClipBoundingBox(context);
            CGAffineTransform transform = CGContextGetCTM(context);
            const uint8_t *pixelBytes = pixels.bytes;
            NSUInteger changedBytes = 0;
            for (NSUInteger i = 0; i < pixels.length; i++)
                changedBytes += pixelBytes[i] != UINT8_MAX;
            NSUInteger center = MIN(pixels.length - 4,
                ((NSUInteger)image.height / 2 * image.bytesPerRow + (NSUInteger)image.width / 2 * 4));
            fprintf(stderr, "CGContextDrawImage context=%p current=%p image=%ux%u bpc=%u bpp=%u row=%u info=0x%x rect=%g,%g,%g,%g clip=%g,%g,%g,%g ctm=%g,%g,%g,%g,%g,%g first=%02x%02x%02x%02x\n",
                    context, currentContext, image.width, image.height, image.bitsPerComponent, image.bitsPerPixel,
                    image.bytesPerRow, image.bitmapInfo, values[0], values[1], values[2], values[3],
                    clip.origin.x, clip.origin.y, clip.size.width, clip.size.height,
                    transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty,
                    ((const uint8_t *)pixels.bytes)[0], ((const uint8_t *)pixels.bytes)[1],
                    ((const uint8_t *)pixels.bytes)[2], ((const uint8_t *)pixels.bytes)[3]);
            fprintf(stderr, "CG pixels nonFF=%lu/%lu center=%02x%02x%02x%02x\n",
                    (unsigned long)changedBytes, (unsigned long)pixels.length,
                    pixelBytes[center], pixelBytes[center + 1], pixelBytes[center + 2], pixelBytes[center + 3]);
        }
        CGRect destination = CGRectMake(values[0], values[1], values[2], values[3]);



        CGContextDrawImage(context, destination, nativeImage);
        CGContextFlush(context);





        NSView *focusView = NSView.focusView;
        NSRect bounds = focusView.bounds;
        BOOL fullFrame = context == currentContext && focusView.window &&
            fabs(destination.origin.x - bounds.origin.x) < 0.5 &&
            fabs(destination.origin.y - bounds.origin.y) < 0.5 &&
            fabs(destination.size.width - bounds.size.width) < 0.5 &&
            fabs(destination.size.height - bounds.size.height) < 0.5;
        if (fullFrame) {
            BRASPassthroughImageView *presentationView = objc_getAssociatedObject(
                focusView, BRASFullFramePresentationViewKey);
            if (!presentationView) {
                presentationView = [[BRASPassthroughImageView alloc] initWithFrame:bounds];
                presentationView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                presentationView.wantsLayer = YES;
                presentationView.layer.contentsGravity = kCAGravityResize;
                [focusView addSubview:presentationView positioned:NSWindowAbove relativeTo:nil];
                objc_setAssociatedObject(focusView, BRASFullFramePresentationViewKey,
                    presentationView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            presentationView.frame = bounds;
            presentationView.layer.contentsScale = focusView.window.backingScaleFactor;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            presentationView.layer.contents = (__bridge id)nativeImage;
            [CATransaction commit];
            [CATransaction flush];
        }
        CGImageRelease(nativeImage); CGDataProviderRelease(provider);
        BRASFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CGContextRelease", @"_CGContextBeginTransparencyLayer",
        @"_CGContextEndTransparencyLayer", @"_CGContextClipToRect",
        @"_CGContextDrawShading", @"_CGContextFillRect", @"_CGContextSetRGBFillColor",
        @"_CGContextSetShouldSmoothFonts"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_CGContextSetAlpha" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASBitmapContext *context = BRASObject(registry, state->gpr[3]);
        if ([context isKindOfClass:[BRASBitmapContext class]]) context.alpha = (float)state->fpr[1];
        BRASFinish(state, 0); return YES;
    }];
    NSDictionary *transformKinds = @{@"_CGContextTranslateCTM": @0, @"_CGContextScaleCTM": @1,
        @"_CGContextRotateCTM": @2};
    [transformKinds enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASBitmapContext *context = BRASObject(registry, state->gpr[3]);
            float m[] = {1, 0, 0, 1, 0, 0};
            if (kind.intValue == 0) { m[4] = state->fpr[1]; m[5] = state->fpr[2]; }
            else if (kind.intValue == 1) { m[0] = state->fpr[1]; m[3] = state->fpr[2]; }
            else { float a = state->fpr[1]; m[0] = cosf(a); m[1] = sinf(a); m[2] = -m[1]; m[3] = m[0]; }
            if ([context isKindOfClass:[BRASBitmapContext class]]) BRASConcat(context->_transform, m);
            BRASFinish(state, 0); return YES;
        }];
    }];
    [registry registerSymbol:@"_CGContextConcatCTM" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASBitmapContext *context = BRASObject(registry, state->gpr[3]); float m[6];
        for (NSUInteger i = 0; i < 6; i++) { uint32_t word = 0; BRASArgument(registry, state, i + 1, &word); m[i] = BRASFloat(word); }
        if ([context isKindOfClass:[BRASBitmapContext class]]) BRASConcat(context->_transform, m);
        BRASFinish(state, 0); return YES;
    }];
    NSDictionary *affineKinds = @{@"_CGAffineTransformMakeScale": @0,
        @"_CGAffineTransformMakeTranslation": @1, @"_CGAffineTransformScale": @2,
        @"_CGAffineTransformTranslate": @3, @"_CGAffineTransformRotate": @4};
    [affineKinds enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = state->gpr[3]; float m[] = {1, 0, 0, 1, 0, 0};
            if (kind.intValue >= 2) for (NSUInteger i = 0; i < 6; i++) m[i] = BRASFloat(state->gpr[4 + i]);
            if (kind.intValue == 0) { m[0] = state->fpr[1]; m[3] = state->fpr[2]; }
            else if (kind.intValue == 1) { m[4] = state->fpr[1]; m[5] = state->fpr[2]; }
            else { float n[] = {1, 0, 0, 1, 0, 0};
                if (kind.intValue == 2) { n[0] = state->fpr[1]; n[3] = state->fpr[2]; }
                else if (kind.intValue == 3) { n[4] = state->fpr[1]; n[5] = state->fpr[2]; }
                else { float a = state->fpr[1]; n[0] = cosf(a); n[1] = sinf(a); n[2] = -n[1]; n[3] = n[0]; }
                BRASConcat(m, n);
            }
            if (!BRASWriteFloats(registry, output, m, 6)) return NO; BRASFinish(state, output); return YES;
        }];
    }];
    [registry registerSymbol:@"_CGAffineTransformIsIdentity" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; float expected[] = {1, 0, 0, 1, 0, 0}; BOOL equal = YES;
        for (NSUInteger i = 0; i < 6; i++) equal &= BRASFloat(state->gpr[3 + i]) == expected[i];
        BRASFinish(state, equal); return YES;
    }];
    for (NSString *symbol in @[@"_CGFunctionCreate", @"_CGShadingCreateAxial"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASFinish(state, BRASHandle(registry, [NSObject new])); return YES;
        }];
    for (NSString *symbol in @[@"_CGFunctionRelease", @"_CGShadingRelease"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_CGImageSourceCreateWithData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id data = BRASObject(registry, state->gpr[3]);
        BRASImageSource *source = [BRASImageSource new];
        source.data = [data isKindOfClass:[NSData class]] ? data : [NSData data];
        BRASFinish(state, BRASHandle(registry, source)); return YES;
    }];
    [registry registerSymbol:@"_CGImageSourceCreateImageAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASImageSource *source = BRASObject(registry, state->gpr[3]);
        if (![source isKindOfClass:[BRASImageSource class]]) { BRASFinish(state, 0); return YES; }
        CGImageSourceRef native = CGImageSourceCreateWithData((__bridge CFDataRef)source.data, NULL);
        CGImageRef decoded = native && state->gpr[4] < CGImageSourceGetCount(native)
            ? CGImageSourceCreateImageAtIndex(native, state->gpr[4], NULL) : NULL;
        BRASImage *image = nil;
        if (decoded) { image = [BRASImage new]; image.width = (uint32_t)CGImageGetWidth(decoded);
            image.height = (uint32_t)CGImageGetHeight(decoded); image.bitsPerComponent = (uint32_t)CGImageGetBitsPerComponent(decoded);
            image.bitsPerPixel = (uint32_t)CGImageGetBitsPerPixel(decoded); image.bytesPerRow = (uint32_t)CGImageGetBytesPerRow(decoded); CGImageRelease(decoded); }
        if (native) CFRelease(native); BRASFinish(state, BRASHandle(registry, image)); return YES;
    }];
    [registry registerSymbol:@"_CGImageDestinationCreateWithData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id data = BRASObject(registry, state->gpr[3]); BRASImageDestination *destination = [BRASImageDestination new];
        destination.data = [data isKindOfClass:[NSMutableData class]] ? data : [NSMutableData data];
        destination.images = [NSMutableArray array]; BRASFinish(state, BRASHandle(registry, destination)); return YES;
    }];
    [registry registerSymbol:@"_CGImageDestinationAddImageFromSource" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASImageDestination *destination = BRASObject(registry, state->gpr[3]);
        BRASImageSource *source = BRASObject(registry, state->gpr[4]);
        if ([destination isKindOfClass:[BRASImageDestination class]] &&
            [source isKindOfClass:[BRASImageSource class]]) {
            [destination.images addObject:source];
        }
        BRASFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CGImageDestinationFinalize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, [BRASObject(registry, state->gpr[3]) isKindOfClass:[BRASImageDestination class]]); return YES;
    }];
    for (NSString *symbol in @[@"_CGRectGetMaxY", @"_CGRectGetMinX"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; state->fpr[1] = [symbol hasSuffix:@"MinX"] ? state->fpr[1] : state->fpr[2] + state->fpr[4];
            state->pc = state->lr; return YES;
        }];
    for (NSString *symbol in @[@"_CGRectInset", @"_CGRectIntegral", @"_CGRectIntersection"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = state->gpr[3]; float rect[4] = {
                BRASFloat(state->gpr[4]), BRASFloat(state->gpr[5]), BRASFloat(state->gpr[6]), BRASFloat(state->gpr[7])};
            if ([symbol hasSuffix:@"Inset"]) { rect[0] += state->fpr[1]; rect[1] += state->fpr[2]; rect[2] -= 2 * state->fpr[1]; rect[3] -= 2 * state->fpr[2]; }
            else if ([symbol hasSuffix:@"Integral"]) { float x2 = ceilf(rect[0] + rect[2]), y2 = ceilf(rect[1] + rect[3]);
                rect[0] = floorf(rect[0]); rect[1] = floorf(rect[1]); rect[2] = x2 - rect[0]; rect[3] = y2 - rect[1]; }
            BRASWriteFloats(registry, output, rect, 4); BRASFinish(state, output); return YES;
        }];
    [registry registerSymbol:@"_CGWarpMouseCursorPosition" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        CGPoint point = CGPointMake(BRASFloat(state->gpr[3]), BRASFloat(state->gpr[4]));
        BRASFinish(state, (uint32_t)CGWarpMouseCursorPosition(point)); return YES;
    }];
    [registry registerSymbol:@"_CGWindowLevelForKey" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, (uint32_t)CGWindowLevelForKey((CGWindowLevelKey)state->gpr[3])); return YES;
    }];
    for (NSString *symbol in @[@"_CGSDisableUpdate", @"_CGSReenableUpdate", @"_CGSReleaseRegion",
        @"_CGSSetWindowOpaqueShape", @"_CGSSetWindowShadowAndRimParameters", @"_CGSSetWindowTransform",
        @"_CGSSetWindowWarp", @"_CGSUnionRegionWithRect", @"_CMCloseProfile", @"_CMGetProfileHeader",
        @"_CMMakeProfile", @"_CMSetProfileHeader", @"_CMUpdateProfile", @"_CreateNewPort", @"_SetPort",
        @"_ICLaunchURL", @"_ICStop", @"_LSCopyItemInfoForRef", @"_LSGetExtensionInfo"])
        [self registerZeroFunction:symbol registry:registry];
    for (NSString *symbol in @[@"_CGSNewRegionWithRect", @"_CMGetProfileByAVID", @"_CMNewProfile",
        @"_ICStart"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = state->gpr[4];
            if (output) [registry.memory writeUInt32:BRASHandle(registry, [NSObject new]) address:output];
            BRASFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_GetCurrentProcess", @"_GetNextProcess", @"_GetProcessInformation",
        @"_SameProcess", @"_LSFindApplicationForInfo", @"_LSGetApplicationForInfo",
        @"_ATSFontActivateFromFileSpecification"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_UTCreateStringForOSType" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t value = state->gpr[3]; char chars[5] = {value >> 24, value >> 16, value >> 8, value, 0};
        NSString *string = [[NSString alloc] initWithBytes:chars length:4 encoding:NSMacOSRomanStringEncoding];
        BRASFinish(state, BRASHandle(registry, string ?: @"????")); return YES;
    }];
    [registry registerSymbol:@"__CGSDefaultConnection" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, 1); return YES;
    }];
    [registry registerSymbol:@"_CGMainDisplayID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, CGMainDisplayID()); return YES;
    }];
    [registry registerSymbol:@"_CGDisplayBounds" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        CGRect bounds = CGDisplayBounds(state->gpr[4]);
        float values[] = {(float)bounds.origin.x, (float)bounds.origin.y,
                          (float)bounds.size.width, (float)bounds.size.height};
        if (!BRASWriteFloats(registry, state->gpr[3], values, 4)) return NO;
        BRASFinish(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_CGDisplayBitsPerPixel" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, 32); return YES;
    }];
    [registry registerSymbol:@"_CGAssociateMouseAndMouseCursorPosition"
                    handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        BRASFinish(state, (uint32_t)CGAssociateMouseAndMouseCursorPosition(state->gpr[3] != 0));
        return YES;
    }];
    [registry registerSymbol:@"_CGDisplayMoveCursorToPoint"
                    handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        CGPoint point = CGPointMake(BRASFloat(state->gpr[4]), BRASFloat(state->gpr[5]));
        BRASFinish(state, (uint32_t)CGDisplayMoveCursorToPoint(state->gpr[3], point));
        return YES;
    }];
    [registry registerSymbol:@"_CGDisplayHideCursor" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, (uint32_t)CGDisplayHideCursor(state->gpr[3])); return YES;
    }];
    [registry registerSymbol:@"_CGDisplayShowCursor" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, (uint32_t)CGDisplayShowCursor(state->gpr[3])); return YES;
    }];
    for (NSString *symbol in @[@"_CGDisplayCapture", @"_CGDisplayRelease", @"_AEInstallEventHandler"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_NewAEEventHandlerUPP" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRASFinish(state, state->gpr[3]); return YES;
    }];
    [registry registerSymbol:@"_CGGetActiveDisplayList" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t capacity = state->gpr[3], displays = state->gpr[4], count = state->gpr[5];
        if (count && ![registry.memory writeUInt32:capacity ? 1 : 0 address:count]) {
            BRASFinish(state, 1001); return YES;
        }
        if (capacity && displays &&
            ![registry.memory writeUInt32:CGMainDisplayID() address:displays]) {
            BRASFinish(state, 1001); return YES;
        }
        BRASFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CGDisplayUsesOpenGLAcceleration"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CGDisplayIDToOpenGLDisplayMask"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CGDisplayUnitNumber"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRASFinish(state, 0); return YES;
        }];
    [self registerZeroFunction:@"_CGDisplayRegisterReconfigurationCallback" registry:registry];
    [self registerZeroFunction:@"_CGDisplayRemoveReconfigurationCallback" registry:registry];
    return YES;
}
@end
