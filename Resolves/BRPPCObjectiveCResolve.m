#import "BRPPCObjectiveCResolve.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import "BRPPCMachOLoader.h"
#import <AppKit/AppKit.h>
#import <CoreImage/CoreImage.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/objc-sync.h>
#include <ctype.h>
#include <dlfcn.h>
#include <ffi/ffi.h>

static NSString * const BRPPCObjectiveCErrorDomain = @"theoderoy.Bismuth.objective-c";
static const uint32_t BRPPCConstantStringUnicodeFlag = 0x10u;
static const uint32_t BRPPCGuestNotFound = INT32_MAX;
static const void *BRPPCBitmapStorageKey = &BRPPCBitmapStorageKey;
static const void *BRPPCLegacyOpenGLPresentationViewKey =
    &BRPPCLegacyOpenGLPresentationViewKey;
static const void *BRPPCLegacyOpenGLPresentationLayerKey =
    &BRPPCLegacyOpenGLPresentationLayerKey;
static const void *BRPPCLegacyOpenGLPresentationTimeKey =
    &BRPPCLegacyOpenGLPresentationTimeKey;
static const void *BRPPCLegacyOpenGLFrameStorageKey =
    &BRPPCLegacyOpenGLFrameStorageKey;
static _Thread_local BOOL BRPPCLegacyOpenGLPresentationActive;

@interface BRPPCPassthroughImageView : NSImageView
@end

@implementation BRPPCPassthroughImageView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end

@interface BRPPCLegacyOpenGLFrameStorage : NSObject
@property(nonatomic) int32_t width;
@property(nonatomic) int32_t height;
@property(nonatomic) size_t rowBytes;
@property(nonatomic, strong) NSMutableData *pixels;
@end

@implementation BRPPCLegacyOpenGLFrameStorage
@end

static FILE *BRPPCUITraceStream(void) {
    static FILE *stream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *path = getenv("BISMUTH_UI_TRACE_FILE");
        stream = path && *path ? fopen(path, "a") : stderr;
        if (!stream) stream = stderr;
        setvbuf(stream, NULL, _IOLBF, 0);
    });
    return stream;
}

