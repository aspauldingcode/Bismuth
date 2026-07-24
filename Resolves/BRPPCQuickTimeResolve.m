#import "BRPPCQuickTimeResolve.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import <CoreServices/CoreServices.h>

static const int32_t BRQTFixedOne = 1 << 16;
static const int32_t BRQTPerspectiveOne = 1 << 30;

static void BRQTFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

static uint32_t BRQTStackWord(BRPPCResolveRegistry *registry, BRPPCState *state,
                              NSUInteger position) {
    if (position <= 10) return state->gpr[position];
    uint32_t value = 0;
    [registry.memory readUInt32:&value
                        address:state->gpr[1] + 24 + (uint32_t)(position - 3) * 4];
    return value;
}

@interface BRPPCQuickTimeMedia : NSObject
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t track;
@property(nonatomic) uint32_t type;
@property(nonatomic) int32_t timeScale;
@property(nonatomic) int64_t duration;
@property(nonatomic) BOOL editing;
@property(nonatomic) uint32_t sampleCount;
@property(nonatomic) uint32_t syncSampleCount;
@property(nonatomic) uint32_t playHints;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *dataReferences;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *sampleDescriptions;
@property(nonatomic) uint32_t inputMap;
@end
@implementation BRPPCQuickTimeMedia @end

@interface BRPPCQuickTimeTrack : NSObject
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t movie;
@property(nonatomic) uint32_t media;
@property(nonatomic) uint32_t identifier;
@property(nonatomic) int64_t duration;
@property(nonatomic) int32_t layer;
@property(nonatomic) int32_t volume;
@property(nonatomic) BOOL enabled;
@property(nonatomic) int64_t offset;
@property(nonatomic) int32_t width;
@property(nonatomic) int32_t height;
@property(nonatomic, strong) NSData *matrix;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *references;
@end
@implementation BRPPCQuickTimeTrack @end

@interface BRPPCQuickTimeMovie : NSObject
@property(nonatomic) uint32_t handle;
@property(nonatomic) int32_t timeScale;
@property(nonatomic) int64_t duration;
@property(nonatomic) int32_t rate;
@property(nonatomic) int64_t time;
@property(nonatomic) BOOL active;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *tracks;
@property(nonatomic) int64_t selectionTime;
@property(nonatomic) int64_t selectionDuration;
@property(nonatomic) BOOL threadAttached;
@property(nonatomic) uint32_t visualContext;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *userData;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *properties;
@property(nonatomic) uint32_t timeBase;
@property(nonatomic) uint32_t audioContext;
@property(nonatomic) uint32_t playHints;
@property(nonatomic) uint32_t progressProc;
@property(nonatomic) BOOL audioMetering;
@property(nonatomic, strong) NSData *box;
@property(nonatomic, strong) NSData *matrix;
@end
@implementation BRPPCQuickTimeMovie @end

@interface BRPPCQuickTimeSession : NSObject
@property(nonatomic, copy) NSString *kind;
@property(nonatomic) int32_t timeScale;
@property(nonatomic) uint32_t callback;
@property(nonatomic) uint32_t refcon;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSData *> *properties;
@end
@implementation BRPPCQuickTimeSession @end

@interface BRPPCQuickTimeAtomContainer : NSObject
@property(nonatomic) uint32_t nextAtom;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSData *> *atoms;
@end
@implementation BRPPCQuickTimeAtomContainer @end

@interface BRPPCQuickTimeResolve ()
@property(nonatomic) uint32_t nextHandle;
@property(nonatomic) int32_t moviesError;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCQuickTimeMovie *> *movies;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCQuickTimeTrack *> *tracks;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCQuickTimeMedia *> *media;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *externalProperties;
@end

@implementation BRPPCQuickTimeResolve

- (instancetype)init {
    self = [super initWithFrameworkName:@"QuickTime"];
    if (self) {
        _nextHandle = BRPPCGuestQuickTimeHandleBase;
        _movies = [NSMutableDictionary dictionary];
        _tracks = [NSMutableDictionary dictionary];
        _media = [NSMutableDictionary dictionary];
        _externalProperties = [NSMutableDictionary dictionary];
    }
    return self;
}

- (uint32_t)newHandle { uint32_t handle = _nextHandle; _nextHandle += 16; return handle; }
- (BRPPCQuickTimeMovie *)createMovie {
    BRPPCQuickTimeMovie *movie = [BRPPCQuickTimeMovie new];
    movie.handle = [self newHandle]; movie.timeScale = 600; movie.rate = BRQTFixedOne;
    movie.active = YES; movie.tracks = [NSMutableArray array];
    movie.userData = [NSMutableDictionary dictionary];
    movie.properties = [NSMutableDictionary dictionary];
    self.movies[@(movie.handle)] = movie;
    return movie;
}
- (BRPPCQuickTimeMovie *)movie:(uint32_t)handle { return _movies[@(handle)]; }
- (BRPPCQuickTimeTrack *)track:(uint32_t)handle { return _tracks[@(handle)]; }
- (BRPPCQuickTimeMedia *)medium:(uint32_t)handle { return _media[@(handle)]; }

static id BRQTObject(BRPPCResolveRegistry *registry, uint32_t handle) {
    return registry.guestObjectDecoder ? registry.guestObjectDecoder(handle) : nil;
}

static uint32_t BRQTObjectHandle(BRPPCResolveRegistry *registry, id object) {
    return registry.guestObjectEncoder ? registry.guestObjectEncoder(object) : 0;
}

- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    if (![self registerStringConstants:@[@"_kQTVisualContextPixelBufferAttributesKey",
                                         @"_kQTVisualContextWorkingColorSpaceKey"]
                              registry:registry error:error]) return NO;
    __weak typeof(self) weakSelf = self;
    for (NSString *symbol in @[@"_EnterMovies", @"_ExitMovies", @"_EnterMoviesOnThread",
                               @"_ExitMoviesOnThread", @"_MoviesTask"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_NewMovie" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        BRPPCQuickTimeMovie *movie = [weakSelf createMovie];
        BRQTFinish(state, movie.handle); return YES;
    }];
    [registry registerSymbol:@"_DisposeMovie" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        for (NSNumber *trackHandle in movie.tracks.copy) {
            BRPPCQuickTimeTrack *track = [weakSelf track:trackHandle.unsignedIntValue];
            if (track.media) [weakSelf.media removeObjectForKey:@(track.media)];
            [weakSelf.tracks removeObjectForKey:trackHandle];
        }
        [weakSelf.movies removeObjectForKey:@(state->gpr[3])]; BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_NewMovieTrack" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        if (!movie) { weakSelf.moviesError = paramErr; BRQTFinish(state, 0); return YES; }
        BRPPCQuickTimeTrack *track = [BRPPCQuickTimeTrack new];
        track.handle = [weakSelf newHandle]; track.movie = movie.handle;
        track.identifier = (uint32_t)movie.tracks.count + 1; track.volume = (int32_t)state->gpr[6];
        track.width = (int32_t)state->gpr[4]; track.height = (int32_t)state->gpr[5];
        track.enabled = YES; track.references = [NSMutableDictionary dictionary];
        weakSelf.tracks[@(track.handle)] = track;
        [movie.tracks addObject:@(track.handle)]; BRQTFinish(state, track.handle); return YES;
    }];
    [registry registerSymbol:@"_DisposeMovieTrack" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        BRPPCQuickTimeMovie *movie = [weakSelf movie:track.movie];
        [movie.tracks removeObject:@(track.handle)];
        if (track.media) [weakSelf.media removeObjectForKey:@(track.media)];
        [weakSelf.tracks removeObjectForKey:@(state->gpr[3])]; BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_NewTrackMedia" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        if (!track) { weakSelf.moviesError = paramErr; BRQTFinish(state, 0); return YES; }
        BRPPCQuickTimeMedia *medium = [BRPPCQuickTimeMedia new];
        medium.handle = [weakSelf newHandle]; medium.track = track.handle;
        medium.type = state->gpr[4]; medium.timeScale = (int32_t)state->gpr[5];
        medium.dataReferences = [NSMutableArray array];
        medium.sampleDescriptions = [NSMutableArray array];
        weakSelf.media[@(medium.handle)] = medium; track.media = medium.handle;
        BRQTFinish(state, medium.handle); return YES;
    }];
    [registry registerSymbol:@"_DisposeTrackMedia" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        BRPPCQuickTimeTrack *track = [weakSelf track:medium.track]; track.media = 0;
        [weakSelf.media removeObjectForKey:@(state->gpr[3])]; BRQTFinish(state, 0); return YES;
    }];

    NSDictionary<NSString *, NSNumber *> *movieGetters = @{
        @"_GetMovieDuration": @1, @"_GetMovieTimeScale": @2, @"_GetMovieRate": @3,
        @"_GetMoviePreferredRate": @3, @"_GetMovieTrackCount": @4, @"_GetMovieActive": @5
    };
    [movieGetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]]; uint32_t value = 0;
            switch (kind.unsignedIntValue) {
                case 1: value = (uint32_t)movie.duration; break; case 2: value = (uint32_t)movie.timeScale; break;
                case 3: value = (uint32_t)movie.rate; break; case 4: value = (uint32_t)movie.tracks.count; break;
                case 5: value = movie.active; break; default: break;
            }
            BRQTFinish(state, value); return YES;
        }];
    }];
    NSDictionary<NSString *, NSNumber *> *movieSetters = @{
        @"_SetMovieTimeScale": @1, @"_SetMovieRate": @2, @"_SetMoviePreferredRate": @2,
        @"_SetMovieActive": @3
    };
    [movieSetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
            if (kind.unsignedIntValue == 1) movie.timeScale = (int32_t)state->gpr[4];
            else if (kind.unsignedIntValue == 2) movie.rate = (int32_t)state->gpr[4];
            else movie.active = state->gpr[4] != 0;
            BRQTFinish(state, 0); return YES;
        }];
    }];
    [registry registerSymbol:@"_GetMovieIndTrack" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        NSUInteger index = state->gpr[4]; uint32_t result = index && index <= movie.tracks.count
            ? movie.tracks[index - 1].unsignedIntValue : 0; BRQTFinish(state, result); return YES;
    }];
    for (NSString *symbol in @[@"_StartMovie", @"_StopMovie", @"_GoToBeginningOfMovie"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
            if ([symbol isEqualToString:@"_StartMovie"]) movie.rate = BRQTFixedOne;
            else if ([symbol isEqualToString:@"_StopMovie"]) movie.rate = 0;
            else movie.time = 0; BRQTFinish(state, 0); return YES;
        }];

    NSDictionary<NSString *, NSNumber *> *trackGetters = @{
        @"_GetTrackMovie": @1, @"_GetTrackMedia": @2, @"_GetTrackDuration": @3,
        @"_GetTrackID": @4, @"_GetTrackLayer": @5, @"_GetTrackVolume": @6,
        @"_GetTrackEnabled": @7
    };
    [trackGetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]]; uint32_t value = 0;
            switch (kind.unsignedIntValue) {
                case 1: value = track.movie; break; case 2: value = track.media; break;
                case 3: value = (uint32_t)track.duration; break; case 4: value = track.identifier; break;
                case 5: value = (uint32_t)track.layer; break; case 6: value = (uint32_t)track.volume; break;
                case 7: value = track.enabled; break; default: break;
            }
            BRQTFinish(state, value); return YES;
        }];
    }];
    NSDictionary<NSString *, NSNumber *> *trackSetters = @{
        @"_SetTrackLayer": @1, @"_SetTrackVolume": @2, @"_SetTrackEnabled": @3
    };
    [trackSetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
            if (kind.unsignedIntValue == 1) track.layer = (int32_t)state->gpr[4];
            else if (kind.unsignedIntValue == 2) track.volume = (int32_t)state->gpr[4];
            else track.enabled = state->gpr[4] != 0; BRQTFinish(state, 0); return YES;
        }];
    }];
    NSDictionary<NSString *, NSNumber *> *mediaGetters = @{
        @"_GetMediaDuration": @1, @"_GetMediaTimeScale": @2, @"_GetMediaHandler": @3
    };
    [mediaGetters enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
            uint32_t value = kind.unsignedIntValue == 1 ? (uint32_t)medium.duration
                : (kind.unsignedIntValue == 2 ? (uint32_t)medium.timeScale : medium.handle);
            BRQTFinish(state, value); return YES;
        }];
    }];
    [registry registerSymbol:@"_SetMediaTimeScale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf medium:state->gpr[3]].timeScale = (int32_t)state->gpr[4];
        BRQTFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_BeginMediaEdits", @"_EndMediaEdits"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; [weakSelf medium:state->gpr[3]].editing = [symbol isEqualToString:@"_BeginMediaEdits"];
            BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_AddMediaSample" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        uint32_t sampleDescription = state->gpr[8], count = state->gpr[9];
        if (!medium || !medium.editing) { weakSelf.moviesError = paramErr; BRQTFinish(state, (uint32_t)paramErr); return YES; }
        medium.sampleCount += count; medium.syncSampleCount += count;
        medium.duration += (int64_t)(int32_t)state->gpr[7] * count;
        if (sampleDescription && ![medium.sampleDescriptions containsObject:@(sampleDescription)])
            [medium.sampleDescriptions addObject:@(sampleDescription)];
        uint32_t output = BRQTStackWord(registry, state, 11);
        if (output) [registry.memory writeUInt32:(uint32_t)(medium.duration -
            (int64_t)(int32_t)state->gpr[7] * count) address:output];
        BRQTFinish(state, 0); return YES;
    }];
    NSDictionary<NSString *, NSNumber *> *sampleCounts = @{
        @"_GetMediaSampleCount": @1, @"_GetMediaSyncSampleCount": @2,
        @"_GetMediaSampleDescriptionCount": @3
    };
    [sampleCounts enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *kind, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]]; uint32_t value = 0;
            if (kind.unsignedIntValue == 1) value = medium.sampleCount;
            else if (kind.unsignedIntValue == 2) value = medium.syncSampleCount;
            else value = (uint32_t)medium.sampleDescriptions.count;
            BRQTFinish(state, value); return YES;
        }];
    }];
    [registry registerSymbol:@"_GetMediaSampleDescription" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        NSUInteger index = state->gpr[4]; uint32_t description = index && index <= medium.sampleDescriptions.count
            ? medium.sampleDescriptions[index - 1].unsignedIntValue : 0;
        if (state->gpr[5]) [registry.memory writeUInt32:description address:state->gpr[5]];
        BRQTFinish(state, description ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetMediaSampleDescription" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        NSUInteger index = state->gpr[4];
        if (medium && index && index <= medium.sampleDescriptions.count)
            medium.sampleDescriptions[index - 1] = @(state->gpr[5]);
        BRQTFinish(state, medium && index ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AddMediaDataRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        if (!medium) { BRQTFinish(state, (uint32_t)paramErr); return YES; }
        [medium.dataReferences addObject:@(state->gpr[4])];
        if (state->gpr[6]) [registry.memory writeUInt32:(uint32_t)medium.dataReferences.count
                                                address:state->gpr[6]];
        BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetMediaDataRefCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, (uint32_t)[weakSelf medium:state->gpr[3]].dataReferences.count);
        return YES;
    }];
    [registry registerSymbol:@"_GetMediaDataRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        NSUInteger index = state->gpr[4]; uint32_t dataReference = index && index <= medium.dataReferences.count
            ? medium.dataReferences[index - 1].unsignedIntValue : 0;
        BOOL valid = dataReference && state->gpr[5] &&
            [registry.memory writeUInt32:dataReference address:state->gpr[5]];
        if (valid && state->gpr[6]) valid = [registry.memory writeUInt32:0 address:state->gpr[6]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_GetMediaPlayHints", @"_SetMediaPlayHints"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
            if ([symbol hasPrefix:@"_Get"]) BRQTFinish(state, medium.playHints);
            else { medium.playHints = (medium.playHints & ~state->gpr[5]) |
                                      (state->gpr[4] & state->gpr[5]); BRQTFinish(state, 0); }
            return YES;
        }];
    [registry registerSymbol:@"_InsertMediaIntoTrack" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        int64_t end = (int64_t)(int32_t)state->gpr[4] + (int32_t)state->gpr[6];
        track.duration = MAX(track.duration, end);
        BRPPCQuickTimeMovie *movie = [weakSelf movie:track.movie]; movie.duration = MAX(movie.duration, track.duration);
        BRQTFinish(state, track ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_InsertTrackSegment", @"_InsertMovieSegment"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; int64_t duration = (int32_t)state->gpr[6];
            if ([symbol isEqualToString:@"_InsertTrackSegment"]) {
                BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[4]];
                track.duration = MAX(track.duration, (int64_t)(int32_t)state->gpr[7] + duration);
            } else {
                BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[4]];
                movie.duration = MAX(movie.duration, (int64_t)(int32_t)state->gpr[7] + duration);
            }
            BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_GetMovieSelection" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        BOOL valid = movie && state->gpr[4] && state->gpr[5] &&
            [registry.memory writeUInt32:(uint32_t)movie.selectionTime address:state->gpr[4]] &&
            [registry.memory writeUInt32:(uint32_t)movie.selectionDuration address:state->gpr[5]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetMovieSelection" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        movie.selectionTime = (int32_t)state->gpr[4]; movie.selectionDuration = (int32_t)state->gpr[5];
        BRQTFinish(state, movie ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetMovieTimeValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf movie:state->gpr[3]].time = (int32_t)state->gpr[4];
        BRQTFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_AttachMovieToCurrentThread", @"_DetachMovieFromCurrentThread"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
            movie.threadAttached = [symbol hasPrefix:@"_Attach"];
            BRQTFinish(state, movie ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_GetMovieThreadAttachState" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, [weakSelf movie:state->gpr[3]].threadAttached); return YES;
    }];
    [registry registerSymbol:@"_SetMovieVisualContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf movie:state->gpr[3]].visualContext = state->gpr[4];
        BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetTrackDimensions" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        BOOL valid = track && state->gpr[4] && state->gpr[5] &&
            [registry.memory writeUInt32:(uint32_t)track.width address:state->gpr[4]] &&
            [registry.memory writeUInt32:(uint32_t)track.height address:state->gpr[5]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetTrackDimensions" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        track.width = (int32_t)state->gpr[4]; track.height = (int32_t)state->gpr[5];
        BRQTFinish(state, track ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetIdentityMatrix" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int32_t matrix[9] = {
            BRQTFixedOne, 0, 0, 0, BRQTFixedOne, 0, 0, 0, BRQTPerspectiveOne};
        BOOL valid = state->gpr[3] != 0;
        for (NSUInteger i = 0; valid && i < 9; i++)
            valid = [registry.memory writeUInt32:(uint32_t)matrix[i]
                                          address:state->gpr[3] + (uint32_t)i * 4];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetTrackMatrix" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        NSMutableData *matrix = [NSMutableData dataWithLength:36];
        BOOL valid = track && [registry.memory readBytes:matrix.mutableBytes address:state->gpr[4] length:36];
        if (valid) track.matrix = matrix; BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetTrackMatrix" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        BOOL valid = track.matrix.length == 36 && state->gpr[4] &&
            [registry.memory writeBytes:track.matrix.bytes address:state->gpr[4] length:36];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AddTrackReference" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        NSMutableArray *references = track.references[@(state->gpr[5])];
        if (!references) { references = [NSMutableArray array]; track.references[@(state->gpr[5])] = references; }
        [references addObject:@(state->gpr[4])];
        if (state->gpr[6]) [registry.memory writeUInt32:(uint32_t)references.count address:state->gpr[6]];
        BRQTFinish(state, track ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetTrackReferenceCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        BRQTFinish(state, (uint32_t)track.references[@(state->gpr[4])].count); return YES;
    }];
    [registry registerSymbol:@"_GetTrackReference" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        NSArray *references = track.references[@(state->gpr[4])]; NSUInteger index = state->gpr[5];
        NSNumber *reference = index && index <= references.count ? references[index - 1] : nil;
        BRQTFinish(state, reference.unsignedIntValue);
        return YES;
    }];
    [registry registerSymbol:@"_DeleteTrackReference" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[3]];
        NSMutableArray *references = track.references[@(state->gpr[4])]; NSUInteger index = state->gpr[5];
        if (index && index <= references.count) [references removeObjectAtIndex:index - 1];
        BRQTFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_TrackTimeToMediaTime", @"_TrackTimeToMediaDisplayTime"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeTrack *track = [weakSelf track:state->gpr[4]];
            BRQTFinish(state, (uint32_t)((int32_t)state->gpr[3] - track.offset)); return YES;
        }];
    for (NSString *symbol in @[@"_ICMCompressionSessionOptionsCreate",
                               @"_ICMDecompressionSessionOptionsCreate"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeSession *options = [BRPPCQuickTimeSession new];
            options.kind = [symbol containsString:@"Decompression"] ? @"decompression-options"
                                                                     : @"compression-options";
            options.properties = [NSMutableDictionary dictionary];
            uint32_t handle = BRQTObjectHandle(registry, options);
            BOOL valid = state->gpr[4] && handle &&
                [registry.memory writeUInt32:handle address:state->gpr[4]];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    NSArray<NSString *> *compressionOptionSetters = @[
        @"_ICMCompressionSessionOptionsSetAllowFrameReordering",
        @"_ICMCompressionSessionOptionsSetAllowFrameTimeChanges",
        @"_ICMCompressionSessionOptionsSetAllowTemporalCompression",
        @"_ICMCompressionSessionOptionsSetDurationsNeeded",
        @"_ICMCompressionSessionOptionsSetMaxKeyFrameInterval"
    ];
    for (NSString *symbol in compressionOptionSetters)
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeSession *options = BRQTObject(registry, state->gpr[3]);
            uint32_t value = state->gpr[4];
            options.properties[@(symbol.hash)] = [NSData dataWithBytes:&value length:sizeof(value)];
            BRQTFinish(state, options ? 0 : (uint32_t)paramErr); return YES;
        }];
    for (NSString *symbol in @[@"_ICMCompressionSessionOptionsSetProperty",
                               @"_ICMDecompressionSessionOptionsSetProperty"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeSession *options = BRQTObject(registry, state->gpr[3]);
            uint32_t size = state->gpr[6], address = state->gpr[7];
            NSMutableData *data = [NSMutableData dataWithLength:size];
            BOOL valid = options && (!size || [registry.memory readBytes:data.mutableBytes
                                                                address:address length:size]);
            if (valid) options.properties[@(state->gpr[5])] = data;
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_ICMCompressionSessionCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = [BRPPCQuickTimeSession new];
        session.kind = @"compression"; session.timeScale = (int32_t)state->gpr[7];
        session.properties = [NSMutableDictionary dictionary];
        session.callback = BRQTStackWord(registry, state, 11);
        session.refcon = BRQTStackWord(registry, state, 12);
        uint32_t output = BRQTStackWord(registry, state, 13);
        uint32_t handle = BRQTObjectHandle(registry, session);
        BRQTFinish(state, output && handle && [registry.memory writeUInt32:handle address:output]
            ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_ICMCompressionSessionGetTimeScale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = BRQTObject(registry, state->gpr[3]);
        BRQTFinish(state, (uint32_t)session.timeScale); return YES;
    }];
    for (NSString *symbol in @[@"_ICMCompressionSessionEncodeFrame",
                               @"_ICMCompressionSessionCompleteFrames",
                               @"_ICMDecompressionSessionDecodeFrame",
                               @"_ICMDecompressionSessionSetNonScheduledDisplayTime"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeSession *session = BRQTObject(registry, state->gpr[3]);
            BRQTFinish(state, session ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_ICMDecompressionSessionCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = [BRPPCQuickTimeSession new];
        session.kind = @"decompression"; session.properties = [NSMutableDictionary dictionary];
        session.callback = state->gpr[7]; session.refcon = state->gpr[8];
        uint32_t output = state->gpr[9], handle = BRQTObjectHandle(registry, session);
        BRQTFinish(state, output && handle && [registry.memory writeUInt32:handle address:output]
            ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_ICMCompressionSessionRelease",
                               @"_ICMDecompressionSessionRelease",
                               @"_ICMDecompressionSessionOptionsRelease"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_ICMEncodedFrameGetDecodeDuration" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_QTPixelBufferContextCreate", @"_QTOpenGLTextureContextCreate"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeSession *context = [BRPPCQuickTimeSession new];
            context.kind = [symbol containsString:@"PixelBuffer"] ? @"pixel-buffer-context"
                                                                : @"opengl-texture-context";
            context.properties = [NSMutableDictionary dictionary];
            NSUInteger outputPosition = [symbol containsString:@"PixelBuffer"] ? 7 : 9;
            uint32_t output = BRQTStackWord(registry, state, outputPosition);
            uint32_t handle = BRQTObjectHandle(registry, context);
            BRQTFinish(state, output && handle && [registry.memory writeUInt32:handle address:output]
                ? 0 : (uint32_t)paramErr); return YES;
        }];
    for (NSString *symbol in @[@"_QTVisualContextTask", @"_QTVisualContextIsNewImageAvailable"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeSession *context = BRQTObject(registry, state->gpr[3]);
            BRQTFinish(state, [symbol hasSuffix:@"Available"] ? 0 : (context ? 0 : (uint32_t)paramErr));
            return YES;
        }];
    [registry registerSymbol:@"_QTVisualContextCopyImageForTime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_QTNewAtomContainer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = [BRPPCQuickTimeAtomContainer new];
        container.nextAtom = 1; container.atoms = [NSMutableDictionary dictionary];
        uint32_t handle = BRQTObjectHandle(registry, container);
        BRQTFinish(state, state->gpr[3] && handle && [registry.memory writeUInt32:handle address:state->gpr[3]]
            ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_QTInsertChild" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = BRQTObject(registry, state->gpr[3]);
        uint32_t size = state->gpr[8], dataAddress = state->gpr[9];
        NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = [container isKindOfClass:[BRPPCQuickTimeAtomContainer class]] &&
            (!size || [registry.memory readBytes:data.mutableBytes address:dataAddress length:size]);
        uint32_t atom = valid ? container.nextAtom++ : 0;
        if (valid) container.atoms[@(atom)] = data;
        uint32_t output = state->gpr[10];
        if (valid && output) valid = [registry.memory writeUInt32:atom address:output];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_QTSetAtomData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = BRQTObject(registry, state->gpr[3]);
        uint32_t size = state->gpr[5], dataAddress = state->gpr[6];
        NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = [container isKindOfClass:[BRPPCQuickTimeAtomContainer class]] &&
            container.atoms[@(state->gpr[4])] &&
            (!size || [registry.memory readBytes:data.mutableBytes address:dataAddress length:size]);
        if (valid) container.atoms[@(state->gpr[4])] = data;
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_QTCopyAtomDataToPtr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = BRQTObject(registry, state->gpr[3]);
        NSData *data = container.atoms[@(state->gpr[4])]; uint32_t capacity = state->gpr[5];
        uint32_t copied = MIN(capacity, (uint32_t)data.length);
        BOOL valid = data && (!copied || [registry.memory writeBytes:data.bytes
                                                               address:state->gpr[6] length:copied]);
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_QTGetAtomDataPtr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = BRQTObject(registry, state->gpr[3]);
        NSData *data = container.atoms[@(state->gpr[4])];
        uint32_t guestData = data.length && registry.guestAllocator
            ? registry.guestAllocator((uint32_t)data.length, NO) : 0;
        BOOL valid = data && state->gpr[5] && state->gpr[6] &&
            [registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[5]] &&
            [registry.memory writeUInt32:guestData address:state->gpr[6]] &&
            (!data.length || (guestData && [registry.memory writeBytes:data.bytes
                                                               address:guestData length:data.length]));
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_QTFindChildByID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = BRQTObject(registry, state->gpr[3]);
        uint32_t atom = container.atoms[@(state->gpr[6])] ? state->gpr[6] : 0;
        BOOL valid = atom && state->gpr[7] && [registry.memory writeUInt32:atom address:state->gpr[7]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_QTLockContainer", @"_QTUnlockContainer", @"_QTDisposeAtomContainer",
                               @"_QTDisposeHandle"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_QTGetHandleSize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id object = BRQTObject(registry, state->gpr[3]);
        BRQTFinish(state, [object isKindOfClass:[NSData class]] ? (uint32_t)[object length] : 0); return YES;
    }];
    for (NSString *symbol in @[@"_NewMovieFromDataRef", @"_NewMovieFromHandle"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf createMovie];
            BOOL valid = state->gpr[3] && [registry.memory writeUInt32:movie.handle address:state->gpr[3]];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_OpenMovieStorage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *storage = [BRPPCQuickTimeSession new];
        storage.kind = @"movie-storage"; storage.properties = [NSMutableDictionary dictionary];
        uint32_t handle = BRQTObjectHandle(registry, storage);
        BRQTFinish(state, state->gpr[5] && handle && [registry.memory writeUInt32:handle address:state->gpr[5]]
            ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_CreateMovieStorage" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *storage = [BRPPCQuickTimeSession new];
        storage.kind = @"movie-storage"; storage.properties = [NSMutableDictionary dictionary];
        BRPPCQuickTimeMovie *movie = [weakSelf createMovie];
        uint32_t storageHandle = BRQTObjectHandle(registry, storage);
        BOOL valid = state->gpr[8] && state->gpr[9] &&
            [registry.memory writeUInt32:storageHandle address:state->gpr[8]] &&
            [registry.memory writeUInt32:movie.handle address:state->gpr[9]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_CloseMovieStorage", @"_AddMovieToStorage", @"_UpdateMovieInStorage",
                               @"_PutMovieIntoHandle"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_QTNewDataReferenceFromCFURL",
                               @"_QTNewDataReferenceFromFullPathCFString"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id source = BRQTObject(registry, state->gpr[3]);
            uint32_t handle = BRQTObjectHandle(registry, source ?: @"");
            BOOL fullPath = [symbol containsString:@"FullPath"];
            uint32_t dataReferenceOutput = state->gpr[fullPath ? 6 : 5];
            uint32_t typeOutput = state->gpr[fullPath ? 7 : 6];
            BOOL valid = dataReferenceOutput &&
                [registry.memory writeUInt32:handle address:dataReferenceOutput];
            if (valid && typeOutput) valid = [registry.memory writeUInt32:'url ' address:typeOutput];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_QTGetDataReferenceFullPathCFString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id source = BRQTObject(registry, state->gpr[3]);
        NSString *path = [source isKindOfClass:[NSURL class]] ? [source path]
            : ([source isKindOfClass:[NSString class]] ? source : @"");
        uint32_t handle = BRQTObjectHandle(registry, path);
        BOOL valid = state->gpr[6] && [registry.memory writeUInt32:handle address:state->gpr[6]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetMovieUserData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        BRQTFinish(state, BRQTObjectHandle(registry, movie.userData)); return YES;
    }];
    [registry registerSymbol:@"_CopyMovieUserData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *source = [weakSelf movie:state->gpr[3]];
        BRPPCQuickTimeMovie *target = [weakSelf movie:state->gpr[4]];
        [target.userData addEntriesFromDictionary:source.userData];
        BRQTFinish(state, source && target ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_CopyUserData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDictionary *source = BRQTObject(registry, state->gpr[3]);
        NSMutableDictionary *target = BRQTObject(registry, state->gpr[4]);
        if ([source isKindOfClass:[NSDictionary class]] &&
            [target isKindOfClass:[NSMutableDictionary class]]) [target addEntriesFromDictionary:source];
        BRQTFinish(state, source && target ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_NewUserDataFromHandle" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableDictionary *userData = [NSMutableDictionary dictionary];
        uint32_t handle = BRQTObjectHandle(registry, userData);
        BOOL valid = state->gpr[4] && [registry.memory writeUInt32:handle address:state->gpr[4]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetUserDataItem" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableDictionary *userData = BRQTObject(registry, state->gpr[3]);
        uint32_t size = state->gpr[5]; NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = [userData isKindOfClass:[NSMutableDictionary class]] &&
            (!size || [registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:size]);
        if (valid) userData[[NSString stringWithFormat:@"%08x:%u", state->gpr[6], state->gpr[7]]] = data;
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AddUserDataText" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableDictionary *userData = BRQTObject(registry, state->gpr[3]);
        NSString *key = [NSString stringWithFormat:@"%08x:%u", state->gpr[5], state->gpr[7]];
        uint32_t source = state->gpr[4]; NSMutableData *data = [NSMutableData dataWithLength:256];
        BOOL valid = [userData isKindOfClass:[NSMutableDictionary class]] && source &&
            [registry.memory readBytes:data.mutableBytes address:source length:data.length];
        if (valid) userData[key] = data; BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetUserDataText" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDictionary *userData = BRQTObject(registry, state->gpr[3]);
        NSString *key = [NSString stringWithFormat:@"%08x:%u", state->gpr[5], state->gpr[7]];
        NSData *data = userData[key]; BOOL valid = data && state->gpr[4] &&
            [registry.memory writeBytes:data.bytes address:state->gpr[4] length:data.length];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    NSArray<NSString *> *propertySetters = @[@"_QTSetMovieProperty", @"_QTSetComponentProperty",
        @"_QTSetProcessProperty", @"_ICMImageDescriptionSetProperty"];
    for (NSString *symbol in propertySetters)
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t size = state->gpr[6], address = state->gpr[7];
            NSMutableData *data = [NSMutableData dataWithLength:size];
            BOOL valid = state->gpr[3] && (!size ||
                [registry.memory readBytes:data.mutableBytes address:address length:size]);
            NSString *key = [NSString stringWithFormat:@"%08x:%08x:%08x",
                             state->gpr[3], state->gpr[4], state->gpr[5]];
            if (valid) weakSelf.externalProperties[key] = data;
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    NSArray<NSString *> *propertyGetters = @[@"_QTGetMovieProperty", @"_QTGetComponentProperty",
        @"_ICMImageDescriptionGetProperty", @"_QTSoundDescriptionGetProperty"];
    for (NSString *symbol in propertyGetters)
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *key = [NSString stringWithFormat:@"%08x:%08x:%08x",
                state->gpr[3], state->gpr[4], state->gpr[5]];
            NSData *data = weakSelf.externalProperties[key]; uint32_t capacity = state->gpr[6];
            uint32_t copied = MIN(capacity, (uint32_t)data.length);
            BOOL valid = data && (!copied || [registry.memory writeBytes:data.bytes
                                                                   address:state->gpr[7] length:copied]);
            if (state->gpr[8]) valid = valid && [registry.memory writeUInt32:(uint32_t)data.length
                                                                     address:state->gpr[8]];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_QTSoundDescriptionCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *description = [BRPPCQuickTimeSession new];
        description.kind = @"sound-description"; description.properties = [NSMutableDictionary dictionary];
        uint32_t handle = BRQTObjectHandle(registry, description);
        BOOL valid = state->gpr[9] && [registry.memory writeUInt32:handle address:state->gpr[9]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetMovieTime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        if (state->gpr[4]) {
            [registry.memory writeUInt32:(uint32_t)((uint64_t)movie.time >> 32) address:state->gpr[4]];
            [registry.memory writeUInt32:(uint32_t)movie.time address:state->gpr[4] + 4];
            [registry.memory writeUInt32:(uint32_t)movie.timeScale address:state->gpr[4] + 8];
            [registry.memory writeUInt32:0 address:state->gpr[4] + 12];
        }
        BRQTFinish(state, (uint32_t)movie.time); return YES;
    }];
    [registry registerSymbol:@"_GetTrackOffset" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, (uint32_t)[weakSelf track:state->gpr[3]].offset); return YES;
    }];
    [registry registerSymbol:@"_MediaTimeToSampleNum" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        int64_t duration = medium.sampleCount ? medium.duration / medium.sampleCount : 0;
        uint32_t sample = duration > 0 ? (uint32_t)((int32_t)state->gpr[4] / duration) + 1 : 0;
        BOOL valid = medium && state->gpr[5] && [registry.memory writeUInt32:sample address:state->gpr[5]];
        if (valid && state->gpr[6]) valid = [registry.memory writeUInt32:(sample ? sample - 1 : 0) *
            (uint32_t)duration address:state->gpr[6]];
        if (valid && state->gpr[7]) valid = [registry.memory writeUInt32:(uint32_t)duration address:state->gpr[7]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_QTSampleNumToChunkNum" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, state->gpr[4]); return YES;
    }];
    for (NSString *symbol in @[@"_GetMediaNextInterestingDecodeTime", @"_GetTrackNextInterestingTime"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t outputTime = state->gpr[7], outputDuration = state->gpr[8];
            BOOL valid = outputTime && [registry.memory writeUInt32:state->gpr[5] address:outputTime];
            if (valid && outputDuration) valid = [registry.memory writeUInt32:1 address:outputDuration];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_GetMovieIndTrackType" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        NSUInteger index = state->gpr[4]; NSNumber *track = index && index <= movie.tracks.count
            ? movie.tracks[index - 1] : nil; BRQTFinish(state, track.unsignedIntValue); return YES;
    }];
    for (NSString *symbol in @[@"_PrerollMovie", @"_MCMovieChanged", @"_MediaCompareForCopy",
                               @"_GenerateMovieApertureModeDimensions",
                               @"_RemoveMovieApertureModeDimensions",
                               @"_ExtendMediaDecodeDurationToDisplayEndTime"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_MovieAudioExtractionBegin" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = [BRPPCQuickTimeSession new];
        session.kind = @"audio-extraction"; session.properties = [NSMutableDictionary dictionary];
        uint32_t handle = BRQTObjectHandle(registry, session);
        BOOL valid = [weakSelf movie:state->gpr[3]] && state->gpr[5] &&
            [registry.memory writeUInt32:handle address:state->gpr[5]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_MovieAudioExtractionSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = BRQTObject(registry, state->gpr[3]);
        uint32_t size = state->gpr[5]; NSMutableData *data = [NSMutableData dataWithLength:size];
        BOOL valid = [session.kind isEqualToString:@"audio-extraction"] &&
            (!size || [registry.memory readBytes:data.mutableBytes address:state->gpr[6] length:size]);
        if (valid) session.properties[@(state->gpr[4])] = data;
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_MovieAudioExtractionGetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = BRQTObject(registry, state->gpr[3]);
        NSData *data = session.properties[@(state->gpr[4])]; uint32_t capacity = 0;
        BOOL valid = state->gpr[5] && [registry.memory readUInt32:&capacity address:state->gpr[5]];
        uint32_t copied = MIN(capacity, (uint32_t)data.length);
        if (valid && copied) valid = [registry.memory writeBytes:data.bytes address:state->gpr[6] length:copied];
        if (valid) valid = [registry.memory writeUInt32:(uint32_t)data.length address:state->gpr[5]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_MovieAudioExtractionFillBuffer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = BRQTObject(registry, state->gpr[3]);
        BOOL valid = [session.kind isEqualToString:@"audio-extraction"] && state->gpr[4] &&
            [registry.memory writeUInt32:0 address:state->gpr[4]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_MovieAudioExtractionEnd" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *session = BRQTObject(registry, state->gpr[3]);
        BRQTFinish(state, [session.kind isEqualToString:@"audio-extraction"] ? 0 : (uint32_t)paramErr);
        return YES;
    }];
    [registry registerSymbol:@"_MovieExportGetSettingsAsAtomContainer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = [BRPPCQuickTimeAtomContainer new];
        container.nextAtom = 1; container.atoms = [NSMutableDictionary dictionary];
        uint32_t handle = BRQTObjectHandle(registry, container);
        BOOL valid = state->gpr[4] && [registry.memory writeUInt32:handle address:state->gpr[4]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_MovieExportSetSettingsFromAtomContainer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeAtomContainer *container = BRQTObject(registry, state->gpr[4]);
        BRQTFinish(state, container ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_MovieExportDoUserDialog", @"_QTMovieExportSessionDoUserDialog"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; if (state->gpr[7]) [registry.memory writeUInt32:0 address:state->gpr[7]];
            BRQTFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_MovieExportAddDataSource", @"_MovieExportFromProceduresToDataRef",
        @"_MovieExportSetProgressProc", @"_MovieExportDisposeGetDataAndPropertiesProcs"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_MovieExportNewGetDataAndPropertiesProcs" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = state->gpr[9] && state->gpr[10] &&
            [registry.memory writeUInt32:0 address:state->gpr[9]] &&
            [registry.memory writeUInt32:0 address:state->gpr[10]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_SCGetSettingsAsAtomContainer", @"_SCCopyCompressionSessionOptions"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeAtomContainer *container = [BRPPCQuickTimeAtomContainer new];
            container.nextAtom = 1; container.atoms = [NSMutableDictionary dictionary];
            uint32_t output = state->gpr[4], handle = BRQTObjectHandle(registry, container);
            BRQTFinish(state, output && [registry.memory writeUInt32:handle address:output]
                ? 0 : (uint32_t)paramErr); return YES;
        }];
    for (NSString *symbol in @[@"_SCSetSettingsFromAtomContainer", @"_SCRequestSequenceSettings",
                               @"_SCGetInfo", @"_SCSetInfo"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    NSArray<NSString *> *codecBandCalls = @[@"_ImageCodecBandDecompress", @"_ImageCodecBeginBand",
        @"_ImageCodecDecodeBand", @"_ImageCodecDrawBand", @"_ImageCodecDroppingFrame",
        @"_ImageCodecEndBand", @"_ImageCodecPreDecompress", @"_ImageCodecQueueStarting",
        @"_ImageCodecQueueStopping"];
    for (NSString *symbol in codecBandCalls)
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CanQuickTimeOpenDataRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = YES;
        if (state->gpr[6]) valid = [registry.memory writeUInt32:1 address:state->gpr[6]];
        if (valid && state->gpr[7]) valid = [registry.memory writeUInt32:0 address:state->gpr[7]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_FindCodec" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BOOL valid = YES;
        if (state->gpr[7]) valid = [registry.memory writeUInt32:0 address:state->gpr[7]];
        if (valid && state->gpr[8]) valid = [registry.memory writeUInt32:0 address:state->gpr[8]];
        BRQTFinish(state, valid ? (uint32_t)codecErr : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AddMediaSampleFromEncodedFrame" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        if (medium) { medium.sampleCount++; medium.syncSampleCount++; medium.duration++; }
        BRQTFinish(state, medium ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_AddMediaSampleReferences64" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        uint32_t count = state->gpr[5]; medium.sampleCount += count; medium.syncSampleCount += count;
        medium.duration += count; BRQTFinish(state, medium ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetMediaSampleReferences64" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        uint32_t requested = state->gpr[7], returned = MIN(requested, medium.sampleCount);
        BOOL valid = medium && state->gpr[8] && [registry.memory writeUInt32:returned address:state->gpr[8]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetMediaSample2" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        if (state->gpr[7]) [registry.memory writeUInt32:0 address:state->gpr[7]];
        if (state->gpr[8]) [registry.memory writeUInt32:0 address:state->gpr[8]];
        BRQTFinish(state, medium ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_GetMediaDisplayDuration", @"_GetMediaInputMap"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
            BRQTFinish(state, [symbol containsString:@"Duration"] ? (uint32_t)medium.duration
                                                                  : medium.inputMap); return YES;
        }];
    [registry registerSymbol:@"_SetMediaInputMap" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf medium:state->gpr[3]].inputMap = state->gpr[4];
        BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetMediaHandlerDescription" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMedia *medium = [weakSelf medium:state->gpr[3]];
        BOOL valid = medium && state->gpr[4] && [registry.memory writeUInt32:medium.type address:state->gpr[4]];
        if (valid && state->gpr[5]) valid = [registry.memory writeUInt32:0 address:state->gpr[5]];
        if (valid && state->gpr[6]) valid = [registry.memory writeUInt32:0 address:state->gpr[6]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_GetMovieAnchorDataRef", @"_GetMovieDefaultDataRef"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BOOL valid = [weakSelf movie:state->gpr[3]] != nil;
            if (valid && state->gpr[4]) valid = [registry.memory writeUInt32:0 address:state->gpr[4]];
            if (valid && state->gpr[5]) valid = [registry.memory writeUInt32:0 address:state->gpr[5]];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_GetMovieAudioContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        BRQTFinish(state, movie.audioContext); return YES;
    }];
    [registry registerSymbol:@"_GetMovieAudioVolumeLevels" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t channels = state->gpr[4], address = state->gpr[5]; BOOL valid = address != 0;
        for (uint32_t index = 0; valid && index < channels; index++)
            valid = [registry.memory writeUInt32:0 address:address + index * 4];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetMovieAudioVolumeMeteringEnabled" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf movie:state->gpr[3]].audioMetering = state->gpr[4] != 0;
        BRQTFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_GetMovieBox", @"_GetMovieMatrix"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
            NSData *data = [symbol containsString:@"Box"] ? movie.box : movie.matrix;
            NSUInteger size = [symbol containsString:@"Box"] ? 8 : 36;
            if (!data) data = [NSMutableData dataWithLength:size];
            BOOL valid = state->gpr[4] && [registry.memory writeBytes:data.bytes
                                                               address:state->gpr[4] length:size];
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    for (NSString *symbol in @[@"_SetMovieBox", @"_SetMovieMatrix"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
            NSUInteger size = [symbol containsString:@"Box"] ? 8 : 36;
            NSMutableData *data = [NSMutableData dataWithLength:size];
            BOOL valid = movie && [registry.memory readBytes:data.mutableBytes
                                                      address:state->gpr[4] length:size];
            if ([symbol containsString:@"Box"]) movie.box = data; else movie.matrix = data;
            BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
        }];
    [registry registerSymbol:@"_SetMoviePlayHints" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        movie.playHints = (movie.playHints & ~state->gpr[5]) | (state->gpr[4] & state->gpr[5]);
        BRQTFinish(state, movie ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_SetMovieProgressProc" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [weakSelf movie:state->gpr[3]].progressProc = state->gpr[4];
        BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_GetMovieTimeBase" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeMovie *movie = [weakSelf movie:state->gpr[3]];
        if (!movie.timeBase) {
            BRPPCQuickTimeSession *timeBase = [BRPPCQuickTimeSession new];
            timeBase.kind = @"time-base"; timeBase.timeScale = movie.timeScale;
            timeBase.properties = [NSMutableDictionary dictionary];
            movie.timeBase = BRQTObjectHandle(registry, timeBase);
        }
        BRQTFinish(state, movie.timeBase); return YES;
    }];
    [registry registerSymbol:@"_GetTimeBaseStatus" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *timeBase = BRQTObject(registry, state->gpr[3]);
        if (state->gpr[4]) [registry.memory writeUInt32:0 address:state->gpr[4]];
        BRQTFinish(state, timeBase ? 0 : (uint32_t)paramErr); return YES;
    }];
    [registry registerSymbol:@"_GetTimeBaseTime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *timeBase = BRQTObject(registry, state->gpr[3]);
        if (state->gpr[5]) {
            [registry.memory writeUInt32:0 address:state->gpr[5]];
            [registry.memory writeUInt32:0 address:state->gpr[5] + 4];
            [registry.memory writeUInt32:state->gpr[4] ?: (uint32_t)timeBase.timeScale address:state->gpr[5] + 8];
            [registry.memory writeUInt32:state->gpr[3] address:state->gpr[5] + 12];
        }
        BRQTFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_SetTimeBaseMasterTimeBase" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCQuickTimeSession *timeBase = BRQTObject(registry, state->gpr[3]);
        uint32_t master = state->gpr[4];
        timeBase.properties[@((uint32_t)'mast')] = [NSData dataWithBytes:&master length:sizeof(master)];
        BRQTFinish(state, timeBase ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_ScaleTrackSegment", @"_ScaleMovieSegment"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; int64_t duration = (int32_t)state->gpr[5];
            if ([symbol containsString:@"Track"]) [weakSelf track:state->gpr[3]].duration = duration;
            else [weakSelf movie:state->gpr[3]].duration = duration;
            BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_QTNewDataReferenceFromFSRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *reference = [NSMutableData dataWithLength:80];
        BOOL valid = state->gpr[3] && [registry.memory readBytes:reference.mutableBytes
                                                        address:state->gpr[3] length:reference.length];
        uint32_t handle = BRQTObjectHandle(registry, reference);
        if (valid) valid = state->gpr[4] && [registry.memory writeUInt32:handle address:state->gpr[4]];
        if (valid && state->gpr[5]) valid = [registry.memory writeUInt32:'alis' address:state->gpr[5]];
        BRQTFinish(state, valid ? 0 : (uint32_t)paramErr); return YES;
    }];
    for (NSString *symbol in @[@"_GetImageDescriptionExtension", @"_ICMUpdateImageDescriptionForCVPixelBuffer",
                               @"_QTGetMediaChunkInfo", @"_QTGetMediaSampleSizes",
                               @"_ConvertMovieToDataRef"])
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRQTFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_GetMoviesError" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRQTFinish(state, (uint32_t)weakSelf.moviesError); return YES;
    }];
    return YES;
}
@end
