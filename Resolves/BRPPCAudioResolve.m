#import "BRPPCAudioResolve.h"
#import "BRPPCAddressSpace.h"
#import <CoreServices/CoreServices.h>

@interface BRPPCAudioUnit : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *properties;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *parameters;
@property(nonatomic) BOOL initialized;
@property(nonatomic) BOOL running;
@end
@implementation BRPPCAudioUnit @end

@interface BRPPCAudioGraph : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCAudioUnit *> *nodes;
@property(nonatomic) uint32_t nextNode;
@property(nonatomic) BOOL open;
@property(nonatomic) BOOL initialized;
@property(nonatomic) BOOL running;
@end
@implementation BRPPCAudioGraph @end

@interface BRPPCAudioFile : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSData *> *properties;
@end
@implementation BRPPCAudioFile @end

static void BRAudioReturn(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value; state->pc = state->lr;
}

static id BRAudioObject(BRPPCResolveRegistry *registry, uint32_t handle) {
    return registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
}

static uint32_t BRAudioHandle(BRPPCResolveRegistry *registry, id object) {
    return registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0;
}

static NSString *BRAudioPropertyKey(uint32_t property, uint32_t scope, uint32_t element) {
    return [NSString stringWithFormat:@"%u:%u:%u", property, scope, element];
}

@interface BRPPCAudioResolve ()
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSData *> *> *converterProperties;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *coreAudioProperties;
@end