static CGImageRef BRPPCCopyOpenGLBackBuffer(id context, NSView **viewResult) {
    NSView *view = [context valueForKey:@"view"];
    if (!view || view.bounds.size.width <= 0 || view.bounds.size.height <= 0) return NULL;
    SEL makeCurrentSelector = NSSelectorFromString(@"makeCurrentContext");
    if ([context respondsToSelector:makeCurrentSelector]) {
        void (*makeCurrent)(id, SEL) =
            (void (*)(id, SEL))[context methodForSelector:makeCurrentSelector];
        makeCurrent(context, makeCurrentSelector);
    }
    static void (*getInteger)(uint32_t, int32_t *);
    static void (*readBuffer)(uint32_t);
    static void (*readPixels)(int32_t, int32_t, int32_t, int32_t, uint32_t, uint32_t, void *);
    static void (*pixelStore)(uint32_t, int32_t);
    static CGColorSpaceRef colorSpace;
    static dispatch_once_t openGLSymbolsToken;
    dispatch_once(&openGLSymbolsToken, ^{
        getInteger = dlsym(RTLD_DEFAULT, "glGetIntegerv");
        readBuffer = dlsym(RTLD_DEFAULT, "glReadBuffer");
        readPixels = dlsym(RTLD_DEFAULT, "glReadPixels");
        pixelStore = dlsym(RTLD_DEFAULT, "glPixelStorei");
        colorSpace = CGColorSpaceCreateDeviceRGB();
    });
    if (!getInteger || !readPixels) return NULL;
    int32_t viewport[4] = {0};
    getInteger(GL_VIEWPORT, viewport);
    int32_t width = viewport[2], height = viewport[3];
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return NULL;
    size_t rowBytes = (size_t)width * 4, length = rowBytes * (size_t)height;
    BRPPCLegacyOpenGLFrameStorage *storage = objc_getAssociatedObject(
        context, BRPPCLegacyOpenGLFrameStorageKey);
    if (!storage || storage.width != width || storage.height != height ||
        storage.rowBytes != rowBytes) {
        storage = [BRPPCLegacyOpenGLFrameStorage new];
        storage.width = width;
        storage.height = height;
        storage.rowBytes = rowBytes;
        storage.pixels = [NSMutableData dataWithLength:length];
        objc_setAssociatedObject(context, BRPPCLegacyOpenGLFrameStorageKey, storage,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableData *pixels = storage.pixels;

    if (readBuffer) readBuffer(GL_FRONT);
    int32_t packAlignment = 4, packRowLength = 0, packSkipRows = 0, packSkipPixels = 0;
    getInteger(GL_PACK_ALIGNMENT, &packAlignment);
    getInteger(GL_PACK_ROW_LENGTH, &packRowLength);
    getInteger(GL_PACK_SKIP_ROWS, &packSkipRows);
    getInteger(GL_PACK_SKIP_PIXELS, &packSkipPixels);
    if (pixelStore) {
        pixelStore(GL_PACK_ALIGNMENT, 4);
        pixelStore(GL_PACK_ROW_LENGTH, 0);
        pixelStore(GL_PACK_SKIP_ROWS, 0);
        pixelStore(GL_PACK_SKIP_PIXELS, 0);
    }
    readPixels(viewport[0], viewport[1], width, height, GL_BGRA,
               GL_UNSIGNED_INT_8_8_8_8_REV, pixels.mutableBytes);
    if (pixelStore) {
        pixelStore(GL_PACK_ALIGNMENT, packAlignment);
        pixelStore(GL_PACK_ROW_LENGTH, packRowLength);
        pixelStore(GL_PACK_SKIP_ROWS, packSkipRows);
        pixelStore(GL_PACK_SKIP_PIXELS, packSkipPixels);
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little |
        (CGBitmapInfo)kCGImageAlphaNoneSkipFirst;
    CGImageRef image = CGImageCreate((size_t)width, (size_t)height, 8, 32, rowBytes,
        colorSpace, bitmapInfo, provider, NULL, false,
        kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    if (viewResult) *viewResult = view;
    return image;
}

@class BRPPCObjectiveCResolve;

@interface BRPPCUnavailableCIFilter : CIFilter
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *compatibilityValues;
@end
@implementation BRPPCUnavailableCIFilter
- (instancetype)init { if ((self = [super init])) _compatibilityValues = [NSMutableDictionary dictionary]; return self; }
- (void)setValue:(id)value forUndefinedKey:(NSString *)key { if (value) self.compatibilityValues[key] = value; }
- (id)valueForUndefinedKey:(NSString *)key { return self.compatibilityValues[key]; }
- (CIImage *)outputImage { return self.compatibilityValues[kCIInputImageKey]; }
@end
@interface BRPPCGuestMethod : NSObject {
@public
    ffi_cif _cif;
    ffi_closure *_closure;
    void *_closureCode;
    ffi_type **_argumentTypes;
}
@property(nonatomic, weak) BRPPCObjectiveCResolve *resolver;
@property(nonatomic) uint32_t implementationAddress;
@property(nonatomic) uint32_t selectorAddress;
@property(nonatomic) IMP fallbackImplementation;
@property(nonatomic) Class owningClass;
@property(nonatomic) BOOL classMethod;
@property(nonatomic, copy) NSString *types;
@property(nonatomic, copy) NSString *hostTypes;
@property(nonatomic, strong) NSMutableArray<NSValue *> *ffiAllocations;
@end
@implementation BRPPCGuestMethod
- (void)dealloc {
    if (_closure) ffi_closure_free(_closure);
    free(_argumentTypes);
    for (NSValue *allocation in _ffiAllocations) free(allocation.pointerValue);
}
@end

@interface BRPPCPointerScratch : NSObject
@property(nonatomic) uint32_t guestAddress;
@property(nonatomic, copy) NSString *type;
@property(nonatomic, strong) NSMutableData *hostData;
@property(nonatomic, strong) id retainedObject;
@property(nonatomic) BOOL copyBack;
@end
@implementation BRPPCPointerScratch
@end

@interface BRPPCCallbackPointerScratch : NSObject
@property(nonatomic) void *hostPointer;
@property(nonatomic) uint32_t guestAddress;
@property(nonatomic, copy) NSString *hostType;
@property(nonatomic, copy) NSString *guestType;
@property(nonatomic) NSUInteger capacity;
@property(nonatomic) BOOL cString;
@property(nonatomic) BOOL copyBack;
@end
@implementation BRPPCCallbackPointerScratch
@end

@interface BRPPCEncodedType : NSObject
@property(nonatomic) char code;
@property(nonatomic) NSUInteger count;
@property(nonatomic) NSUInteger guestSize;
@property(nonatomic) NSUInteger guestAlignment;
@property(nonatomic) NSUInteger hostSize;
@property(nonatomic) NSUInteger hostAlignment;
@property(nonatomic) BOOL aggregateSafe;
@property(nonatomic, strong) NSArray<BRPPCEncodedType *> *children;
@end
@implementation BRPPCEncodedType
@end

static const void *BRPPCGuestMethodsKey = &BRPPCGuestMethodsKey;
static const void *BRPPCGuestInstanceSizeKey = &BRPPCGuestInstanceSizeKey;
static const void *BRPPCGuestClassAddressKey = &BRPPCGuestClassAddressKey;
static const void *BRPPCGuestIvarsKey = &BRPPCGuestIvarsKey;
static const void *BRPPCGuestResolverKey = &BRPPCGuestResolverKey;
static const void *BRPPCGuestKVCValuesKey = &BRPPCGuestKVCValuesKey;

@interface BRPPCObjectiveCResolve ()
@property(nonatomic, weak) BRPPCResolveRegistry *registry;
@property(nonatomic, strong) NSMapTable<NSNumber *, id> *objects;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, id> *retainedObjects;
@property(nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *handles;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *poolHandles;
@property(nonatomic) uint32_t nextHandle;
@property(nonatomic, strong) BRPowerPC32 *cpu;
@property(nonatomic) BRPPCState activeState;
@property(nonatomic) BOOL hasActiveState;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *selectorAddresses;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, id> *guestClassesByAddress;
@property(nonatomic, strong) NSMutableArray<BRPPCGuestMethod *> *activeGuestMethods;
@property(nonatomic, strong) NSRecursiveLock *guestExecutionLock;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableData *> *guestVoidPointers;
@property(nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *hostVoidPointers;
@property(nonatomic) uint32_t nextSelectorAddress;
@property(nonatomic, strong) NSError *callbackError;
@property(nonatomic) BOOL launchCallbackDelivered;
@property(nonatomic, strong) NSBundle *applicationBundle;
- (void)invokeGuestFFIMethodUnlocked:(BRPPCGuestMethod *)method
                         returnValue:(void *)returnValue
                           arguments:(void **)arguments;
- (void)setGuestKVCValue:(id)value forKey:(NSString *)key object:(id)object;
- (id)guestKVCValueForKey:(NSString *)key object:(id)object;
@end

static _Thread_local NSUInteger BRPPCNativeDrawRectSuperDepth;
static _Thread_local void *BRPPCNativeDrawRectSuperReceivers[64];

static void BRPPCGuestSetValueForUndefinedKey(id object, SEL selector, id value, NSString *key) {
    (void)selector;
    BRPPCObjectiveCResolve *resolver = objc_getAssociatedObject(object_getClass(object),
                                                                BRPPCGuestResolverKey);
    [resolver setGuestKVCValue:value forKey:key object:object];
}

static id BRPPCGuestValueForUndefinedKey(id object, SEL selector, NSString *key) {
    (void)selector;
    BRPPCObjectiveCResolve *resolver = objc_getAssociatedObject(object_getClass(object),
                                                                BRPPCGuestResolverKey);
    return [resolver guestKVCValueForKey:key object:object];
}

@implementation BRPPCObjectiveCResolve

- (instancetype)init { return [self initWithApplicationBundleURL:nil]; }
- (instancetype)initWithApplicationBundleURL:(NSURL *)bundleURL {
    if ((self = [super init]))
        _applicationBundle = bundleURL ? [NSBundle bundleWithURL:bundleURL] : nil;
    return self;
}

- (NSArray *)hostObjectsSnapshot {
    return _retainedObjects.allValues ?: @[];
}

static const char *SkipTypeQualifiers(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static char ABITypeCategory(const char *type) {
    type = SkipTypeQualifiers(type);
    if (strchr("cCsSiIlLqQf dB", *type)) return 'n';
    if (*type == '@' || *type == '#') return 'o';
    if (*type == '^' || *type == '*' || *type == '?') return 'p';
    if (*type == '{' || *type == '[') return 'a';
    return *type;
}

static NSUInteger AlignOffset(NSUInteger offset, NSUInteger alignment) {
    return alignment > 1 ? (offset + alignment - 1) & ~(alignment - 1) : offset;
}

static void ScalarLayouts(char code, NSUInteger *guestSize, NSUInteger *guestAlignment,
                          NSUInteger *hostSize, NSUInteger *hostAlignment, BOOL *safe) {
    *safe = YES;
    switch (code) {
        case 'v': *guestSize = *hostSize = 0; *guestAlignment = *hostAlignment = 1; break;
        case 'c': case 'C': case 'B':
            *guestSize = *hostSize = 1; *guestAlignment = *hostAlignment = 1; break;
        case 's': case 'S':
            *guestSize = *hostSize = 2; *guestAlignment = *hostAlignment = 2; break;
        case 'i': case 'I': case 'f':
            *guestSize = *hostSize = 4; *guestAlignment = *hostAlignment = 4; break;
        case 'l': case 'L':
            *guestSize = 4; *guestAlignment = 4;
            *hostSize = sizeof(long); *hostAlignment = _Alignof(long); break;
        case 'q': case 'Q': case 'd':
            *guestSize = *hostSize = 8; *guestAlignment = *hostAlignment = 8; break;
        case '@': case '#':
            *guestSize = 4; *guestAlignment = 4;
            *hostSize = sizeof(void *); *hostAlignment = _Alignof(void *); break;
        case ':': case '*': case '^': case '?':
            *guestSize = 4; *guestAlignment = 4;
            *hostSize = sizeof(void *); *hostAlignment = _Alignof(void *); *safe = NO; break;
        default:
            *guestSize = *hostSize = 0; *guestAlignment = *hostAlignment = 1; *safe = NO; break;
    }
}

static void FinishAggregateLayout(BRPPCEncodedType *node) {
    if (node.code == '[') {
        BRPPCEncodedType *child = node.children.firstObject;
        node.guestAlignment = child.guestAlignment; node.hostAlignment = child.hostAlignment;
        node.guestSize = child.guestSize * node.count; node.hostSize = child.hostSize * node.count;
        node.aggregateSafe = child.aggregateSafe;
        return;
    }
    BOOL isUnion = node.code == '(';
    NSUInteger guestOffset = 0, hostOffset = 0, guestAlignment = 1, hostAlignment = 1;
    BOOL safe = !isUnion && node.children.count > 0;
    for (BRPPCEncodedType *child in node.children) {
        guestAlignment = MAX(guestAlignment, child.guestAlignment);
        hostAlignment = MAX(hostAlignment, child.hostAlignment);
        if (isUnion) {
            guestOffset = MAX(guestOffset, child.guestSize);
            hostOffset = MAX(hostOffset, child.hostSize);
        } else {
            guestOffset = AlignOffset(guestOffset, child.guestAlignment) + child.guestSize;
            hostOffset = AlignOffset(hostOffset, child.hostAlignment) + child.hostSize;
        }
        safe = safe && child.aggregateSafe;
    }
    node.guestAlignment = guestAlignment; node.hostAlignment = hostAlignment;
    node.guestSize = AlignOffset(guestOffset, guestAlignment);
    node.hostSize = AlignOffset(hostOffset, hostAlignment);
    node.aggregateSafe = safe;
}

static void FinishScalarLayout(BRPPCEncodedType *node) {
    NSUInteger guestSize = 0, guestAlignment = 1, hostSize = 0, hostAlignment = 1;
    BOOL safe = NO;
    ScalarLayouts(node.code, &guestSize, &guestAlignment, &hostSize, &hostAlignment, &safe);
    node.guestSize = guestSize; node.guestAlignment = guestAlignment;
    node.hostSize = hostSize; node.hostAlignment = hostAlignment; node.aggregateSafe = safe;
}

static BRPPCEncodedType *ParseEncodedType(const char **cursor) {
    const char *p = SkipTypeQualifiers(*cursor);
    while (isdigit(*p)) p++;
    if (!*p) return nil;
    BRPPCEncodedType *node = [BRPPCEncodedType new];
    node.code = *p++;
    if (node.code == '@' && *p == '?') { p++; FinishScalarLayout(node); node.aggregateSafe = NO; }
    else if (node.code == '^') {
        BRPPCEncodedType *child = ParseEncodedType(&p);
        node.children = child ? @[child] : @[];
        FinishScalarLayout(node);
    } else if (node.code == '[') {
        NSUInteger count = 0;
        while (isdigit(*p)) count = count * 10 + (NSUInteger)(*p++ - '0');
        BRPPCEncodedType *child = ParseEncodedType(&p);
        if (*p == ']') p++;
        node.count = count; node.children = child ? @[child] : @[];
        FinishAggregateLayout(node);
    } else if (node.code == '{' || node.code == '(') {
        char closer = node.code == '{' ? '}' : ')';
        while (*p && *p != '=' && *p != closer) p++;
        NSMutableArray *children = [NSMutableArray array];
        if (*p == '=') {
            p++;
            while (*p && *p != closer) {
                if (*p == '"') { p++; while (*p && *p != '"') p++; if (*p) p++; continue; }
                const char *before = p;
                BRPPCEncodedType *child = ParseEncodedType(&p);
                if (!child || p == before) break;
                [children addObject:child];
            }
        }
        if (*p == closer) p++;
        node.children = children;
        FinishAggregateLayout(node);
    } else {
        FinishScalarLayout(node);
    }
    while (isdigit(*p)) p++;
    *cursor = p;
    return node;
}

static BOOL StructureUsesFloat(const char *type) {
    return strchr(type, 'f') != NULL && strchr(type, 'd') == NULL;
}

static BOOL SelectorReturnsBoolean(SEL selector) {
    NSString *name = NSStringFromSelector(selector);
    static NSString * const prefixes[] = {@"is", @"has", @"can", @"should", @"will",
        @"does", @"did", @"got", @"accepts", @"allows", @"wants", @"needs",
        @"responds", @"contains"};
    for (NSUInteger index = 0; index < sizeof(prefixes) / sizeof(prefixes[0]); index++) {
        NSString *prefix = prefixes[index];
        if ([name hasPrefix:prefix] && name.length > prefix.length) return YES;
    }
    return NO;
}

static void *FFIAllocate(BRPPCGuestMethod *method, size_t size) {
    void *pointer = calloc(1, size);
    if (pointer) [method.ffiAllocations addObject:[NSValue valueWithPointer:pointer]];
    return pointer;
}

static ffi_type *FFITypeForCursor(const char **cursor, BRPPCGuestMethod *method) {
    const char *p = SkipTypeQualifiers(*cursor);
    while (isdigit(*p)) p++;
    ffi_type *result = NULL;
    switch (*p) {
        case 'v': result = &ffi_type_void; p++; break;
        case 'c': result = &ffi_type_sint8; p++; break;
        case 'C': case 'B': result = &ffi_type_uint8; p++; break;
        case 's': result = &ffi_type_sint16; p++; break;
        case 'S': result = &ffi_type_uint16; p++; break;
        case 'i': result = &ffi_type_sint32; p++; break;
        case 'I': result = &ffi_type_uint32; p++; break;
        case 'l': result = sizeof(long) == 8 ? &ffi_type_sint64 : &ffi_type_sint32; p++; break;
        case 'L': result = sizeof(unsigned long) == 8 ? &ffi_type_uint64 : &ffi_type_uint32; p++; break;
        case 'q': result = &ffi_type_sint64; p++; break;
        case 'Q': result = &ffi_type_uint64; p++; break;
        case 'f': result = &ffi_type_float; p++; break;
        case 'd': result = &ffi_type_double; p++; break;
        case '@': case '#': case ':': case '*': case '^': case '?':
            result = &ffi_type_pointer;
            if (*p == '^') { p++; if (*p) { const char *ignored = p; (void)FFITypeForCursor(&ignored, method); p = ignored; } }
            else p++;
            break;
        case '{': {
            p++;
            while (*p && *p != '=' && *p != '}') p++;
            NSMutableArray<NSValue *> *elements = [NSMutableArray array];
            if (*p == '=') {
                p++;
                while (*p && *p != '}') {
                    if (*p == '"') { p++; while (*p && *p != '"') p++; if (*p) p++; continue; }
                    ffi_type *element = FFITypeForCursor(&p, method);
                    if (!element) return NULL;
                    [elements addObject:[NSValue valueWithPointer:element]];
                }
            }
            if (*p == '}') p++;
            ffi_type *structure = FFIAllocate(method, sizeof(ffi_type));
            ffi_type **fields = FFIAllocate(method, sizeof(ffi_type *) * (elements.count + 1));
            if (!structure || !fields) return NULL;
            structure->type = FFI_TYPE_STRUCT;
            structure->elements = fields;
            for (NSUInteger i = 0; i < elements.count; i++) fields[i] = elements[i].pointerValue;
            result = structure;
            break;
        }
        case '[': {
            p++;
            NSUInteger count = 0;
            while (isdigit(*p)) count = count * 10 + (*p++ - '0');
            ffi_type *element = FFITypeForCursor(&p, method);
            if (*p == ']') p++;
            ffi_type *structure = FFIAllocate(method, sizeof(ffi_type));
            ffi_type **fields = FFIAllocate(method, sizeof(ffi_type *) * (count + 1));
            if (!structure || !fields) return NULL;
            structure->type = FFI_TYPE_STRUCT;
            structure->elements = fields;
            for (NSUInteger i = 0; i < count; i++) fields[i] = element;
            result = structure;
            break;
        }
        default: return NULL;
    }
    while (isdigit(*p)) p++;
    *cursor = p;
    return result;
}

static void BRPPCGuestFFICall(ffi_cif *cif, void *returnValue, void **arguments,
                              void *userData) {
    (void)cif;
    BRPPCGuestMethod *method = (__bridge BRPPCGuestMethod *)userData;
    [method.resolver invokeGuestFFIMethod:method returnValue:returnValue arguments:arguments];
}

static BOOL ReadGuestArgumentWord(BRPPCAddressSpace *memory, BRPPCState *state,
                                  NSUInteger *index, uint32_t *value) {
    NSUInteger position = (*index)++;
    if (position <= 10) {
        *value = state->gpr[position];
        return YES;
    }
    return [memory readUInt32:value
                     address:state->gpr[1] + 24 + (uint32_t)(position - 3) * 4];
}

static FILE *BRPPCObjectiveCTraceStream(void) {
    static FILE *stream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *path = getenv("BISMUTH_OBJC_TRACE_FILE");
        stream = path && *path ? fopen(path, "a") : stderr;
        if (stream) setvbuf(stream, NULL, _IOLBF, 0);
    });
    return stream ?: stderr;
}

static void BRPPCActivateHostWindow(NSWindow *window) {
    if (!window) return;
    typedef struct { uint32_t high; uint32_t low; } BRProcessSerialNumber;
    typedef int32_t (*BRTransformProcessTypeFunction)(const BRProcessSerialNumber *, uint32_t);
    typedef int16_t (*BRSetFrontProcessFunction)(const BRProcessSerialNumber *);
    static BRTransformProcessTypeFunction transformProcess;
    static BRSetFrontProcessFunction setFrontProcess;
    static dispatch_once_t activationFunctionsToken;
    dispatch_once(&activationFunctionsToken, ^{
        transformProcess = (BRTransformProcessTypeFunction)dlsym(RTLD_DEFAULT,
                                                                  "TransformProcessType");
        setFrontProcess = (BRSetFrontProcessFunction)dlsym(RTLD_DEFAULT, "SetFrontProcess");
    });
    BRProcessSerialNumber currentProcess = {0, 2};
    if (transformProcess) transformProcess(&currentProcess, 1);
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSApplicationActivationOptions options = NSApplicationActivateAllWindows;
    if (@available(macOS 14.0, *)) {
        [NSRunningApplication.currentApplication activateWithOptions:options];
        [NSApp activate];
    } else {
        [NSRunningApplication.currentApplication activateWithOptions:options | (1u << 1)];
        [NSApp activateIgnoringOtherApps:YES];
    }
    if (setFrontProcess) setFrontProcess(&currentProcess);
    [window makeMainWindow];
    [window makeKeyAndOrderFront:nil];
    [window orderFrontRegardless];
}

- (uint32_t)handleForObject:(__unsafe_unretained id)object {
    if (!object) return 0;
    NSValue *identity = [NSValue valueWithPointer:(__bridge void *)object];
    NSNumber *existing = _handles[identity];
    if (existing) return existing.unsignedIntValue;
    uint32_t handle = _nextHandle;
    __unsafe_unretained Class cls = object_getClass(object);
    __unsafe_unretained Class guestClass = cls;
    NSNumber *guestSize = nil, *guestClassAddress = nil;
    while (guestClass && !guestSize) {
        guestSize = objc_getAssociatedObject(guestClass, BRPPCGuestInstanceSizeKey);
        guestClassAddress = objc_getAssociatedObject(guestClass, BRPPCGuestClassAddressKey);
        if (!guestSize) guestClass = class_getSuperclass(guestClass);
    }
    uint32_t size = guestSize ? MAX(guestSize.unsignedIntValue, 8u) : 16u;
    size = (size + 15) & ~15u;
    if ((uint64_t)handle + size > BRPPCGuestObjectHandleBase + BRPPCGuestObjectStorageSize) return 0;
    _nextHandle += size;
    NSMutableData *zeros = [NSMutableData dataWithLength:size];
    if (![_registry.memory writeBytes:zeros.bytes address:handle length:size]) return 0;
    if (guestClassAddress)
        [_registry.memory writeUInt32:guestClassAddress.unsignedIntValue address:handle];
    NSNumber *key = @(handle);
    [_objects setObject:object forKey:key];
    Class poolClass = NSClassFromString(@"NSAutoreleasePool");
    if (!poolClass || ![object isKindOfClass:poolClass]) _retainedObjects[key] = object;
    _handles[identity] = key;
    return handle;
}

- (void *)hostPointerForGuestOpaqueAddress:(uint32_t)address {
    if (!address) return NULL;
    NSNumber *key = @(address);
    NSMutableData *storage = _guestVoidPointers[key];
    if (!storage) {
        storage = [NSMutableData dataWithLength:16];
        _guestVoidPointers[key] = storage;
        _hostVoidPointers[[NSValue valueWithPointer:storage.mutableBytes]] = key;
    }
    return storage.mutableBytes;
}

- (uint32_t)guestAddressForHostOpaquePointer:(void *)pointer {
    return pointer ? _hostVoidPointers[[NSValue valueWithPointer:pointer]].unsignedIntValue : 0;
}

- (void)attachCPU:(BRPowerPC32 *)cpu {
    self.cpu = cpu;
    [_registry attachCPU:cpu];
}

- (BOOL)performHostCallbackScopeWithState:(BRPPCState *)state
                                    block:(BOOL (^)(NSError **error))block
                                    error:(NSError **)error {
    BRPPCState previousActiveState = _activeState;
    BOOL previouslyActive = _hasActiveState;
    NSError *previousCallbackError = _callbackError;
    _activeState = *state;
    _hasActiveState = YES;
    _callbackError = nil;
    BOOL succeeded = block ? block(error) : YES;
    NSError *callbackError = _callbackError;
    _activeState = previousActiveState;
    _hasActiveState = previouslyActive;
    _callbackError = previousCallbackError;
    if (!succeeded) return NO;
    if (callbackError) {
        if (error) *error = callbackError;
        return NO;
    }
    return YES;
}

- (NSArray<NSString *> *)argumentTypesInEncoding:(NSString *)encoding {
    NSMutableArray *types = [NSMutableArray array];
    const char *p = encoding.UTF8String;
    while (*p) {
        p = SkipTypeQualifiers(p);
        while (isdigit(*p)) p++;
        if (!*p) break;
        const char *start = p;
        BRPPCEncodedType *parsed = ParseEncodedType(&p);
        if (!parsed || p == start) break;
        [types addObject:[[NSString alloc] initWithBytes:start length:p - start
                                                encoding:NSASCIIStringEncoding]];
        while (isdigit(*p)) p++;
    }
    return types;
}

static uint64_t ReadBigEndianInteger(const uint8_t *bytes, NSUInteger size) {
    uint64_t value = 0;
    for (NSUInteger i = 0; i < size; i++) value = value << 8 | bytes[i];
    return value;
}

static void WriteBigEndianInteger(uint8_t *bytes, NSUInteger size, uint64_t value) {
    for (NSUInteger i = 0; i < size; i++) bytes[size - i - 1] = (uint8_t)(value >> (i * 8));
}

- (BOOL)convertAggregateNode:(BRPPCEncodedType *)node
                       guest:(uint8_t *)guest guestOffset:(NSUInteger)guestOffset
                        host:(uint8_t *)host hostOffset:(NSUInteger)hostOffset
                      toHost:(BOOL)toHost {
    if (node.code == '{' || node.code == '[') {
        NSUInteger guestCursor = guestOffset, hostCursor = hostOffset;
        NSUInteger repetitions = node.code == '[' ? node.count : 1;
        NSArray<BRPPCEncodedType *> *children = node.children;
        for (NSUInteger repetition = 0; repetition < repetitions; repetition++) {
            for (BRPPCEncodedType *child in children) {
                guestCursor = AlignOffset(guestCursor, child.guestAlignment);
                hostCursor = AlignOffset(hostCursor, child.hostAlignment);
                if (![self convertAggregateNode:child guest:guest guestOffset:guestCursor
                                            host:host hostOffset:hostCursor toHost:toHost]) return NO;
                guestCursor += child.guestSize; hostCursor += child.hostSize;
            }
        }
        return YES;
    }
    if (!node.aggregateSafe) return NO;
    uint8_t *guestValue = guest + guestOffset;
    uint8_t *hostValue = host + hostOffset;
    if (toHost) {
        uint64_t bits = ReadBigEndianInteger(guestValue, node.guestSize);
        switch (node.code) {
            case 'c': { int8_t value = (int8_t)bits; memcpy(hostValue, &value, 1); return YES; }
            case 'C': case 'B': { uint8_t value = (uint8_t)bits; memcpy(hostValue, &value, 1); return YES; }
            case 's': { int16_t value = (int16_t)bits; memcpy(hostValue, &value, 2); return YES; }
            case 'S': { uint16_t value = (uint16_t)bits; memcpy(hostValue, &value, 2); return YES; }
            case 'i': { int32_t value = (int32_t)bits; memcpy(hostValue, &value, 4); return YES; }
            case 'I': { uint32_t value = (uint32_t)bits; memcpy(hostValue, &value, 4); return YES; }
            case 'l': { long value = (long)(int32_t)bits; memcpy(hostValue, &value, sizeof(value)); return YES; }
            case 'L': { unsigned long value = (unsigned long)(uint32_t)bits; memcpy(hostValue, &value, sizeof(value)); return YES; }
            case 'q': { int64_t value = (int64_t)bits; memcpy(hostValue, &value, 8); return YES; }
            case 'Q': { uint64_t value = bits; memcpy(hostValue, &value, 8); return YES; }
            case 'f': { uint32_t value = (uint32_t)bits; memcpy(hostValue, &value, 4); return YES; }
            case 'd': { memcpy(hostValue, &bits, 8); return YES; }
            case '@': case '#': {
                id object = [self objectAtGuestAddress:(uint32_t)bits allowClassName:node.code == '#'];
                __unsafe_unretained id value = object; memcpy(hostValue, &value, sizeof(value)); return YES;
            }
            case ':': {
                NSString *name = [_registry.memory readCStringAtAddress:(uint32_t)bits maximumLength:1024];
                SEL value = name.length ? NSSelectorFromString(name) : NULL;
                memcpy(hostValue, &value, sizeof(value)); return !bits || value != NULL;
            }
            default: return NO;
        }
    }
    uint64_t bits = 0;
    switch (node.code) {
        case 'c': { int8_t value; memcpy(&value, hostValue, 1); bits = (uint8_t)value; break; }
        case 'C': case 'B': { uint8_t value; memcpy(&value, hostValue, 1); bits = value; break; }
        case 's': { int16_t value; memcpy(&value, hostValue, 2); bits = (uint16_t)value; break; }
        case 'S': { uint16_t value; memcpy(&value, hostValue, 2); bits = value; break; }
        case 'i': { int32_t value; memcpy(&value, hostValue, 4); bits = (uint32_t)value; break; }
        case 'I': case 'f': { uint32_t value; memcpy(&value, hostValue, 4); bits = value; break; }
        case 'l': { long value; memcpy(&value, hostValue, sizeof(value)); bits = (uint32_t)value; break; }
        case 'L': { unsigned long value; memcpy(&value, hostValue, sizeof(value)); bits = (uint32_t)value; break; }
        case 'q': case 'Q': case 'd': { memcpy(&bits, hostValue, 8); break; }
        case '@': case '#': {
            __unsafe_unretained id value = nil; memcpy(&value, hostValue, sizeof(value));
            bits = [self handleForObject:value]; break;
        }
        case ':': {
            SEL value = NULL; memcpy(&value, hostValue, sizeof(value));
            NSString *name = value ? NSStringFromSelector(value) : nil;
            bits = name ? [self handleForObject:name] : 0; break;
        }
        default: return NO;
    }
    WriteBigEndianInteger(guestValue, node.guestSize, bits);
    return YES;
}

- (BRPPCEncodedType *)safeAggregateForType:(const char *)rawType {
    const char *cursor = SkipTypeQualifiers(rawType);
    BRPPCEncodedType *node = ParseEncodedType(&cursor);
    return node && (node.code == '{' || node.code == '[') && node.aggregateSafe &&
        node.guestSize && node.hostSize ? node : nil;
}

- (NSMutableData *)hostAggregateFromGuestData:(NSData *)guestData
                                          type:(const char *)type {
    BRPPCEncodedType *node = [self safeAggregateForType:type];
    if (!node || guestData.length < node.guestSize) return nil;
    NSMutableData *hostData = [NSMutableData dataWithLength:node.hostSize];
    if (![self convertAggregateNode:node guest:(uint8_t *)guestData.bytes guestOffset:0
                               host:hostData.mutableBytes hostOffset:0 toHost:YES]) return nil;
    return hostData;
}

- (NSMutableData *)guestAggregateFromHostData:(NSData *)hostData
                                          type:(const char *)type {
    BRPPCEncodedType *node = [self safeAggregateForType:type];
    if (!node || hostData.length < node.hostSize) return nil;
    NSMutableData *guestData = [NSMutableData dataWithLength:node.guestSize];
    if (![self convertAggregateNode:node guest:guestData.mutableBytes guestOffset:0
                               host:(uint8_t *)hostData.bytes hostOffset:0 toHost:NO]) return nil;
    return guestData;
}

- (NSMutableData *)readAggregateArgumentType:(const char *)type state:(BRPPCState *)state
                                          gpr:(NSUInteger *)gpr {
    BRPPCEncodedType *node = [self safeAggregateForType:type];
    if (!node) return nil;
    NSMutableData *guestData = [NSMutableData dataWithLength:node.guestSize];
    uint8_t *bytes = guestData.mutableBytes;
    for (NSUInteger offset = 0; offset < node.guestSize; offset += 4) {
        uint32_t word = 0;
        if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return nil;
        NSUInteger count = MIN((NSUInteger)4, node.guestSize - offset);
        for (NSUInteger i = 0; i < count; i++) bytes[offset + i] = (uint8_t)(word >> (24 - i * 8));
    }
    return [self hostAggregateFromGuestData:guestData type:type];
}

- (BOOL)writeCallbackWord:(uint32_t)value state:(BRPPCState *)state index:(NSUInteger *)index {
    NSUInteger position = (*index)++;
    if (position <= 10) { state->gpr[position] = value; return YES; }
    return [_registry.memory writeUInt32:value
                                  address:state->gpr[1] + 24 + (uint32_t)(position - 3) * 4];
}

- (uint64_t)unsignedHostValue:(void *)value type:(const char *)rawType {
    const char *type = SkipTypeQualifiers(rawType);
    switch (*type) {
        case 'c': return (uint64_t)*(int8_t *)value;
        case 'C': case 'B': return *(uint8_t *)value;
        case 's': return (uint64_t)*(int16_t *)value;
        case 'S': return *(uint16_t *)value;
        case 'i': return (uint64_t)*(int32_t *)value;
        case 'I': return *(uint32_t *)value;
        case 'l': return (uint64_t)*(long *)value;
        case 'L': return *(unsigned long *)value;
        case 'q': return (uint64_t)*(int64_t *)value;
        case 'Q': return *(uint64_t *)value;
        default: return 0;
    }
}

- (double)floatingHostValue:(void *)value type:(const char *)rawType {
    const char *type = SkipTypeQualifiers(rawType);
    return *type == 'f' ? *(float *)value : *type == 'd' ? *(double *)value
        : (double)[self unsignedHostValue:value type:type];
}

static BOOL IsNumericType(char type) {
    return strchr("cCsSiIlLqQBfd", type) != NULL;
}

static NSUInteger GuestValueSize(const char *rawType) {
    const char *type = SkipTypeQualifiers(rawType);
    switch (*type) {
        case 'c': case 'C': case 'B': return 1;
        case 's': case 'S': return 2;
        case 'i': case 'I': case 'l': case 'L': case 'f':
        case '@': case '#': case ':': case '*': case '^': return 4;
        case 'q': case 'Q': case 'd': return 8;
        default: {
            NSUInteger size = 0;
            NSGetSizeAndAlignment(type, &size, NULL);
            return size;
        }
    }
}

- (BOOL)writeCallbackNumeric:(void *)hostValue hostType:(const char *)hostRawType
                    guestType:(const char *)guestRawType address:(uint32_t)address {
    const char *hostType = SkipTypeQualifiers(hostRawType);
    const char *guestType = SkipTypeQualifiers(guestRawType);
    if (*guestType == 'f') {
        float number = (float)[self floatingHostValue:hostValue type:hostType];
        uint32_t bits = 0; memcpy(&bits, &number, 4);
        return [_registry.memory writeUInt32:bits address:address];
    }
    if (*guestType == 'd') {
        double number = [self floatingHostValue:hostValue type:hostType];
        uint64_t bits = 0; memcpy(&bits, &number, 8);
        return [_registry.memory writeUInt32:(uint32_t)(bits >> 32) address:address] &&
               [_registry.memory writeUInt32:(uint32_t)bits address:address + 4];
    }
    uint64_t value = [self unsignedHostValue:hostValue type:hostType];
    switch (*guestType) {
        case 'c': case 'C': case 'B': {
            uint8_t byte = (uint8_t)value;
            return [_registry.memory writeBytes:&byte address:address length:1];
        }
        case 's': case 'S': {
            uint8_t bytes[] = {(uint8_t)(value >> 8), (uint8_t)value};
            return [_registry.memory writeBytes:bytes address:address length:2];
        }
        case 'i': case 'I': case 'l': case 'L':
            return [_registry.memory writeUInt32:(uint32_t)value address:address];
        case 'q': case 'Q':
            return [_registry.memory writeUInt32:(uint32_t)(value >> 32) address:address] &&
                   [_registry.memory writeUInt32:(uint32_t)value address:address + 4];
        default: return NO;
    }
}

- (BOOL)copyCallbackNumericAtAddress:(uint32_t)address guestType:(const char *)guestRawType
                             toHost:(void *)hostValue hostType:(const char *)hostRawType {
    const char *guestType = SkipTypeQualifiers(guestRawType);
    const char *hostType = SkipTypeQualifiers(hostRawType);
    uint64_t integer = 0;
    double floating = 0;
    BOOL sourceFloating = *guestType == 'f' || *guestType == 'd';
    uint32_t first = 0, second = 0;
    if (*guestType == 'f') {
        if (![_registry.memory readUInt32:&first address:address]) return NO;
        float number; memcpy(&number, &first, 4); floating = number;
    } else if (*guestType == 'd') {
        if (![_registry.memory readUInt32:&first address:address] ||
            ![_registry.memory readUInt32:&second address:address + 4]) return NO;
        uint64_t bits = (uint64_t)first << 32 | second;
        memcpy(&floating, &bits, 8);
    } else if (*guestType == 'c' || *guestType == 'C' || *guestType == 'B') {
        uint8_t byte = 0;
        if (![_registry.memory readBytes:&byte address:address length:1]) return NO;
        integer = *guestType == 'c' ? (uint64_t)(int64_t)(int8_t)byte : byte;
    } else if (*guestType == 's' || *guestType == 'S') {
        uint8_t bytes[2];
        if (![_registry.memory readBytes:bytes address:address length:2]) return NO;
        uint16_t value = (uint16_t)bytes[0] << 8 | bytes[1];
        integer = *guestType == 's' ? (uint64_t)(int64_t)(int16_t)value : value;
    } else if (strchr("iIlL", *guestType)) {
        if (![_registry.memory readUInt32:&first address:address]) return NO;
        integer = strchr("il", *guestType) ? (uint64_t)(int64_t)(int32_t)first : first;
    } else if (*guestType == 'q' || *guestType == 'Q') {
        if (![_registry.memory readUInt32:&first address:address] ||
            ![_registry.memory readUInt32:&second address:address + 4]) return NO;
        integer = (uint64_t)first << 32 | second;
    } else return NO;
    if (*hostType == 'f') { float value = sourceFloating ? (float)floating : (float)integer; memcpy(hostValue, &value, 4); return YES; }
    if (*hostType == 'd') { double value = sourceFloating ? floating : (double)integer; memcpy(hostValue, &value, 8); return YES; }
    uint64_t value = sourceFloating ? (uint64_t)floating : integer;
    switch (*hostType) {
        case 'c': { int8_t v = (int8_t)value; memcpy(hostValue, &v, 1); return YES; }
        case 'C': case 'B': { uint8_t v = (uint8_t)value; memcpy(hostValue, &v, 1); return YES; }
        case 's': { int16_t v = (int16_t)value; memcpy(hostValue, &v, 2); return YES; }
        case 'S': { uint16_t v = (uint16_t)value; memcpy(hostValue, &v, 2); return YES; }
        case 'i': { int32_t v = (int32_t)value; memcpy(hostValue, &v, 4); return YES; }
        case 'I': { uint32_t v = (uint32_t)value; memcpy(hostValue, &v, 4); return YES; }
        case 'l': { long v = (long)(int64_t)value; memcpy(hostValue, &v, sizeof(v)); return YES; }
        case 'L': { unsigned long v = (unsigned long)value; memcpy(hostValue, &v, sizeof(v)); return YES; }
        case 'q': { int64_t v = (int64_t)value; memcpy(hostValue, &v, 8); return YES; }
        case 'Q': { uint64_t v = value; memcpy(hostValue, &v, 8); return YES; }
        default: return NO;
    }
}

- (BOOL)marshalHostArgument:(void *)argument hostType:(const char *)hostRawType
                  guestType:(const char *)guestRawType state:(BRPPCState *)state
                        gpr:(NSUInteger *)gpr fpr:(NSUInteger *)fpr
              scratchCursor:(uint32_t *)scratchCursor scratchLimit:(uint32_t)scratchLimit
                    scratch:(NSMutableArray<BRPPCCallbackPointerScratch *> *)scratch {
    const char *hostType = SkipTypeQualifiers(hostRawType);
    const char *guestType = SkipTypeQualifiers(guestRawType);
    uint64_t value = 0;
    switch (*guestType) {
        case '@': case '#': {
            __unsafe_unretained id object = *(__unsafe_unretained id *)argument;
            return [self writeCallbackWord:[self handleForObject:object] state:state index:gpr];
        }
        case ':': {
            SEL selector = *(SEL *)argument;
            NSString *name = selector ? NSStringFromSelector(selector) : nil;
            uint32_t address = name.length ? _selectorAddresses[name].unsignedIntValue : 0;
            if (name.length) {
                if (!address) {
                    NSData *bytes = [name dataUsingEncoding:NSUTF8StringEncoding];
                    uint32_t needed = (uint32_t)bytes.length + 1;
                    if ((uint64_t)_nextSelectorAddress + needed >
                        BRPPCGuestObjectiveCDataBase + BRPPCGuestObjectiveCDataSize) return NO;
                    address = _nextSelectorAddress;
                    uint8_t zero = 0;
                    if (![_registry.memory writeBytes:bytes.bytes address:address length:bytes.length] ||
                        ![_registry.memory writeBytes:&zero address:address + (uint32_t)bytes.length length:1]) return NO;
                    _selectorAddresses[name] = @(address);
                    _nextSelectorAddress = (address + needed + 3) & ~3u;
                }
            }
            return [self writeCallbackWord:address state:state index:gpr];
        }
        case '*': {
            char *pointer = *(char **)argument;
            if (!pointer) return [self writeCallbackWord:0 state:state index:gpr];
            size_t length = strnlen(pointer, BRPPCGuestCallbackSlotSize - 1);
            if (length >= BRPPCGuestCallbackSlotSize - 1) return NO;
            uint32_t needed = (uint32_t)length + 1;
            uint32_t address = (*scratchCursor + 3) & ~3u;
            if ((uint64_t)address + needed > scratchLimit ||
                ![_registry.memory writeBytes:pointer address:address length:needed]) return NO;
            BRPPCCallbackPointerScratch *record = [BRPPCCallbackPointerScratch new];
            record.hostPointer = pointer; record.guestAddress = address; record.capacity = needed;
            record.cString = YES; record.copyBack = strchr(guestRawType, 'r') == NULL;
            [scratch addObject:record]; *scratchCursor = address + needed;
            return [self writeCallbackWord:address state:state index:gpr];
        }
        case '^': {
            void *pointer = *(void **)argument;
            if (!pointer) return [self writeCallbackWord:0 state:state index:gpr];
            const char *hostPointee = SkipTypeQualifiers(hostType + 1);
            const char *guestPointee = SkipTypeQualifiers(guestType + 1);
            if (!*hostPointee || !*guestPointee) return NO;
            NSUInteger guestSize = GuestValueSize(guestPointee), hostSize = 0;
            NSGetSizeAndAlignment(hostPointee, &hostSize, NULL);
            if (*guestPointee == 'v') {
                uint32_t opaqueAddress = [self guestAddressForHostOpaquePointer:pointer];
                if (opaqueAddress)
                    return [self writeCallbackWord:opaqueAddress state:state index:gpr];
                return [self writeCallbackWord:
                    [self handleForObject:[NSValue valueWithPointer:pointer]] state:state index:gpr];
            }
            if (!guestSize || !hostSize ||
                guestSize > BRPPCGuestCallbackSlotSize || hostSize > BRPPCGuestCallbackSlotSize)
                return [self writeCallbackWord:
                    [self handleForObject:[NSValue valueWithPointer:pointer]] state:state index:gpr];
            uint32_t address = (*scratchCursor + 15) & ~15u;
            if ((uint64_t)address + guestSize > scratchLimit) return NO;
            BOOL wrote = NO;
            if (IsNumericType(*guestPointee) && IsNumericType(*hostPointee))
                wrote = [self writeCallbackNumeric:pointer hostType:hostPointee
                                          guestType:guestPointee address:address];
            else {
                NSData *data = [NSData dataWithBytes:pointer length:hostSize];
                wrote = [self writeHostData:data guestAddress:address type:hostPointee error:NULL];
            }
            if (!wrote) return NO;
            BRPPCCallbackPointerScratch *record = [BRPPCCallbackPointerScratch new];
            record.hostPointer = pointer; record.guestAddress = address;
            record.hostType = [NSString stringWithUTF8String:hostPointee];
            record.guestType = [NSString stringWithUTF8String:guestPointee];
            record.copyBack = strchr(guestRawType, 'r') == NULL;
            [scratch addObject:record]; *scratchCursor = address + (uint32_t)guestSize;
            return [self writeCallbackWord:address state:state index:gpr];
        }
        case 'c': case 'C': case 's': case 'S': case 'i': case 'I':
        case 'l': case 'L': case 'B':
            value = [self unsignedHostValue:argument type:hostType];
            return [self writeCallbackWord:(uint32_t)value state:state index:gpr];
        case 'q': case 'Q': {
            value = [self unsignedHostValue:argument type:hostType];
            if (((*gpr - 3) & 1) != 0) (*gpr)++;
            return [self writeCallbackWord:(uint32_t)(value >> 32) state:state index:gpr] &&
                   [self writeCallbackWord:(uint32_t)value state:state index:gpr];
        }
        case 'f': {
            float number = (float)[self floatingHostValue:argument type:hostType];
            state->fpr[(*fpr)++] = number;
            uint32_t bits = 0; memcpy(&bits, &number, sizeof(bits));
            return [self writeCallbackWord:bits state:state index:gpr];
        }
        case 'd': {
            double number = [self floatingHostValue:argument type:hostType];
            state->fpr[(*fpr)++] = number;
            uint64_t bits = 0; memcpy(&bits, &number, sizeof(bits));
            if (((*gpr - 3) & 1) != 0) (*gpr)++;
            return [self writeCallbackWord:(uint32_t)(bits >> 32) state:state index:gpr] &&
                   [self writeCallbackWord:(uint32_t)bits state:state index:gpr];
        }
        case '{':
        case '[': {
            if (strstr(guestType, "Rect")) {
                float components[4];
                if (!strstr(hostType, "Rect")) return NO;
                if (StructureUsesFloat(hostType)) memcpy(components, argument, sizeof(components));
                else {
                    CGRect rect; memcpy(&rect, argument, sizeof(rect));
                    components[0] = (float)rect.origin.x; components[1] = (float)rect.origin.y;
                    components[2] = (float)rect.size.width; components[3] = (float)rect.size.height;
                }
                for (NSUInteger i = 0; i < 4; i++) {
                    uint32_t bits = 0; memcpy(&bits, &components[i], sizeof(bits));
                    if (![self writeCallbackWord:bits state:state index:gpr]) return NO;
                }
                return YES;
            }
            if (strstr(guestType, "Point") || strstr(guestType, "Size")) {
                double first = 0, second = 0;
                if (StructureUsesFloat(hostType)) { float v[2]; memcpy(v, argument, sizeof(v)); first = v[0]; second = v[1]; }
                else if (strstr(hostType, "Point")) { CGPoint v; memcpy(&v, argument, sizeof(v)); first = v.x; second = v.y; }
                else if (strstr(hostType, "Size")) { CGSize v; memcpy(&v, argument, sizeof(v)); first = v.width; second = v.height; }
                else return NO;
                float components[] = {(float)first, (float)second};
                for (NSUInteger i = 0; i < 2; i++) {
                    uint32_t bits = 0; memcpy(&bits, &components[i], sizeof(bits));
                    if (![self writeCallbackWord:bits state:state index:gpr]) return NO;
                }
                return YES;
            }
            if (strstr(guestType, "Range") && strstr(hostType, "Range")) {
                NSRange range; memcpy(&range, argument, sizeof(range));
                return [self writeCallbackWord:(uint32_t)range.location state:state index:gpr] &&
                       [self writeCallbackWord:(uint32_t)range.length state:state index:gpr];
            }
            BRPPCEncodedType *node = [self safeAggregateForType:hostType];
            if (node) {
                NSData *hostData = [NSData dataWithBytes:argument length:node.hostSize];
                NSMutableData *guestData = [self guestAggregateFromHostData:hostData type:hostType];
                const uint8_t *bytes = guestData.bytes;
                if (!guestData) return NO;
                for (NSUInteger offset = 0; offset < guestData.length; offset += 4) {
                    NSUInteger count = MIN((NSUInteger)4, guestData.length - offset);
                    uint32_t word = 0;
                    for (NSUInteger i = 0; i < count; i++) word |= (uint32_t)bytes[offset + i] << (24 - i * 8);
                    if (![self writeCallbackWord:word state:state index:gpr]) return NO;
                }
                return YES;
            }
            return NO;
        }
        default: return NO;
    }
}

- (BRPPCState)executeGuestCallbackState:(BRPPCState)state {
    NSError *error = nil;
    if (![_registry executeGuestCallbackState:&state instructionLimit:10000000
                                         label:@"Objective-C" error:&error])
        self.callbackError = error;
    return state;
}

- (void)invokeGuestFFIMethod:(BRPPCGuestMethod *)method returnValue:(void *)returnValue
                    arguments:(void **)arguments {
    [_guestExecutionLock lock];
    @try {
        [self invokeGuestFFIMethodUnlocked:method returnValue:returnValue arguments:arguments];
    } @finally {
        [_guestExecutionLock unlock];
    }
}

- (void)invokeGuestFFIMethodUnlocked:(BRPPCGuestMethod *)method returnValue:(void *)returnValue
                            arguments:(void **)arguments {
    if (!method) return;
    if (!_cpu || !_hasActiveState) {
        if (method.fallbackImplementation)
            ffi_call(&method->_cif, FFI_FN(method.fallbackImplementation), returnValue, arguments);
        else if (returnValue && method->_cif.rtype->size)
            memset(returnValue, 0, method->_cif.rtype->size);
        return;
    }
    NSArray<NSString *> *guestTypes = [self argumentTypesInEncoding:method.types];
    NSArray<NSString *> *hostTypes = [self argumentTypesInEncoding:method.hostTypes];
    const char *deepTrace = getenv("BISMUTH_OBJC_DEEP_TRACE_DEPTH");
    NSUInteger deepTraceDepth = deepTrace ? strtoul(deepTrace, NULL, 10) : NSUIntegerMax;
    NSString *callbackSelectorName =
        [_registry.memory readCStringAtAddress:method.selectorAddress maximumLength:1024];
    const char *selectorTrace = getenv("BISMUTH_OBJC_TRACE_SELECTOR");
    BOOL selectorTraceMatches = selectorTrace &&
        [callbackSelectorName isEqualToString:@(selectorTrace)];
    if (getenv("BISMUTH_OBJC_TRACE") || selectorTraceMatches ||
        _registry.callbackDepth >= deepTraceDepth) {
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc guest ffi callback depth=%lu class=%s selector=%s\n",
                (unsigned long)_registry.callbackDepth,
                method.owningClass ? class_getName(method.owningClass) : "(null)",
                callbackSelectorName.UTF8String);
        if (selectorTraceMatches && method->_cif.nargs > 2 && hostTypes.count > 3 &&
            *SkipTypeQualifiers(hostTypes[3].UTF8String) == '@') {
            __unsafe_unretained id tracedArgument = *(__unsafe_unretained id *)arguments[2];
            fprintf(BRPPCObjectiveCTraceStream(), "objc traced object argument=%p class=%s\n",
                    tracedArgument,
                    tracedArgument ? class_getName(object_getClass(tracedArgument)) : "(null)");
        }
    }
    if (returnValue && method->_cif.rtype->size) memset(returnValue, 0, method->_cif.rtype->size);
    if (guestTypes.count < 3 || hostTypes.count < 3) return;
    __unsafe_unretained id receiver = *(__unsafe_unretained id *)arguments[0];
    SEL selector = *(SEL *)arguments[1];
    if (BRPPCNativeDrawRectSuperDepth && getenv("BISMUTH_OBJC_TRACE_DRAW_CALLBACKS"))
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc native draw callback class=%s selector=%s depth=%lu\n",
                method.owningClass ? class_getName(method.owningClass) : "(null)",
                callbackSelectorName.UTF8String,
                (unsigned long)BRPPCNativeDrawRectSuperDepth);
    if (BRPPCNativeDrawRectSuperDepth &&
        [callbackSelectorName isEqualToString:@"drawRect:"]) {
        void *receiverPointer = (__bridge void *)receiver;
        for (NSUInteger i = 0; i < BRPPCNativeDrawRectSuperDepth &&
             i < sizeof(BRPPCNativeDrawRectSuperReceivers) /
                 sizeof(BRPPCNativeDrawRectSuperReceivers[0]); i++)
            if (BRPPCNativeDrawRectSuperReceivers[i] == receiverPointer) return;
    }
    if (selector == @selector(applicationDidFinishLaunching:)) {
        if (_launchCallbackDelivered) return;
        _launchCallbackDelivered = YES;
    }
    BRPPCState state = _activeState;
    state.pc = method.implementationAddress;
    state.gpr[12] = method.implementationAddress;
    BOOL structureReturn = *SkipTypeQualifiers(guestTypes[0].UTF8String) == '{';
    NSUInteger callbackSlot = _registry.callbackDepth + 1;
    if (callbackSlot >= BRPPCGuestCallbackSlotCount) {
        self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:19
            userInfo:@{NSLocalizedDescriptionKey: @"Objective-C callback nesting exceeds scratch capacity."}];
        return;
    }
    uint32_t structureAddress = BRPPCGuestCallbackDataBase + (uint32_t)callbackSlot * BRPPCGuestCallbackSlotSize;
    state.gpr[1] = BRPPCGuestCallbackStackBase + (uint32_t)callbackSlot *
        BRPPCGuestCallbackSlotSize - BRPPCGuestStackFrameReserve;
    uint32_t scratchCursor = structureAddress + BRPPCGuestCallbackScratchOffset;
    uint32_t scratchLimit = structureAddress + BRPPCGuestCallbackSlotSize;
    NSMutableArray<BRPPCCallbackPointerScratch *> *pointerScratch = [NSMutableArray array];
    NSUInteger gpr = structureReturn ? 6 : 5, fpr = 1;
    if (structureReturn) {
        state.gpr[3] = structureAddress;
        state.gpr[4] = [self handleForObject:receiver];
        state.gpr[5] = method.selectorAddress;
    } else {
        state.gpr[3] = [self handleForObject:receiver];
        state.gpr[4] = method.selectorAddress;
    }
    NSUInteger argumentCount = MIN(guestTypes.count, hostTypes.count);
    for (NSUInteger i = 3; i < argumentCount; i++) {
        if (![self marshalHostArgument:arguments[i - 1] hostType:hostTypes[i].UTF8String
                              guestType:guestTypes[i].UTF8String state:&state gpr:&gpr fpr:&fpr
                            scratchCursor:&scratchCursor scratchLimit:scratchLimit
                                  scratch:pointerScratch]) {
            self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:17
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Cannot marshal callback argument %@ as %@.",
                                               hostTypes[i], guestTypes[i]]}];
            return;
        }
    }
    [_activeGuestMethods addObject:method];
    state = [self executeGuestCallbackState:state];
    [_activeGuestMethods removeLastObject];
    if (_callbackError) {
        if (getenv("BISMUTH_OBJC_TRACE"))
            fprintf(stderr, "objc guest callback error class=%s selector=%s error=%s\n",
                    receiver ? class_getName(object_getClass(receiver)) : "(null)",
                    sel_getName(selector), _callbackError.localizedDescription.UTF8String);
        return;
    }
    for (BRPPCCallbackPointerScratch *record in pointerScratch) {
        if (!record.copyBack) continue;
        BOOL copied = NO;
        if (record.cString) {
            NSMutableData *data = [NSMutableData dataWithLength:record.capacity];
            copied = [_registry.memory readBytes:data.mutableBytes address:record.guestAddress
                                          length:record.capacity];
            if (copied) memcpy(record.hostPointer, data.bytes, record.capacity);
        } else {
            const char *hostType = record.hostType.UTF8String;
            const char *guestType = record.guestType.UTF8String;
            if (IsNumericType(*SkipTypeQualifiers(hostType)) &&
                IsNumericType(*SkipTypeQualifiers(guestType)))
                copied = [self copyCallbackNumericAtAddress:record.guestAddress guestType:guestType
                                                     toHost:record.hostPointer hostType:hostType];
            else {
                id retainedObject = nil;
                NSMutableData *data = [self hostDataForGuestValueAtAddress:record.guestAddress
                                                                      type:hostType
                                                            retainedObject:&retainedObject error:NULL];
                if (data) { memcpy(record.hostPointer, data.bytes, data.length); copied = YES; }
            }
        }
        if (!copied) {
            self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:20
                userInfo:@{NSLocalizedDescriptionKey: @"Cannot copy Objective-C callback pointer result."}];
            return;
        }
    }
    const char *guestReturn = SkipTypeQualifiers(guestTypes[0].UTF8String);
    const char *hostReturn = SkipTypeQualifiers(hostTypes[0].UTF8String);
    if (selectorTraceMatches && [receiver isKindOfClass:[NSWindow class]]) {
        NSView *contentView = [(NSWindow *)receiver contentView];
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc traced window content=%p class=%s subviews=%lu\n", contentView,
                contentView ? class_getName(object_getClass(contentView)) : "(null)",
                (unsigned long)contentView.subviews.count);
    }
    if (getenv("BISMUTH_OBJC_TRACE") && [NSStringFromSelector(selector) hasPrefix:@"init"])
        fprintf(stderr, "objc init types guest=%s host=%s r3=0x%08x\n",
                guestReturn, hostReturn, state.gpr[3]);
    if (*guestReturn == 'v') return;
    if (!returnValue) {
        self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:18
            userInfo:@{NSLocalizedDescriptionKey: @"Native callback supplied no return storage."}];
        return;
    }
    if (*guestReturn == '@' || *guestReturn == '#') {
        id object = [self objectAtGuestAddress:state.gpr[3] allowClassName:*guestReturn == '#'];
        if (getenv("BISMUTH_OBJC_TRACE"))
            fprintf(stderr, "objc guest return selector=%s address=0x%08x object=%p\n",
                    sel_getName(selector), state.gpr[3], object);
        __unsafe_unretained id value = object; memcpy(returnValue, &value, sizeof(value)); return;
    }
    if (*guestReturn == '^' || *guestReturn == '?') {
        void *value = NULL;
        if (state.gpr[3]) {
            id opaque = [self objectAtGuestAddress:state.gpr[3] allowClassName:NO];
            if ([opaque isKindOfClass:[NSValue class]]) value = [(NSValue *)opaque pointerValue];
            else {
                self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:26
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Guest returned unbridged pointer 0x%08x.", state.gpr[3]]}];
                return;
            }
        }
        memcpy(returnValue, &value, sizeof(value));
        return;
    }
    if (*guestReturn == 'f') {
        float value = (float)state.fpr[1];
        if (*hostReturn == 'd') { double widened = value; memcpy(returnValue, &widened, sizeof(widened)); }
        else memcpy(returnValue, &value, sizeof(value));
        return;
    }
    if (*guestReturn == 'd') { double value = state.fpr[1]; memcpy(returnValue, &value, sizeof(value)); return; }
    if (*guestReturn == 'q' || *guestReturn == 'Q') {
        uint64_t value = (uint64_t)state.gpr[3] << 32 | state.gpr[4];
        memcpy(returnValue, &value, MIN(method->_cif.rtype->size, sizeof(value))); return;
    }
    if (*guestReturn == '{') {
        if (strstr(guestReturn, "Rect") && strstr(hostReturn, "Rect")) {
            float c[4]; uint32_t bits = 0;
            for (NSUInteger i = 0; i < 4; i++) { [_registry.memory readUInt32:&bits address:structureAddress + (uint32_t)i * 4]; memcpy(&c[i], &bits, 4); }
            if (StructureUsesFloat(hostReturn)) memcpy(returnValue, c, sizeof(c));
            else { CGRect value = CGRectMake(c[0], c[1], c[2], c[3]); memcpy(returnValue, &value, sizeof(value)); }
        } else if ((strstr(guestReturn, "Point") || strstr(guestReturn, "Size"))) {
            float c[2]; uint32_t bits = 0;
            for (NSUInteger i = 0; i < 2; i++) { [_registry.memory readUInt32:&bits address:structureAddress + (uint32_t)i * 4]; memcpy(&c[i], &bits, 4); }
            if (StructureUsesFloat(hostReturn)) memcpy(returnValue, c, sizeof(c));
            else if (strstr(hostReturn, "Point")) { CGPoint value = CGPointMake(c[0], c[1]); memcpy(returnValue, &value, sizeof(value)); }
            else { CGSize value = CGSizeMake(c[0], c[1]); memcpy(returnValue, &value, sizeof(value)); }
        } else if (strstr(guestReturn, "Range") && strstr(hostReturn, "Range")) {
            uint32_t location = 0, length = 0; [_registry.memory readUInt32:&location address:structureAddress]; [_registry.memory readUInt32:&length address:structureAddress + 4];
            NSRange value = NSMakeRange(location, length); memcpy(returnValue, &value, sizeof(value));
        } else {
            BRPPCEncodedType *node = [self safeAggregateForType:hostReturn];
            NSMutableData *guestData = node ? [NSMutableData dataWithLength:node.guestSize] : nil;
            if (!guestData || ![_registry.memory readBytes:guestData.mutableBytes
                                                  address:structureAddress length:guestData.length]) {
                self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:23
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Cannot marshal guest aggregate return %s.", guestReturn]}];
                return;
            }
            NSMutableData *hostData = [self hostAggregateFromGuestData:guestData type:hostReturn];
            if (!hostData || hostData.length > method->_cif.rtype->size) {
                self.callbackError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:23
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"Cannot marshal host aggregate return %s.", hostReturn]}];
                return;
            }
            memcpy(returnValue, hostData.bytes, hostData.length);
        }
        return;
    }
    uint64_t scalar = state.gpr[3];
    switch (*hostReturn) {
        case 'c': {
            int8_t v = SelectorReturnsBoolean(selector) ? (scalar != 0) : (int8_t)scalar;
            memcpy(returnValue, &v, 1); break;
        }
        case 'C': case 'B': {
            uint8_t v = *hostReturn == 'B' || SelectorReturnsBoolean(selector)
                ? (scalar != 0) : (uint8_t)scalar;
            memcpy(returnValue, &v, 1); break;
        }
        case 's': { int16_t v = (int16_t)scalar; memcpy(returnValue, &v, 2); break; }
        case 'S': { uint16_t v = (uint16_t)scalar; memcpy(returnValue, &v, 2); break; }
        case 'i': { int32_t v = (int32_t)scalar; memcpy(returnValue, &v, 4); break; }
        case 'I': { uint32_t v = (uint32_t)scalar; memcpy(returnValue, &v, 4); break; }
        case 'l': { long v = (int32_t)scalar; memcpy(returnValue, &v, sizeof(v)); break; }
        case 'L': { unsigned long v = (uint32_t)scalar; memcpy(returnValue, &v, sizeof(v)); break; }
        case 'q': { int64_t v = (int32_t)scalar; memcpy(returnValue, &v, 8); break; }
        case 'Q': { uint64_t v = (uint32_t)scalar; memcpy(returnValue, &v, 8); break; }
        default: break;
    }
}

