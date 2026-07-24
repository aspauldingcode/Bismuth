#import "BRPPCCocoaResolve.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCMachOLoader.h"
#import "BRPPCObjectiveCResolve.h"
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/runtime.h>

static NSString * const BRPPCCocoaErrorDomain = @"theoderoy.Bismuth.cocoa";
static const void *BRPPCDynamicValuesKey = &BRPPCDynamicValuesKey;
static __strong NSBundle *BRPPCGuestMainBundle;
static IMP BRPPCOriginalMainBundleImplementation;
static IMP BRPPCOriginalNextStepFrameNeedsFillImplementation;
static IMP BRPPCFallbackNextStepFrameNeedsFillImplementation;
static _Thread_local NSUInteger BRPPCNextStepFrameNeedsFillDepth;

static BOOL BRPPCNextStepFrameNeedsFill(id receiver, SEL selector) {
    BOOL (*implementation)(id, SEL) = (BOOL (*)(id, SEL))
        (BRPPCNextStepFrameNeedsFillDepth
            ? BRPPCFallbackNextStepFrameNeedsFillImplementation
            : BRPPCOriginalNextStepFrameNeedsFillImplementation);
    if (!implementation) return NO;
    BRPPCNextStepFrameNeedsFillDepth++;
    @try {
        return implementation(receiver, selector);
    } @finally {
        BRPPCNextStepFrameNeedsFillDepth--;
    }
}

static FILE *BRPPCCocoaTraceStream(void) {
    static FILE *stream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char *path = getenv("BISMUTH_COCOA_TRACE_FILE");
        stream = path && *path ? fopen(path, "a") : stderr;
        if (!stream) stream = stderr;
        setvbuf(stream, NULL, _IOLBF, 0);
    });
    return stream;
}

static void BRPPCCocoaTraceViewTree(NSView *view, NSUInteger depth) {
    if (!view || depth > 5) return;
    NSRect frame = view.frame;
    fprintf(BRPPCCocoaTraceStream(),
            "cocoa view depth=%lu class=%s frame=%.0f,%.0f %.0fx%.0f hidden=%d alpha=%.2f subviews=%lu\n",
            (unsigned long)depth, NSStringFromClass(view.class).UTF8String,
            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
            view.isHidden, view.alphaValue, (unsigned long)view.subviews.count);
    for (NSView *subview in view.subviews)
        BRPPCCocoaTraceViewTree(subview, depth + 1);
}

static NSUInteger BRPPCViewDescendantCount(NSView *view) {
    NSUInteger count = view.subviews.count;
    for (NSView *subview in view.subviews)
        count += BRPPCViewDescendantCount(subview);
    return count;
}

static void BRPPCMarkViewTreeNeedsDisplay(NSView *view) {
    view.needsDisplay = YES;
    for (NSView *subview in view.subviews)
        BRPPCMarkViewTreeNeedsDisplay(subview);
}

