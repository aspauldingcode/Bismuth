#import "BRPPCOpenALResolve.h"
#import "BRPPCAddressSpace.h"
#import <OpenAL/al.h>
#import <dlfcn.h>

@interface BRPPCOpenALResolve ()
@property(nonatomic) void *handle;
@end

static void BROALFinish(BRPPCState *state, uint32_t result) {
    state->gpr[3] = result; state->pc = state->lr;
}

static void *BROALSymbol(void *handle, NSString *name) {
    return dlsym(handle ?: RTLD_DEFAULT, name.UTF8String + (name.UTF8String[0] == '_'));
}

static uint32_t BROALEncode(BRPPCResolveRegistry *registry, void *pointer) {
    return pointer && registry.guestObjectEncoder
        ? registry.guestObjectEncoder([NSValue valueWithPointer:pointer]) : 0;
}

static void *BROALDecode(BRPPCResolveRegistry *registry, uint32_t handle) {
    id object = registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
    return [object isKindOfClass:[NSValue class]] ? [object pointerValue] : NULL;
}

@implementation BRPPCOpenALResolve
- (instancetype)init { return [super initWithFrameworkName:@"OpenAL"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    self.handle = [self openFramework];
    __weak typeof(self) weakSelf = self;
    for (NSString *symbol in @[@"_alGenBuffers", @"_alGenSources"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t count = state->gpr[3];
            NSMutableData *values = [NSMutableData dataWithLength:(NSUInteger)count * 4];
            void (*function)(int32_t, uint32_t *) = BROALSymbol(weakSelf.handle, symbol);
            if (function) function((int32_t)count, values.mutableBytes);
            uint32_t *words = values.mutableBytes;
            for (uint32_t index = 0; index < count; index++)
                if (![registry.memory writeUInt32:words[index] address:state->gpr[4] + index * 4]) return NO;
            BROALFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_alDeleteBuffers", @"_alDeleteSources",
        @"_alSourceQueueBuffers", @"_alSourceUnqueueBuffers"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BOOL deleting = [symbol hasPrefix:@"_alDelete"];
            uint32_t count = state->gpr[deleting ? 3 : 4];
            uint32_t guestValues = state->gpr[deleting ? 4 : 5];
            NSMutableData *values = [NSMutableData dataWithLength:(NSUInteger)count * 4];
            uint32_t *words = values.mutableBytes;
            for (uint32_t index = 0; index < count; index++)
                if (![registry.memory readUInt32:&words[index] address:guestValues + index * 4]) return NO;
            void (*function)(uint32_t, int32_t, uint32_t *) = BROALSymbol(weakSelf.handle, symbol);
            if (deleting) {
                void (*deleteFunction)(int32_t, const uint32_t *) = (void *)function;
                if (deleteFunction) deleteFunction((int32_t)count, words);
            } else if (function) function(state->gpr[3], (int32_t)count, words);
            if ([symbol isEqualToString:@"_alSourceUnqueueBuffers"])
                for (uint32_t index = 0; index < count; index++)
                    if (![registry.memory writeUInt32:words[index] address:guestValues + index * 4]) return NO;
            BROALFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_alBufferData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[6];
        NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[5] length:length]) return NO;
        if (state->gpr[4] == AL_FORMAT_MONO16 || state->gpr[4] == AL_FORMAT_STEREO16) {
            uint8_t *bytes = data.mutableBytes;
            for (NSUInteger index = 0; index + 1 < data.length; index += 2) {
                uint8_t value = bytes[index]; bytes[index] = bytes[index + 1]; bytes[index + 1] = value;
            }
        }
        void (*function)(uint32_t, int32_t, const void *, int32_t, int32_t) =
            BROALSymbol(weakSelf.handle, @"_alBufferData");
        if (function) function(state->gpr[3], (int32_t)state->gpr[4], data.bytes,
                               (int32_t)length, (int32_t)state->gpr[7]);
        BROALFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_alSourcePlay", @"_alSourceStop", @"_alDistanceModel"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; void (*function)(uint32_t) = BROALSymbol(weakSelf.handle, symbol);
            if (function) function(state->gpr[3]); BROALFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_alSourcef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; void (*function)(uint32_t, uint32_t, float) = BROALSymbol(weakSelf.handle, @"_alSourcef");
        if (function) function(state->gpr[3], state->gpr[4], (float)state->fpr[1]);
        BROALFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_alGetSourcei" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t value = 0;
        void (*function)(uint32_t, uint32_t, int32_t *) = BROALSymbol(weakSelf.handle, @"_alGetSourcei");
        if (function) function(state->gpr[3], state->gpr[4], &value);
        if (!state->gpr[5] || ![registry.memory writeUInt32:(uint32_t)value address:state->gpr[5]]) return NO;
        BROALFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_alGetError", @"_alcGetError"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            if ([symbol isEqualToString:@"_alGetError"]) {
                uint32_t (*function)(void) = BROALSymbol(weakSelf.handle, symbol);
                BROALFinish(state, function ? function() : 0);
            } else {
                uint32_t (*function)(void *) = BROALSymbol(weakSelf.handle, symbol);
                BROALFinish(state, function ? function(BROALDecode(registry, state->gpr[3])) : 0);
            }
            return YES;
        }];
    [registry registerSymbol:@"_alcOpenDevice" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = state->gpr[3]
            ? [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:4096] : nil;
        void *(*function)(const char *) = BROALSymbol(weakSelf.handle, @"_alcOpenDevice");
        BROALFinish(state, BROALEncode(registry, function ? function(name.UTF8String) : NULL)); return YES;
    }];
    [registry registerSymbol:@"_alcCreateContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t attributes[64]; int32_t *attributesPointer = NULL;
        if (state->gpr[4]) {
            attributesPointer = attributes;
            for (NSUInteger index = 0; index < 64; index++) {
                uint32_t value = 0;
                if (![registry.memory readUInt32:&value address:state->gpr[4] + (uint32_t)index * 4]) return NO;
                attributes[index] = (int32_t)value; if (!value) break;
            }
        }
        void *(*function)(void *, const int32_t *) = BROALSymbol(weakSelf.handle, @"_alcCreateContext");
        void *context = function ? function(BROALDecode(registry, state->gpr[3]), attributesPointer) : NULL;
        BROALFinish(state, BROALEncode(registry, context)); return YES;
    }];
    for (NSString *symbol in @[@"_alcCloseDevice", @"_alcMakeContextCurrent"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint8_t (*function)(void *) = BROALSymbol(weakSelf.handle, symbol);
            BROALFinish(state, function ? function(BROALDecode(registry, state->gpr[3])) : 0); return YES;
        }];
    [registry registerSymbol:@"_alcDestroyContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; void (*function)(void *) = BROALSymbol(weakSelf.handle, @"_alcDestroyContext");
        if (function) function(BROALDecode(registry, state->gpr[3])); BROALFinish(state, 0); return YES;
    }];
    return YES;
}
- (void)dealloc { if (_handle) dlclose(_handle); }
@end