- (NSString *)hostTypesForSelector:(SEL)selector superclass:(Class)superclass
                       classMethod:(BOOL)classMethod fallback:(NSString *)fallback {
    Method inherited = classMethod ? class_getClassMethod(superclass, selector)
                                   : class_getInstanceMethod(superclass, selector);
    if (inherited) return [NSString stringWithUTF8String:method_getTypeEncoding(inherited)];
    unsigned int count = 0;
    Protocol *__unsafe_unretained *protocols = objc_copyProtocolList(&count);
    NSString *result = nil;
    for (unsigned int i = 0; i < count && !result; i++) {
        for (NSUInteger required = 0; required < 2 && !result; required++) {
            struct objc_method_description description = protocol_getMethodDescription(
                protocols[i], selector, required == 0, !classMethod);
            if (description.name && description.types)
                result = [NSString stringWithUTF8String:description.types];
        }
    }
    free(protocols);
    if (result) {
        NSArray<NSString *> *host = [self argumentTypesInEncoding:result];
        NSArray<NSString *> *guest = [self argumentTypesInEncoding:fallback];



        if (!host.count || host.count != guest.count) result = nil;
        for (NSUInteger i = 0; result && i < host.count; i++)
            if (ABITypeCategory(host[i].UTF8String) !=
                ABITypeCategory(guest[i].UTF8String)) result = nil;
    }
    return result ?: fallback;
}

