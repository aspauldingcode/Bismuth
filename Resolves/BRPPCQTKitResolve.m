#import "BRPPCQTKitResolve.h"
#import "BRPPCAddressSpace.h"

typedef struct {
    int64_t value;
    int32_t scale;
    uint32_t flags;
} BRPPCQTTime;

static uint32_t BRQTArgumentWord(BRPPCResolveRegistry *registry, BRPPCState *state,
                                 NSUInteger position) {
    if (position <= 10) return state->gpr[position];
    uint32_t value = 0;
    [registry.memory readUInt32:&value
                        address:state->gpr[1] + 24 + (uint32_t)(position - 3) * 4];
    return value;
}

static BRPPCQTTime BRQTReadArgument(BRPPCResolveRegistry *registry, BRPPCState *state,
                                    NSUInteger position) {
    uint64_t bits = (uint64_t)BRQTArgumentWord(registry, state, position) << 32 |
                    BRQTArgumentWord(registry, state, position + 1);
    return (BRPPCQTTime){(int64_t)bits,
        (int32_t)BRQTArgumentWord(registry, state, position + 2),
        BRQTArgumentWord(registry, state, position + 3)};
}

static BOOL BRQTWriteTime(BRPPCResolveRegistry *registry, uint32_t address, BRPPCQTTime time) {
    return address && [registry.memory writeUInt32:(uint32_t)((uint64_t)time.value >> 32)
                                          address:address] &&
        [registry.memory writeUInt32:(uint32_t)time.value address:address + 4] &&
        [registry.memory writeUInt32:(uint32_t)time.scale address:address + 8] &&
        [registry.memory writeUInt32:time.flags address:address + 12];
}

static BRPPCQTTime BRQTScaleTime(BRPPCQTTime time, int32_t scale) {
    if (!time.scale || !scale || time.scale == scale) {
        if (scale) time.scale = scale;
        return time;
    }
    long double scaled = (long double)time.value * scale / time.scale;
    time.value = (int64_t)scaled;
    time.scale = scale;
    return time;
}

static BRPPCQTTime BRQTAddTime(BRPPCQTTime left, BRPPCQTTime right, BOOL subtract) {
    int32_t scale = left.scale ?: right.scale;
    left = BRQTScaleTime(left, scale); right = BRQTScaleTime(right, scale);
    left.value += subtract ? -right.value : right.value;
    left.flags |= right.flags;
    return left;
}

static void BRQTFinishTime(BRPPCState *state) { state->pc = state->lr; }