static void BRPPCNormalizePrimaryWindow(NSWindow *window) {
    window.alphaValue = 1.0;
    window.level = NSNormalWindowLevel;
    NSColor *background = [window.backgroundColor
        colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    if (window.styleMask != NSWindowStyleMaskBorderless &&
        (!background || background.alphaComponent <= 0.01)) {
        window.backgroundColor = NSColor.windowBackgroundColor;
        window.opaque = YES;
    }
    SEL sharingTypeSelector = NSSelectorFromString(@"sharingType");
    SEL setSharingTypeSelector = NSSelectorFromString(@"setSharingType:");
    if ([window respondsToSelector:sharingTypeSelector] &&
        [window respondsToSelector:setSharingTypeSelector]) {
        NSInteger sharingType = ((NSInteger (*)(id, SEL))
            [window methodForSelector:sharingTypeSelector])(window, sharingTypeSelector);
        if (sharingType == 0)
            ((void (*)(id, SEL, NSInteger))[window methodForSelector:setSharingTypeSelector])
                (window, setSharingTypeSelector, 1);
    }
}

static NSView *BRPPCReconcileWindowContent(NSWindow *window,
                                            BRPPCObjectiveCResolve *objectiveCBridge) {
    NSView *contentView = window.contentView;
    NSUInteger contentDescendants = BRPPCViewDescendantCount(contentView);
    BOOL trace = getenv("BISMUTH_COCOA_TRACE") != NULL;
    if (trace)
        fprintf(BRPPCCocoaTraceStream(),
                "cocoa reconcile window=%s content=%s size=%.0fx%.0f descendants=%lu\n",
                window.title.UTF8String, NSStringFromClass(contentView.class).UTF8String,
                contentView.bounds.size.width, contentView.bounds.size.height,
                (unsigned long)contentDescendants);
    NSView *orphanRoot = nil;
    NSUInteger orphanDescendants = 0;
    NSMutableSet<NSValue *> *seenRoots = [NSMutableSet set];
    for (id object in objectiveCBridge.hostObjectsSnapshot) {
        if (![object isKindOfClass:[NSView class]]) continue;
        NSView *root = object;
        while (root.superview && root.superview != contentView)
            root = root.superview;
        NSValue *rootIdentity = [NSValue valueWithNonretainedObject:root];
        if ([seenRoots containsObject:rootIdentity]) continue;
        [seenRoots addObject:rootIdentity];
        NSSize rootSize = root.frame.size;
        NSUInteger descendants = BRPPCViewDescendantCount(root);
        if (root == contentView || root.superview == contentView ||
            [contentView isDescendantOf:root] ||
            (root.window && root.window != window)) continue;
        NSSize contentSize = window.contentLayoutRect.size;
        if (contentSize.width <= 0.0 || contentSize.height <= 0.0)
            contentSize = contentView.bounds.size;
        NSSize conventionalContentSize =
            [NSWindow contentRectForFrameRect:window.frame styleMask:window.styleMask].size;
        BOOL matchesLayout = fabs(rootSize.width - contentSize.width) <= 2.0 &&
            fabs(rootSize.height - contentSize.height) <= 2.0;
        BOOL matchesConventionalContent =
            fabs(rootSize.width - conventionalContentSize.width) <= 2.0 &&
            fabs(rootSize.height - conventionalContentSize.height) <= 2.0;
        CGFloat titlebarInset = contentView.bounds.size.height - rootSize.height;
        BOOL matchesTitlebarInset = fabs(rootSize.width - contentView.bounds.size.width) <= 2.0 &&
            titlebarInset >= 0.0 && titlebarInset <= 64.0;
        if (!matchesLayout && !matchesConventionalContent && !matchesTitlebarInset) continue;
        if (trace)
            fprintf(BRPPCCocoaTraceStream(),
                    "cocoa reconcile candidate=%s size=%.0fx%.0f descendants=%lu window=%s\n",
                    NSStringFromClass(root.class).UTF8String, rootSize.width, rootSize.height,
                    (unsigned long)descendants, root.window.title.UTF8String ?: "(none)");
        if (descendants > contentDescendants && descendants > orphanDescendants) {
            orphanRoot = root;
            orphanDescendants = descendants;
        }
    }
    if (orphanRoot) {
        if (trace)
            fprintf(BRPPCCocoaTraceStream(), "cocoa reconcile attach=%s descendants=%lu\n",
                    NSStringFromClass(orphanRoot.class).UTF8String,
                    (unsigned long)orphanDescendants);
        [window setContentView:orphanRoot];
        contentView = window.contentView;
    }
    BRPPCMarkViewTreeNeedsDisplay(contentView);
    return contentView;
}

static id BRPPCMainBundle(id receiver, SEL selector) {
    if (BRPPCGuestMainBundle) return BRPPCGuestMainBundle;
    id (*original)(id, SEL) = (id (*)(id, SEL))BRPPCOriginalMainBundleImplementation;
    return original ? original(receiver, selector) : nil;
}

@interface BRPPCCocoaGuestObject : NSObject
@end

@implementation BRPPCCocoaGuestObject
- (NSMutableDictionary *)br_values {
    NSMutableDictionary *values = objc_getAssociatedObject(self, BRPPCDynamicValuesKey);
    if (!values) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, BRPPCDynamicValuesKey, values, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return values;
}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    [self br_values][key] = value ?: [NSNull null];
}
- (id)valueForUndefinedKey:(NSString *)key {
    id value = [self br_values][key];
    return value == [NSNull null] ? nil : value;
}
@end