- (BOOL)prepareFFIMethod:(BRPPCGuestMethod *)method {
    method.ffiAllocations = [NSMutableArray array];
    NSArray<NSString *> *types = [self argumentTypesInEncoding:method.hostTypes];
    if (types.count < 3) {
        if (getenv("BISMUTH_OBJC_TRACE")) fprintf(stderr, "objc ffi parse failed encoding=%s\n", method.hostTypes.UTF8String);
        return NO;
    }
    const char *returnCursor = types[0].UTF8String;
    ffi_type *returnType = FFITypeForCursor(&returnCursor, method);
    if (!returnType) {
        if (getenv("BISMUTH_OBJC_TRACE")) fprintf(stderr, "objc ffi return failed encoding=%s\n", method.hostTypes.UTF8String);
        return NO;
    }
    method->_argumentTypes = calloc(types.count - 1, sizeof(ffi_type *));
    if (!method->_argumentTypes) return NO;
    for (NSUInteger i = 1; i < types.count; i++) {
        const char *cursor = types[i].UTF8String;
        method->_argumentTypes[i - 1] = FFITypeForCursor(&cursor, method);
        if (!method->_argumentTypes[i - 1]) {
            if (getenv("BISMUTH_OBJC_TRACE")) fprintf(stderr, "objc ffi argument failed encoding=%s index=%lu\n", method.hostTypes.UTF8String, (unsigned long)i);
            return NO;
        }
    }
    if (ffi_prep_cif(&method->_cif, FFI_DEFAULT_ABI, (unsigned int)types.count - 1,
                     returnType, method->_argumentTypes) != FFI_OK) {
        if (getenv("BISMUTH_OBJC_TRACE")) fprintf(stderr, "objc ffi prepare failed encoding=%s\n", method.hostTypes.UTF8String);
        return NO;
    }
    method->_closure = ffi_closure_alloc(sizeof(ffi_closure), &method->_closureCode);
    if (!method->_closure) return NO;
    return ffi_prep_closure_loc(method->_closure, &method->_cif, BRPPCGuestFFICall,
                                (__bridge void *)method, method->_closureCode) == FFI_OK;
}

- (BOOL)invokeInvocation:(NSInvocation *)invocation usingIMP:(IMP)implementation
                   error:(NSError **)error {
    NSMethodSignature *signature = invocation.methodSignature;
    NSMutableString *encoding = [NSMutableString stringWithUTF8String:signature.methodReturnType];
    for (NSUInteger i = 0; i < signature.numberOfArguments; i++)
        [encoding appendFormat:@"%s", [signature getArgumentTypeAtIndex:i]];
    BRPPCGuestMethod *adapter = [BRPPCGuestMethod new];
    adapter.hostTypes = encoding;
    if (![self prepareFFIMethod:adapter]) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:26
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot prepare Objective-C super-call ABI."}];
        return NO;
    }
    NSUInteger count = signature.numberOfArguments;
    void **arguments = calloc(count, sizeof(void *));
    NSMutableArray<NSMutableData *> *storage = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment([signature getArgumentTypeAtIndex:i], &size, NULL);
        NSMutableData *data = [NSMutableData dataWithLength:MAX(size, sizeof(void *))];
        [invocation getArgument:data.mutableBytes atIndex:i];
        [storage addObject:data];
        arguments[i] = data.mutableBytes;
    }
    NSMutableData *returnStorage = [NSMutableData dataWithLength:
        MAX((NSUInteger)adapter->_cif.rtype->size, (NSUInteger)1)];
    ffi_call(&adapter->_cif, FFI_FN(implementation), returnStorage.mutableBytes, arguments);
    free(arguments);
    if (signature.methodReturnLength)
        [invocation setReturnValue:returnStorage.mutableBytes];
    return YES;
}

- (BOOL)dispatchSuperMessage:(BRPPCState *)state structureReturn:(BOOL)structureReturn
                       error:(NSError **)error {
    uint32_t resultAddress = structureReturn ? state->gpr[3] : 0;
    uint32_t superAddress = state->gpr[structureReturn ? 4 : 3];
    uint32_t selectorAddress = state->gpr[structureReturn ? 5 : 4];
    uint32_t receiverAddress = 0, classAddress = 0;
    if (![_registry.memory readUInt32:&receiverAddress address:superAddress] ||
        ![_registry.memory readUInt32:&classAddress address:superAddress + 4]) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:27
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot read guest objc_super structure."}];
        return NO;
    }
    id receiver = [self objectAtGuestAddress:receiverAddress allowClassName:YES];
    NSString *selectorName = [_registry.memory readCStringAtAddress:selectorAddress maximumLength:1024];
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    BRPPCGuestMethod *activeMethod = _activeGuestMethods.lastObject;
    BOOL classMethod = activeMethod ? activeMethod.classMethod
                                    : (receiver && object_isClass(receiver));
    Class startClass = activeMethod ? class_getSuperclass(activeMethod.owningClass)
                                    : _guestClassesByAddress[@(classAddress)];
    if (!startClass && receiver)
        startClass = class_getSuperclass(classMethod ? (Class)receiver : object_getClass(receiver));
    if (!activeMethod) {
        NSDictionary *startClassGuestMethods = startClass
            ? objc_getAssociatedObject(startClass, BRPPCGuestMethodsKey) : nil;
        if (startClassGuestMethods[selectorName])
            startClass = class_getSuperclass(startClass);
    }
    Method method = NULL;
    if (receiver && selector && startClass)
        method = classMethod ? class_getClassMethod(startClass, selector)
                             : class_getInstanceMethod(startClass, selector);
    if (!method) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:28
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Cannot resolve Objective-C super message %@.",
                                           selectorName ?: @"(null)"]}];
        return NO;
    }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    NSUInteger gpr = structureReturn ? 6 : 5, fpr = 1;
    NSMutableArray *scratch = [NSMutableArray array];
    NSDictionary *records = objc_getAssociatedObject(object_getClass(receiver), BRPPCGuestMethodsKey);
    BRPPCGuestMethod *guestMethod = records[selectorName];
    NSArray<NSString *> *guestTypes = guestMethod ? [self argumentTypesInEncoding:guestMethod.types] : nil;
    for (NSUInteger i = 2; i < signature.numberOfArguments; i++)
        if (![self setInvocationArgument:invocation index:i type:[signature getArgumentTypeAtIndex:i]
                               guestType:i + 1 < guestTypes.count ? guestTypes[i + 1].UTF8String :
                                   (strchr("qQ", *SkipTypeQualifiers([signature getArgumentTypeAtIndex:i]))
                                       ? (*SkipTypeQualifiers([signature getArgumentTypeAtIndex:i]) == 'q' ? "l" : "L")
                                       : [signature getArgumentTypeAtIndex:i])
                                     gpr:&gpr fpr:&fpr state:state scratch:scratch error:error]) return NO;
    BOOL invoked = NO;
    BOOL nativeDrawRect = [selectorName isEqualToString:@"drawRect:"];
    if (nativeDrawRect) {
        NSUInteger slot = BRPPCNativeDrawRectSuperDepth++;
        if (slot < sizeof(BRPPCNativeDrawRectSuperReceivers) /
                   sizeof(BRPPCNativeDrawRectSuperReceivers[0]))
            BRPPCNativeDrawRectSuperReceivers[slot] = (__bridge void *)receiver;
    }
    @try {
        invoked = [self invokeInvocation:invocation usingIMP:method_getImplementation(method)
                                   error:error];
    } @finally {
        if (nativeDrawRect) {
            NSUInteger slot = --BRPPCNativeDrawRectSuperDepth;
            if (slot < sizeof(BRPPCNativeDrawRectSuperReceivers) /
                       sizeof(BRPPCNativeDrawRectSuperReceivers[0]))
                BRPPCNativeDrawRectSuperReceivers[slot] = NULL;
        }
    }
    if (!invoked) return NO;
    for (id item in scratch) {
        if (![item isKindOfClass:[BRPPCPointerScratch class]]) continue;
        BRPPCPointerScratch *record = item;
        if (record.copyBack && ![self writeHostData:record.hostData guestAddress:record.guestAddress
                                               type:record.type.UTF8String error:error]) return NO;
    }
    const char *hostReturn = SkipTypeQualifiers(signature.methodReturnType);
    const char *guestReturn = guestTypes.count ? guestTypes[0].UTF8String : hostReturn;
    if (![self copyInvocationReturn:invocation state:state guestAddress:resultAddress
                          guestType:guestReturn error:error]) return NO;
    state->pc = state->lr;
    return YES;
}

