#import "BRPPCAppKitResolve.h"
#import "BRPPCAddressSpace.h"
#import <AppKit/AppKit.h>

static NSString *BRPPCGuestString(BRPPCResolveRegistry *registry, uint32_t handle) {
    id object = registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

static void BRPPCRegisterAlertPanel(NSString *symbol, BRPPCResolveRegistry *registry) {
    [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **error) {
        NSString *title = BRPPCGuestString(registry, state->gpr[3]) ?: @"";
        NSString *messageFormat = BRPPCGuestString(registry, state->gpr[4]) ?: @"";
        NSString *message = messageFormat;
        if (registry.guestFormatRenderer && registry.guestAllocator && registry.guestDeallocator) {
            NSData *bytes = [messageFormat dataUsingEncoding:NSUTF8StringEncoding];
            uint32_t address = registry.guestAllocator((uint32_t)bytes.length + 1, YES);
            if (address && [registry.memory writeBytes:bytes.bytes address:address length:bytes.length]) {
                NSData *rendered = registry.guestFormatRenderer(address, state, 8, error);
                if (rendered) message = [[NSString alloc] initWithData:rendered
                                                               encoding:NSUTF8StringEncoding] ?: message;
            }
            if (address) registry.guestDeallocator(address);
        }
        if (getenv("BISMUTH_FRAMEWORK_TRACE"))
            fprintf(stderr, "%s title=%s message=%s\n", symbol.UTF8String,
                    title.UTF8String, message.UTF8String);
        state->gpr[3] = 1;
        state->pc = state->lr;
        return YES;
    }];
}

@implementation BRPPCAppKitResolve
- (instancetype)init { return [super initWithFrameworkName:@"AppKit"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    NSArray<NSString *> *strings = @[@"_NSApplicationDidFinishLaunchingNotification",
        @"_NSApplicationDidBecomeActiveNotification", @"_NSApplicationDidUnhideNotification",
        @"_NSAllRomanInputSourcesLocaleIdentifier",
        @"_NSApplicationWillHideNotification", @"_NSApplicationWillResignActiveNotification",
        @"_NSApplicationWillTerminateNotification", @"_NSBackgroundColorAttributeName",
        @"_NSBaselineOffsetAttributeName", @"_NSCalibratedRGBColorSpace",
        @"_NSColorPanelColorDidChangeNotification", @"_NSControlTextDidBeginEditingNotification",
        @"_NSControlTextDidChangeNotification", @"_NSControlTextDidEndEditingNotification",
        @"_NSDragPboard", @"_NSEventTrackingRunLoopMode", @"_NSFilenamesPboardType",
        @"_NSDeviceRGBColorSpace", @"_NSStringPboardType",
        @"_NSFontAttributeName", @"_NSFontNameAttribute", @"_NSForegroundColorAttributeName",
        @"_NSImageCompressionFactor", @"_NSKernAttributeName", @"_NSModalPanelRunLoopMode",
        @"_NSMultipleValuesMarker", @"_NSNoSelectionMarker", @"_NSNotApplicableMarker",
        @"_NSNullPlaceholderBindingOption", @"_NSObservedKeyPathKey", @"_NSObservedObjectKey",
        @"_NSOptionsKey", @"_NSParagraphStyleAttributeName", @"_NSPrintScalingFactor",
        @"_NSRaisesForNotApplicableKeysBindingOption", @"_NSShadowAttributeName",
        @"_NSSplitViewWillResizeSubviewsNotification", @"_NSStrokeColorAttributeName",
        @"_NSStrokeWidthAttributeName", @"_NSTextViewDidChangeSelectionNotification",
        @"_NSUnderlineStyleAttributeName", @"_NSValueTransformerNameBindingOption",
        @"_NSViewBoundsDidChangeNotification", @"_NSViewFrameDidChangeNotification",
        @"_NSWindowDidBecomeKeyNotification", @"_NSWindowDidChangeScreenNotification",
        @"_NSWindowDidDeminiaturizeNotification", @"_NSWindowDidMoveNotification",
        @"_NSWindowDidResignKeyNotification", @"_NSWindowDidResizeNotification",
        @"_NSWindowWillCloseNotification", @"_NSWorkspaceDestroyOperation",
        @"_NSWorkspaceDidMountNotification", @"_NSWorkspaceDidUnmountNotification",
        @"_NSWorkspaceMoveOperation", @"_NSWorkspaceRecycleOperation",
        @"_NSWorkspaceWillUnmountNotification", @"_NSPasteboardTypeString"];
    if (![self registerStringConstants:strings registry:registry error:error]) return NO;
    double appKitVersion = 949.0;
    uint64_t appKitBits = 0; memcpy(&appKitBits, &appKitVersion, sizeof(appKitBits));
    uint8_t appKitBytes[8];
    for (NSUInteger i = 0; i < 8; i++) appKitBytes[i] = (uint8_t)(appKitBits >> (56 - i * 8));
    if (![self registerDataConstant:@"_NSAppKitVersionNumber"
        data:[NSData dataWithBytes:appKitBytes length:8] alignment:8 registry:registry error:error]) return NO;
    [self registerZeroFunctions:@[@"_NSBeep", @"_NSRectFill", @"_NSFrameRect"]
                         registry:registry];
    [registry registerSymbol:@"_NSDisableScreenUpdates" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_NSEnableScreenUpdates" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_NSFrameRectWithWidth", @"_NSRectClip", @"_NSRectFillUsingOperation",
        @"_NSSetFocusRingStyle", @"_NSShowAnimationEffect"])
        [self registerZeroFunction:symbol registry:registry];
    [registry registerSymbol:@"_NSReadPixel" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->gpr[3] = registry.guestObjectEncoder ? registry.guestObjectEncoder([NSColor clearColor]) : 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_PSstilldown" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->gpr[3] = 0; state->pc = state->lr; return YES;
    }];
    BRPPCRegisterAlertPanel(@"_NSRunAlertPanel", registry);
    BRPPCRegisterAlertPanel(@"_NSRunCriticalAlertPanel", registry);
    BRPPCRegisterAlertPanel(@"_NSRunInformationalAlertPanel", registry);
    return YES;
}
@end