@implementation BRPPCAudioResolve
- (instancetype)init {
    self = [super initWithFrameworkName:@"Audio"];
    if (self) {
        _converterProperties = [NSMutableDictionary dictionary];
        _coreAudioProperties = [NSMutableDictionary dictionary];
    }
    return self;
}
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    [registry registerSymbol:@"_NewAUGraph" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioGraph *graph = [BRPPCAudioGraph new];
        graph.nodes = [NSMutableDictionary dictionary]; graph.nextNode = 1;
        uint32_t handle = BRAudioHandle(registry, graph);
        BRAudioReturn(state, state->gpr[3] && [registry.memory writeUInt32:handle address:state->gpr[3]]
            ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AUGraphNewNode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioGraph *graph = BRAudioObject(registry, state->gpr[3]);
        uint32_t output = state->gpr[7];
        if (![graph isKindOfClass:[BRPPCAudioGraph class]] || !output) {
            BRAudioReturn(state, (uint32_t)paramErr); return YES;
        }
        uint32_t node = graph.nextNode++; BRPPCAudioUnit *unit = [BRPPCAudioUnit new];
        unit.properties = [NSMutableDictionary dictionary]; unit.parameters = [NSMutableDictionary dictionary];
        graph.nodes[@(node)] = unit;
        BRAudioReturn(state, [registry.memory writeUInt32:node address:output] ? 0 : (uint32_t)paramErr);
        return YES;
    }];
    [registry registerSymbol:@"_AUGraphGetNodeInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioGraph *graph = BRAudioObject(registry, state->gpr[3]);
        BRPPCAudioUnit *unit = graph.nodes[@(state->gpr[4])]; uint32_t handle = BRAudioHandle(registry, unit);
        BOOL valid = unit && state->gpr[6] && [registry.memory writeUInt32:handle address:state->gpr[6]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    NSDictionary<NSString *, NSString *> *graphStates = @{
        @"_AUGraphOpen": @"open", @"_AUGraphInitialize": @"initialized",
        @"_AUGraphUninitialize": @"uninitialize", @"_AUGraphStart": @"running",
        @"_AUGraphStop": @"stopped", @"_AUGraphClose": @"closed"
    };
    [graphStates enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSString *action, BOOL *stop) {
        (void)stop;
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCAudioGraph *graph = BRAudioObject(registry, state->gpr[3]);
            if ([action isEqualToString:@"open"]) graph.open = YES;
            else if ([action isEqualToString:@"initialized"]) graph.initialized = YES;
            else if ([action isEqualToString:@"uninitialize"]) graph.initialized = NO;
            else if ([action isEqualToString:@"running"]) graph.running = YES;
            else if ([action isEqualToString:@"stopped"]) graph.running = NO;
            else { graph.open = NO; graph.running = NO; graph.initialized = NO; }
            BRAudioReturn(state, graph ? 0 : (uint32_t)paramErr); return YES;
        }];
    }];
    [registry registerSymbol:@"_AUGraphIsRunning" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioGraph *graph = BRAudioObject(registry, state->gpr[3]);
        BOOL valid = graph && state->gpr[4] && [registry.memory writeUInt32:graph.running address:state->gpr[4]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_AUGraphConnectNodeInput", @"_AUGraphDisconnectNodeInput"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRAudioReturn(state,
                [BRAudioObject(registry, state->gpr[3]) isKindOfClass:[BRPPCAudioGraph class]] ? 0 : (uint32_t)paramErr);
            return YES;
        }];
    [registry registerSymbol:@"_AudioUnitSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioUnit *unit = BRAudioObject(registry, state->gpr[3]);
        uint32_t dataAddress = state->gpr[7], size = state->gpr[8];
        NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = [unit isKindOfClass:[BRPPCAudioUnit class]] &&
            (!size || [registry.memory readBytes:data.mutableBytes address:dataAddress length:size]);
        if (valid) unit.properties[BRAudioPropertyKey(state->gpr[4], state->gpr[5], state->gpr[6])] = data;
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioUnitGetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioUnit *unit = BRAudioObject(registry, state->gpr[3]);
        NSData *data = unit.properties[BRAudioPropertyKey(state->gpr[4], state->gpr[5], state->gpr[6])];
        uint32_t capacity = 0; BOOL valid = state->gpr[8] &&
            [registry.memory readUInt32:&capacity address:state->gpr[8]];
        uint32_t copied = MIN(capacity, (uint32_t)data.length);
        if (valid && copied) valid = [registry.memory writeBytes:data.bytes address:state->gpr[7] length:copied];
        if (valid) valid = [registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[8]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioUnitSetParameter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioUnit *unit = BRAudioObject(registry, state->gpr[3]);
        NSString *key = BRAudioPropertyKey(state->gpr[4], state->gpr[5], state->gpr[6]);
        if (unit) unit.parameters[key] = @((float)state->fpr[1]);
        BRAudioReturn(state, unit ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioUnitGetParameter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioUnit *unit = BRAudioObject(registry, state->gpr[3]);
        float value = [unit.parameters[BRAudioPropertyKey(state->gpr[4], state->gpr[5], state->gpr[6])] floatValue];
        uint32_t bits = 0; memcpy(&bits, &value, 4);
        BRAudioReturn(state, unit && state->gpr[7] && [registry.memory writeUInt32:bits address:state->gpr[7]]
            ? 0 : (uint32_t)paramErr); return YES;
    }];
    NSDictionary<NSString *, NSNumber *> *unitStates = @{
        @"_AudioUnitInitialize": @1, @"_AudioUnitUninitialize": @0,
        @"_AudioOutputUnitStart": @2, @"_AudioOutputUnitStop": @3,
        @"_AudioUnitReset": @4
    };
    [unitStates enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *action, BOOL *stop) {
        (void)stop;
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCAudioUnit *unit = BRAudioObject(registry, state->gpr[3]);
            if (action.intValue == 1) unit.initialized = YES;
            else if (action.intValue == 0) unit.initialized = NO;
            else if (action.intValue == 2) unit.running = YES;
            else if (action.intValue == 3) unit.running = NO;
            BRAudioReturn(state, unit ? 0 : (uint32_t)paramErr); return YES;
        }];
    }];
    for (NSString *symbol in @[@"_AudioUnitAddRenderNotify", @"_AudioUnitRemoveRenderNotify",
        @"_AudioUnitRender"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRAudioReturn(state,
                [BRAudioObject(registry, state->gpr[3]) isKindOfClass:[BRPPCAudioUnit class]] ? 0 : (uint32_t)paramErr);
            return YES;
        }];
    [registry registerSymbol:@"_ExtAudioFileCreateWithURL" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t output = state->gpr[8];
        BRPPCAudioFile *file = [BRPPCAudioFile new]; file.properties = [NSMutableDictionary dictionary];
        uint32_t handle = BRAudioHandle(registry, file);
        BRAudioReturn(state, output && [registry.memory writeUInt32:handle address:output] ? 0 : (uint32_t)paramErr);
        return YES;
    }];
    [registry registerSymbol:@"_ExtAudioFileSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioFile *file = BRAudioObject(registry, state->gpr[3]);
        NSMutableData *data = [NSMutableData dataWithLength:state->gpr[5]];
        BOOL valid = file && (!data.length || [registry.memory readBytes:data.mutableBytes
            address:state->gpr[6] length:data.length]);
        if (valid) file.properties[@(state->gpr[4])] = data;
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_ExtAudioFileGetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCAudioFile *file = BRAudioObject(registry, state->gpr[3]);
        NSData *data = file.properties[@(state->gpr[4])]; uint32_t capacity = 0;
        BOOL valid = file && state->gpr[5] && [registry.memory readUInt32:&capacity address:state->gpr[5]];
        uint32_t copied = MIN(capacity, (uint32_t)data.length);
        if (valid && copied) valid = [registry.memory writeBytes:data.bytes address:state->gpr[6] length:copied];
        if (valid) valid = [registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[5]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_ExtAudioFileWrite", @"_ExtAudioFileWriteAsync"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRAudioReturn(state,
                [BRAudioObject(registry, state->gpr[3]) isKindOfClass:[BRPPCAudioFile class]] ? 0 : (uint32_t)paramErr);
            return YES;
        }];
    for (NSString *symbol in @[@"_AudioComponentInstanceDispose", @"_AudioConverterDispose",
        @"_AudioFileClose", @"_ExtAudioFileDispose"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRAudioReturn(state, 0); return YES;
        }];
    __weak typeof(self) weakSelf = self;
    [registry registerSymbol:@"_AudioConverterSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t size = state->gpr[5], address = state->gpr[6];
        NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = state->gpr[3] && (!size ||
            [registry.memory readBytes:data.mutableBytes address:address length:size]);
        if (valid) {
            NSNumber *converter = @(state->gpr[3]);
            NSMutableDictionary *properties = weakSelf.converterProperties[converter];
            if (!properties) {
                properties = [NSMutableDictionary dictionary];
                weakSelf.converterProperties[converter] = properties;
            }
            properties[@(state->gpr[4])] = data;
        }
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioDeviceGetPropertyInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = state->gpr[7] &&
            [registry.memory writeUInt32:4 address:state->gpr[7]];
        if (valid && state->gpr[8]) valid = [registry.memory writeUInt32:1 address:state->gpr[8]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioDeviceGetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *key = [NSString stringWithFormat:@"%u:%u:%u:%u",
            state->gpr[3], state->gpr[4], state->gpr[5], state->gpr[6]];
        NSData *data = weakSelf.coreAudioProperties[key] ?: [NSData dataWithBytes:(uint32_t[]){0} length:4];
        uint32_t capacity = 0; BOOL valid = state->gpr[7] &&
            [registry.memory readUInt32:&capacity address:state->gpr[7]];
        uint32_t copied = MIN(capacity, (uint32_t)data.length);
        if (valid && copied) valid = [registry.memory writeBytes:data.bytes address:state->gpr[8] length:copied];
        if (valid) valid = [registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[7]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioDeviceSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t size = state->gpr[8]; uint32_t address = state->gpr[9];
        NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = !size || [registry.memory readBytes:data.mutableBytes address:address length:size];
        NSString *key = [NSString stringWithFormat:@"%u:%u:%u:%u",
            state->gpr[3], state->gpr[5], state->gpr[6], state->gpr[7]];
        if (valid) weakSelf.coreAudioProperties[key] = data;
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioHardwareGetPropertyInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = state->gpr[4] && [registry.memory writeUInt32:4 address:state->gpr[4]];
        if (valid && state->gpr[5]) valid = [registry.memory writeUInt32:0 address:state->gpr[5]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioHardwareGetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *key = [NSString stringWithFormat:@"hardware:%u", state->gpr[3]];
        const uint8_t defaultDevice[] = {0, 0, 0, 1};
        NSData *data = weakSelf.coreAudioProperties[key] ?:
            [NSData dataWithBytes:defaultDevice length:sizeof(defaultDevice)];
        uint32_t capacity = 0; BOOL valid = state->gpr[4] &&
            [registry.memory readUInt32:&capacity address:state->gpr[4]];
        uint32_t copied = MIN(capacity, (uint32_t)data.length);
        if (valid && copied) valid = [registry.memory writeBytes:data.bytes address:state->gpr[5] length:copied];
        if (valid) valid = [registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[4]];
        BRAudioReturn(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AudioHardwareAddPropertyListener" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRAudioReturn(state, 0); return YES;
    }];
    return YES;
}
@end