- (void)registerGuestMethodsAtAddress:(uint32_t)methodsAddress
                          targetClass:(Class)targetClass
                           superclass:(Class)superclass
                          classMethod:(BOOL)classMethod
                            className:(NSString *)className {
    if (!methodsAddress || !targetClass) return;
    NSDictionary *existingRecords = objc_getAssociatedObject(targetClass, BRPPCGuestMethodsKey);
    NSMutableDictionary *records = existingRecords ? [existingRecords mutableCopy]
                                                   : [NSMutableDictionary dictionary];
    uint32_t count = 0;
    if (![_registry.memory readUInt32:&count address:methodsAddress + 4] || count >= 4096) return;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t methodAddress = methodsAddress + 8 + i * 12;
        uint32_t selectorAddress = 0, typesAddress = 0, implementationAddress = 0;
        if (![_registry.memory readUInt32:&selectorAddress address:methodAddress] ||
            ![_registry.memory readUInt32:&typesAddress address:methodAddress + 4] ||
            ![_registry.memory readUInt32:&implementationAddress address:methodAddress + 8]) continue;
        NSString *selectorName = [_registry.memory readCStringAtAddress:selectorAddress maximumLength:1024];
        NSString *types = [_registry.memory readCStringAtAddress:typesAddress maximumLength:1024];
        if (!selectorName.length || !types.length || !implementationAddress) continue;
        if (!classMethod && [targetClass isSubclassOfClass:[NSApplication class]] &&
            [selectorName isEqualToString:@"nextEventMatchingMask:untilDate:inMode:dequeue:"])
            continue;
        if (!classMethod && ( [selectorName isEqualToString:@"retain"] ||
                              [selectorName isEqualToString:@"release"] ||
                              [selectorName isEqualToString:@"autorelease"] ||
                              [selectorName isEqualToString:@"retainCount"] ||
                              [selectorName isEqualToString:@"_tryRetain"] ||
                              [selectorName isEqualToString:@"_isDeallocating"] ||
                              [selectorName isEqualToString:@"allowsWeakReference"] ||
                              [selectorName isEqualToString:@"retainWeakReference"] )) continue;
        BRPPCGuestMethod *record = [BRPPCGuestMethod new];
        record.resolver = self;
        record.owningClass = targetClass;
        record.classMethod = classMethod;
        record.implementationAddress = implementationAddress;
        record.selectorAddress = selectorAddress;
        record.types = types;
        SEL selector = NSSelectorFromString(selectorName);
        Method inherited = classMethod ? class_getClassMethod(superclass, selector)
                                       : class_getInstanceMethod(superclass, selector);
        record.fallbackImplementation = inherited ? method_getImplementation(inherited) : NULL;
        record.hostTypes = [self hostTypesForSelector:selector
                                          superclass:superclass classMethod:classMethod fallback:types];
        if (![self prepareFFIMethod:record]) continue;
        records[selectorName] = record;
        class_addMethod(targetClass, NSSelectorFromString(selectorName), (IMP)record->_closureCode,
                        record.hostTypes.UTF8String);
        if (getenv("BISMUTH_OBJC_CLASS_TRACE"))
            fprintf(stderr, "objc guest method class=%s selector=%s pc=0x%08x\n",
                    className.UTF8String, selectorName.UTF8String, implementationAddress);
    }
    objc_setAssociatedObject(targetClass, BRPPCGuestMethodsKey, records,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)guestIvarForKey:(NSString *)key object:(id)object {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSDictionary *record = objc_getAssociatedObject(cls, BRPPCGuestIvarsKey)[key];
        if (record) return record;
    }
    return nil;
}

- (void)setGuestKVCValue:(id)value forKey:(NSString *)key object:(id)object {
    NSDictionary *record = [self guestIvarForKey:key object:object];
    const char *type = [record[@"type"] UTF8String];
    if (getenv("BISMUTH_OBJC_KVC_TRACE"))
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc guest kvc set class=%s key=%s offset=%u type=%s value=%s\n",
                class_getName(object_getClass(object)), key.UTF8String,
                [record[@"offset"] unsignedIntValue], type ?: "(none)",
                value ? class_getName(object_getClass(value)) : "(null)");
    if (record && (*SkipTypeQualifiers(type) == '@' || *SkipTypeQualifiers(type) == '#')) {
        uint32_t objectAddress = [self handleForObject:object];
        uint32_t valueAddress = [self handleForObject:value];
        [_registry.memory writeUInt32:valueAddress
                              address:objectAddress + [record[@"offset"] unsignedIntValue]];
        return;
    }
    NSMutableDictionary *values = objc_getAssociatedObject(object, BRPPCGuestKVCValuesKey);
    if (!values) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(object, BRPPCGuestKVCValuesKey, values,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    values[key] = value ?: [NSNull null];
}

- (id)guestKVCValueForKey:(NSString *)key object:(id)object {
    NSDictionary *record = [self guestIvarForKey:key object:object];
    const char *type = [record[@"type"] UTF8String];
    if (record && (*SkipTypeQualifiers(type) == '@' || *SkipTypeQualifiers(type) == '#')) {
        uint32_t valueAddress = 0;
        uint32_t objectAddress = [self handleForObject:object];
        if ([_registry.memory readUInt32:&valueAddress
                                 address:objectAddress + [record[@"offset"] unsignedIntValue]])
            return [self objectAtGuestAddress:valueAddress allowClassName:*SkipTypeQualifiers(type) == '#'];
    }
    id value = [objc_getAssociatedObject(object, BRPPCGuestKVCValuesKey) objectForKey:key];
    return value == [NSNull null] ? nil : value;
}

- (void)registerGuestClasses {
    BRPPCMachOSection *classes = [_registry.image sectionInSegment:@"__OBJC" name:@"__class"];
    if (!classes || classes.size % 48) return;
    NSMutableArray<NSDictionary *> *pendingClasses = [NSMutableArray array];
    NSMutableSet<NSString *> *guestClassNames = [NSMutableSet set];
    for (uint32_t offset = 0; offset < classes.size; offset += 48) {
        uint32_t base = classes.address + offset, nameAddress = 0;
        if (![_registry.memory readUInt32:&nameAddress address:base + 8] ||
            !nameAddress) continue;
        NSString *name = [_registry.memory readCStringAtAddress:nameAddress maximumLength:512];
        if (!name.length) continue;
        [guestClassNames addObject:name];
        [pendingClasses addObject:@{@"base": @(base), @"name": name}];
    }
    while (pendingClasses.count) {
        BOOL madeProgress = NO;
        for (NSInteger index = (NSInteger)pendingClasses.count - 1; index >= 0; index--) {
            NSDictionary *candidate = pendingClasses[(NSUInteger)index];
            uint32_t base = [candidate[@"base"] unsignedIntValue];
            NSString *name = candidate[@"name"];
            Class existingClass = NSClassFromString(name);
            if (existingClass) {
                [pendingClasses removeObjectAtIndex:(NSUInteger)index];
                madeProgress = YES;
                continue;
            }
            uint32_t superclassAddress = 0;
            [_registry.memory readUInt32:&superclassAddress address:base + 4];
        NSString *superclassName = [_registry.memory readCStringAtAddress:superclassAddress maximumLength:512];
        Class superclass = superclassName.length ? NSClassFromString(superclassName) : Nil;
            if (!superclass && [guestClassNames containsObject:superclassName]) continue;
        if (!superclass) superclass = [NSObject class];
            uint32_t methodsAddress = 0, metaClassAddress = 0, instanceSize = 0;
            [_registry.memory readUInt32:&methodsAddress address:base + 28];
            [_registry.memory readUInt32:&metaClassAddress address:base];
            [_registry.memory readUInt32:&instanceSize address:base + 20];
            if (getenv("BISMUTH_OBJC_CLASS_TRACE"))
                fprintf(stderr, "objc guest class=%s superclass=%s methods=0x%08x\n",
                        name.UTF8String, class_getName(superclass), methodsAddress);
        Class cls = objc_allocateClassPair(superclass, name.UTF8String, 0);
            if (!cls) {
                [pendingClasses removeObjectAtIndex:(NSUInteger)index];
                madeProgress = YES;
                continue;
            }
        uint32_t ivarsAddress = 0, ivarCount = 0;
        [_registry.memory readUInt32:&ivarsAddress address:base + 24];
        if (ivarsAddress) [_registry.memory readUInt32:&ivarCount address:ivarsAddress + 4];
        NSMutableDictionary *guestIvars = [NSMutableDictionary dictionary];
        if (ivarCount < 4096) {
            for (uint32_t ivarIndex = 0; ivarIndex < ivarCount; ivarIndex++) {
                uint32_t entry = ivarsAddress + 8 + ivarIndex * 12;
                uint32_t ivarNameAddress = 0, ivarTypeAddress = 0, ivarOffset = 0;
                if (![_registry.memory readUInt32:&ivarNameAddress address:entry] ||
                    ![_registry.memory readUInt32:&ivarTypeAddress address:entry + 4] ||
                    ![_registry.memory readUInt32:&ivarOffset address:entry + 8]) continue;
                NSString *ivarName = [_registry.memory readCStringAtAddress:ivarNameAddress
                                                               maximumLength:512];
                NSString *ivarType = [_registry.memory readCStringAtAddress:ivarTypeAddress
                                                               maximumLength:512];
                if (ivarName.length && ivarType.length)
                    guestIvars[ivarName] = @{@"offset": @(ivarOffset), @"type": ivarType};
            }
        }
        objc_setAssociatedObject(cls, BRPPCGuestIvarsKey, guestIvars,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cls, BRPPCGuestResolverKey, self,
                                 OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(cls, BRPPCGuestInstanceSizeKey, @(instanceSize),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cls, BRPPCGuestClassAddressKey, @(base),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        _guestClassesByAddress[@(base)] = cls;
        if (metaClassAddress) _guestClassesByAddress[@(metaClassAddress)] = object_getClass(cls);
        [self registerGuestMethodsAtAddress:methodsAddress targetClass:cls superclass:superclass
                                classMethod:NO className:name];
        uint32_t classMethodsAddress = 0;
        if (metaClassAddress)
            [_registry.memory readUInt32:&classMethodsAddress address:metaClassAddress + 28];
        [self registerGuestMethodsAtAddress:classMethodsAddress
                                targetClass:object_getClass(cls) superclass:superclass
                                classMethod:YES className:name];
        class_addMethod(cls, @selector(setValue:forUndefinedKey:),
                        (IMP)BRPPCGuestSetValueForUndefinedKey, "v@:@@");
        class_addMethod(cls, @selector(valueForUndefinedKey:),
                        (IMP)BRPPCGuestValueForUndefinedKey, "@@:@");
        objc_registerClassPair(cls);
            [pendingClasses removeObjectAtIndex:(NSUInteger)index];
            madeProgress = YES;
        }
        if (!madeProgress) {
            NSDictionary *candidate = pendingClasses.lastObject;
            [guestClassNames removeObject:candidate[@"name"]];
        }
    }
    BRPPCMachOSection *categories = [_registry.image sectionInSegment:@"__OBJC"
                                                                  name:@"__category"];
    uint32_t categorySize = categories && categories.size % 28 == 0 ? 28
        : (categories && categories.size % 24 == 0 ? 24 : 20);
    if (!categories || categories.size % categorySize) return;
    for (uint32_t offset = 0; offset < categories.size; offset += categorySize) {
        uint32_t base = categories.address + offset;
        uint32_t categoryNameAddress = 0, classNameAddress = 0;
        uint32_t instanceMethodsAddress = 0, classMethodsAddress = 0;
        if (![_registry.memory readUInt32:&categoryNameAddress address:base] ||
            ![_registry.memory readUInt32:&classNameAddress address:base + 4] ||
            ![_registry.memory readUInt32:&instanceMethodsAddress address:base + 8] ||
            ![_registry.memory readUInt32:&classMethodsAddress address:base + 12]) continue;
        NSString *categoryName = [_registry.memory readCStringAtAddress:categoryNameAddress
                                                          maximumLength:512];
        NSString *className = [_registry.memory readCStringAtAddress:classNameAddress
                                                       maximumLength:512];
        Class targetClass = className.length ? NSClassFromString(className) : Nil;
        if (!targetClass) continue;
        NSString *displayName = categoryName.length
            ? [NSString stringWithFormat:@"%@(%@)", className, categoryName] : className;
        [self registerGuestMethodsAtAddress:instanceMethodsAddress targetClass:targetClass
                                 superclass:targetClass classMethod:NO className:displayName];
        [self registerGuestMethodsAtAddress:classMethodsAddress
                                 targetClass:object_getClass(targetClass)
                                 superclass:targetClass classMethod:YES className:displayName];
    }
}

- (id)constantStringAtAddress:(uint32_t)address {
    uint32_t flags = 0, bytesAddress = 0, length = 0;
    if (![_registry.memory readUInt32:&flags address:address + 4] ||
        ![_registry.memory readUInt32:&bytesAddress address:address + 8] ||
        ![_registry.memory readUInt32:&length address:address + 12] ||
        length > (1u << 24)) return nil;
    NSMutableData *bytes = [NSMutableData dataWithLength:length];
    if (![_registry.memory readBytes:bytes.mutableBytes address:bytesAddress length:length]) return nil;
    NSStringEncoding encoding = (flags & BRPPCConstantStringUnicodeFlag)
        ? NSUnicodeStringEncoding : NSUTF8StringEncoding;
    NSString *string = [[NSString alloc] initWithData:bytes encoding:encoding];
    return string;
}

- (id)objectAtGuestAddress:(uint32_t)address allowClassName:(BOOL)allowClassName {
    if (!address) return nil;
    id object = [_objects objectForKey:@(address)];
    if (object) return object;
    id guestClass = _guestClassesByAddress[@(address)];
    if (guestClass) return guestClass;
    NSString *name = [_registry.memory readCStringAtAddress:address maximumLength:1024];
    if (allowClassName && name.length) {
        Class cls = NSClassFromString(name);
        if (cls) return cls;
    }
    id constant = [self constantStringAtAddress:address];
    if (constant) {
        NSNumber *key = @(address);
        [_objects setObject:constant forKey:key];
        _retainedObjects[key] = constant;
        _handles[[NSValue valueWithPointer:(__bridge void *)constant]] = key;
    }
    return constant;
}

- (NSMutableData *)hostDataForGuestValueAtAddress:(uint32_t)address
                                              type:(const char *)rawType
                                    retainedObject:(id __strong *)retainedObject
                                             error:(NSError **)error {
    const char *type = SkipTypeQualifiers(rawType);
    NSUInteger hostSize = 0;
    NSGetSizeAndAlignment(type, &hostSize, NULL);
    if (!hostSize || hostSize > (1u << 20)) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:hostSize];
    uint32_t first = 0, second = 0;
    switch (*type) {
        case 'c': case 'C': {
            uint8_t value = 0;
            if (![_registry.memory readBytes:&value address:address length:1]) return nil;
            memcpy(data.mutableBytes, &value, 1); return data;
        }
        case 's': case 'S': {
            uint8_t bytes[2];
            if (![_registry.memory readBytes:bytes address:address length:2]) return nil;
            uint16_t value = (uint16_t)bytes[0] << 8 | bytes[1];
            memcpy(data.mutableBytes, &value, 2); return data;
        }
        case 'i': case 'I': case 'l': case 'L': case 'B': {
            if (![_registry.memory readUInt32:&first address:address]) return nil;
            if (*type == 'B') { BOOL value = first != 0; memcpy(data.mutableBytes, &value, sizeof(value)); }
            else if (*type == 'l') { long value = (int32_t)first; memcpy(data.mutableBytes, &value, sizeof(value)); }
            else if (*type == 'L') { unsigned long value = first; memcpy(data.mutableBytes, &value, sizeof(value)); }
            else memcpy(data.mutableBytes, &first, MIN(hostSize, sizeof(first)));
            return data;
        }
        case 'q': case 'Q': {
            if (![_registry.memory readUInt32:&first address:address] ||
                ![_registry.memory readUInt32:&second address:address + 4]) return nil;
            uint64_t value = (uint64_t)first << 32 | second;
            memcpy(data.mutableBytes, &value, sizeof(value)); return data;
        }
        case 'f': {
            if (![_registry.memory readUInt32:&first address:address]) return nil;
            float value; memcpy(&value, &first, sizeof(value));
            memcpy(data.mutableBytes, &value, sizeof(value)); return data;
        }
        case 'd': {
            if (![_registry.memory readUInt32:&first address:address] ||
                ![_registry.memory readUInt32:&second address:address + 4]) return nil;
            uint64_t bits = (uint64_t)first << 32 | second;
            double value; memcpy(&value, &bits, sizeof(value));
            memcpy(data.mutableBytes, &value, sizeof(value)); return data;
        }
        case '@': case '#': {
            if (![_registry.memory readUInt32:&first address:address]) return nil;
            id object = [self objectAtGuestAddress:first allowClassName:*type == '#'];
            if (retainedObject) *retainedObject = object;
            __unsafe_unretained id value = object;
            memcpy(data.mutableBytes, &value, sizeof(value)); return data;
        }
        case ':': {
            if (![_registry.memory readUInt32:&first address:address]) return nil;
            NSString *name = [_registry.memory readCStringAtAddress:first maximumLength:1024];
            SEL value = name.length ? NSSelectorFromString(name) : NULL;
            memcpy(data.mutableBytes, &value, sizeof(value)); return data;
        }
        case '{':
        case '[': {
            if (strstr(type, "CGRect") || strstr(type, "NSRect")) {
                float components[4];
                for (NSUInteger i = 0; i < 4; i++) {
                    if (![_registry.memory readUInt32:&first address:address + (uint32_t)i * 4]) return nil;
                    memcpy(&components[i], &first, sizeof(first));
                }
                if (StructureUsesFloat(type)) memcpy(data.mutableBytes, components, sizeof(components));
                else {
                    CGRect value = CGRectMake(components[0], components[1], components[2], components[3]);
                    memcpy(data.mutableBytes, &value, sizeof(value));
                }
                return data;
            }
            if (strstr(type, "CGPoint") || strstr(type, "NSPoint") ||
                strstr(type, "CGSize") || strstr(type, "NSSize")) {
                float components[2];
                for (NSUInteger i = 0; i < 2; i++) {
                    if (![_registry.memory readUInt32:&first address:address + (uint32_t)i * 4]) return nil;
                    memcpy(&components[i], &first, sizeof(first));
                }
                if (StructureUsesFloat(type)) memcpy(data.mutableBytes, components, sizeof(components));
                else if (strstr(type, "Point")) {
                    CGPoint value = CGPointMake(components[0], components[1]);
                    memcpy(data.mutableBytes, &value, sizeof(value));
                } else {
                    CGSize value = CGSizeMake(components[0], components[1]);
                    memcpy(data.mutableBytes, &value, sizeof(value));
                }
                return data;
            }
            if (strstr(type, "Range")) {
                if (![_registry.memory readUInt32:&first address:address] ||
                    ![_registry.memory readUInt32:&second address:address + 4]) return nil;
                NSRange value = NSMakeRange(first, second);
                memcpy(data.mutableBytes, &value, sizeof(value)); return data;
            }
            BRPPCEncodedType *node = [self safeAggregateForType:type];
            if (node) {
                NSMutableData *guestData = [NSMutableData dataWithLength:node.guestSize];
                if (![_registry.memory readBytes:guestData.mutableBytes address:address
                                          length:guestData.length]) return nil;
                return [self hostAggregateFromGuestData:guestData type:type];
            }
            break;
        }
        default: break;
    }
    if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:14
        userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"Cannot convert guest value type %s.", type]}];
    return nil;
}

