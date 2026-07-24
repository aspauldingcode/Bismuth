#import "BRPPCIOKitResolve.h"
#import "BRPPCAddressSpace.h"
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

static void BRIOFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

@interface BRPPCIOKitResolve ()
@property(nonatomic) void *IOKitHandle;
@end

@interface BRIOKitNotificationPort : NSObject
@property(nonatomic) IONotificationPortRef port;
@property(nonatomic, strong) id source;
@property(nonatomic) void (*destroyPort)(IONotificationPortRef);
@end
@implementation BRIOKitNotificationPort
- (void)dealloc { if (_port && _destroyPort) _destroyPort(_port); }
@end

@implementation BRPPCIOKitResolve
- (instancetype)init { return [super initWithFrameworkName:@"IOKit"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    self.IOKitHandle = [self openFramework];
    if (![self registerWordConstant:@"_kIOMasterPortDefault" value:0
                            registry:registry error:error]) return NO;
    [registry registerSymbol:@"_IOMasterPort" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!state->gpr[4] || ![registry.memory writeUInt32:0 address:state->gpr[4]])
            BRIOFinish(state, KERN_INVALID_ARGUMENT);
        else BRIOFinish(state, 0);
        return YES;
    }];
    __weak typeof(self) weakSelf = self;
    [registry registerSymbol:@"_IONotificationPortCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; IONotificationPortRef (*call)(mach_port_t) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IONotificationPortCreate") : NULL;
        IONotificationPortRef port = call ? call((mach_port_t)state->gpr[3]) : NULL;
        BRIOKitNotificationPort *wrapper = port ? [BRIOKitNotificationPort new] : nil; wrapper.port = port;
        wrapper.destroyPort = weakSelf.IOKitHandle ? dlsym(weakSelf.IOKitHandle, "IONotificationPortDestroy") : NULL;
        BRIOFinish(state, wrapper && registry.guestObjectEncoder ? registry.guestObjectEncoder(wrapper) : 0); return YES;
    }];
    [registry registerSymbol:@"_IONotificationPortGetRunLoopSource" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRIOKitNotificationPort *wrapper = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        if ([wrapper isKindOfClass:[BRIOKitNotificationPort class]] && !wrapper.source) {
            CFRunLoopSourceRef (*call)(IONotificationPortRef) = weakSelf.IOKitHandle
                ? dlsym(weakSelf.IOKitHandle, "IONotificationPortGetRunLoopSource") : NULL;
            CFRunLoopSourceRef source = call ? call(wrapper.port) : NULL; wrapper.source = (__bridge id)source;
        }
        BRIOFinish(state, wrapper.source && registry.guestObjectEncoder ? registry.guestObjectEncoder(wrapper.source) : 0); return YES;
    }];
    [registry registerSymbol:@"_IOObjectConformsTo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *className = [registry.memory readCStringAtAddress:state->gpr[4] maximumLength:1024];
        boolean_t (*call)(io_object_t, const io_name_t) = weakSelf.IOKitHandle ? dlsym(weakSelf.IOKitHandle, "IOObjectConformsTo") : NULL;
        BRIOFinish(state, call && className.length ? call((io_object_t)state->gpr[3], className.UTF8String) : 0); return YES;
    }];
    [registry registerSymbol:@"_IOIteratorReset" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; kern_return_t (*call)(io_iterator_t) = weakSelf.IOKitHandle ? dlsym(weakSelf.IOKitHandle, "IOIteratorReset") : NULL;
        BRIOFinish(state, call ? (uint32_t)call((io_iterator_t)state->gpr[3]) : KERN_FAILURE); return YES;
    }];
    [registry registerSymbol:@"_IOServiceMatchPropertyTable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id table = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil; boolean_t matches = 0;
        kern_return_t (*call)(io_service_t, CFDictionaryRef, boolean_t *) = weakSelf.IOKitHandle ? dlsym(weakSelf.IOKitHandle, "IOServiceMatchPropertyTable") : NULL;
        kern_return_t result = call && [table isKindOfClass:[NSDictionary class]] ? call((io_service_t)state->gpr[3], (__bridge CFDictionaryRef)table, &matches) : KERN_INVALID_ARGUMENT;
        if (state->gpr[5] && ![registry.memory writeUInt32:matches address:state->gpr[5]]) result = KERN_INVALID_ARGUMENT;
        BRIOFinish(state, (uint32_t)result); return YES;
    }];
    NSDictionary *iteratorCalls = @{@"_IORegistryEntryGetChildIterator": @0, @"_IORegistryEntryGetParentEntry": @1};
    [iteratorCalls enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *parent, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *plane = [registry.memory readCStringAtAddress:state->gpr[4] maximumLength:128]; io_object_t output = 0;
            typedef kern_return_t (*EntryCall)(io_registry_entry_t, const io_name_t, io_object_t *);
            EntryCall call = weakSelf.IOKitHandle ? dlsym(weakSelf.IOKitHandle, parent.boolValue ? "IORegistryEntryGetParentEntry" : "IORegistryEntryGetChildIterator") : NULL;
            kern_return_t result = call && plane.length && state->gpr[5] ? call((io_registry_entry_t)state->gpr[3], plane.UTF8String, &output) : KERN_INVALID_ARGUMENT;
            if (state->gpr[5] && ![registry.memory writeUInt32:output address:state->gpr[5]]) result = KERN_INVALID_ARGUMENT;
            BRIOFinish(state, (uint32_t)result); return YES;
        }];
    }];
    for (NSString *symbol in @[@"_IODestroyPlugInInterface", @"_IOCreatePlugInInterfaceForService",
        @"_IOServiceAddInterestNotification", @"_IOServiceAddMatchingNotification"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRIOFinish(state, (uint32_t)KERN_NOT_SUPPORTED); return YES;
        }];
    [registry registerSymbol:@"_IOServiceMatching" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSString *name = [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:1024];
        CFMutableDictionaryRef (*call)(const char *) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IOServiceMatching") : NULL;
        CFMutableDictionaryRef nativeMatching = name.length && call ? call(name.UTF8String) : NULL;
        NSDictionary *matching = nativeMatching ? CFBridgingRelease(nativeMatching)
                                                : (name ? @{@"IOProviderClass": name} : @{});
        BRIOFinish(state, registry.guestObjectEncoder ? registry.guestObjectEncoder(matching) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IOBSDNameMatching" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSString *name = [registry.memory readCStringAtAddress:state->gpr[5] maximumLength:1024];
        NSDictionary *matching = name ? @{@"BSD Name": name} : @{};
        BRIOFinish(state, registry.guestObjectEncoder ? registry.guestObjectEncoder(matching) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IOServiceGetMatchingServices" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; io_iterator_t iterator = IO_OBJECT_NULL;
        kern_return_t (*call)(mach_port_t, CFDictionaryRef, io_iterator_t *) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IOServiceGetMatchingServices") : NULL;
        id matching = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil;
        kern_return_t result = call && matching
            ? call((mach_port_t)state->gpr[3], (__bridge CFDictionaryRef)matching, &iterator)
            : KERN_SUCCESS;
        if (!state->gpr[5] || ![registry.memory writeUInt32:iterator address:state->gpr[5]])
            result = KERN_INVALID_ARGUMENT;
        BRIOFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_IOServiceGetMatchingService" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        io_service_t (*call)(mach_port_t, CFDictionaryRef) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IOServiceGetMatchingService") : NULL;
        id matching = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil;
        BRIOFinish(state, call && matching
            ? call((mach_port_t)state->gpr[3], (__bridge CFDictionaryRef)matching) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IOIteratorNext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; io_object_t (*call)(io_iterator_t) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IOIteratorNext") : NULL;
        BRIOFinish(state, call ? call((io_iterator_t)state->gpr[3]) : 0); return YES;
    }];
    [registry registerSymbol:@"_IOObjectRelease" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; kern_return_t (*call)(io_object_t) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IOObjectRelease") : NULL;
        BRIOFinish(state, call && state->gpr[3] ? (uint32_t)call((io_object_t)state->gpr[3]) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IORegistryEntryCreateCFProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        CFTypeRef (*call)(io_registry_entry_t, CFStringRef, CFAllocatorRef, IOOptionBits) =
            weakSelf.IOKitHandle ? dlsym(weakSelf.IOKitHandle, "IORegistryEntryCreateCFProperty") : NULL;
        id key = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil;
        CFTypeRef value = call && [key isKindOfClass:[NSString class]]
            ? call((io_registry_entry_t)state->gpr[3], (__bridge CFStringRef)key, NULL,
                   (IOOptionBits)state->gpr[6]) : NULL;
        id object = value ? CFBridgingRelease(value) : nil;
        BRIOFinish(state, registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IORegistryEntryFromPath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        io_registry_entry_t (*call)(mach_port_t, const io_string_t) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IORegistryEntryFromPath") : NULL;
        NSString *path = [registry.memory readCStringAtAddress:state->gpr[4] maximumLength:4096];
        BRIOFinish(state, call && path.length
            ? call((mach_port_t)state->gpr[3], path.fileSystemRepresentation) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IORegistryEntrySearchCFProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        CFTypeRef (*call)(io_registry_entry_t, const io_name_t, CFStringRef,
                          CFAllocatorRef, IOOptionBits) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IORegistryEntrySearchCFProperty") : NULL;
        NSString *plane = [registry.memory readCStringAtAddress:state->gpr[4] maximumLength:128];
        id key = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[5]) : nil;
        CFTypeRef value = call && plane.length && [key isKindOfClass:[NSString class]]
            ? call((io_registry_entry_t)state->gpr[3], plane.UTF8String,
                   (__bridge CFStringRef)key, NULL, (IOOptionBits)state->gpr[7]) : NULL;
        id object = value ? CFBridgingRelease(value) : nil;
        BRIOFinish(state, registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_IORegistryEntryGetName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; io_name_t name = {0};
        kern_return_t (*call)(io_registry_entry_t, io_name_t) = weakSelf.IOKitHandle
            ? dlsym(weakSelf.IOKitHandle, "IORegistryEntryGetName") : NULL;
        kern_return_t result = call ? call((io_registry_entry_t)state->gpr[3], name) : KERN_SUCCESS;
        size_t length = strnlen(name, sizeof(name)) + 1;
        if (!state->gpr[4] || ![registry.memory writeBytes:name address:state->gpr[4] length:length])
            result = KERN_INVALID_ARGUMENT;
        BRIOFinish(state, (uint32_t)result);
        return YES;
    }];
    [registry registerSymbol:@"_IOPMAssertionCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (state->gpr[5]) [registry.memory writeUInt32:1 address:state->gpr[5]];
        BRIOFinish(state, 0); return YES;
    }];
    [self registerZeroFunction:@"_IOPMAssertionRelease" registry:registry];
    return YES;
}
@end