static NSString *PropertyForSetter(SEL selector) {
    NSString *name = NSStringFromSelector(selector);
    if (![name hasPrefix:@"set"] || ![name hasSuffix:@":"] || name.length < 5) return name;
    NSString *stem = [name substringWithRange:NSMakeRange(3, name.length - 4)];
    return [[stem substringToIndex:1].lowercaseString stringByAppendingString:[stem substringFromIndex:1]];
}
static NSMutableDictionary *BRPPCGuestValues(id object) {
    NSMutableDictionary *values = objc_getAssociatedObject(object, BRPPCDynamicValuesKey);
    if (!values) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(object, BRPPCDynamicValuesKey, values, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return values;
}
static void BRPPCGuestVoid0(id self, SEL selector) { (void)self; (void)selector; }
static void BRPPCGuestVoid1(id self, SEL selector, id value) {
    BRPPCGuestValues(self)[PropertyForSetter(selector)] = value ?: [NSNull null];
}
static id BRPPCGuestObject0(id self, SEL selector) {
    if (selector == @selector(init)) return self;
    id value = BRPPCGuestValues(self)[NSStringFromSelector(selector)];
    return value == [NSNull null] ? nil : value;
}
static id BRPPCGuestObject1(id self, SEL selector, id value) {
    (void)value;
    id result = BRPPCGuestValues(self)[NSStringFromSelector(selector)];
    return result == [NSNull null] ? nil : result;
}

@interface BRPPCCocoaResolve ()
@property(nonatomic, strong, nullable) NSURL *bundleURL;
@property(nonatomic, strong) NSArray *topLevelObjects;
@end


@implementation BRPPCCocoaResolve
- (instancetype)initWithApplicationBundleURL:(nullable NSURL *)bundleURL {
    if ((self = [super init])) _bundleURL = bundleURL;
    return self;
}

- (void)registerLegacyClassesFromImage:(BRPPCMachOImage *)image
                                 memory:(BRPPCAddressSpace *)memory {
    BRPPCMachOSection *classes = [image sectionInSegment:@"__OBJC" name:@"__class"];
    if (!classes || classes.size % 48) return;
    for (uint32_t offset = 0; offset < classes.size; offset += 48) {
        uint32_t base = classes.address + offset, superclassAddress = 0;
        uint32_t nameAddress = 0, methodsAddress = 0;
        if (![memory readUInt32:&nameAddress address:base + 8] ||
            ![memory readUInt32:&methodsAddress address:base + 28]) continue;
        NSString *name = [memory readCStringAtAddress:nameAddress maximumLength:512];
        if (!name.length || NSClassFromString(name)) continue;
        Class superclass = Nil;
        if ([memory readUInt32:&superclassAddress address:base + 4] && superclassAddress) {
            NSString *superclassName = [memory readCStringAtAddress:superclassAddress
                                                      maximumLength:512];
            superclass = NSClassFromString(superclassName);
            if (getenv("BISMUTH_SCARLET_TRACE"))
                fprintf(stderr, "class %s superclass %s at 0x%08x\n", name.UTF8String,
                        superclassName.UTF8String, superclassAddress);
        }
        if (!superclass) superclass = [BRPPCCocoaGuestObject class];
        Class cls = objc_allocateClassPair(superclass, name.UTF8String, 0);
        if (!cls) continue;
        uint32_t count = 0;
        if (methodsAddress && [memory readUInt32:&count address:methodsAddress + 4] && count < 4096) {
            for (uint32_t i = 0; i < count; i++) {
                uint32_t method = methodsAddress + 8 + i * 12;
                uint32_t selectorAddress = 0, typesAddress = 0;
                if (![memory readUInt32:&selectorAddress address:method] ||
                    ![memory readUInt32:&typesAddress address:method + 4]) continue;
                NSString *selectorName = [memory readCStringAtAddress:selectorAddress maximumLength:1024];
                NSString *types = [memory readCStringAtAddress:typesAddress maximumLength:1024];
                if (!selectorName.length || !types.length) continue;
                SEL selector = NSSelectorFromString(selectorName);
                NSUInteger colons = 0;
                NSUInteger selectorLength = selectorName.length;
                for (NSUInteger index = 0; index < selectorLength; index++)
                    colons += [selectorName characterAtIndex:index] == ':';
                IMP implementation;
                if ([types hasPrefix:@"v"])
                    implementation = colons ? (IMP)BRPPCGuestVoid1 : (IMP)BRPPCGuestVoid0;
                else
                    implementation = colons ? (IMP)BRPPCGuestObject1 : (IMP)BRPPCGuestObject0;
                class_addMethod(cls, selector, implementation, types.UTF8String);
            }
        }
        objc_registerClassPair(cls);
    }
}

- (BOOL)runGuestApplicationWithRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    Method mainBundleMethod = NULL;
    IMP previousMainBundleImplementation = NULL;
    Method nextStepNeedsFillMethod = NULL;
    IMP previousNextStepNeedsFillImplementation = NULL;
    @try {
    if (!_bundleURL) {
        if (error) *error = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey:
                @"NSApplicationMain requires an application bundle; a direct executable has none."}];
        return NO;
    }
    NSBundle *bundle = [NSBundle bundleWithURL:_bundleURL];
    if (!bundle) {
        if (error) *error = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot open guest application bundle."}];
        return NO;
    }
    mainBundleMethod = class_getClassMethod([NSBundle class], @selector(mainBundle));
    if (mainBundleMethod) {
        BRPPCGuestMainBundle = bundle;
        previousMainBundleImplementation = method_setImplementation(
            mainBundleMethod, (IMP)BRPPCMainBundle);
        BRPPCOriginalMainBundleImplementation = previousMainBundleImplementation;
    }
    NSDictionary *info = bundle.infoDictionary;
    NSString *principalName = info[@"NSPrincipalClass"] ?: @"NSApplication";
    Class principalClass = NSClassFromString(principalName) ?: [NSApplication class];
    Method sharedApplicationMethod = class_getClassMethod([NSApplication class],
                                                           @selector(sharedApplication));
    NSApplication *(*createSharedApplication)(id, SEL) =
        (NSApplication *(*)(id, SEL))method_getImplementation(sharedApplicationMethod);
    NSApplication *application = createSharedApplication(principalClass,
                                                          @selector(sharedApplication));
    NSApp = application;


    Class nextStepFrameClass = NSClassFromString(@"NSNextStepFrame");
    Class nextStepFrameSuperclass = class_getSuperclass(nextStepFrameClass);
    SEL needsFillSelector = NSSelectorFromString(@"needsFill");
    nextStepNeedsFillMethod = class_getInstanceMethod(nextStepFrameClass, needsFillSelector);
    Method inheritedNeedsFillMethod = class_getInstanceMethod(nextStepFrameSuperclass, needsFillSelector);
    if (nextStepNeedsFillMethod && inheritedNeedsFillMethod) {
        BRPPCOriginalNextStepFrameNeedsFillImplementation =
            method_getImplementation(nextStepNeedsFillMethod);
        BRPPCFallbackNextStepFrameNeedsFillImplementation =
            method_getImplementation(inheritedNeedsFillMethod);
        previousNextStepNeedsFillImplementation = method_setImplementation(
            nextStepNeedsFillMethod, (IMP)BRPPCNextStepFrameNeedsFill);
    }
    uint32_t guestNSAppAddress = [registry addressForSymbol:@"_NSApp"];
    if (guestNSAppAddress && registry.guestObjectEncoder) {
        uint32_t guestApplication = registry.guestObjectEncoder(application);
        if (![registry.memory writeUInt32:guestApplication address:guestNSAppAddress]) {
            if (error) *error = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Cannot publish NSApp to guest application memory."}];
            return NO;
        }
    }
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (getenv("BISMUTH_COCOA_TRACE"))
        fprintf(BRPPCCocoaTraceStream(), "cocoa principal=%s nib=%s\n", principalName.UTF8String,
                [info[@"NSMainNibFile"] UTF8String]);
    NSString *nibName = info[@"NSMainNibFile"];
    if (nibName.length) {
        NSNib *nib = [[NSNib alloc] initWithNibNamed:nibName bundle:bundle];
        NSArray *objects = nil;
        NSApp = application;
        if (getenv("BISMUTH_COCOA_TRACE"))
            fprintf(BRPPCCocoaTraceStream(), "cocoa app=%p NSApp=%p\n", application, NSApp);
        if (!nib || ![nib instantiateWithOwner:application topLevelObjects:&objects]) {
            if (error) *error = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Cannot instantiate guest main nib %@.", nibName]}];
            return NO;
        }
        self.topLevelObjects = objects;
        if (getenv("BISMUTH_COCOA_TRACE")) {
            id delegate = application.delegate;
            fprintf(BRPPCCocoaTraceStream(), "cocoa delegate=%s didFinish=%d\n",
                    delegate ? class_getName(object_getClass(delegate)) : "(null)",
                    [delegate respondsToSelector:@selector(applicationDidFinishLaunching:)]);
        }
        [application finishLaunching];
        NSWindow *declaredMainWindow = application.mainWindow;
        NSString *applicationName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"];
        NSWindow *primaryWindow = declaredMainWindow;
        CGFloat primaryScore = -1;
        for (NSWindow *window in application.windows) {
            if (!declaredMainWindow && ![window isKindOfClass:[NSPanel class]] &&
                window.styleMask != NSWindowStyleMaskBorderless) {
                NSSize size = window.frame.size;
                CGFloat score = size.width * size.height;
                if (applicationName.length && [window.title isEqualToString:applicationName])
                    score += 1000000000.0;
                if (window.canBecomeMainWindow) score += 1000000.0;
                if (score > primaryScore) {
                    primaryWindow = window;
                    primaryScore = score;
                }
            }
            if (getenv("BISMUTH_COCOA_TRACE"))
                fprintf(BRPPCCocoaTraceStream(), "cocoa window=%p class=%s title=%s visible=%d keyable=%d style=0x%lx\n",
                        window, NSStringFromClass(window.class).UTF8String, window.title.UTF8String,
                        window.isVisible, window.canBecomeKeyWindow, (unsigned long)window.styleMask);
        }
        if (primaryWindow) {
            BRPPCReconcileWindowContent(primaryWindow, self.objectiveCBridge);
            BRPPCNormalizePrimaryWindow(primaryWindow);
            NSRect frame = primaryWindow.frame;
            if (frame.size.width > 0.0 && frame.size.height > 0.0)
                [primaryWindow setFrame:frame display:YES];
            [primaryWindow makeKeyAndOrderFront:nil];
            primaryWindow.viewsNeedDisplay = YES;
            [primaryWindow displayIfNeeded];
        }
        NSTimeInterval searchStarted = NSDate.timeIntervalSinceReferenceDate;
        NSTimer *primaryWindowTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES
                                                               block:^(NSTimer *timer) {
                NSWindow *deferredPrimary = application.mainWindow;
                if (deferredPrimary == primaryWindow && applicationName.length &&
                    ![deferredPrimary.title isEqualToString:applicationName])
                    deferredPrimary = nil;
                if (!deferredPrimary || [deferredPrimary isKindOfClass:[NSPanel class]]) {
                    deferredPrimary = nil;
                    for (NSWindow *window in application.windows) {
                        if (![window isKindOfClass:[NSPanel class]] && applicationName.length &&
                            [window.title isEqualToString:applicationName]) {
                            deferredPrimary = window;
                            break;
                        }
                    }
                }
                if (deferredPrimary && ![deferredPrimary isKindOfClass:[NSPanel class]]) {
                    BRPPCNormalizePrimaryWindow(deferredPrimary);
                    NSRect frame = deferredPrimary.frame;
                    if (frame.size.width > 0.0 && frame.size.height > 0.0)
                        [deferredPrimary setFrame:frame display:YES];
                    [deferredPrimary makeKeyAndOrderFront:nil];
                    deferredPrimary.viewsNeedDisplay = YES;
                    [deferredPrimary displayIfNeeded];
                    NSView *contentView = BRPPCReconcileWindowContent(
                        deferredPrimary, self.objectiveCBridge);
                    if (getenv("BISMUTH_COCOA_TRACE"))
                        fprintf(BRPPCCocoaTraceStream(),
                                "cocoa deferred primary=%s title=%s visible=%d alpha=%.2f content=%s subviews=%lu\n",
                                NSStringFromClass(deferredPrimary.class).UTF8String,
                                deferredPrimary.title.UTF8String, deferredPrimary.isVisible,
                                deferredPrimary.alphaValue,
                                NSStringFromClass(contentView.class).UTF8String,
                                (unsigned long)contentView.subviews.count);
                    if (getenv("BISMUTH_COCOA_TRACE"))
                        BRPPCCocoaTraceViewTree(contentView, 0);
                    [timer invalidate];
                } else if (NSDate.timeIntervalSinceReferenceDate - searchStarted > 900.0) {
                    [timer invalidate];
                }
        }];
        [NSRunLoop.mainRunLoop addTimer:primaryWindowTimer forMode:NSRunLoopCommonModes];
        if (getenv("BISMUTH_COCOA_TRACE"))
            fprintf(BRPPCCocoaTraceStream(), "cocoa nib objects=%lu windows=%lu\n",
                    (unsigned long)objects.count, (unsigned long)application.windows.count);
    }
    [application activateIgnoringOtherApps:YES];
    if (getenv("BISMUTH_COCOA_TRACE")) fprintf(BRPPCCocoaTraceStream(), "cocoa run begin\n");
    [application run];
    if (getenv("BISMUTH_COCOA_TRACE")) fprintf(BRPPCCocoaTraceStream(), "cocoa run end\n");
    return YES;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:5
            userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
        return NO;
    } @finally {
        if (mainBundleMethod && previousMainBundleImplementation)
            method_setImplementation(mainBundleMethod, previousMainBundleImplementation);
        if (nextStepNeedsFillMethod && previousNextStepNeedsFillImplementation)
            method_setImplementation(nextStepNeedsFillMethod, previousNextStepNeedsFillImplementation);
        BRPPCOriginalNextStepFrameNeedsFillImplementation = NULL;
        BRPPCFallbackNextStepFrameNeedsFillImplementation = NULL;
        BRPPCGuestMainBundle = nil;
    }
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    (void)error;
    __weak typeof(self) weakSelf = self;
    __weak BRPPCResolveRegistry *weakRegistry = registry;
    [registry registerSymbol:@"_GetCurrentProcess" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;



        OSStatus result = state->gpr[3] &&
            [weakRegistry.memory writeUInt32:0 address:state->gpr[3]] &&
            [weakRegistry.memory writeUInt32:(uint32_t)kCurrentProcess
                                     address:state->gpr[3] + 4]
            ? noErr : paramErr;
        state->gpr[3] = (uint32_t)result;
        state->pc = state->lr;
        return YES;
    }];
    [registry registerSymbol:@"_SetFrontProcess" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        ProcessSerialNumber process = {0};
        BOOL readHigh = [weakRegistry.memory readUInt32:&process.highLongOfPSN address:state->gpr[3]];
        BOOL readLow = [weakRegistry.memory readUInt32:&process.lowLongOfPSN address:state->gpr[3] + 4];
        if (!readHigh || !readLow) {
            state->gpr[3] = (uint32_t)paramErr;
        } else {
            OSStatus (*setFrontProcess)(const ProcessSerialNumber *) =
                (OSStatus (*)(const ProcessSerialNumber *))dlsym(RTLD_DEFAULT, "SetFrontProcess");
            state->gpr[3] = (uint32_t)(setFrontProcess ? setFrontProcess(&process) : unimpErr);
        }
        state->pc = state->lr;
        return YES;
    }];
    [registry registerSymbol:@"_TransformProcessType" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        ProcessSerialNumber process = {0};
        BOOL readHigh = [weakRegistry.memory readUInt32:&process.highLongOfPSN address:state->gpr[3]];
        BOOL readLow = [weakRegistry.memory readUInt32:&process.lowLongOfPSN address:state->gpr[3] + 4];
        if (getenv("BISMUTH_COCOA_TRACE"))
            fprintf(BRPPCCocoaTraceStream(), "TransformProcessType ptr=0x%08x psn={%u,%u} state=%u read=%d/%d\n",
                    state->gpr[3], process.highLongOfPSN, process.lowLongOfPSN,
                    state->gpr[4], readHigh, readLow);
        if (!readHigh || !readLow) {
            state->gpr[3] = (uint32_t)paramErr;
        } else if (process.highLongOfPSN != 0 ||
                   process.lowLongOfPSN != (uint32_t)kCurrentProcess) {
            state->gpr[3] = (uint32_t)procNotFound;
        } else {
            NSApplicationActivationPolicy policy;
            switch ((ProcessApplicationTransformState)state->gpr[4]) {
            case kProcessTransformToForegroundApplication:
                policy = NSApplicationActivationPolicyRegular;
                break;
            case kProcessTransformToBackgroundApplication:
                policy = NSApplicationActivationPolicyProhibited;
                break;
            case kProcessTransformToUIElementApplication:
                policy = NSApplicationActivationPolicyAccessory;
                break;
            default:
                state->gpr[3] = (uint32_t)paramErr;
                state->pc = state->lr;
                return YES;
            }
            NSApplication *application = NSApplication.sharedApplication;
            BOOL changed = [application setActivationPolicy:policy];
            if (changed && policy == NSApplicationActivationPolicyRegular)
                [application activate];
            if (getenv("BISMUTH_COCOA_TRACE"))
                fprintf(BRPPCCocoaTraceStream(), "TransformProcessType state=%u policy=%ld changed=%d current=%ld\n",
                        state->gpr[4], (long)policy, changed, (long)application.activationPolicy);
            state->gpr[3] = application.activationPolicy == policy ? noErr : (uint32_t)paramErr;
        }
        state->pc = state->lr;
        return YES;
    }];
    [registry registerSymbol:@"_NSApplicationMain" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCCocoaResolve *self = weakSelf;
        BRPPCResolveRegistry *registry = weakRegistry;
        if (!self || !registry) return NO;
        if (![NSThread isMainThread]) {
            if (callError) *callError = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey: @"AppKit resolver must run on main thread."}];
            return NO;
        }
        BRPPCObjectiveCResolve *bridge = self.objectiveCBridge;
        BOOL ran = bridge
            ? [bridge performHostCallbackScopeWithState:state block:^BOOL(NSError **scopeError) {
                return [self runGuestApplicationWithRegistry:registry error:scopeError];
              } error:callError]
            : [self runGuestApplicationWithRegistry:registry error:callError];
        if (!ran) return NO;
        state->gpr[3] = 0;
        state->pc = state->lr;
        return YES;
    }];

    [registry registerSymbol:@".objc_class_name_NSObject" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)state;
        if (callError) *callError = [NSError errorWithDomain:BRPPCCocoaErrorDomain code:4
            userInfo:@{NSLocalizedDescriptionKey: @"Objective-C class marker is data, not callable code."}];
        return NO;
    }];
    return YES;
}
@end