- (BOOL)writeHostData:(NSData *)data guestAddress:(uint32_t)address
                  type:(const char *)rawType error:(NSError **)error {
    const char *type = SkipTypeQualifiers(rawType);
    uint32_t first = 0;
    switch (*type) {
        case 'c': case 'C':
            return [_registry.memory writeBytes:data.bytes address:address length:1];
        case 's': case 'S': {
            uint16_t value = 0; memcpy(&value, data.bytes, sizeof(value));
            uint8_t bytes[] = {value >> 8, value};
            return [_registry.memory writeBytes:bytes address:address length:2];
        }
        case 'i': case 'I': case 'l': case 'L': {
            memcpy(&first, data.bytes, MIN(data.length, sizeof(first)));
            return [_registry.memory writeUInt32:first address:address];
        }
        case 'B': {
            BOOL value = NO; memcpy(&value, data.bytes, MIN(data.length, sizeof(value)));
            return [_registry.memory writeUInt32:value ? 1 : 0 address:address];
        }
        case 'q': case 'Q': {
            uint64_t value = 0; memcpy(&value, data.bytes, MIN(data.length, sizeof(value)));
            return [_registry.memory writeUInt32:(uint32_t)(value >> 32) address:address] &&
                   [_registry.memory writeUInt32:(uint32_t)value address:address + 4];
        }
        case 'f': {
            float value = 0; memcpy(&value, data.bytes, sizeof(value));
            memcpy(&first, &value, sizeof(first));
            return [_registry.memory writeUInt32:first address:address];
        }
        case 'd': {
            double value = 0; uint64_t bits = 0;
            memcpy(&value, data.bytes, sizeof(value)); memcpy(&bits, &value, sizeof(bits));
            return [_registry.memory writeUInt32:(uint32_t)(bits >> 32) address:address] &&
                   [_registry.memory writeUInt32:(uint32_t)bits address:address + 4];
        }
        case '@': case '#': {
            __unsafe_unretained id value = nil; memcpy(&value, data.bytes, sizeof(value));
            return [_registry.memory writeUInt32:[self handleForObject:value] address:address];
        }
        case '{':
        case '[': {
            if (strstr(type, "CGRect") || strstr(type, "NSRect")) {
                float components[4];
                if (StructureUsesFloat(type)) memcpy(components, data.bytes, sizeof(components));
                else {
                    CGRect value; memcpy(&value, data.bytes, sizeof(value));
                    float converted[] = {(float)value.origin.x, (float)value.origin.y,
                                         (float)value.size.width, (float)value.size.height};
                    memcpy(components, converted, sizeof(components));
                }
                for (NSUInteger i = 0; i < 4; i++) {
                    memcpy(&first, &components[i], sizeof(first));
                    if (![_registry.memory writeUInt32:first address:address + (uint32_t)i * 4]) return NO;
                }
                return YES;
            }
            if (strstr(type, "Point") || strstr(type, "Size")) {
                float components[2];
                if (StructureUsesFloat(type)) memcpy(components, data.bytes, sizeof(components));
                else {
                    double a = 0, b = 0;
                    if (strstr(type, "Point")) { CGPoint v; memcpy(&v, data.bytes, sizeof(v)); a = v.x; b = v.y; }
                    else { CGSize v; memcpy(&v, data.bytes, sizeof(v)); a = v.width; b = v.height; }
                    components[0] = (float)a; components[1] = (float)b;
                }
                for (NSUInteger i = 0; i < 2; i++) {
                    memcpy(&first, &components[i], sizeof(first));
                    if (![_registry.memory writeUInt32:first address:address + (uint32_t)i * 4]) return NO;
                }
                return YES;
            }
            if (strstr(type, "Range")) {
                NSRange value; memcpy(&value, data.bytes, sizeof(value));
                return [_registry.memory writeUInt32:(uint32_t)value.location address:address] &&
                       [_registry.memory writeUInt32:(uint32_t)value.length address:address + 4];
            }
            NSMutableData *guestData = [self guestAggregateFromHostData:data type:type];
            if (guestData)
                return [_registry.memory writeBytes:guestData.bytes address:address length:guestData.length];
            break;
        }
        default: break;
    }
    if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:15
        userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"Cannot convert host value type %s.", type]}];
    return NO;
}

- (BOOL)handleInvocationMemoryMessage:(NSString *)selectorName receiver:(NSInvocation *)invocation
                                state:(BRPPCState *)state error:(NSError **)error handled:(BOOL *)handled {
    *handled = NO;
    BOOL setter = [selectorName isEqualToString:@"setArgument:atIndex:"];
    BOOL getter = [selectorName isEqualToString:@"getArgument:atIndex:"];
    BOOL returnSetter = [selectorName isEqualToString:@"setReturnValue:"];
    BOOL returnGetter = [selectorName isEqualToString:@"getReturnValue:"];
    if (!setter && !getter && !returnSetter && !returnGetter) return YES;
    *handled = YES;
    uint32_t address = state->gpr[5];
    NSUInteger index = (setter || getter) ? state->gpr[6] : 0;
    if ((setter || getter) && index >= invocation.methodSignature.numberOfArguments) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:16
            userInfo:@{NSLocalizedDescriptionKey: @"NSInvocation argument index is out of bounds."}];
        return NO;
    }
    const char *type = (setter || getter)
        ? [invocation.methodSignature getArgumentTypeAtIndex:index]
        : invocation.methodSignature.methodReturnType;
    if (setter || returnSetter) {
        id retainedObject = nil;
        NSMutableData *data = [self hostDataForGuestValueAtAddress:address type:type
                                                    retainedObject:&retainedObject error:error];
        if (!data) return NO;
        if (setter) [invocation setArgument:data.mutableBytes atIndex:index];
        else [invocation setReturnValue:data.mutableBytes];
        [invocation retainArguments];
    } else {
        NSUInteger size = 0; NSGetSizeAndAlignment(SkipTypeQualifiers(type), &size, NULL);
        NSMutableData *data = [NSMutableData dataWithLength:size];
        if (getter) [invocation getArgument:data.mutableBytes atIndex:index];
        else [invocation getReturnValue:data.mutableBytes];
        if (![self writeHostData:data guestAddress:address type:type error:error]) return NO;
    }
    state->pc = state->lr;
    return YES;
}

- (BOOL)setInvocationArgument:(NSInvocation *)invocation index:(NSUInteger)index
                         type:(const char *)rawType guestType:(const char *)guestRawType
                          gpr:(NSUInteger *)gpr
                          fpr:(NSUInteger *)fpr state:(BRPPCState *)state
                      scratch:(NSMutableArray *)scratch error:(NSError **)error {
    const char *type = SkipTypeQualifiers(rawType);
    const char *guestType = SkipTypeQualifiers(guestRawType ?: rawType);
    uint32_t word = 0;
    switch (*type) {
        case '@':
        case '#': {
            if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO;
            id value = [self objectAtGuestAddress:word
                                   allowClassName:*type == '#'];
            if (value) [scratch addObject:value];
            [invocation setArgument:&value atIndex:index];
            return YES;
        }
        case ':': {
            uint32_t address = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &address)) return NO;
            NSString *name = [_registry.memory readCStringAtAddress:address maximumLength:1024];
            SEL selector = name.length ? NSSelectorFromString(name) : NULL;
            [invocation setArgument:&selector atIndex:index];
            return selector != NULL;
        }
        case 'c': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; int8_t v = (int8_t)word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'C': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; uint8_t v = (uint8_t)word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 's': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; int16_t v = (int16_t)word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'S': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; uint16_t v = (uint16_t)word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'i': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; int32_t v = (int32_t)word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'I': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; uint32_t v = word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'l': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; long v = (int32_t)word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'L': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; unsigned long v = word; [invocation setArgument:&v atIndex:index]; return YES; }
        case 'q': {
            if (*guestType != 'q' && *guestType != 'Q') {
                if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO;
                int64_t v = (int32_t)word;
                [invocation setArgument:&v atIndex:index]; return YES;
            }
            if (((*gpr - 3) & 1) != 0) (*gpr)++;
            uint32_t low = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word) ||
                !ReadGuestArgumentWord(_registry.memory, state, gpr, &low)) return NO;
            int64_t v = (int64_t)((uint64_t)word << 32 | low);
            [invocation setArgument:&v atIndex:index]; return YES;
        }
        case 'Q': {
            if (*guestType != 'q' && *guestType != 'Q') {
                if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO;
                uint64_t v = word;
                [invocation setArgument:&v atIndex:index]; return YES;
            }
            if (((*gpr - 3) & 1) != 0) (*gpr)++;
            uint32_t low = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word) ||
                !ReadGuestArgumentWord(_registry.memory, state, gpr, &low)) return NO;
            uint64_t v = (uint64_t)word << 32 | low;
            [invocation setArgument:&v atIndex:index]; return YES;
        }
        case 'f': { float v = (float)state->fpr[(*fpr)++]; [invocation setArgument:&v atIndex:index]; (*gpr)++; return YES; }
        case 'd': { double v = state->fpr[(*fpr)++]; [invocation setArgument:&v atIndex:index]; (*gpr)++; return YES; }
        case 'B': { if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO; BOOL v = word != 0; [invocation setArgument:&v atIndex:index]; return YES; }
        case '*': {
            uint32_t address = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &address)) return NO;
            NSString *string = [_registry.memory readCStringAtAddress:address maximumLength:1u << 20];
            NSData *bytes = [(string ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
            NSMutableData *terminated = [bytes mutableCopy];
            uint8_t zero = 0;
            [terminated appendBytes:&zero length:1];
            [scratch addObject:terminated];
            const char *pointer = terminated.bytes;
            [invocation setArgument:&pointer atIndex:index];
            return YES;
        }
        case '^': {
            uint32_t address = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &address)) return NO;
            if (!address) {
                void *pointer = NULL;
                [invocation setArgument:&pointer atIndex:index];
                return YES;
            }
            id opaque = [self objectAtGuestAddress:address allowClassName:NO];
            if ([opaque isKindOfClass:[NSValue class]]) {
                void *pointer = [(NSValue *)opaque pointerValue];
                [invocation setArgument:&pointer atIndex:index];
                return YES;
            }
            SEL nativePointerSelector = NSSelectorFromString(@"bismuthNativePointer");
            if ([opaque respondsToSelector:nativePointerSelector]) {
                void *(*getter)(id, SEL) = (void *(*)(id, SEL))
                    [opaque methodForSelector:nativePointerSelector];
                void *pointer = getter(opaque, nativePointerSelector);
                [invocation setArgument:&pointer atIndex:index];
                return YES;
            }
            const char *pointeeType = SkipTypeQualifiers(type + 1);
            if (*pointeeType == 'v') {
                void *pointer = [self hostPointerForGuestOpaqueAddress:address];
                [invocation setArgument:&pointer atIndex:index];
                return YES;
            }
            if (*pointeeType != 'v') {
                id retainedObject = nil;
                NSMutableData *data = [self hostDataForGuestValueAtAddress:address type:pointeeType
                                                            retainedObject:&retainedObject error:error];
                if (!data) return NO;
                BRPPCPointerScratch *record = [BRPPCPointerScratch new];
                record.guestAddress = address;
                record.type = [NSString stringWithUTF8String:pointeeType];
                record.hostData = data;
                record.retainedObject = retainedObject;
                record.copyBack = strchr(rawType, 'r') == NULL;
                [scratch addObject:record];
                void *pointer = data.mutableBytes;
                [invocation setArgument:&pointer atIndex:index];
                return YES;
            }
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:8
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:
                        @"Objective-C void pointer 0x%08x has no encoded size; typed Resolve required.", address]}];
            return NO;
        }
        case '{':
        case '[': {
            if (strstr(type, "CGRect") || strstr(type, "NSRect")) {
                float components[4];
                for (NSUInteger i = 0; i < 4; i++) {
                    if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO;
                    memcpy(&components[i], &word, sizeof(word));
                }
                if (StructureUsesFloat(type)) [invocation setArgument:components atIndex:index];
                else {
                    CGRect value = CGRectMake(components[0], components[1], components[2], components[3]);
                    [invocation setArgument:&value atIndex:index];
                }
                return YES;
            }
            if (strstr(type, "CGPoint") || strstr(type, "NSPoint") ||
                strstr(type, "CGSize") || strstr(type, "NSSize")) {
                float components[2];
                for (NSUInteger i = 0; i < 2; i++) {
                    if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &word)) return NO;
                    memcpy(&components[i], &word, sizeof(word));
                }
                if (StructureUsesFloat(type)) [invocation setArgument:components atIndex:index];
                else if (strstr(type, "Point")) {
                    CGPoint value = CGPointMake(components[0], components[1]);
                    [invocation setArgument:&value atIndex:index];
                } else {
                    CGSize value = CGSizeMake(components[0], components[1]);
                    [invocation setArgument:&value atIndex:index];
                }
                return YES;
            }
            if (strstr(type, "Range")) {
                uint32_t location = 0, length = 0;
                if (!ReadGuestArgumentWord(_registry.memory, state, gpr, &location) ||
                    !ReadGuestArgumentWord(_registry.memory, state, gpr, &length)) return NO;
                NSRange value = NSMakeRange(location, length);
                [invocation setArgument:&value atIndex:index];
                return YES;
            }
            NSMutableData *data = [self readAggregateArgumentType:type state:state gpr:gpr];
            if (data) {
                [scratch addObject:data];
                [invocation setArgument:data.mutableBytes atIndex:index];
                return YES;
            }
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:11
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Objective-C aggregate type %s needs a PowerPC ABI adapter.", type]}];
            return NO;
        }
        default:
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Objective-C argument type %s needs a PowerPC ABI adapter.", type]}];
            return NO;
    }
}

- (BOOL)dispatchBitmapImageInitializer:(id)receiver selector:(SEL)selector
                                  state:(BRPPCState *)state firstGPR:(NSUInteger)firstGPR
                                  error:(NSError **)error {
    uint32_t words[10] = {0};
    NSUInteger gpr = firstGPR;
    for (NSUInteger index = 0; index < 10; index++)
        if (!ReadGuestArgumentWord(_registry.memory, state, &gpr, words + index)) return NO;
    uint32_t guestPixels = 0;
    if (words[0] && ![_registry.memory readUInt32:&guestPixels address:words[0]]) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:29
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot read NSBitmapImageRep plane table."}];
        return NO;
    }
    uint64_t byteCount = (uint64_t)words[8] * words[2];
    if (byteCount > UINT32_MAX) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:30
            userInfo:@{NSLocalizedDescriptionKey: @"NSBitmapImageRep pixel storage exceeds PowerPC32 range."}];
        return NO;
    }
    NSMutableData *pixels = guestPixels ? [NSMutableData dataWithLength:(NSUInteger)byteCount] : nil;
    if (pixels.length && ![_registry.memory readBytes:pixels.mutableBytes address:guestPixels
                                               length:pixels.length]) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:31
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot read NSBitmapImageRep pixel storage."}];
        return NO;
    }
    unsigned char *planes[5] = {pixels.mutableBytes, NULL, NULL, NULL, NULL};
    unsigned char **planePointer = words[0] ? planes : NULL;
    NSInteger width = words[1], height = words[2], bitsPerSample = words[3];
    NSInteger samplesPerPixel = words[4], bytesPerRow = words[8], bitsPerPixel = words[9];
    BOOL hasAlpha = words[5] != 0, planar = words[6] != 0;
    id colorSpace = [self objectAtGuestAddress:words[7] allowClassName:NO];
    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver; invocation.selector = selector;
    [invocation setArgument:&planePointer atIndex:2];
    [invocation setArgument:&width atIndex:3]; [invocation setArgument:&height atIndex:4];
    [invocation setArgument:&bitsPerSample atIndex:5];
    [invocation setArgument:&samplesPerPixel atIndex:6];
    [invocation setArgument:&hasAlpha atIndex:7]; [invocation setArgument:&planar atIndex:8];
    [invocation setArgument:&colorSpace atIndex:9];
    [invocation setArgument:&bytesPerRow atIndex:10];
    [invocation setArgument:&bitsPerPixel atIndex:11];
    @try { [invocation invoke]; }
    @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        return NO;
    }
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    if (result && pixels) objc_setAssociatedObject(result, BRPPCBitmapStorageKey, pixels,
                                                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state->gpr[3] = [self handleForObject:result];
    state->pc = state->lr;
    return YES;
}

- (BOOL)writeStructureReturn:(NSInvocation *)invocation guestAddress:(uint32_t)address
                       error:(NSError **)error {
    const char *type = SkipTypeQualifiers(invocation.methodSignature.methodReturnType);
    if (strstr(type, "CGRect") || strstr(type, "NSRect")) {
        float components[4];
        if (StructureUsesFloat(type)) [invocation getReturnValue:components];
        else {
            CGRect value;
            [invocation getReturnValue:&value];
            float converted[] = {(float)value.origin.x, (float)value.origin.y,
                                 (float)value.size.width, (float)value.size.height};
            memcpy(components, converted, sizeof(components));
        }
        for (NSUInteger i = 0; i < 4; i++) {
            uint32_t bits = 0;
            memcpy(&bits, &components[i], sizeof(bits));
            if (![_registry.memory writeUInt32:bits address:address + (uint32_t)i * 4]) return NO;
        }
        return YES;
    }
    if (strstr(type, "CGPoint") || strstr(type, "NSPoint") ||
        strstr(type, "CGSize") || strstr(type, "NSSize")) {
        float components[2];
        double first = 0, second = 0;
        if (StructureUsesFloat(type)) [invocation getReturnValue:components];
        else if (strstr(type, "Point")) {
            CGPoint value; [invocation getReturnValue:&value];
            first = value.x; second = value.y;
        } else {
            CGSize value; [invocation getReturnValue:&value];
            first = value.width; second = value.height;
        }
        if (!StructureUsesFloat(type)) { components[0] = (float)first; components[1] = (float)second; }
        for (NSUInteger i = 0; i < 2; i++) {
            uint32_t bits = 0;
            memcpy(&bits, &components[i], sizeof(bits));
            if (![_registry.memory writeUInt32:bits address:address + (uint32_t)i * 4]) return NO;
        }
        return YES;
    }
    if (strstr(type, "Range")) {
        NSRange value;
        [invocation getReturnValue:&value];
        return [_registry.memory writeUInt32:(uint32_t)value.location address:address] &&
               [_registry.memory writeUInt32:(uint32_t)value.length address:address + 4];
    }
    BRPPCEncodedType *node = [self safeAggregateForType:type];
    if (node) {
        NSMutableData *hostData = [NSMutableData dataWithLength:node.hostSize];
        [invocation getReturnValue:hostData.mutableBytes];
        NSMutableData *guestData = [self guestAggregateFromHostData:hostData type:type];
        return guestData && [_registry.memory writeBytes:guestData.bytes address:address
                                                   length:guestData.length];
    }
    if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:12
        userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"Objective-C structure return type %s needs a PowerPC ABI adapter.",
                                       type]}];
    return NO;
}

