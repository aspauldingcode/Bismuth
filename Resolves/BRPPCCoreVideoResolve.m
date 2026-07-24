#import "BRPPCCoreVideoResolve.h"
#import "BRPPCAddressSpace.h"
#import <CoreVideo/CoreVideo.h>

@interface BRPPCPixelBuffer : NSObject
@property(nonatomic) uint32_t width;
@property(nonatomic) uint32_t height;
@property(nonatomic) uint32_t pixelFormat;
@property(nonatomic) uint32_t baseAddress;
@property(nonatomic) uint32_t bytesPerRow;
@property(nonatomic, strong) NSMutableDictionary *attachments;
@end
@implementation BRPPCPixelBuffer @end

@interface BRPPCPixelBufferPool : NSObject
@property(nonatomic, strong) NSDictionary *attributes;
@end
@implementation BRPPCPixelBufferPool @end

@interface BRPPCDisplayLink : NSObject
@property(nonatomic) uint32_t displayID;
@property(nonatomic) BOOL running;
@property(nonatomic) uint32_t callback;
@property(nonatomic) uint32_t context;
@end
@implementation BRPPCDisplayLink @end

@interface BRPPCOpenGLTextureCache : NSObject
@property(nonatomic) uint32_t context;
@property(nonatomic) uint32_t pixelFormat;
@property(nonatomic, strong) NSDictionary *attributes;
@end
@implementation BRPPCOpenGLTextureCache @end

@interface BRPPCOpenGLTexture : NSObject
@property(nonatomic, strong) BRPPCPixelBuffer *image;
@property(nonatomic) BOOL flipped;
@end
@implementation BRPPCOpenGLTexture @end

static void BRCVReturn(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value; state->pc = state->lr;
}

static BOOL BRCVStackWord(BRPPCResolveRegistry *registry, BRPPCState *state,
                          NSUInteger argumentIndex, uint32_t *value) {
    NSUInteger gpr = argumentIndex + 3;
    if (gpr <= 10) { *value = state->gpr[gpr]; return YES; }
    return [registry.memory readUInt32:value
        address:state->gpr[1] + 24 + (uint32_t)(gpr - 3) * 4];
}

static id BRCVObject(BRPPCResolveRegistry *registry, uint32_t handle) {
    return registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
}

static uint32_t BRCVHandle(BRPPCResolveRegistry *registry, id object) {
    return registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0;
}

