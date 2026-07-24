#import "BRPPCSystemConfigurationResolve.h"
#import "BRPPCAddressSpace.h"
#import <SystemConfiguration/SystemConfiguration.h>

@interface BRPPCReachability : NSObject
@property(nonatomic, copy) NSString *hostName;
@property(nonatomic, strong) NSData *address;
@property(nonatomic) uint32_t callback;
@property(nonatomic) uint32_t context;
@end
@implementation BRPPCReachability @end

@interface BRPPCPreferences : NSObject
@property(nonatomic, strong) NSMutableDictionary *values;
@end
@implementation BRPPCPreferences @end

static void BRSCFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value; state->pc = state->lr;
}

static id BRSCObject(BRPPCResolveRegistry *registry, uint32_t handle) {
    return registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
}

static uint32_t BRSCHandle(BRPPCResolveRegistry *registry, id object) {
    return registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0;
}

@implementation BRPPCSystemConfigurationResolve
- (instancetype)init { return [super initWithFrameworkName:@"SystemConfiguration"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    [registry registerSymbol:@"_SCNetworkReachabilityCreateWithName"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *name = [registry.memory readCStringAtAddress:state->gpr[4]
                                                                     maximumLength:4096];
            BRPPCReachability *reachability = name ? [BRPPCReachability new] : nil;
            reachability.hostName = name;
            BRSCFinish(state, BRSCHandle(registry, reachability)); return YES;
        }];
    [registry registerSymbol:@"_SCNetworkReachabilityCreateWithAddress"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint8_t length = 0;
            if (!state->gpr[4] || ![registry.memory readBytes:&length address:state->gpr[4] length:1] ||
                length < 2 || length > 128) { BRSCFinish(state, 0); return YES; }
            NSMutableData *address = [NSMutableData dataWithLength:length];
            if (![registry.memory readBytes:address.mutableBytes address:state->gpr[4] length:length]) return NO;
            BRPPCReachability *reachability = [BRPPCReachability new]; reachability.address = address;
            BRSCFinish(state, BRSCHandle(registry, reachability)); return YES;
        }];
    [registry registerSymbol:@"_SCNetworkReachabilityGetFlags"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCReachability *reachability = BRSCObject(registry, state->gpr[3]);
            BOOL valid = [reachability isKindOfClass:[BRPPCReachability class]] && state->gpr[4];
            if (valid) valid = [registry.memory
                writeUInt32:kSCNetworkReachabilityFlagsReachable address:state->gpr[4]];
            BRSCFinish(state, valid); return YES;
        }];
    [registry registerSymbol:@"_SCNetworkReachabilitySetCallback"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCReachability *reachability = BRSCObject(registry, state->gpr[3]);
            if ([reachability isKindOfClass:[BRPPCReachability class]]) {
                reachability.callback = state->gpr[4];
                if (state->gpr[5]) {
                    uint32_t context = 0;
                    [registry.memory readUInt32:&context address:state->gpr[5] + 4];
                    reachability.context = context;
                }
            }
            BRSCFinish(state, reachability != nil); return YES;
        }];
    for (NSString *symbol in @[@"_SCNetworkReachabilityScheduleWithRunLoop",
        @"_SCNetworkReachabilityUnscheduleFromRunLoop"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRSCFinish(state,
                [BRSCObject(registry, state->gpr[3]) isKindOfClass:[BRPPCReachability class]]); return YES;
        }];
    [registry registerSymbol:@"_SCPreferencesCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPreferences *preferences = [BRPPCPreferences new];
        preferences.values = [NSMutableDictionary dictionary];
        BRSCFinish(state, BRSCHandle(registry, preferences)); return YES;
    }];
    [registry registerSymbol:@"_SCPreferencesGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPreferences *preferences = BRSCObject(registry, state->gpr[3]);
        id key = BRSCObject(registry, state->gpr[4]);
        BRSCFinish(state, BRSCHandle(registry, preferences.values[key])); return YES;
    }];
    [registry registerSymbol:@"_SCPreferencesSetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPreferences *preferences = BRSCObject(registry, state->gpr[3]);
        id key = BRSCObject(registry, state->gpr[4]), value = BRSCObject(registry, state->gpr[5]);
        BOOL valid = [preferences isKindOfClass:[BRPPCPreferences class]] && key;
        if (valid) preferences.values[key] = value ?: [NSNull null];
        BRSCFinish(state, valid); return YES;
    }];
    [registry registerSymbol:@"_SCPreferencesRemoveValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCPreferences *preferences = BRSCObject(registry, state->gpr[3]);
        id key = BRSCObject(registry, state->gpr[4]); BOOL valid = preferences && key;
        if (valid) [preferences.values removeObjectForKey:key]; BRSCFinish(state, valid); return YES;
    }];
    for (NSString *symbol in @[@"_SCPreferencesSynchronize", @"_SCPreferencesCommitChanges",
        @"_SCPreferencesApplyChanges", @"_SCPreferencesLock", @"_SCPreferencesUnlock"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRSCFinish(state,
                [BRSCObject(registry, state->gpr[3]) isKindOfClass:[BRPPCPreferences class]]); return YES;
        }];
    return YES;
}
@end