- (BOOL)copyInvocationReturn:(NSInvocation *)invocation state:(BRPPCState *)state
                guestAddress:(uint32_t)guestAddress guestType:(const char *)guestRawType
                       error:(NSError **)error {
    const char *type = SkipTypeQualifiers(invocation.methodSignature.methodReturnType);
    const char *guestType = SkipTypeQualifiers(guestRawType ?: type);
    switch (*type) {
        case 'v': return YES;
        case '@':
        case '#': {
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            state->gpr[3] = [self handleForObject:value];
            return YES;
        }
        case ':': {
            SEL value = NULL; [invocation getReturnValue:&value];
            NSString *name = value ? NSStringFromSelector(value) : nil;
            state->gpr[3] = name ? [self handleForObject:name] : 0;
            return YES;
        }
        case 'c': { int8_t v; [invocation getReturnValue:&v]; state->gpr[3] = (uint32_t)(int32_t)v; return YES; }
        case 'C': { uint8_t v; [invocation getReturnValue:&v]; state->gpr[3] = v; return YES; }
        case 's': { int16_t v; [invocation getReturnValue:&v]; state->gpr[3] = (uint32_t)(int32_t)v; return YES; }
        case 'S': { uint16_t v; [invocation getReturnValue:&v]; state->gpr[3] = v; return YES; }
        case 'i': { int32_t v; [invocation getReturnValue:&v]; state->gpr[3] = (uint32_t)v; return YES; }
        case 'I': { uint32_t v; [invocation getReturnValue:&v]; state->gpr[3] = v; return YES; }
        case 'l': { long v; [invocation getReturnValue:&v]; state->gpr[3] = (uint32_t)v; return YES; }
        case 'L': { unsigned long v; [invocation getReturnValue:&v]; state->gpr[3] = (uint32_t)v; return YES; }
        case 'q':
        case 'Q': {
            uint64_t v; [invocation getReturnValue:&v];
            if (*guestType == 'q' || *guestType == 'Q') {
                state->gpr[3] = (uint32_t)(v >> 32); state->gpr[4] = (uint32_t)v;
            } else if (strchr("iIlL", *guestType) &&
                       (v == (uint64_t)NSNotFound || v == UINT64_MAX)) {

                state->gpr[3] = BRPPCGuestNotFound;
            } else state->gpr[3] = (uint32_t)v;
            return YES;
        }
        case 'f': { float v; [invocation getReturnValue:&v]; state->fpr[1] = v; return YES; }
        case 'd': { double v; [invocation getReturnValue:&v]; state->fpr[1] = v; return YES; }
        case 'B': { BOOL v; [invocation getReturnValue:&v]; state->gpr[3] = v; return YES; }
        case '*': {
            const char *value = NULL;
            [invocation getReturnValue:&value];
            if (!value) { state->gpr[3] = 0; return YES; }
            size_t length = strnlen(value, 16 * 1024 * 1024);
            if (length == 16 * 1024 * 1024 || !_registry.guestAllocator) {
                if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:4
                    userInfo:@{NSLocalizedDescriptionKey:
                        @"Objective-C C-string return is unterminated or has no guest allocator."}];
                return NO;
            }
            uint32_t address = _registry.guestAllocator((uint32_t)length + 1, YES);
            if (!address || ![_registry.memory writeBytes:value address:address length:length]) {
                if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:4
                    userInfo:@{NSLocalizedDescriptionKey:
                        @"Cannot copy Objective-C C-string return into guest memory."}];
                return NO;
            }
            state->gpr[3] = address;
            return YES;
        }
        case '^':
        case '?': {
            void *value = NULL;
            [invocation getReturnValue:&value];
            state->gpr[3] = value ? [self handleForObject:[NSValue valueWithPointer:value]] : 0;
            return YES;
        }
        case '{':
        case '[': {
            if (!guestAddress) {
                if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:13
                    userInfo:@{NSLocalizedDescriptionKey:
                        @"PowerPC structure return call has no guest result address."}];
                return NO;
            }
            if (![self writeStructureReturn:invocation guestAddress:guestAddress error:error]) return NO;
            state->gpr[3] = guestAddress;
            return YES;
        }
        default:
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Objective-C return type %s needs a PowerPC ABI adapter.", type]}];
            return NO;
    }
}