@implementation BRPPCCoreVideoResolve
- (instancetype)init { return [super initWithFrameworkName:@"CoreVideo"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if (![self registerStringConstants:@[@"_kCVBufferMovieTimeKey", @"_kCVBufferTimeScaleKey",
        @"_kCVBufferTimeValueKey", @"_kCVImageBufferCGColorSpaceKey",
        @"_kCVImageBufferGammaLevelKey", @"_kCVImageBufferYCbCrMatrix_ITU_R_709_2",
        @"_kCVPixelBufferHeightKey", @"_kCVPixelBufferOpenGLCompatibilityKey",
        @"_kCVPixelBufferPixelFormatTypeKey", @"_kCVPixelBufferWidthKey"]
        registry:registry error:error]) return NO;
    [registry registerSymbol:@"_CVPixelBufferCreateWithBytes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t output = 0;
            if (!BRCVStackWord(registry, state, 9, &output) || !output) {
                BRCVReturn(state, (uint32_t)kCVReturnInvalidArgument); return YES;
            }
            BRPPCPixelBuffer *buffer = [BRPPCPixelBuffer new];
            buffer.width = state->gpr[4]; buffer.height = state->gpr[5];
            buffer.pixelFormat = state->gpr[6]; buffer.baseAddress = state->gpr[7];
            buffer.bytesPerRow = state->gpr[8]; buffer.attachments = [NSMutableDictionary dictionary];
            uint32_t handle = BRCVHandle(registry, buffer);
            if (!handle || ![registry.memory writeUInt32:handle address:output])
                BRCVReturn(state, (uint32_t)kCVReturnInvalidArgument);
            else BRCVReturn(state, 0);
            return YES;
        }];
    NSDictionary<NSString *, NSNumber *> *pixelGetters = @{
        @"_CVPixelBufferGetWidth": @0, @"_CVPixelBufferGetHeight": @1,
        @"_CVPixelBufferGetPixelFormatType": @2, @"_CVPixelBufferGetBaseAddress": @3,
        @"_CVPixelBufferGetBytesPerRow": @4
    };
    [pixelGetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop;
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCPixelBuffer *buffer = BRCVObject(registry, state->gpr[3]);
            uint32_t value = 0;
            if ([buffer isKindOfClass:[BRPPCPixelBuffer class]]) {
                switch (kind.unsignedIntValue) {
                    case 0: value = buffer.width; break; case 1: value = buffer.height; break;
                    case 2: value = buffer.pixelFormat; break; case 3: value = buffer.baseAddress; break;
                    default: value = buffer.bytesPerRow; break;
                }
            }
            BRCVReturn(state, value); return YES;
        }];
    }];
    for (NSString *symbol in @[@"_CVPixelBufferLockBaseAddress",
        @"_CVPixelBufferUnlockBaseAddress"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRCVReturn(state,
                [BRCVObject(registry, state->gpr[3]) isKindOfClass:[BRPPCPixelBuffer class]] ? 0 : (uint32_t)kCVReturnInvalidArgument);
            return YES;
        }];
    for (NSString *symbol in @[@"_CVBufferRetain", @"_CVPixelBufferRetain",
        @"_CVDisplayLinkRetain", @"_CVOpenGLTextureRetain"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t handle = state->gpr[3]; BRCVReturn(state, handle); return YES;
        }];
    for (NSString *symbol in @[@"_CVBufferRelease", @"_CVPixelBufferRelease",
        @"_CVPixelBufferPoolRelease", @"_CVDisplayLinkRelease", @"_CVOpenGLTextureRelease"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRCVReturn(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CVBufferSetAttachment" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPixelBuffer *buffer = BRCVObject(registry, state->gpr[3]);
        id key = BRCVObject(registry, state->gpr[4]), value = BRCVObject(registry, state->gpr[5]);
        if ([buffer isKindOfClass:[BRPPCPixelBuffer class]] && key)
            buffer.attachments[key] = value ?: [NSNull null];
        BRCVReturn(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CVBufferGetAttachment" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPixelBuffer *buffer = BRCVObject(registry, state->gpr[3]);
        id key = BRCVObject(registry, state->gpr[4]); id value = buffer.attachments[key];
        if (state->gpr[5]) [registry.memory writeUInt32:value ? 1 : 0 address:state->gpr[5]];
        BRCVReturn(state, value == [NSNull null] ? 0 : BRCVHandle(registry, value)); return YES;
    }];
    [registry registerSymbol:@"_CVBufferPropagateAttachments"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCPixelBuffer *source = BRCVObject(registry, state->gpr[3]);
            BRPPCPixelBuffer *target = BRCVObject(registry, state->gpr[4]);
            if ([source isKindOfClass:[BRPPCPixelBuffer class]] &&
                [target isKindOfClass:[BRPPCPixelBuffer class]])
                [target.attachments addEntriesFromDictionary:source.attachments];
            BRCVReturn(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CVPixelBufferPoolCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPixelBufferPool *pool = [BRPPCPixelBufferPool new];
        id attributes = BRCVObject(registry, state->gpr[5]);
        pool.attributes = [attributes isKindOfClass:[NSDictionary class]] ? attributes : @{};
        uint32_t handle = BRCVHandle(registry, pool);
        BRCVReturn(state, state->gpr[6] && [registry.memory writeUInt32:handle address:state->gpr[6]]
            ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
    }];
    [registry registerSymbol:@"_CVPixelBufferPoolCreatePixelBuffer"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCPixelBufferPool *pool = BRCVObject(registry, state->gpr[4]);
            if (![pool isKindOfClass:[BRPPCPixelBufferPool class]] || !state->gpr[5]) {
                BRCVReturn(state, (uint32_t)kCVReturnInvalidArgument); return YES;
            }
            BRPPCPixelBuffer *buffer = [BRPPCPixelBuffer new];
            buffer.width = [pool.attributes[@"kCVPixelBufferWidthKey"] unsignedIntValue];
            buffer.height = [pool.attributes[@"kCVPixelBufferHeightKey"] unsignedIntValue];
            buffer.pixelFormat = [pool.attributes[@"kCVPixelBufferPixelFormatTypeKey"] unsignedIntValue];
            buffer.bytesPerRow = buffer.width * 4; buffer.attachments = [NSMutableDictionary dictionary];
            uint64_t byteCount = (uint64_t)buffer.bytesPerRow * buffer.height;
            buffer.baseAddress = byteCount <= UINT32_MAX && registry.guestAllocator
                ? registry.guestAllocator((uint32_t)byteCount, YES) : 0;
            uint32_t handle = BRCVHandle(registry, buffer);
            BRCVReturn(state, handle && [registry.memory writeUInt32:handle address:state->gpr[5]]
                ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
        }];
    [registry registerSymbol:@"_CVImageBufferGetDisplaySize"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCPixelBuffer *buffer = BRCVObject(registry, state->gpr[4]);
            float values[] = {buffer.width, buffer.height};
            for (NSUInteger i = 0; i < 2; i++) { uint32_t bits = 0; memcpy(&bits, &values[i], 4);
                if (![registry.memory writeUInt32:bits address:state->gpr[3] + (uint32_t)i * 4]) return NO; }
            BRCVReturn(state, state->gpr[3]); return YES;
        }];
    [registry registerSymbol:@"_CVDisplayLinkCreateWithOpenGLDisplayMask"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCDisplayLink *link = [BRPPCDisplayLink new]; link.displayID = state->gpr[3];
            uint32_t handle = BRCVHandle(registry, link);
            BRCVReturn(state, state->gpr[4] && [registry.memory writeUInt32:handle address:state->gpr[4]]
                ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
        }];
    [registry registerSymbol:@"_CVDisplayLinkSetOutputCallback"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCDisplayLink *link = BRCVObject(registry, state->gpr[3]);
            if ([link isKindOfClass:[BRPPCDisplayLink class]]) { link.callback = state->gpr[4]; link.context = state->gpr[5]; }
            BRCVReturn(state, link ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
        }];
    for (NSString *symbol in @[@"_CVDisplayLinkStart", @"_CVDisplayLinkStop"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCDisplayLink *link = BRCVObject(registry, state->gpr[3]);
            if ([link isKindOfClass:[BRPPCDisplayLink class]]) link.running = [symbol hasSuffix:@"Start"];
            BRCVReturn(state, link ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
        }];
    [registry registerSymbol:@"_CVDisplayLinkIsRunning" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCDisplayLink *link = BRCVObject(registry, state->gpr[3]);
        BRCVReturn(state, link.running); return YES;
    }];
    [registry registerSymbol:@"_CVDisplayLinkGetCurrentCGDisplay"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCDisplayLink *link = BRCVObject(registry, state->gpr[3]);
            BRCVReturn(state, link.displayID); return YES;
        }];
    [registry registerSymbol:@"_CVDisplayLinkSetCurrentCGDisplay"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCDisplayLink *link = BRCVObject(registry, state->gpr[3]);
            if ([link isKindOfClass:[BRPPCDisplayLink class]]) link.displayID = state->gpr[4];
            BRCVReturn(state, link ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
        }];
    [registry registerSymbol:@"_CVOpenGLTextureCacheCreate"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCOpenGLTextureCache *cache = [BRPPCOpenGLTextureCache new];
            cache.context = state->gpr[5]; cache.pixelFormat = state->gpr[6];
            id attributes = BRCVObject(registry, state->gpr[4]);
            cache.attributes = [attributes isKindOfClass:[NSDictionary class]] ? attributes : @{};
            uint32_t handle = BRCVHandle(registry, cache);
            BRCVReturn(state, state->gpr[8] && handle &&
                [registry.memory writeUInt32:handle address:state->gpr[8]] ? 0 : (uint32_t)kCVReturnInvalidArgument);
            return YES;
        }];
    [registry registerSymbol:@"_CVOpenGLTextureCacheCreateTextureFromImage"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCOpenGLTextureCache *cache = BRCVObject(registry, state->gpr[4]);
            BRPPCPixelBuffer *image = BRCVObject(registry, state->gpr[5]);
            if (![cache isKindOfClass:[BRPPCOpenGLTextureCache class]] ||
                ![image isKindOfClass:[BRPPCPixelBuffer class]] || !state->gpr[7]) {
                BRCVReturn(state, (uint32_t)kCVReturnInvalidArgument); return YES;
            }
            BRPPCOpenGLTexture *texture = [BRPPCOpenGLTexture new];
            texture.image = image; texture.flipped = NO;
            uint32_t handle = BRCVHandle(registry, texture);
            BRCVReturn(state, handle && [registry.memory writeUInt32:handle address:state->gpr[7]]
                ? 0 : (uint32_t)kCVReturnInvalidArgument); return YES;
        }];
    [registry registerSymbol:@"_CVOpenGLTextureCacheFlush"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRCVReturn(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CVOpenGLTextureIsFlipped"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCOpenGLTexture *texture = BRCVObject(registry, state->gpr[3]);
            BRCVReturn(state, [texture isKindOfClass:[BRPPCOpenGLTexture class]] && texture.flipped);
            return YES;
        }];
    return YES;
}
@end