@implementation BRPPCQTKitResolve
- (instancetype)init { return [super initWithFrameworkName:@"QTKit"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    NSArray<NSString *> *strings = @[
        @"_QTAddImageCodecQuality", @"_QTAddImageCodecType", @"_QTMediaTimeScaleAttribute",
        @"_QTMediaTypeMPEG", @"_QTMediaTypeSound", @"_QTMediaTypeTween", @"_QTMediaTypeVideo",
        @"_QTMovieApertureModeAttribute", @"_QTMovieApertureModeClean",
        @"_QTMovieAskUnresolvedDataRefsAttribute", @"_QTMovieCurrentSizeAttribute",
        @"_QTMovieEditableAttribute", @"_QTMovieExport", @"_QTMovieExportSettings",
        @"_QTMovieExportType", @"_QTMovieFileNameAttribute", @"_QTMovieFlatten",
        @"_QTMovieFrameImageDeinterlaceFields", @"_QTMovieFrameImageHighQuality",
        @"_QTMovieFrameImageSingleField", @"_QTMovieFrameImageType",
        @"_QTMovieFrameImageTypeCGImageRef", @"_QTMovieFrameImageTypeCVPixelBufferRef",
        @"_QTMovieFrameImageTypeNSImage", @"_QTMovieHasApertureModeDimensionsAttribute",
        @"_QTMovieHasVideoAttribute", @"_QTMovieIsActiveAttribute", @"_QTMovieLoopsAttribute",
        @"_QTMovieNaturalSizeAttribute", @"_QTMovieOpenAsyncOKAttribute",
        @"_QTMoviePlaysSelectionOnlyAttribute", @"_QTMovieRateDidChangeNotification",
        @"_QTMovieRateDidChangeNotificationParameter", @"_QTMovieResolveDataRefsAttribute",
        @"_QTMovieTimeDidChangeNotification", @"_QTMovieTimeScaleAttribute",
        @"_QTMovieURLAttribute", @"_QTMovieUneditableException", @"_QTTrackIDAttribute",
        @"_QTTrackMediaTypeAttribute", @"_QTTrackRangeAttribute", @"_QTTrackTimeScaleAttribute"
    ];
    if (![self registerStringConstants:strings registry:registry error:error]) return NO;
    uint8_t zeroTime[16] = {0};
    if (![self registerDataConstant:@"_QTZeroTime"
        data:[NSData dataWithBytes:zeroTime length:sizeof(zeroTime)] alignment:8
        registry:registry error:error]) return NO;
    [registry registerSymbol:@"_QTMakeTime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        BRPPCQTTime time = {(int64_t)((uint64_t)state->gpr[4] << 32 | state->gpr[5]),
                            (int32_t)state->gpr[6], 0};
        if (!BRQTWriteTime(registry, state->gpr[3], time)) return NO;
        BRQTFinishTime(state); return YES;
    }];
    [registry registerSymbol:@"_QTMakeTimeScaled" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQTTime time = BRQTReadArgument(registry, state, 4);
        if (!BRQTWriteTime(registry, state->gpr[3], BRQTScaleTime(time, (int32_t)state->gpr[8])))
            return NO;
        BRQTFinishTime(state); return YES;
    }];
    [registry registerSymbol:@"_QTTimeCompare" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQTTime left = BRQTReadArgument(registry, state, 3);
        BRPPCQTTime right = BRQTReadArgument(registry, state, 7);
        long double leftValue = left.scale ? (long double)left.value / left.scale : left.value;
        long double rightValue = right.scale ? (long double)right.value / right.scale : right.value;
        state->gpr[3] = leftValue < rightValue ? UINT32_MAX : (leftValue > rightValue ? 1 : 0);
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_QTTimeIncrement", @"_QTTimeDecrement"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQTTime left = BRQTReadArgument(registry, state, 4);
            BRPPCQTTime right = BRQTReadArgument(registry, state, 8);
            if (!BRQTWriteTime(registry, state->gpr[3],
                               BRQTAddTime(left, right, [symbol hasSuffix:@"Decrement"]))) return NO;
            BRQTFinishTime(state); return YES;
        }];
    [registry registerSymbol:@"_QTMakeTimeRange" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t output = state->gpr[3];
        BRPPCQTTime start = BRQTReadArgument(registry, state, 4);
        BRPPCQTTime duration = BRQTReadArgument(registry, state, 8);
        if (!BRQTWriteTime(registry, output, start) || !BRQTWriteTime(registry, output + 16, duration))
            return NO;
        BRQTFinishTime(state); return YES;
    }];
    [registry registerSymbol:@"_QTTimeRangeEnd" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQTTime start = BRQTReadArgument(registry, state, 4);
        BRPPCQTTime duration = BRQTReadArgument(registry, state, 8);
        if (!BRQTWriteTime(registry, state->gpr[3], BRQTAddTime(start, duration, NO))) return NO;
        BRQTFinishTime(state); return YES;
    }];
    [registry registerSymbol:@"_QTTimeInTimeRange" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQTTime time = BRQTReadArgument(registry, state, 3);
        BRPPCQTTime start = BRQTReadArgument(registry, state, 7);
        BRPPCQTTime duration = BRQTReadArgument(registry, state, 11);
        int32_t scale = time.scale ?: (start.scale ?: duration.scale);
        time = BRQTScaleTime(time, scale); start = BRQTScaleTime(start, scale);
        duration = BRQTScaleTime(duration, scale);
        state->gpr[3] = time.value >= start.value && time.value < start.value + duration.value;
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_QTMakeTimeWithTimeRecord", @"_QTGetTimeRecord"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQTTime value = BRQTReadArgument(registry, state, 4);
            if (!BRQTWriteTime(registry, state->gpr[3], value)) return NO;
            BRQTFinishTime(state); return YES;
        }];
    [registry registerSymbol:@"_QTEqualTimeRanges" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQTTime leftStart = BRQTReadArgument(registry, state, 3);
        BRPPCQTTime leftDuration = BRQTReadArgument(registry, state, 7);
        BRPPCQTTime rightStart = BRQTReadArgument(registry, state, 11);
        BRPPCQTTime rightDuration = BRQTReadArgument(registry, state, 15);
        int32_t scale = leftStart.scale ?: (rightStart.scale ?: 1);
        leftStart = BRQTScaleTime(leftStart, scale); rightStart = BRQTScaleTime(rightStart, scale);
        leftDuration = BRQTScaleTime(leftDuration, scale); rightDuration = BRQTScaleTime(rightDuration, scale);
        state->gpr[3] = leftStart.value == rightStart.value &&
                        leftDuration.value == rightDuration.value;
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_QTIntersectionTimeRange", @"_QTUnionTimeRange"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQTTime firstStart = BRQTReadArgument(registry, state, 4);
            BRPPCQTTime firstDuration = BRQTReadArgument(registry, state, 8);
            BRPPCQTTime secondStart = BRQTReadArgument(registry, state, 12);
            BRPPCQTTime secondDuration = BRQTReadArgument(registry, state, 16);
            int32_t scale = firstStart.scale ?: (secondStart.scale ?: 1);
            firstStart = BRQTScaleTime(firstStart, scale);
            firstDuration = BRQTScaleTime(firstDuration, scale);
            secondStart = BRQTScaleTime(secondStart, scale);
            secondDuration = BRQTScaleTime(secondDuration, scale);
            int64_t firstEnd = firstStart.value + firstDuration.value;
            int64_t secondEnd = secondStart.value + secondDuration.value;
            BOOL intersection = [symbol hasPrefix:@"_QTIntersection"];
            int64_t start = intersection ? MAX(firstStart.value, secondStart.value)
                                         : MIN(firstStart.value, secondStart.value);
            int64_t end = intersection ? MIN(firstEnd, secondEnd) : MAX(firstEnd, secondEnd);
            if (intersection && end < start) end = start;
            BRPPCQTTime outputStart = {start, scale, firstStart.flags | secondStart.flags};
            BRPPCQTTime outputDuration = {end - start, scale,
                firstDuration.flags | secondDuration.flags};
            if (!BRQTWriteTime(registry, state->gpr[3], outputStart) ||
                !BRQTWriteTime(registry, state->gpr[3] + 16, outputDuration)) return NO;
            BRQTFinishTime(state); return YES;
        }];
    [registry registerSymbol:@"_QTStringForOSType" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t value = state->gpr[3];
        uint8_t bytes[4] = {(uint8_t)(value >> 24), (uint8_t)(value >> 16),
                            (uint8_t)(value >> 8), (uint8_t)value};
        NSString *string = [[NSString alloc] initWithBytes:bytes length:4
                                                   encoding:NSMacOSRomanStringEncoding] ?: @"????";
        state->gpr[3] = registry.guestObjectEncoder ? registry.guestObjectEncoder(string) : 0;
        state->pc = state->lr; return YES;
    }];
    return YES;
}
@end
