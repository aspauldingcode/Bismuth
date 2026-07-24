#import "BRPPCFrameworkResolve.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import <dlfcn.h>
#import <objc/runtime.h>

static const void *BRPPCFrameworkDataContextKey = &BRPPCFrameworkDataContextKey;

@interface BRPPCFrameworkDataContext : NSObject
@property(nonatomic) uint32_t cursor;
@end
@implementation BRPPCFrameworkDataContext
@end

@implementation BRPPCFrameworkResolve
- (instancetype)initWithFrameworkName:(NSString *)frameworkName {
    if ((self = [super init])) _frameworkName = [frameworkName copy];
    return self;
}
- (void *)openFramework {
    NSString *libraryDirectory = NSSearchPathForDirectoriesInDomains(
        NSLibraryDirectory, NSSystemDomainMask, YES).firstObject;
    if (!libraryDirectory.length) return NULL;
    NSString *frameworkDirectory = [libraryDirectory stringByAppendingPathComponent:@"Frameworks"];
    NSString *bundleName = [_frameworkName stringByAppendingPathExtension:@"framework"];
    NSString *frameworkPath = [[frameworkDirectory stringByAppendingPathComponent:bundleName]
        stringByAppendingPathComponent:_frameworkName];
    return dlopen(frameworkPath.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
}
- (void)registerZeroFunction:(NSString *)symbol registry:(BRPPCResolveRegistry *)registry {
    if ([registry addressForSymbol:symbol]) return;
    [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **error) {
        (void)error; state->gpr[3] = 0; state->gpr[4] = 0; state->pc = state->lr; return YES;
    }];
}
- (void)registerZeroFunctions:(NSArray<NSString *> *)symbols
                     registry:(BRPPCResolveRegistry *)registry {
    for (NSString *symbol in symbols) [self registerZeroFunction:symbol registry:registry];
}
- (BOOL)registerStringConstant:(NSString *)symbol value:(NSString *)value
                       registry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    uint32_t object = registry.guestObjectEncoder ? registry.guestObjectEncoder(value) : 0;
    return [self registerWordConstant:symbol value:object registry:registry error:error];
}
- (BOOL)registerStringConstants:(NSArray<NSString *> *)symbols
                        registry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    for (NSString *symbol in symbols) {
        NSString *value = [symbol hasPrefix:@"_"] ? [symbol substringFromIndex:1] : symbol;
        if (![self registerStringConstant:symbol value:value registry:registry error:error]) return NO;
    }
    return YES;
}
- (BOOL)registerWordConstant:(NSString *)symbol value:(uint32_t)value
                     registry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if ([registry addressForSymbol:symbol]) return YES;
    @synchronized([BRPPCFrameworkResolve class]) {
        BRPPCFrameworkDataContext *context = objc_getAssociatedObject(registry,
            BRPPCFrameworkDataContextKey);
        if (!context) {
            if (![registry.memory mapAddress:BRPPCGuestFrameworkDataBase size:BRPPCGuestFrameworkDataSize
                                  protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                        name:@"framework constants" error:error]) return NO;
            context = [BRPPCFrameworkDataContext new];
            context.cursor = BRPPCGuestFrameworkDataBase;
            objc_setAssociatedObject(registry, BRPPCFrameworkDataContextKey, context,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        uint32_t address = context.cursor;
        context.cursor += 4;
        if (context.cursor > BRPPCGuestFrameworkDataBase + BRPPCGuestFrameworkDataSize ||
            ![registry.memory writeUInt32:value address:address]) return NO;
        return [registry registerSymbol:symbol atAddress:address
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                (void)state;
                if (callError) *callError = [NSError errorWithDomain:@"theoderoy.Bismuth.framework"
                    code:1 userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"%@ is data, not callable code.", symbol]}];
                return NO;
            } error:error];
    }
}
- (BOOL)registerDataConstant:(NSString *)symbol data:(NSData *)data alignment:(uint32_t)alignment
                     registry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if ([registry addressForSymbol:symbol]) return YES;
    if (!data.length) return NO;
    @synchronized([BRPPCFrameworkResolve class]) {
        BRPPCFrameworkDataContext *context = objc_getAssociatedObject(registry,
            BRPPCFrameworkDataContextKey);
        if (!context) {
            if (![registry.memory mapAddress:BRPPCGuestFrameworkDataBase size:BRPPCGuestFrameworkDataSize
                                  protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                        name:@"framework constants" error:error]) return NO;
            context = [BRPPCFrameworkDataContext new];
            context.cursor = BRPPCGuestFrameworkDataBase;
            objc_setAssociatedObject(registry, BRPPCFrameworkDataContextKey, context,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        uint32_t effectiveAlignment = MAX(alignment, 1u);
        uint32_t address = (context.cursor + effectiveAlignment - 1) & ~(effectiveAlignment - 1);
        uint64_t end = (uint64_t)address + data.length;
        if (end > BRPPCGuestFrameworkDataBase + BRPPCGuestFrameworkDataSize ||
            ![registry.memory writeBytes:data.bytes address:address length:data.length]) return NO;
        context.cursor = (uint32_t)end;
        return [registry registerSymbol:symbol atAddress:address
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                (void)state;
                if (callError) *callError = [NSError errorWithDomain:@"theoderoy.Bismuth.framework"
                    code:1 userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"%@ is data, not callable code.", symbol]}];
                return NO;
            } error:error];
    }
}
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)registry; (void)error; return YES;
}
- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    return [self installFrameworkSymbolsInRegistry:registry error:error];
}
@end