- (BOOL)dispatchMessage:(BRPPCState *)state error:(NSError **)error {
    NSNumber *receiverAddress = @(state->gpr[3]);
    if ([_poolHandles containsObject:receiverAddress]) {
        NSString *name = [_registry.memory readCStringAtAddress:state->gpr[4] maximumLength:1024];
        if ([name isEqualToString:@"init"] || [name isEqualToString:@"retain"] ||
            [name isEqualToString:@"autorelease"]) state->gpr[3] = receiverAddress.unsignedIntValue;
        else if (![name isEqualToString:@"release"] && ![name isEqualToString:@"drain"]) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:6
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Unsupported NSAutoreleasePool message %@.", name]}];
            return NO;
        }
        state->pc = state->lr;
        return YES;
    }
    uint32_t structureReturnAddress = 0;
    NSUInteger firstArgumentGPR = 5;
    NSString *selectorName = [_registry.memory readCStringAtAddress:state->gpr[4] maximumLength:1024];
    if (!state->gpr[3]) {
        state->gpr[3] = 0;
        state->gpr[4] = 0;
        state->fpr[1] = 0;
        state->pc = state->lr;
        return YES;
    }
    id receiver = [self objectAtGuestAddress:state->gpr[3] allowClassName:YES];
    SEL initialSelector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    if (!receiver || !initialSelector || ![receiver methodSignatureForSelector:initialSelector]) {
        id shiftedReceiver = [self objectAtGuestAddress:state->gpr[4] allowClassName:YES];
        NSString *shiftedSelector = [_registry.memory readCStringAtAddress:state->gpr[5]
                                                              maximumLength:1024];
        SEL shiftedSEL = shiftedSelector.length ? NSSelectorFromString(shiftedSelector) : NULL;
        NSMethodSignature *shiftedSignature = shiftedReceiver && shiftedSEL
            ? [shiftedReceiver methodSignatureForSelector:shiftedSEL] : nil;
        if (shiftedSignature) {
            if (*SkipTypeQualifiers(shiftedSignature.methodReturnType) == '{')
                structureReturnAddress = state->gpr[3];
            receiver = shiftedReceiver;
            selectorName = shiftedSelector;
            firstArgumentGPR = 6;
        }
    }
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    BOOL traceEnabled = getenv("BISMUTH_OBJC_TRACE") != NULL;
    const char *messageTraceSelector = getenv("BISMUTH_OBJC_TRACE_SELECTOR");
    BOOL tracesMessage = messageTraceSelector &&
        [selectorName isEqualToString:@(messageTraceSelector)];
    if (tracesMessage)
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc host message receiver=0x%08x class=%s selector=%s\n",
                state->gpr[3], receiver ? class_getName(object_getClass(receiver)) : "(null)",
                selectorName.UTF8String);
    if (traceEnabled)
        fprintf(stderr, "objc receiver=0x%08x class=%s selector=%s\n", state->gpr[3],
                receiver ? class_getName(object_getClass(receiver)) : "(null)",
                selectorName.UTF8String);
    if (traceEnabled && [selectorName isEqualToString:@"arrayWithObject:"])
        fprintf(stderr, "objc array object handle=0x%08x object=%p\n", state->gpr[5],
                [self objectAtGuestAddress:state->gpr[5] allowClassName:YES]);
    if (traceEnabled && [selectorName isEqualToString:@"changeClassTo:"]) {
        id targetClass = [self objectAtGuestAddress:state->gpr[5] allowClassName:YES];
        fprintf(stderr, "objc changeClassTo argument=0x%08x class=%s\n", state->gpr[5],
                targetClass && object_isClass(targetClass) ? class_getName(targetClass) : "(null)");
    }
    if (!receiver && selector) {
        NSString *className = [_registry.memory readCStringAtAddress:state->gpr[3] maximumLength:512];
        NSString *marker = className.length ? [@".objc_class_name_" stringByAppendingString:className] : nil;
        if (marker && [_registry.image.undefinedSymbols containsObject:marker]) {
            state->gpr[3] = state->gpr[4] = 0; state->fpr[1] = 0; state->pc = state->lr;
            return YES;
        }
    }
    if (!receiver || !selector) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Cannot decode Objective-C receiver 0x%08x or selector 0x%08x.",
                                           state->gpr[3], state->gpr[4]]}];
        return NO;
    }
    Class poolClass = NSClassFromString(@"NSAutoreleasePool");
    if (object_isClass(receiver) && receiver == poolClass &&
        ([selectorName isEqualToString:@"alloc"] || [selectorName isEqualToString:@"new"])) {
        uint32_t handle = _nextHandle;
        _nextHandle += 16;
        [_poolHandles addObject:@(handle)];
        state->gpr[3] = handle;
        state->pc = state->lr;
        return YES;
    }
    if ([selectorName isEqualToString:@"release"] || [selectorName isEqualToString:@"autorelease"] ||
        [selectorName isEqualToString:@"retain"]) {
        if ([selectorName isEqualToString:@"retain"] || [selectorName isEqualToString:@"autorelease"])
            state->gpr[3] = [self handleForObject:receiver];
        state->pc = state->lr;
        return YES;
    }
    if ([receiver isKindOfClass:[NSInvocation class]]) {
        BOOL memoryMessageHandled = NO;
        if (![self handleInvocationMemoryMessage:selectorName receiver:receiver state:state
                                           error:error handled:&memoryMessageHandled]) return NO;
        if (memoryMessageHandled) return YES;
    }
    if (object_isClass(receiver) && receiver == [NSBundle class] &&
        [selectorName isEqualToString:@"mainBundle"] && _applicationBundle) {
        state->gpr[3] = [self handleForObject:_applicationBundle];
        state->pc = state->lr;
        return YES;
    }
    if ([selectorName isEqualToString:@"changeClassTo:"]) {
        id target = [self objectAtGuestAddress:state->gpr[5] allowClassName:YES];
        Class currentClass = object_getClass(receiver);
        Class targetClass = target && object_isClass(target) ? (Class)target : Nil;
        BOOL related = targetClass &&
            ([targetClass isSubclassOfClass:currentClass] || [currentClass isSubclassOfClass:targetClass]);
        if (!related || class_getInstanceSize(currentClass) != class_getInstanceSize(targetClass)) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:29
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Unsafe Objective-C class migration from %s to %s.",
                        class_getName(currentClass), targetClass ? class_getName(targetClass) : "(null)"]}];
            return NO;
        }
        object_setClass(receiver, targetClass);
        state->gpr[3] = [self handleForObject:receiver];
        state->pc = state->lr;
        return YES;
    }
    BOOL variadicDictionary = [selectorName isEqualToString:@"dictionaryWithObjectsAndKeys:"] ||
                              [selectorName isEqualToString:@"initWithObjectsAndKeys:"];
    BOOL variadicArray = [selectorName isEqualToString:@"arrayWithObjects:"] ||
                         [selectorName isEqualToString:@"initWithObjects:"];
    BOOL variadicSet = [selectorName isEqualToString:@"setWithObjects:"];
    if (variadicDictionary || variadicArray || variadicSet) {
        NSMutableArray *objects = [NSMutableArray array];
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        NSUInteger argumentIndex = firstArgumentGPR;
        BOOL terminated = NO;
        for (NSUInteger count = 0; count < 4096; count++) {
            uint32_t objectAddress = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, &argumentIndex, &objectAddress)) break;
            if (!objectAddress) { terminated = YES; break; }
            id object = [self objectAtGuestAddress:objectAddress allowClassName:NO];
            if (!object) break;
            if (variadicDictionary) {
                uint32_t keyAddress = 0;
                if (!ReadGuestArgumentWord(_registry.memory, state, &argumentIndex, &keyAddress) ||
                    !keyAddress) break;
                id<NSCopying> key = [self objectAtGuestAddress:keyAddress allowClassName:NO];
                if (!key) break;
                dictionary[key] = object;
            } else {
                [objects addObject:object];
            }
        }
        if (!terminated) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:30
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"%@ has invalid or unterminated guest arguments.",
                                               selectorName]}];
            return NO;
        }
        id result = variadicDictionary ? [dictionary copy]
                  : variadicSet ? [NSSet setWithArray:objects] : [objects copy];
        state->gpr[3] = [self handleForObject:result];
        state->pc = state->lr;
        return YES;
    }
    if ([selectorName isEqualToString:
            @"initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"])
        return [self dispatchBitmapImageInitializer:receiver selector:selector state:state
                                          firstGPR:firstArgumentGPR error:error];
    if ([selectorName isEqualToString:@"initWithAttributes:"] &&
        [receiver isKindOfClass:NSClassFromString(@"NSOpenGLPixelFormat")]) {
        uint32_t guestAttributes = 0;
        NSUInteger argumentGPR = firstArgumentGPR;
        if (!ReadGuestArgumentWord(_registry.memory, state, &argumentGPR, &guestAttributes) ||
            !guestAttributes) return NO;
        NSMutableData *storage = [NSMutableData dataWithLength:256 * sizeof(uint32_t)];
        uint32_t *attributes = storage.mutableBytes;
        BOOL terminated = NO;
        for (NSUInteger index = 0; index < 256; index++) {
            uint32_t value = 0;
            if (![_registry.memory readUInt32:&value
                                      address:guestAttributes + (uint32_t)index * 4]) return NO;
            attributes[index] = value;
            if (!value) { terminated = YES; break; }
        }
        if (!terminated) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:34
                userInfo:@{NSLocalizedDescriptionKey:
                    @"NSOpenGLPixelFormat attributes are not zero-terminated."}];
            return NO;
        }
        id (*initialize)(id, SEL, const uint32_t *) =
            (id (*)(id, SEL, const uint32_t *))[receiver methodForSelector:selector];
        id result = initialize(receiver, selector, attributes);
        state->gpr[3] = [self handleForObject:result];
        state->pc = state->lr;
        return YES;
    }
    if ([selectorName isEqualToString:@"bind:toObject:withKeyPath:options:"] &&
        ![self objectAtGuestAddress:state->gpr[6] allowClassName:YES]) {
        state->gpr[3] = 0;
        state->pc = state->lr;
        return YES;
    }
    if ([receiver isKindOfClass:[NSUserDefaults class]]) {
        if ([selectorName hasPrefix:@"transfer"] &&
            [selectorName rangeOfString:@"Prefs"].location != NSNotFound) {
            state->gpr[3] = 0;
            state->pc = state->lr;
            return YES;
        }
        NSDictionary<NSString *, NSString *> *legacyDefaultsSelectors = @{
            @"setDefaultInt:forKey:": @"setInteger:forKey:",
            @"setDefaultBool:forKey:": @"setBool:forKey:",
            @"setDefaultFloat:forKey:": @"setFloat:forKey:",
            @"setDefaultDouble:forKey:": @"setDouble:forKey:",
            @"setDefaultObject:forKey:": @"setObject:forKey:"
        };
        NSString *modernSelectorName = legacyDefaultsSelectors[selectorName];
        if (modernSelectorName) {
            selectorName = modernSelectorName;
            selector = NSSelectorFromString(modernSelectorName);
        }
    }
    BOOL stringFormatMessage = [selectorName isEqualToString:@"stringWithFormat:"] ||
        [selectorName isEqualToString:@"localizedStringWithFormat:"] ||
        [selectorName isEqualToString:@"initWithFormat:"] ||
        [selectorName isEqualToString:@"initWithFormat:locale:"] ||
        [selectorName isEqualToString:@"appendFormat:"];
    if (stringFormatMessage) {
        id formatObject = [self objectAtGuestAddress:state->gpr[5] allowClassName:NO];
        if (![formatObject isKindOfClass:[NSString class]] || !_registry.guestFormatRenderer ||
            !_registry.guestAllocator || !_registry.guestDeallocator) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:23
                userInfo:@{NSLocalizedDescriptionKey:
                    @"NSString format message has no valid guest format or formatter."}];
            return NO;
        }
        NSData *formatBytes = [(NSString *)formatObject dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t formatAddress = _registry.guestAllocator((uint32_t)formatBytes.length + 1, YES);
        if (!formatAddress || ![_registry.memory writeBytes:formatBytes.bytes address:formatAddress
                                                    length:formatBytes.length]) {
            if (formatAddress) _registry.guestDeallocator(formatAddress);
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:24
                userInfo:@{NSLocalizedDescriptionKey: @"Cannot allocate guest NSString format bytes."}];
            return NO;
        }
        NSUInteger firstVariadicGPR = [selectorName isEqualToString:@"initWithFormat:locale:"] ? 7 : 6;
        NSData *rendered = _registry.guestFormatRenderer(formatAddress, state,
                                                         firstVariadicGPR, error);
        _registry.guestDeallocator(formatAddress);
        if (!rendered) return NO;
        NSString *result = [[NSString alloc] initWithData:rendered encoding:NSUTF8StringEncoding] ?: @"";
        if ([selectorName isEqualToString:@"appendFormat:"]) {
            if (![receiver isKindOfClass:[NSMutableString class]]) {
                if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:25
                    userInfo:@{NSLocalizedDescriptionKey: @"appendFormat: receiver is not mutable."}];
                return NO;
            }
            [(NSMutableString *)receiver appendString:result];
            state->gpr[3] = 0;
        } else {
            state->gpr[3] = [self handleForObject:result];
        }
        state->pc = state->lr;
        return YES;
    }
    if ([selectorName isEqualToString:@"filterWithName:keysAndValues:"] &&
        object_isClass(receiver) && [(Class)receiver isSubclassOfClass:[CIFilter class]]) {
        NSUInteger argumentGPR = firstArgumentGPR;
        uint32_t nameAddress = 0;
        if (!ReadGuestArgumentWord(_registry.memory, state, &argumentGPR, &nameAddress)) return NO;
        id nameObject = [self objectAtGuestAddress:nameAddress allowClassName:NO];
        if (![nameObject isKindOfClass:[NSString class]]) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:27
                userInfo:@{NSLocalizedDescriptionKey: @"CIFilter name is not a guest NSString."}];
            return NO;
        }
        CIFilter *filter = [CIFilter filterWithName:nameObject];
        if (!filter) filter = [BRPPCUnavailableCIFilter new];
        for (NSUInteger pair = 0; pair < 256; pair++) {
            uint32_t keyAddress = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, &argumentGPR, &keyAddress)) return NO;
            if (!keyAddress) break;
            uint32_t valueAddress = 0;
            if (!ReadGuestArgumentWord(_registry.memory, state, &argumentGPR, &valueAddress)) return NO;
            id key = [self objectAtGuestAddress:keyAddress allowClassName:NO];
            id value = [self objectAtGuestAddress:valueAddress allowClassName:YES];
            if (![key isKindOfClass:[NSString class]] || !value) continue;
            @try { [filter setValue:value forKey:key]; }
            @catch (__unused NSException *exception) {
                if ([filter isKindOfClass:[BRPPCUnavailableCIFilter class]])
                    [(BRPPCUnavailableCIFilter *)filter setValue:value forUndefinedKey:key];
            }
        }
        state->gpr[3] = [self handleForObject:filter];
        state->pc = state->lr;
        return YES;
    }
    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
    if (!signature) {
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:2
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"%@ does not respond to %@.", receiver, selectorName]}];
        return NO;
    }
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    NSUInteger gpr = firstArgumentGPR, fpr = 1;
    NSMutableArray *scratch = [NSMutableArray array];
    Class methodClass = object_isClass(receiver) ? object_getClass(receiver) : object_getClass(receiver);
    NSDictionary *guestMethodRecords = objc_getAssociatedObject(methodClass, BRPPCGuestMethodsKey);
    BRPPCGuestMethod *guestMethod = guestMethodRecords[selectorName];
    NSArray<NSString *> *guestTypes = guestMethod ? [self argumentTypesInEncoding:guestMethod.types] : nil;
    for (NSUInteger i = 2; i < signature.numberOfArguments; i++)
        if (![self setInvocationArgument:invocation index:i type:[signature getArgumentTypeAtIndex:i]
                               guestType:i + 1 < guestTypes.count ? guestTypes[i + 1].UTF8String :
                                   (strchr("qQ", *SkipTypeQualifiers([signature getArgumentTypeAtIndex:i]))
                                       ? (*SkipTypeQualifiers([signature getArgumentTypeAtIndex:i]) == 'q' ? "l" : "L")
                                       : [signature getArgumentTypeAtIndex:i])
                                     gpr:&gpr fpr:&fpr state:state scratch:scratch error:error]) return NO;
    SEL immediateSelector = NULL;
    __unsafe_unretained id immediateObject = nil;
    id compatibilityReturn = nil;
    BOOL deliverSelectorImmediately = NO;
    BOOL autoDismissAlert = getenv("BISMUTH_AUTO_DISMISS_ALERTS") &&
        [selectorName isEqualToString:@"runModal"] && [receiver isKindOfClass:[NSAlert class]];
    if (getenv("BISMUTH_ALERT_TRACE") && [selectorName isEqualToString:@"runModal"] &&
        [receiver isKindOfClass:[NSAlert class]]) {
        NSAlert *alert = receiver;
        fprintf(BRPPCUITraceStream(), "guest alert message=%s informative=%s\n",
                alert.messageText.UTF8String ?: "", alert.informativeText.UTF8String ?: "");
    }
    if ([selectorName isEqualToString:@"performSelector:withObject:afterDelay:"]) {
        NSTimeInterval delay = 0;
        [invocation getArgument:&immediateSelector atIndex:2];
        [invocation getArgument:&immediateObject atIndex:3];
        [invocation getArgument:&delay atIndex:4];
        deliverSelectorImmediately = immediateSelector && delay <= 0;
    }
    BRPPCState previousActiveState = _activeState;
    BOOL previouslyActive = _hasActiveState;
    _activeState = *state;
    _hasActiveState = YES;
    self.callbackError = nil;
    id legacyOpenGLImage = nil;
    NSView *legacyOpenGLView = nil;
    BOOL presentsLegacyOpenGL = [selectorName isEqualToString:@"flushBuffer"] &&
        [receiver isKindOfClass:NSClassFromString(@"NSOpenGLContext")] &&
        !BRPPCLegacyOpenGLPresentationActive;
    if (presentsLegacyOpenGL) BRPPCLegacyOpenGLPresentationActive = YES;
    if ([selectorName isEqualToString:@"makeKeyAndOrderFront:"] &&
        [receiver isKindOfClass:[NSWindow class]]) {
        NSWindow *window = receiver;
        window.collectionBehavior =
            (window.collectionBehavior & ~NSWindowCollectionBehaviorMoveToActiveSpace) |
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary;
        window.alphaValue = 1.0;
        window.level = NSNormalWindowLevel;
    }
    @try {
        if ([selectorName isEqualToString:@"run"] && [receiver isKindOfClass:[NSApplication class]]) {
            [(NSApplication *)receiver finishLaunching];
            id delegate = [(NSApplication *)receiver delegate];
            SEL launchSelector = @selector(applicationDidFinishLaunching:);
            if (!_launchCallbackDelivered && [delegate respondsToSelector:launchSelector]) {
                NSNotification *notification = [NSNotification
                    notificationWithName:NSApplicationDidFinishLaunchingNotification object:receiver];
                void (*call)(id, SEL, id) = (void (*)(id, SEL, id))[delegate methodForSelector:launchSelector];
                call(delegate, launchSelector, notification);
                if (_callbackError) {
                    _activeState = previousActiveState;
                    _hasActiveState = previouslyActive;
                    if (error) *error = _callbackError;
                    return NO;
                }
            }
        }
        if (autoDismissAlert) {
            NSAlert *alert = receiver;
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSApp abortModal];
                [alert.window orderOut:nil];
            });
            [invocation invoke];
        } else if (deliverSelectorImmediately) {
            NSMethodSignature *delayedSignature = [receiver methodSignatureForSelector:immediateSelector];
            if (!delayedSignature) {
                [receiver doesNotRecognizeSelector:immediateSelector];
            } else {
                NSInvocation *delayedInvocation =
                    [NSInvocation invocationWithMethodSignature:delayedSignature];
                delayedInvocation.target = receiver;
                delayedInvocation.selector = immediateSelector;
                if (delayedSignature.numberOfArguments > 2)
                    [delayedInvocation setArgument:&immediateObject atIndex:2];
                [delayedInvocation invoke];
            }
        } else {
            [invocation invoke];
        }
        if ([selectorName isEqualToString:@"makeKeyAndOrderFront:"] &&
            [receiver isKindOfClass:[NSWindow class]]) {
            NSWindow *window = receiver;
            [window setFrame:window.frame display:YES];
            [window displayIfNeeded];
            BRPPCActivateHostWindow(window);
            [NSApp arrangeInFront:nil];
            [NSApp updateWindows];
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        }
        if (presentsLegacyOpenGL) {
            id context = receiver;
            NSView *contextView = [context valueForKey:@"view"];
            NSNumber *nextTime = objc_getAssociatedObject(
                context, BRPPCLegacyOpenGLPresentationTimeKey);
            CFTimeInterval now = CACurrentMediaTime();
            NSInteger refreshRate = contextView.window.screen.maximumFramesPerSecond;
            CFTimeInterval frameInterval = refreshRate > 0 ? 1.0 / refreshRate : 0;
            BOOL presentationDue = !nextTime || refreshRate <= 0 ||
                now >= nextTime.doubleValue;
            CGImageRef image = presentationDue
                ? BRPPCCopyOpenGLBackBuffer(context, &legacyOpenGLView) : NULL;
            if (image) {
                CFTimeInterval nextDeadline = now + frameInterval;
                if (nextTime && now - nextTime.doubleValue < frameInterval)
                    nextDeadline = nextTime.doubleValue + frameInterval;
                objc_setAssociatedObject(context, BRPPCLegacyOpenGLPresentationTimeKey,
                    @(nextDeadline), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (image) legacyOpenGLImage = CFBridgingRelease(image);
            if (legacyOpenGLImage && legacyOpenGLView) {
                NSView *view = legacyOpenGLView;
                if (view.window) {



                    BRPPCPassthroughImageView *imageView = objc_getAssociatedObject(
                        context, BRPPCLegacyOpenGLPresentationViewKey);
                    NSView *container = view.superview ?: view;
                    NSRect frame = view.superview
                        ? [container convertRect:view.bounds fromView:view] : view.bounds;
                    if (!imageView) {
                        imageView = [[BRPPCPassthroughImageView alloc] initWithFrame:frame];
                        imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                        imageView.imageScaling = NSImageScaleAxesIndependently;
                        imageView.wantsLayer = YES;
                        CALayer *presentationLayer = [CALayer layer];
                        presentationLayer.frame = imageView.layer.bounds;
                        presentationLayer.contentsGravity = kCAGravityResize;
                        presentationLayer.opaque = YES;
                        presentationLayer.contentsFormat = kCAContentsFormatRGBA8Uint;
                        presentationLayer.contentsScale = view.window.backingScaleFactor;
                        presentationLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0);
                        [imageView.layer addSublayer:presentationLayer];
                        [container addSubview:imageView positioned:NSWindowAbove
                                  relativeTo:(container == view ? nil : view)];
                        GLint surfaceOrder = -1;
                        [context setValues:&surfaceOrder forParameter:235];
                        GLint surfaceOpaque = 0;
                        [context setValues:&surfaceOpaque forParameter:236];
                        [context update];
                        objc_setAssociatedObject(context,
                            BRPPCLegacyOpenGLPresentationViewKey, imageView,
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        objc_setAssociatedObject(context,
                            BRPPCLegacyOpenGLPresentationLayerKey, presentationLayer,
                            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    CALayer *presentationLayer = objc_getAssociatedObject(
                        context, BRPPCLegacyOpenGLPresentationLayerKey);
                    [CATransaction begin];
                    [CATransaction setDisableActions:YES];
                    if (!NSEqualRects(imageView.frame, frame)) imageView.frame = frame;
                    if (!CGRectEqualToRect(presentationLayer.frame, imageView.layer.bounds))
                        presentationLayer.frame = imageView.layer.bounds;
                    presentationLayer.contents = legacyOpenGLImage;
                    [CATransaction commit];
                    [CATransaction flush];
                }
            }
        }
    } @catch (NSException *exception) {
        if (presentsLegacyOpenGL) BRPPCLegacyOpenGLPresentationActive = NO;
        _activeState = previousActiveState;
        _hasActiveState = previouslyActive;
        if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        return NO;
    }
    if (presentsLegacyOpenGL) BRPPCLegacyOpenGLPresentationActive = NO;
    _activeState = previousActiveState;
    _hasActiveState = previouslyActive;
    for (id item in scratch) {
        if (![item isKindOfClass:[BRPPCPointerScratch class]]) continue;
        BRPPCPointerScratch *record = item;
        if (record.copyBack && ![self writeHostData:record.hostData guestAddress:record.guestAddress
                                               type:record.type.UTF8String error:error]) return NO;
    }
    if (_callbackError) {
        if (error) *error = _callbackError;
        return NO;
    }
    if ([selectorName hasPrefix:@"filterWithName:"] &&
        *SkipTypeQualifiers(signature.methodReturnType) == '@') {
        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        if (!result) {
            compatibilityReturn = [BRPPCUnavailableCIFilter new];
            __unsafe_unretained id returnedFilter = compatibilityReturn;
            [invocation setReturnValue:&returnedFilter];
        }
    }
    if (traceEnabled && [selectorName isEqualToString:@"setDelegate:"] &&
        [receiver respondsToSelector:@selector(delegate)]) {
        id delegate = [receiver valueForKey:@"delegate"];
        fprintf(stderr, "objc delegate=%s didFinish=%s\n",
                class_getName(object_getClass(delegate)),
                [delegate respondsToSelector:@selector(applicationDidFinishLaunching:)] ? "yes" : "no");
    }
    const char *hostReturn = SkipTypeQualifiers(signature.methodReturnType);
    const char *guestReturn = guestTypes.count ? guestTypes[0].UTF8String
        : (*hostReturn == 'q' ? "l" : *hostReturn == 'Q' ? "L" : signature.methodReturnType);
    if (![self copyInvocationReturn:invocation state:state guestAddress:structureReturnAddress
                          guestType:guestReturn error:error]) return NO;
    if ([selectorName isEqualToString:@"occlusionState"] &&
        [receiver isKindOfClass:[NSWindow class]]) {
        NSWindow *window = receiver;



        if (window.isVisible && !window.isMiniaturized && window.isKeyWindow &&
            window.isMainWindow && NSApp.isActive && window.screen)
            state->gpr[3] |= (uint32_t)NSWindowOcclusionStateVisible;
    }
    if (tracesMessage)
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc host message return selector=%s r3=0x%08x\n",
                selectorName.UTF8String, state->gpr[3]);
    if (tracesMessage && [selectorName isEqualToString:@"occlusionState"] &&
        [receiver isKindOfClass:[NSWindow class]]) {
        NSWindow *window = receiver;
        fprintf(BRPPCObjectiveCTraceStream(),
                "objc host window visible=%d mini=%d key=%d main=%d appActive=%d screen=%d\n",
                window.isVisible, window.isMiniaturized, window.isKeyWindow,
                window.isMainWindow, NSApp.isActive, window.screen != nil);
    }
    if (traceEnabled && *hostReturn == '@')
        fprintf(stderr, "objc host return selector=%s handle=0x%08x\n",
                selectorName.UTF8String, state->gpr[3]);
    if ([selectorName isEqualToString:@"sharedApplication"] && state->gpr[3])
        [_registry.memory writeUInt32:state->gpr[3] address:BRPPCGuestObjectiveCDataBase];
    state->pc = state->lr;
    return YES;
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    self.registry = registry;
    self.objects = [NSMapTable strongToStrongObjectsMapTable];
    self.retainedObjects = [NSMutableDictionary dictionary];
    self.handles = [NSMutableDictionary dictionary];
    self.poolHandles = [NSMutableSet set];
    self.selectorAddresses = [NSMutableDictionary dictionary];
    self.guestClassesByAddress = [NSMutableDictionary dictionary];
    self.activeGuestMethods = [NSMutableArray array];
    self.guestExecutionLock = [NSRecursiveLock new];
    self.guestVoidPointers = [NSMutableDictionary dictionary];
    self.hostVoidPointers = [NSMutableDictionary dictionary];
    self.nextSelectorAddress = BRPPCGuestObjectiveCDataBase +
        BRPPCGuestObjectiveCSelectorOffset;
    self.nextHandle = BRPPCGuestObjectHandleBase;
    __weak typeof(self) objectBridgeSelf = self;
    registry.guestObjectDecoder = ^id(uint32_t address) {
        return [objectBridgeSelf objectAtGuestAddress:address allowClassName:YES];
    };
    registry.guestObjectEncoder = ^uint32_t(id object) {
        return [objectBridgeSelf handleForObject:object];
    };
    [self registerGuestClasses];
    __weak typeof(self) weakSelf = self;
    if (![registry.memory mapAddress:BRPPCGuestObjectiveCDataBase
                                size:BRPPCGuestObjectiveCDataSize
                          protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                name:@"Objective-C globals" error:error] ||
        ![registry.memory mapAddress:BRPPCGuestCallbackDataBase size:BRPPCGuestCallbackDataSize
                          protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                name:@"Objective-C callback scratch" error:error] ||
        ![registry.memory mapAddress:BRPPCGuestCallbackStackBase size:BRPPCGuestCallbackStackSize
                          protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                name:@"guest callback stacks" error:error] ||
        ![registry.memory mapAddress:BRPPCGuestObjectHandleBase size:BRPPCGuestObjectStorageSize
                          protection:BRPPCMemoryRead | BRPPCMemoryWrite
                                name:@"Objective-C guest objects" error:error]) return NO;
    uint32_t markerAddress = BRPPCGuestObjectiveCDataBase + 4;
    for (NSString *symbol in registry.image.undefinedSymbols) {
        if (![symbol hasPrefix:@".objc_class_name_"] &&
            ![symbol isEqualToString:@"___CFConstantStringClassReference"]) continue;
        if ([registry addressForSymbol:symbol]) continue;
        if (markerAddress >= BRPPCGuestObjectiveCDataBase +
                             BRPPCGuestObjectiveCSelectorOffset) {
            if (error) *error = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:21
                userInfo:@{NSLocalizedDescriptionKey: @"Objective-C class marker table is full."}];
            return NO;
        }
        uint32_t address = markerAddress; markerAddress += 4;
        if (![registry registerSymbol:symbol atAddress:address
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                (void)state;
                if (callError) *callError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:22
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"%@ is Objective-C marker data.", symbol]}];
                return NO;
            } error:error]) return NO;
    }
    if (![registry registerSymbol:@"_NSApp" atAddress:BRPPCGuestObjectiveCDataBase
                           handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)state;
        if (callError) *callError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:7
            userInfo:@{NSLocalizedDescriptionKey: @"NSApp is data, not callable code."}];
        return NO;
    } error:error]) return NO;
    if (![registry registerSymbol:@"_objc_msgSend_legacy"
                          atAddress:BRPPCGuestLegacyObjCDispatchAddress
                            handler:^BOOL(BRPPCState *state, NSError **callError) {
        return [weakSelf dispatchMessage:state error:callError];
    } error:error]) return NO;
    [registry registerSymbol:@"_objc_msgSendSuper" handler:^BOOL(BRPPCState *state, NSError **callError) {
        return [weakSelf dispatchSuperMessage:state structureReturn:NO error:callError];
    }];
    [registry registerSymbol:@"_objc_msgSendSuper_stret" handler:^BOOL(BRPPCState *state, NSError **callError) {
        return [weakSelf dispatchSuperMessage:state structureReturn:YES error:callError];
    }];
    for (NSString *symbol in @[@"_objc_msgSend", @"_objc_msgSend_fpret"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            return [weakSelf dispatchMessage:state error:callError];
        }];
    [registry registerSymbol:@"_objc_msgSend_stret"
                      handler:^BOOL(BRPPCState *state, NSError **callError) {
        if (!state->gpr[4]) {
            state->pc = state->lr;
            return YES;
        }
        return [weakSelf dispatchMessage:state error:callError];
    }];
    [registry registerSymbol:@"_objc_getClass" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        NSString *name = [registry.memory readCStringAtAddress:state->gpr[3] maximumLength:1024];
        state->gpr[3] = [weakSelf handleForObject:name.length ? NSClassFromString(name) : Nil];
        state->pc = state->lr;
        return YES;
    }];
    for (NSString *symbol in @[@"_objc_sync_enter", @"_objc_sync_exit"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            id object = [weakSelf objectAtGuestAddress:state->gpr[3] allowClassName:YES];
            int result = [symbol hasSuffix:@"enter"] ? objc_sync_enter(object) : objc_sync_exit(object);
            state->gpr[3] = (uint32_t)result;
            state->pc = state->lr;
            return YES;
        }];
    [registry registerSymbol:@"_objc_enumerationMutation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id object = [weakSelf objectAtGuestAddress:state->gpr[3] allowClassName:NO];
        if (getenv("BISMUTH_OBJC_TRACE")) fprintf(stderr, "objc_enumerationMutation object=%s\n", [[object description] UTF8String]);
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_objc_setProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t objectAddress = state->gpr[3];
        id object = [weakSelf objectAtGuestAddress:objectAddress allowClassName:NO];
        id value = [weakSelf objectAtGuestAddress:state->gpr[6] allowClassName:NO];
        if (state->gpr[8] && [value conformsToProtocol:@protocol(NSCopying)]) value = [value copy];
        int32_t offset = (int32_t)state->gpr[5];
        uint32_t valueAddress = [weakSelf handleForObject:value];
        BOOL atomic = state->gpr[7] != 0;
        if (atomic && object) objc_sync_enter(object);
        BOOL wrote = objectAddress &&
            [registry.memory writeUInt32:valueAddress address:objectAddress + (uint32_t)offset];
        if (atomic && object) objc_sync_exit(object);
        if (!wrote) {
            if (callError) *callError = [NSError errorWithDomain:BRPPCObjectiveCErrorDomain code:29
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Cannot store Objective-C property at 0x%08x%+d.",
                                               objectAddress, offset]}];
            return NO;
        }
        state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_objc_exception_try_enter", @"_objc_exception_try_exit"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; if ([symbol hasSuffix:@"enter"] && state->gpr[3]) {
                uint8_t zero[32] = {0}; if (![registry.memory writeBytes:zero address:state->gpr[3] length:sizeof(zero)]) return NO;
            }
            state->gpr[3] = 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_objc_exception_extract" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t exception = 0; if (state->gpr[3]) [registry.memory readUInt32:&exception address:state->gpr[3]];
        state->gpr[3] = exception; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_objc_exception_match" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id expected = [weakSelf objectAtGuestAddress:state->gpr[3] allowClassName:YES];
        id exception = [weakSelf objectAtGuestAddress:state->gpr[4] allowClassName:NO];
        state->gpr[3] = expected && exception && [exception isKindOfClass:expected]; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_objc_exception_throw" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id exception = [weakSelf objectAtGuestAddress:state->gpr[3] allowClassName:NO];
        if (callError) *callError = [NSError errorWithDomain:@"theoderoy.Bismuth.objective-c" code:30
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Guest Objective-C exception: %@", exception ?: @"(null)"]}];
        return NO;
    }];
    return YES;
}

@end
