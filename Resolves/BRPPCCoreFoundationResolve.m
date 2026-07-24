#import "BRPPCCoreFoundationResolve.h"
#import "BRPPCAddressSpace.h"
#import "BRPPCGuestLayout.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

static NSString * const BRPPCCoreFoundationErrorDomain = @"theoderoy.Bismuth.core-foundation";
static char BRPPCMachPortRecordAssociation;
static char BRPPCMessagePortRecordAssociation;
static char BRPPCUserNotificationRecordAssociation;

typedef struct {
    int32_t year;
    int8_t month;
    int8_t day;
    int8_t hour;
    int8_t minute;
    double second;
} BRHostGregorianDate;

typedef struct {
    int32_t years;
    int32_t months;
    int32_t days;
    int32_t hours;
    int32_t minutes;
    double seconds;
} BRHostGregorianUnits;

static double DoubleFromGuestWords(uint32_t high, uint32_t low) {
    uint64_t bits = (uint64_t)high << 32 | low; double value = 0;
    memcpy(&value, &bits, sizeof(value)); return value;
}

@interface BRPPCGuestTimerRecord : NSObject
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callout;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@property(nonatomic) BOOL released;
@property(nonatomic, strong) id timer;
@end
@implementation BRPPCGuestTimerRecord
@end

@interface BRPPCGuestSourceRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@property(nonatomic) uint32_t equalFunction;
@property(nonatomic) uint32_t hashFunction;
@property(nonatomic) uint32_t scheduleFunction;
@property(nonatomic) uint32_t cancelFunction;
@property(nonatomic) uint32_t performFunction;
@property(nonatomic) BOOL released;
@property(nonatomic, strong) id source;
@end
@implementation BRPPCGuestSourceRecord
@end

@interface BRPPCGuestNotificationRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t callback;
@property(nonatomic) uint32_t observer;
@property(nonatomic, strong) id center;
@property(nonatomic, strong) NSString *name;
@property(nonatomic, strong) id object;
@end
@implementation BRPPCGuestNotificationRecord
@end

@interface BRPPCGuestHeapRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t valueRetain;
@property(nonatomic) uint32_t valueRelease;
@property(nonatomic) uint32_t valueDescription;
@property(nonatomic) uint32_t comparator;
@property(nonatomic) uint32_t contextInfo;
@property(nonatomic) uint32_t contextRetain;
@property(nonatomic) uint32_t contextRelease;
@property(nonatomic) uint32_t contextDescription;
@property(nonatomic) BOOL stringCallbacks;
@end
@implementation BRPPCGuestHeapRecord
@end

@interface BRPPCGuestHeapValue : NSObject
@property(nonatomic, strong) BRPPCGuestHeapRecord *record;
@property(nonatomic) uint32_t guestValue;
@end
@implementation BRPPCGuestHeapValue
@end

@interface BRPPCGuestTreeRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@end
@implementation BRPPCGuestTreeRecord
@end

@interface BRPPCGuestAllocatorRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@property(nonatomic) uint32_t allocateFunction;
@property(nonatomic) uint32_t reallocateFunction;
@property(nonatomic) uint32_t deallocateFunction;
@property(nonatomic) uint32_t preferredSizeFunction;
@end
@implementation BRPPCGuestAllocatorRecord
@end

@interface BRPPCGuestStreamRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callback;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@property(nonatomic, strong) NSMutableData *writeBuffer;
@property(nonatomic) uint32_t guestBufferAddress;
@property(nonatomic) uint32_t bufferCapacity;
@end
@implementation BRPPCGuestStreamRecord
@end

@interface BRPPCGuestSocketRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callout;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@end
@implementation BRPPCGuestSocketRecord
@end

@interface BRPPCGuestFileDescriptorRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callout;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@end
@implementation BRPPCGuestFileDescriptorRecord
@end

@interface BRPPCGuestMachPortRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callout;
@property(nonatomic) uint32_t invalidationCallout;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@end
@implementation BRPPCGuestMachPortRecord
@end

@interface BRPPCGuestMessagePortRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callout;
@property(nonatomic) uint32_t invalidationCallout;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@end
@implementation BRPPCGuestMessagePortRecord
@end

@interface BRPPCGuestUserNotificationRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t callout;
@end
@implementation BRPPCGuestUserNotificationRecord
@end

@interface BRPPCGuestXMLParserRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t createStructure;
@property(nonatomic) uint32_t addChild;
@property(nonatomic) uint32_t endStructure;
@property(nonatomic) uint32_t resolveEntity;
@property(nonatomic) uint32_t handleError;
@property(nonatomic) uint32_t info;
@property(nonatomic) uint32_t retainFunction;
@property(nonatomic) uint32_t releaseFunction;
@property(nonatomic) uint32_t descriptionFunction;
@end
@implementation BRPPCGuestXMLParserRecord
@end

@interface BRPPCGuestExternalStringRecord : NSObject
@property(nonatomic) uint32_t address;
@property(nonatomic) uint32_t capacity;
@property(nonatomic) BOOL ownsBuffer;
@end
@implementation BRPPCGuestExternalStringRecord
@end

@interface BRPPCGuestPlugInFactoryRecord : NSObject
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t function;
@property(nonatomic, strong) id factoryUUID;
@property(nonatomic, strong) id plugIn;
@property(nonatomic, strong) NSMutableSet *types;
@property(nonatomic) NSUInteger instanceCount;
@end
@implementation BRPPCGuestPlugInFactoryRecord
@end

@interface BRPPCGuestPlugInInstanceRecord : NSObject
@property(nonatomic, weak) BRPPCCoreFoundationResolve *resolver;
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t handle;
@property(nonatomic) uint32_t dataAddress;
@property(nonatomic) uint32_t deallocateFunction;
@property(nonatomic) uint32_t getInterfaceFunction;
@property(nonatomic, strong) NSString *factoryName;
@end
@implementation BRPPCGuestPlugInInstanceRecord
@end

@interface BRPPCGuestBlockRecord : NSObject
@property(nonatomic) BRPPCState outerState;
@property(nonatomic) uint32_t address;
@property(nonatomic) uint32_t invoke;
@property(nonatomic) uint32_t handle;
@property(nonatomic, strong) id hostObject;
@end
@implementation BRPPCGuestBlockRecord
@end

@interface BRPPCCoreFoundationResolve ()
@property(nonatomic, weak) BRPPCResolveRegistry *registry;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *copiedBytePointers;
@property(nonatomic) uint32_t availableStringEncodingsAddress;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestTimerRecord *> *timerRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestTimerRecord *> *observerRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestSourceRecord *> *sourceRecords;
@property(nonatomic, strong) NSMutableArray<BRPPCGuestNotificationRecord *> *notificationRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestHeapRecord *> *heapRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestTreeRecord *> *treeRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *allocatorSizes;
@property(nonatomic) uint32_t defaultAllocatorHandle;
@property(nonatomic) uint32_t nullAllocatorHandle;
@property(nonatomic, strong) NSMutableDictionary<NSData *, id> *constantUUIDs;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestStreamRecord *> *streamRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *streamBufferPointers;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestSocketRecord *> *socketRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestFileDescriptorRecord *> *fileDescriptorRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestMachPortRecord *> *machPortRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestMessagePortRecord *> *messagePortRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestUserNotificationRecord *> *userNotificationRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestXMLParserRecord *> *xmlParserRecords;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *aclRecords;
@property(nonatomic) uint32_t nextACLHandle;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *xmlNodeInfoPointers;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestExternalStringRecord *> *externalStringRecords;
@property(nonatomic, strong) NSMutableDictionary *plugInFactories;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestPlugInInstanceRecord *> *plugInInstances;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, BRPPCGuestBlockRecord *> *runLoopBlockRecords;
@property(nonatomic, strong) NSError *pendingCallbackError;
- (BOOL)invokeGuestFunction:(uint32_t)function outerState:(BRPPCState)outerState
                   arguments:(NSArray<NSNumber *> *)arguments result:(uint32_t *)result
                       label:(NSString *)label error:(NSError **)error;
- (id)object:(uint32_t)address;
- (NSString *)string:(uint32_t)address;
@end

static void RecordSourceError(BRPPCGuestSourceRecord *record, NSError *error) {
    if (!record.resolver || !error) return;
    record.resolver.pendingCallbackError = error;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

static const void *RetainSourceRecord(const void *info) {
    return CFRetain((__bridge CFTypeRef)(__bridge id)info);
}

static void ReleaseSourceRecord(const void *info) {
    CFRelease((__bridge CFTypeRef)(__bridge id)info);
}

static CFStringRef CopySourceDescription(const void *info) {
    BRPPCGuestSourceRecord *record = (__bridge BRPPCGuestSourceRecord *)info;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC run-loop source 0x%08x>"), record.handle);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFRunLoopSource description" error:&error]) {
        RecordSourceError(record, error); return NULL;
    }
    id value = record.resolver.registry.guestObjectDecoder
        ? record.resolver.registry.guestObjectDecoder(result) : nil;
    return [value isKindOfClass:[NSString class]] ? CFBridgingRetain(value) : NULL;
}

static Boolean EqualSourceRecords(const void *firstInfo, const void *secondInfo) {
    BRPPCGuestSourceRecord *first = (__bridge BRPPCGuestSourceRecord *)firstInfo;
    BRPPCGuestSourceRecord *second = (__bridge BRPPCGuestSourceRecord *)secondInfo;
    if (!first.equalFunction) return first.info == second.info;
    uint32_t result = 0; NSError *error = nil;
    if (![first.resolver invokeGuestFunction:first.equalFunction outerState:first.outerState
        arguments:@[@(first.info), @(second.info)] result:&result label:@"CFRunLoopSource equality" error:&error]) {
        RecordSourceError(first, error); return false;
    }
    return result != 0;
}

static CFHashCode HashSourceRecord(const void *info) {
    BRPPCGuestSourceRecord *record = (__bridge BRPPCGuestSourceRecord *)info;
    if (!record.hashFunction) return record.info;
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.hashFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFRunLoopSource hash" error:&error]) {
        RecordSourceError(record, error); return 0;
    }
    return result;
}

static void ScheduleSource(void *info, CFRunLoopRef runLoop, CFStringRef mode) {
    BRPPCGuestSourceRecord *record = (__bridge BRPPCGuestSourceRecord *)info;
    if (!record.scheduleFunction) return;
    uint32_t runLoopHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)runLoop) : 0;
    uint32_t modeHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)mode) : 0;
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.scheduleFunction outerState:record.outerState
        arguments:@[@(record.info), @(runLoopHandle), @(modeHandle)] result:NULL
        label:@"CFRunLoopSource schedule" error:&error]) RecordSourceError(record, error);
}

static void CancelSource(void *info, CFRunLoopRef runLoop, CFStringRef mode) {
    BRPPCGuestSourceRecord *record = (__bridge BRPPCGuestSourceRecord *)info;
    if (!record.cancelFunction) return;
    uint32_t runLoopHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)runLoop) : 0;
    uint32_t modeHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)mode) : 0;
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.cancelFunction outerState:record.outerState
        arguments:@[@(record.info), @(runLoopHandle), @(modeHandle)] result:NULL
        label:@"CFRunLoopSource cancel" error:&error]) RecordSourceError(record, error);
}

static void PerformSource(void *info) {
    BRPPCGuestSourceRecord *record = (__bridge BRPPCGuestSourceRecord *)info;
    if (!record.performFunction) return;
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.performFunction outerState:record.outerState
        arguments:@[@(record.info)] result:NULL label:@"CFRunLoopSource perform" error:&error])
        RecordSourceError(record, error);
}

static void DeliverNotification(CFNotificationCenterRef center, void *observer,
                                CFNotificationName name, const void *object,
                                CFDictionaryRef userInfo) {
    (void)center;
    BRPPCGuestNotificationRecord *record = (__bridge BRPPCGuestNotificationRecord *)observer;
    BRPPCCoreFoundationResolve *resolver = record.resolver;
    if (!resolver || !record.callback) return;
    uint32_t centerHandle = resolver.registry.guestObjectEncoder
        ? resolver.registry.guestObjectEncoder(record.center) : 0;
    uint32_t nameHandle = resolver.registry.guestObjectEncoder
        ? resolver.registry.guestObjectEncoder((__bridge id)name) : 0;
    uint32_t objectHandle = resolver.registry.guestObjectEncoder
        ? resolver.registry.guestObjectEncoder((__bridge id)object) : 0;
    uint32_t userInfoHandle = resolver.registry.guestObjectEncoder
        ? resolver.registry.guestObjectEncoder((__bridge id)userInfo) : 0;
    NSError *error = nil;
    if (![resolver invokeGuestFunction:record.callback outerState:record.outerState
        arguments:@[@(centerHandle), @(record.observer), @(nameHandle), @(objectHandle), @(userInfoHandle)]
        result:NULL label:@"CFNotificationCenter callout" error:&error]) resolver.pendingCallbackError = error;
}

static void RecordHeapError(BRPPCGuestHeapRecord *record, NSError *error) {
    if (record.resolver && error) record.resolver.pendingCallbackError = error;
}

static const void *RetainHeapValue(CFAllocatorRef allocator, const void *pointer) {
    (void)allocator;
    BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)pointer;
    if (value.record.valueRetain) {
        uint32_t result = 0; NSError *error = nil;
        if (![value.record.resolver invokeGuestFunction:value.record.valueRetain
            outerState:value.record.outerState arguments:@[@0, @(value.guestValue)] result:&result
            label:@"CFBinaryHeap value retain" error:&error]) RecordHeapError(value.record, error);
        else value.guestValue = result;
    }
    CFRetain((CFTypeRef)pointer);
    return pointer;
}

static void ReleaseHeapValue(CFAllocatorRef allocator, const void *pointer) {
    (void)allocator;
    BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)pointer;
    if (value.record.valueRelease) {
        NSError *error = nil;
        if (![value.record.resolver invokeGuestFunction:value.record.valueRelease
            outerState:value.record.outerState arguments:@[@0, @(value.guestValue)] result:NULL
            label:@"CFBinaryHeap value release" error:&error]) RecordHeapError(value.record, error);
    }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyHeapValueDescription(const void *pointer) {
    BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)pointer;
    if (!value.record.valueDescription) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC heap value 0x%08x>"), value.guestValue);
    uint32_t result = 0; NSError *error = nil;
    if (![value.record.resolver invokeGuestFunction:value.record.valueDescription
        outerState:value.record.outerState arguments:@[@(value.guestValue)] result:&result
        label:@"CFBinaryHeap value description" error:&error]) {
        RecordHeapError(value.record, error); return NULL;
    }
    id description = [value.record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static CFComparisonResult CompareHeapValues(const void *firstPointer, const void *secondPointer, void *context) {
    BRPPCGuestHeapValue *first = (__bridge BRPPCGuestHeapValue *)firstPointer;
    BRPPCGuestHeapValue *second = (__bridge BRPPCGuestHeapValue *)secondPointer;
    BRPPCGuestHeapRecord *record = (__bridge BRPPCGuestHeapRecord *)context;
    if (record.stringCallbacks) {
        NSString *firstString = [record.resolver string:first.guestValue];
        NSString *secondString = [record.resolver string:second.guestValue];
        return (CFComparisonResult)[firstString compare:secondString];
    }
    if (!record.comparator) return first.guestValue < second.guestValue ? kCFCompareLessThan
        : first.guestValue > second.guestValue ? kCFCompareGreaterThan : kCFCompareEqualTo;
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.comparator outerState:record.outerState
        arguments:@[@(first.guestValue), @(second.guestValue), @(record.contextInfo)] result:&result
        label:@"CFBinaryHeap comparator" error:&error]) {
        RecordHeapError(record, error); return kCFCompareEqualTo;
    }
    return (CFComparisonResult)(int32_t)result;
}

static const void *RetainHeapContext(const void *pointer) {
    BRPPCGuestHeapRecord *record = (__bridge BRPPCGuestHeapRecord *)pointer;
    if (record.contextRetain) {
        uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.contextRetain outerState:record.outerState
            arguments:@[@(record.contextInfo)] result:&result label:@"CFBinaryHeap context retain" error:&error])
            RecordHeapError(record, error);
        else record.contextInfo = result;
    }
    CFRetain((CFTypeRef)pointer);
    return pointer;
}

static void ReleaseHeapContext(const void *pointer) {
    BRPPCGuestHeapRecord *record = (__bridge BRPPCGuestHeapRecord *)pointer;
    if (record.contextRelease) {
        NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.contextRelease outerState:record.outerState
            arguments:@[@(record.contextInfo)] result:NULL label:@"CFBinaryHeap context release" error:&error])
            RecordHeapError(record, error);
    }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyHeapContextDescription(const void *pointer) {
    BRPPCGuestHeapRecord *record = (__bridge BRPPCGuestHeapRecord *)pointer;
    if (!record.contextDescription) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC heap context 0x%08x>"), record.contextInfo);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.contextDescription outerState:record.outerState
        arguments:@[@(record.contextInfo)] result:&result label:@"CFBinaryHeap context description" error:&error]) {
        RecordHeapError(record, error); return NULL;
    }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void RecordTreeError(BRPPCGuestTreeRecord *record, NSError *error) {
    if (record.resolver && error) record.resolver.pendingCallbackError = error;
}

static const void *RetainTreeContext(const void *pointer) {
    BRPPCGuestTreeRecord *record = (__bridge BRPPCGuestTreeRecord *)pointer;
    if (record.retainFunction) {
        uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFTree context retain" error:&error])
            RecordTreeError(record, error);
        else record.info = result;
    }
    CFRetain((CFTypeRef)pointer);
    return pointer;
}

static void ReleaseTreeContext(const void *pointer) {
    BRPPCGuestTreeRecord *record = (__bridge BRPPCGuestTreeRecord *)pointer;
    if (record.releaseFunction) {
        NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFTree context release" error:&error])
            RecordTreeError(record, error);
    }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyTreeContextDescription(const void *pointer) {
    BRPPCGuestTreeRecord *record = (__bridge BRPPCGuestTreeRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC tree context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFTree context description" error:&error]) {
        RecordTreeError(record, error); return NULL;
    }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void RecordStreamError(BRPPCGuestStreamRecord *record, NSError *error) {
    if (!record.resolver || !error) return;
    record.resolver.pendingCallbackError = error; CFRunLoopStop(CFRunLoopGetCurrent());
}

static void *RetainStreamContext(void *pointer) {
    BRPPCGuestStreamRecord *record = (__bridge BRPPCGuestStreamRecord *)pointer;
    if (record.retainFunction) {
        uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFStream context retain" error:&error])
            RecordStreamError(record, error);
        else record.info = result;
    }
    CFRetain((CFTypeRef)pointer); return pointer;
}

static void ReleaseStreamContext(void *pointer) {
    BRPPCGuestStreamRecord *record = (__bridge BRPPCGuestStreamRecord *)pointer;
    if (record.releaseFunction) {
        NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFStream context release" error:&error])
            RecordStreamError(record, error);
    }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyStreamContextDescription(void *pointer) {
    BRPPCGuestStreamRecord *record = (__bridge BRPPCGuestStreamRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC stream context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFStream context description" error:&error]) {
        RecordStreamError(record, error); return NULL;
    }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void DeliverStreamEvent(BRPPCGuestStreamRecord *record, CFStreamEventType type) {
    if (!record.callback) return; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.callback outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)type), @(record.info)] result:NULL
        label:@"CFStream client" error:&error]) RecordStreamError(record, error);
}

static void DeliverReadStreamEvent(CFReadStreamRef stream, CFStreamEventType type, void *pointer) {
    (void)stream; DeliverStreamEvent((__bridge BRPPCGuestStreamRecord *)pointer, type);
}

static void DeliverWriteStreamEvent(CFWriteStreamRef stream, CFStreamEventType type, void *pointer) {
    (void)stream; DeliverStreamEvent((__bridge BRPPCGuestStreamRecord *)pointer, type);
}

static CFStringRef HostCFStringConstant(const char *name) {
    CFStringRef *pointer = dlsym(RTLD_DEFAULT, name); return pointer ? *pointer : NULL;
}

static void RecordSocketError(BRPPCGuestSocketRecord *record, NSError *error) {
    if (!record.resolver || !error) return;
    record.resolver.pendingCallbackError = error; CFRunLoopStop(CFRunLoopGetCurrent());
}

static const void *RetainSocketContext(const void *pointer) {
    BRPPCGuestSocketRecord *record = (__bridge BRPPCGuestSocketRecord *)pointer;
    if (record.retainFunction) { uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFSocket context retain" error:&error])
            RecordSocketError(record, error); else record.info = result; }
    CFRetain((CFTypeRef)pointer); return pointer;
}

static void ReleaseSocketContext(const void *pointer) {
    BRPPCGuestSocketRecord *record = (__bridge BRPPCGuestSocketRecord *)pointer;
    if (record.releaseFunction) { NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFSocket context release" error:&error])
            RecordSocketError(record, error); }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopySocketContextDescription(const void *pointer) {
    BRPPCGuestSocketRecord *record = (__bridge BRPPCGuestSocketRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC socket context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFSocket context description" error:&error]) {
        RecordSocketError(record, error); return NULL; }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void DeliverSocketEvent(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address,
                               const void *data, void *pointer) {
    (void)socket; BRPPCGuestSocketRecord *record = (__bridge BRPPCGuestSocketRecord *)pointer;
    uint32_t addressHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)address) : 0;
    uint32_t dataArgument = 0, temporary = 0;
    if (data && type == kCFSocketDataCallBack) dataArgument = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)data) : 0;
    else if (data && (type == kCFSocketAcceptCallBack || type == kCFSocketConnectCallBack)) {
        temporary = record.resolver.registry.guestAllocator ? record.resolver.registry.guestAllocator(4, NO) : 0;
        int32_t value = type == kCFSocketAcceptCallBack ? *(const CFSocketNativeHandle *)data
                                                        : *(const int32_t *)data;
        if (!temporary || ![record.resolver.registry.memory writeUInt32:(uint32_t)value address:temporary]) {
            RecordSocketError(record, [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey: @"Cannot marshal CFSocket callback data."}]); return; }
        dataArgument = temporary;
    }
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.callout outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)type), @(addressHandle), @(dataArgument), @(record.info)]
        result:NULL label:@"CFSocket callout" error:&error]) RecordSocketError(record, error);
    if (temporary && record.resolver.registry.guestDeallocator)
        record.resolver.registry.guestDeallocator(temporary);
}

static void RecordFileDescriptorError(BRPPCGuestFileDescriptorRecord *record, NSError *error) {
    if (!record.resolver || !error) return;
    record.resolver.pendingCallbackError = error; CFRunLoopStop(CFRunLoopGetCurrent());
}

static void *RetainFileDescriptorContext(void *pointer) {
    BRPPCGuestFileDescriptorRecord *record = (__bridge BRPPCGuestFileDescriptorRecord *)pointer;
    if (record.retainFunction) { uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFFileDescriptor context retain" error:&error])
            RecordFileDescriptorError(record, error); else record.info = result; }
    CFRetain((CFTypeRef)pointer); return pointer;
}

static void ReleaseFileDescriptorContext(void *pointer) {
    BRPPCGuestFileDescriptorRecord *record = (__bridge BRPPCGuestFileDescriptorRecord *)pointer;
    if (record.releaseFunction) { NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFFileDescriptor context release" error:&error])
            RecordFileDescriptorError(record, error); }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyFileDescriptorContextDescription(void *pointer) {
    BRPPCGuestFileDescriptorRecord *record = (__bridge BRPPCGuestFileDescriptorRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC file descriptor context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFFileDescriptor context description" error:&error]) {
        RecordFileDescriptorError(record, error); return NULL; }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void DeliverFileDescriptorEvent(CFFileDescriptorRef descriptor, CFOptionFlags types, void *pointer) {
    (void)descriptor; BRPPCGuestFileDescriptorRecord *record = (__bridge BRPPCGuestFileDescriptorRecord *)pointer;
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.callout outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)types), @(record.info)] result:NULL
        label:@"CFFileDescriptor callout" error:&error]) RecordFileDescriptorError(record, error);
}

static void RecordMachPortError(BRPPCGuestMachPortRecord *record, NSError *error) {
    if (!record.resolver || !error) return;
    record.resolver.pendingCallbackError = error; CFRunLoopStop(CFRunLoopGetCurrent());
}

static const void *RetainMachPortContext(const void *pointer) {
    BRPPCGuestMachPortRecord *record = (__bridge BRPPCGuestMachPortRecord *)pointer;
    if (record.retainFunction) { uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFMachPort context retain" error:&error])
            RecordMachPortError(record, error); else record.info = result; }
    CFRetain((CFTypeRef)pointer); return pointer;
}

static void ReleaseMachPortContext(const void *pointer) {
    BRPPCGuestMachPortRecord *record = (__bridge BRPPCGuestMachPortRecord *)pointer;
    if (record.releaseFunction) { NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFMachPort context release" error:&error])
            RecordMachPortError(record, error); }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyMachPortContextDescription(const void *pointer) {
    BRPPCGuestMachPortRecord *record = (__bridge BRPPCGuestMachPortRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC Mach port context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFMachPort context description" error:&error]) {
        RecordMachPortError(record, error); return NULL; }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void DeliverMachPortEvent(CFMachPortRef port, void *message, CFIndex size, void *pointer) {
    (void)port; BRPPCGuestMachPortRecord *record = (__bridge BRPPCGuestMachPortRecord *)pointer;
    uint32_t guestMessage = 0;
    if (message && size > 0) {
        guestMessage = record.resolver.registry.guestAllocator
            ? record.resolver.registry.guestAllocator((uint32_t)size, NO) : 0;
        BOOL wrote = guestMessage != 0;
        if (wrote && size >= (CFIndex)sizeof(mach_msg_header_t)) {
            mach_msg_header_t *header = message; uint32_t words[6] = {header->msgh_bits,
                header->msgh_size, header->msgh_remote_port, header->msgh_local_port,
                header->msgh_voucher_port, (uint32_t)header->msgh_id};
            for (NSUInteger index = 0; wrote && index < 6; index++)
                wrote = [record.resolver.registry.memory writeUInt32:words[index]
                    address:guestMessage + (uint32_t)index * 4];
            if (wrote && size > (CFIndex)sizeof(mach_msg_header_t))
                wrote = [record.resolver.registry.memory writeBytes:(uint8_t *)message + sizeof(mach_msg_header_t)
                    address:guestMessage + sizeof(mach_msg_header_t)
                    length:(uint32_t)size - (uint32_t)sizeof(mach_msg_header_t)];
        } else if (wrote) wrote = [record.resolver.registry.memory writeBytes:message
            address:guestMessage length:(uint32_t)size];
        if (!wrote) { if (guestMessage && record.resolver.registry.guestDeallocator)
                record.resolver.registry.guestDeallocator(guestMessage);
            RecordMachPortError(record, [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey: @"Cannot marshal CFMachPort message."}]); return; }
    }
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.callout outerState:record.outerState
        arguments:@[@(record.handle), @(guestMessage), @((uint32_t)size), @(record.info)] result:NULL
        label:@"CFMachPort callout" error:&error]) RecordMachPortError(record, error);
    if (guestMessage && record.resolver.registry.guestDeallocator)
        record.resolver.registry.guestDeallocator(guestMessage);
}

static void InvalidateMachPort(CFMachPortRef port, void *pointer) {
    BRPPCGuestMachPortRecord *record = pointer ? (__bridge BRPPCGuestMachPortRecord *)pointer
        : objc_getAssociatedObject((__bridge id)port, &BRPPCMachPortRecordAssociation);
    if (!record) return;
    NSError *error = nil;
    if (record.invalidationCallout && ![record.resolver invokeGuestFunction:record.invalidationCallout
        outerState:record.outerState arguments:@[@(record.handle), @(record.info)] result:NULL
        label:@"CFMachPort invalidation callout" error:&error]) RecordMachPortError(record, error);
}

static void RecordMessagePortError(BRPPCGuestMessagePortRecord *record, NSError *error) {
    if (!record.resolver || !error) return;
    record.resolver.pendingCallbackError = error; CFRunLoopStop(CFRunLoopGetCurrent());
}

static const void *RetainMessagePortContext(const void *pointer) {
    BRPPCGuestMessagePortRecord *record = (__bridge BRPPCGuestMessagePortRecord *)pointer;
    if (record.retainFunction) { uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFMessagePort context retain" error:&error])
            RecordMessagePortError(record, error); else record.info = result; }
    CFRetain((CFTypeRef)pointer); return pointer;
}

static void ReleaseMessagePortContext(const void *pointer) {
    BRPPCGuestMessagePortRecord *record = (__bridge BRPPCGuestMessagePortRecord *)pointer;
    if (record.releaseFunction) { NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFMessagePort context release" error:&error])
            RecordMessagePortError(record, error); }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyMessagePortContextDescription(const void *pointer) {
    BRPPCGuestMessagePortRecord *record = (__bridge BRPPCGuestMessagePortRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC message port context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFMessagePort context description" error:&error]) {
        RecordMessagePortError(record, error); return NULL; }
    id description = [record.resolver object:result];
    if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static CFDataRef DeliverMessagePortEvent(CFMessagePortRef port, SInt32 messageID,
                                         CFDataRef data, void *pointer) {
    (void)port; BRPPCGuestMessagePortRecord *record = (__bridge BRPPCGuestMessagePortRecord *)pointer;
    uint32_t dataHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)data) : 0;
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.callout outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)messageID), @(dataHandle), @(record.info)] result:&result
        label:@"CFMessagePort callout" error:&error]) { RecordMessagePortError(record, error); return NULL; }
    id reply = [record.resolver object:result];
    if (![reply isKindOfClass:[NSData class]]) return NULL;
    return CFBridgingRetain(reply);
}

static void InvalidateMessagePort(CFMessagePortRef port, void *pointer) {
    BRPPCGuestMessagePortRecord *record = pointer ? (__bridge BRPPCGuestMessagePortRecord *)pointer
        : objc_getAssociatedObject((__bridge id)port, &BRPPCMessagePortRecordAssociation);
    if (!record) return;
    NSError *error = nil;
    if (record.invalidationCallout && ![record.resolver invokeGuestFunction:record.invalidationCallout
        outerState:record.outerState arguments:@[@(record.handle), @(record.info)] result:NULL
        label:@"CFMessagePort invalidation callout" error:&error]) RecordMessagePortError(record, error);
}

static void DeliverUserNotificationResponse(CFUserNotificationRef notification, CFOptionFlags flags) {
    BRPPCGuestUserNotificationRecord *record = objc_getAssociatedObject(
        (__bridge id)notification, &BRPPCUserNotificationRecordAssociation);
    if (!record || !record.callout) return; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.callout outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)flags)] result:NULL
        label:@"CFUserNotification callout" error:&error]) {
        record.resolver.pendingCallbackError = error; CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

static void RecordXMLParserError(BRPPCGuestXMLParserRecord *record, NSError *error) {
    if (record.resolver && error) record.resolver.pendingCallbackError = error;
}

static const void *RetainXMLParserContext(const void *pointer) {
    BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    if (record.retainFunction) { uint32_t result = 0; NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.retainFunction outerState:record.outerState
            arguments:@[@(record.info)] result:&result label:@"CFXMLParser context retain" error:&error])
            RecordXMLParserError(record, error); else record.info = result; }
    CFRetain((CFTypeRef)pointer); return pointer;
}

static void ReleaseXMLParserContext(const void *pointer) {
    BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    if (record.releaseFunction) { NSError *error = nil;
        if (![record.resolver invokeGuestFunction:record.releaseFunction outerState:record.outerState
            arguments:@[@(record.info)] result:NULL label:@"CFXMLParser context release" error:&error])
            RecordXMLParserError(record, error); }
    CFRelease((CFTypeRef)pointer);
}

static CFStringRef CopyXMLParserContextDescription(const void *pointer) {
    BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    if (!record.descriptionFunction) return CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
        CFSTR("<PowerPC XML parser context 0x%08x>"), record.info);
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.descriptionFunction outerState:record.outerState
        arguments:@[@(record.info)] result:&result label:@"CFXMLParser context description" error:&error]) {
        RecordXMLParserError(record, error); return NULL; }
    id description = [record.resolver object:result]; if (![description isKindOfClass:[NSString class]]) return NULL;
    CFRetain((__bridge CFTypeRef)description); return (__bridge CFStringRef)description;
}

static void *CreateXMLParserStructure(CFXMLParserRef parser, CFXMLNodeRef node, void *pointer) {
    (void)parser; BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    uint32_t nodeHandle = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)node) : 0;
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.createStructure outerState:record.outerState
        arguments:@[@(record.handle), @(nodeHandle), @(record.info)] result:&result
        label:@"CFXMLParser create structure" error:&error]) RecordXMLParserError(record, error);
    return (void *)(uintptr_t)result;
}

static void AddXMLParserChild(CFXMLParserRef parser, void *parent, void *child, void *pointer) {
    (void)parser; BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.addChild outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)(uintptr_t)parent), @((uint32_t)(uintptr_t)child),
                    @(record.info)] result:NULL label:@"CFXMLParser add child" error:&error])
        RecordXMLParserError(record, error);
}

static void EndXMLParserStructure(CFXMLParserRef parser, void *structure, void *pointer) {
    (void)parser; BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.endStructure outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)(uintptr_t)structure), @(record.info)] result:NULL
        label:@"CFXMLParser end structure" error:&error]) RecordXMLParserError(record, error);
}

static CFDataRef ResolveXMLParserEntity(CFXMLParserRef parser, CFXMLExternalID *identifier, void *pointer) {
    (void)parser; BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    uint32_t temporary = record.resolver.registry.guestAllocator
        ? record.resolver.registry.guestAllocator(8, YES) : 0;
    uint32_t systemID = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)identifier->systemID) : 0;
    uint32_t publicID = record.resolver.registry.guestObjectEncoder
        ? record.resolver.registry.guestObjectEncoder((__bridge id)identifier->publicID) : 0;
    if (!temporary || ![record.resolver.registry.memory writeUInt32:systemID address:temporary] ||
        ![record.resolver.registry.memory writeUInt32:publicID address:temporary + 4]) return NULL;
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.resolveEntity outerState:record.outerState
        arguments:@[@(record.handle), @(temporary), @(record.info)] result:&result
        label:@"CFXMLParser resolve entity" error:&error]) RecordXMLParserError(record, error);
    if (record.resolver.registry.guestDeallocator) record.resolver.registry.guestDeallocator(temporary);
    id data = [record.resolver object:result]; return [data isKindOfClass:[NSData class]] ? CFBridgingRetain(data) : NULL;
}

static Boolean HandleXMLParserError(CFXMLParserRef parser, CFXMLParserStatusCode code, void *pointer) {
    (void)parser; BRPPCGuestXMLParserRecord *record = (__bridge BRPPCGuestXMLParserRecord *)pointer;
    uint32_t result = 0; NSError *error = nil;
    if (![record.resolver invokeGuestFunction:record.handleError outerState:record.outerState
        arguments:@[@(record.handle), @((uint32_t)code), @(record.info)] result:&result
        label:@"CFXMLParser handle error" error:&error]) RecordXMLParserError(record, error);
    return result != 0;
}

typedef struct {
    __unsafe_unretained BRPPCCoreFoundationResolve *resolver;
    BRPPCState outerState;
    uint32_t function;
    uint32_t context;
} BRPPCGuestTreeComparatorContext;

static CFComparisonResult CompareTreeChildren(const void *firstPointer, const void *secondPointer,
                                               void *contextPointer) {
    BRPPCGuestTreeComparatorContext *context = contextPointer;
    uint32_t first = context->resolver.registry.guestObjectEncoder
        ? context->resolver.registry.guestObjectEncoder((__bridge id)firstPointer) : 0;
    uint32_t second = context->resolver.registry.guestObjectEncoder
        ? context->resolver.registry.guestObjectEncoder((__bridge id)secondPointer) : 0;
    uint32_t result = 0; NSError *error = nil;
    if (![context->resolver invokeGuestFunction:context->function outerState:context->outerState
        arguments:@[@(first), @(second), @(context->context)] result:&result
        label:@"CFTree comparator" error:&error]) {
        context->resolver.pendingCallbackError = error; return kCFCompareEqualTo;
    }
    return (CFComparisonResult)(int32_t)result;
}

@implementation BRPPCCoreFoundationResolve

static void CFFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value;
    state->pc = state->lr;
}

static NSCharacterSet *PredefinedCharacterSet(uint32_t kind) {
    switch (kind) {
        case kCFCharacterSetControl: return [NSCharacterSet controlCharacterSet];
        case kCFCharacterSetWhitespace: return [NSCharacterSet whitespaceCharacterSet];
        case kCFCharacterSetWhitespaceAndNewline: return [NSCharacterSet whitespaceAndNewlineCharacterSet];
        case kCFCharacterSetDecimalDigit: return [NSCharacterSet decimalDigitCharacterSet];
        case kCFCharacterSetLetter: return [NSCharacterSet letterCharacterSet];
        case kCFCharacterSetLowercaseLetter: return [NSCharacterSet lowercaseLetterCharacterSet];
        case kCFCharacterSetUppercaseLetter: return [NSCharacterSet uppercaseLetterCharacterSet];
        case kCFCharacterSetNonBase: return [NSCharacterSet nonBaseCharacterSet];
        case kCFCharacterSetDecomposable: return [NSCharacterSet decomposableCharacterSet];
        case kCFCharacterSetAlphaNumeric: return [NSCharacterSet alphanumericCharacterSet];
        case kCFCharacterSetPunctuation: return [NSCharacterSet punctuationCharacterSet];
        case kCFCharacterSetIllegal: return [NSCharacterSet illegalCharacterSet];
        case kCFCharacterSetCapitalizedLetter: return [NSCharacterSet capitalizedLetterCharacterSet];
        case kCFCharacterSetSymbol: return [NSCharacterSet symbolCharacterSet];
        case kCFCharacterSetNewline: return [NSCharacterSet newlineCharacterSet];
        default: return nil;
    }
}

- (id)object:(uint32_t)address {
    id object = _registry.guestObjectDecoder ? _registry.guestObjectDecoder(address) : nil;
    NSNumber *pointer = _copiedBytePointers[@(address)];
    if (pointer && [object isKindOfClass:[NSMutableData class]]) {
        NSMutableData *data = object;
        if (data.length) [_registry.memory readBytes:data.mutableBytes
                                             address:pointer.unsignedIntValue length:data.length];
    }
    return object;
}

- (uint32_t)handle:(id)object {
    return _registry.guestObjectEncoder ? _registry.guestObjectEncoder(object) : 0;
}

- (BOOL)invokeGuestFunction:(uint32_t)function outerState:(BRPPCState)outerState
                   arguments:(NSArray<NSNumber *> *)arguments result:(uint32_t *)result
                       label:(NSString *)label error:(NSError **)error {
    if (!function || arguments.count > 8) {
        if (error) *error = [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:3
            userInfo:@{NSLocalizedDescriptionKey: @"CoreFoundation guest callback is invalid."}];
        return NO;
    }
    BRPPCState callback = outerState;
    callback.pc = function; callback.gpr[12] = function;
    for (NSUInteger i = 0; i < arguments.count; i++) callback.gpr[3 + i] = arguments[i].unsignedIntValue;
    if (![_registry executeGuestCallbackState:&callback instructionLimit:10000000
                                         label:label error:error]) return NO;
    if (result) *result = callback.gpr[3];
    return YES;
}

- (BOOL)releaseTimerRecord:(BRPPCGuestTimerRecord *)record error:(NSError **)error {
    if (!record || record.released) return YES;
    record.released = YES;
    if (!record.releaseFunction) return YES;
    return [self invokeGuestFunction:record.releaseFunction outerState:record.outerState
                           arguments:@[@(record.info)] result:NULL
                               label:@"CFRunLoopTimer context release" error:error];
}

- (BOOL)releaseSourceRecord:(BRPPCGuestSourceRecord *)record error:(NSError **)error {
    if (!record || record.released) return YES;
    record.released = YES;
    if (!record.releaseFunction) return YES;
    return [self invokeGuestFunction:record.releaseFunction outerState:record.outerState
                           arguments:@[@(record.info)] result:NULL
                               label:@"CFRunLoopSource context release" error:error];
}

- (NSString *)string:(uint32_t)address {
    id object = [self object:address];
    return [object isKindOfClass:[NSString class]] ? object : nil;
}

- (BOOL)readRangeAtGPR:(NSUInteger)gpr state:(BRPPCState *)state location:(NSUInteger *)location
                 length:(NSUInteger *)length {
    *location = state->gpr[gpr]; *length = state->gpr[gpr + 1]; return YES;
}

- (uint32_t)copyBytesToGuest:(const void *)bytes length:(NSUInteger)length {
    if (!_registry.guestAllocator || length > UINT32_MAX) return 0;
    uint32_t address = _registry.guestAllocator((uint32_t)MAX(length, 1u), NO);
    if (!address || (length && ![_registry.memory writeBytes:bytes address:address length:length])) return 0;
    return address;
}

- (NSData *)cstringDataAtAddress:(uint32_t)address {
    NSMutableData *data = [NSMutableData data]; uint8_t byte = 0;
    for (NSUInteger i = 0; i < (1u << 24); i++) {
        if (![_registry.memory readBytes:&byte address:address + (uint32_t)i length:1]) return nil;
        if (!byte) return data;
        [data appendBytes:&byte length:1];
    }
    return nil;
}

- (BOOL)writeDataSymbol:(NSString *)symbol object:(id)object error:(NSError **)error {
    if (!_registry.guestAllocator) return NO;
    uint32_t address = _registry.guestAllocator(4, YES);
    if (!address || ![_registry.memory writeUInt32:[self handle:object] address:address]) return NO;
    return [_registry registerSymbol:symbol atAddress:address
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)state;
            if (callError) *callError = [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:1
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"%@ is CoreFoundation data.", symbol]}];
            return NO;
        } error:error];
}

- (BOOL)writeUInt32DataSymbol:(NSString *)symbol value:(uint32_t)value error:(NSError **)error {
    if (!_registry.guestAllocator) return NO; uint32_t address = _registry.guestAllocator(4, YES);
    if (!address || ![_registry.memory writeUInt32:value address:address]) return NO;
    return [_registry registerSymbol:symbol atAddress:address
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)state;
            if (callError) *callError = [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:1
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"%@ is CoreFoundation data.", symbol]}];
            return NO;
        } error:error];
}

- (BOOL)readNumberAtAddress:(uint32_t)address type:(CFNumberType)type
                    integer:(int64_t *)integer floating:(double *)floating isFloat:(BOOL *)isFloat {
    uint32_t first = 0, second = 0; *isFloat = NO;
    switch (type) {
        case kCFNumberFloat32Type: case kCFNumberFloatType: {
            if (![_registry.memory readUInt32:&first address:address]) return NO;
            float value; memcpy(&value, &first, 4); *floating = value; *isFloat = YES; return YES;
        }
        case kCFNumberFloat64Type: case kCFNumberDoubleType: case kCFNumberCGFloatType: {
            if (![_registry.memory readUInt32:&first address:address] ||
                ![_registry.memory readUInt32:&second address:address + 4]) return NO;
            uint64_t bits = (uint64_t)first << 32 | second; memcpy(floating, &bits, 8); *isFloat = YES; return YES;
        }
        case kCFNumberSInt64Type: case kCFNumberLongLongType: {
            if (![_registry.memory readUInt32:&first address:address] ||
                ![_registry.memory readUInt32:&second address:address + 4]) return NO;
            *integer = (int64_t)((uint64_t)first << 32 | second); return YES;
        }
        case kCFNumberCharType: {
            uint8_t value = 0; if (![_registry.memory readBytes:&value address:address length:1]) return NO;
            *integer = (int8_t)value; return YES;
        }
        case kCFNumberShortType: {
            uint8_t bytes[2]; if (![_registry.memory readBytes:bytes address:address length:2]) return NO;
            *integer = (int16_t)((uint16_t)bytes[0] << 8 | bytes[1]); return YES;
        }
        default:
            if (![_registry.memory readUInt32:&first address:address]) return NO;
            *integer = (int32_t)first; return YES;
    }
}

- (BOOL)writeNumber:(NSNumber *)number type:(CFNumberType)type address:(uint32_t)address {
    switch (type) {
        case kCFNumberFloat32Type: case kCFNumberFloatType: {
            float value = number.floatValue; uint32_t bits = 0; memcpy(&bits, &value, 4);
            return [_registry.memory writeUInt32:bits address:address];
        }
        case kCFNumberFloat64Type: case kCFNumberDoubleType: case kCFNumberCGFloatType: {
            double value = number.doubleValue; uint64_t bits = 0; memcpy(&bits, &value, 8);
            return [_registry.memory writeUInt32:(uint32_t)(bits >> 32) address:address] &&
                   [_registry.memory writeUInt32:(uint32_t)bits address:address + 4];
        }
        case kCFNumberSInt64Type: case kCFNumberLongLongType: {
            uint64_t value = number.longLongValue;
            return [_registry.memory writeUInt32:(uint32_t)(value >> 32) address:address] &&
                   [_registry.memory writeUInt32:(uint32_t)value address:address + 4];
        }
        case kCFNumberCharType: {
            int8_t value = number.charValue; return [_registry.memory writeBytes:&value address:address length:1];
        }
        case kCFNumberShortType: {
            uint16_t value = number.shortValue; uint8_t bytes[] = {value >> 8, value};
            return [_registry.memory writeBytes:bytes address:address length:2];
        }
        default: return [_registry.memory writeUInt32:(uint32_t)number.longValue address:address];
    }
}

- (BOOL)writeDouble:(double)value address:(uint32_t)address {
    uint64_t bits = 0; memcpy(&bits, &value, sizeof(bits));
    return [_registry.memory writeUInt32:(uint32_t)(bits >> 32) address:address] &&
           [_registry.memory writeUInt32:(uint32_t)bits address:address + 4];
}

- (BOOL)readDouble:(double *)value address:(uint32_t)address {
    uint32_t high = 0, low = 0;
    if (![_registry.memory readUInt32:&high address:address] ||
        ![_registry.memory readUInt32:&low address:address + 4]) return NO;
    uint64_t bits = (uint64_t)high << 32 | low; memcpy(value, &bits, sizeof(bits)); return YES;
}

- (BOOL)readGuestWord:(uint32_t *)value state:(BRPPCState *)state cursor:(NSUInteger *)cursor {
    NSUInteger position = (*cursor)++;
    if (position <= 10) { *value = state->gpr[position]; return YES; }
    return [_registry.memory readUInt32:value
                                 address:state->gpr[1] + 24 + (uint32_t)(position - 3) * 4];
}

- (BOOL)readSocketSignature:(CFSocketSignature *)signature address:(uint32_t)address {
    uint32_t words[4] = {0};
    if (!address) return NO;
    for (NSUInteger index = 0; index < 4; index++)
        if (![_registry.memory readUInt32:&words[index] address:address + (uint32_t)index * 4]) return NO;
    signature->protocolFamily = (SInt32)words[0]; signature->socketType = (SInt32)words[1];
    signature->protocol = (SInt32)words[2];
    signature->address = (__bridge CFDataRef)[self object:words[3]]; return YES;
}

- (BRPPCGuestSocketRecord *)socketRecordAtAddress:(uint32_t)address callout:(uint32_t)callout
                                             state:(BRPPCState)state {
    BRPPCGuestSocketRecord *record = [BRPPCGuestSocketRecord new]; record.resolver = self;
    record.outerState = state; record.callout = callout; if (!address) return record;
    uint32_t version = 0, info = 0, retain = 0, release = 0, description = 0;
    if (![_registry.memory readUInt32:&version address:address] || version ||
        ![_registry.memory readUInt32:&info address:address + 4] ||
        ![_registry.memory readUInt32:&retain address:address + 8] ||
        ![_registry.memory readUInt32:&release address:address + 12] ||
        ![_registry.memory readUInt32:&description address:address + 16]) return nil;
    record.info = info; record.retainFunction = retain; record.releaseFunction = release;
    record.descriptionFunction = description; return record;
}

- (BRPPCGuestFileDescriptorRecord *)fileDescriptorRecordAtAddress:(uint32_t)address
                                                           callout:(uint32_t)callout
                                                             state:(BRPPCState)state {
    BRPPCGuestFileDescriptorRecord *record = [BRPPCGuestFileDescriptorRecord new];
    record.resolver = self; record.outerState = state; record.callout = callout;
    if (!address) return record;
    uint32_t version = 0, info = 0, retain = 0, release = 0, description = 0;
    if (![_registry.memory readUInt32:&version address:address] || version ||
        ![_registry.memory readUInt32:&info address:address + 4] ||
        ![_registry.memory readUInt32:&retain address:address + 8] ||
        ![_registry.memory readUInt32:&release address:address + 12] ||
        ![_registry.memory readUInt32:&description address:address + 16]) return nil;
    record.info = info; record.retainFunction = retain; record.releaseFunction = release;
    record.descriptionFunction = description; return record;
}

- (BRPPCGuestMachPortRecord *)machPortRecordAtAddress:(uint32_t)address
                                               callout:(uint32_t)callout
                                                 state:(BRPPCState)state {
    BRPPCGuestMachPortRecord *record = [BRPPCGuestMachPortRecord new];
    record.resolver = self; record.outerState = state; record.callout = callout;
    if (!address) return record;
    uint32_t version = 0, info = 0, retain = 0, release = 0, description = 0;
    if (![_registry.memory readUInt32:&version address:address] || version ||
        ![_registry.memory readUInt32:&info address:address + 4] ||
        ![_registry.memory readUInt32:&retain address:address + 8] ||
        ![_registry.memory readUInt32:&release address:address + 12] ||
        ![_registry.memory readUInt32:&description address:address + 16]) return nil;
    record.info = info; record.retainFunction = retain; record.releaseFunction = release;
    record.descriptionFunction = description; return record;
}

- (BRPPCGuestMessagePortRecord *)messagePortRecordAtAddress:(uint32_t)address
                                                     callout:(uint32_t)callout
                                                       state:(BRPPCState)state {
    BRPPCGuestMessagePortRecord *record = [BRPPCGuestMessagePortRecord new];
    record.resolver = self; record.outerState = state; record.callout = callout;
    if (!address) return record;
    uint32_t version = 0, info = 0, retain = 0, release = 0, description = 0;
    if (![_registry.memory readUInt32:&version address:address] || version ||
        ![_registry.memory readUInt32:&info address:address + 4] ||
        ![_registry.memory readUInt32:&retain address:address + 8] ||
        ![_registry.memory readUInt32:&release address:address + 12] ||
        ![_registry.memory readUInt32:&description address:address + 16]) return nil;
    record.info = info; record.retainFunction = retain; record.releaseFunction = release;
    record.descriptionFunction = description; return record;
}

- (uint32_t)registerACL:(acl_t)ACL {
    if (!ACL) return 0; uint32_t handle = self.nextACLHandle; self.nextACLHandle += 4;
    self.aclRecords[@(handle)] = [NSValue valueWithPointer:ACL]; return handle;
}

- (acl_t)ACLForHandle:(uint32_t)handle {
    if (handle == UINT32_MAX) return kCFFileSecurityRemoveACL;
    return handle ? self.aclRecords[@(handle)].pointerValue : NULL;
}

- (id)createXMLNodeType:(CFXMLNodeTypeCode)type dataString:(NSString *)string
             infoAddress:(uint32_t)address version:(CFIndex)version {
    typedef CFXMLNodeRef (*Function)(CFAllocatorRef, CFXMLNodeTypeCode, CFStringRef, const void *, CFIndex);
    Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLNodeCreate"); if (!function) return nil;
    uint32_t words[5] = {0};
    #define READ_XML_WORDS(count) do { for (NSUInteger index = 0; index < (count); index++) \
        if (![_registry.memory readUInt32:&words[index] address:address + (uint32_t)index * 4]) return nil; } while (0)
    CFXMLElementInfo element = {0}; CFXMLProcessingInstructionInfo instruction = {0};
    CFXMLDocumentInfo document = {0}; CFXMLDocumentTypeInfo documentType = {0};
    CFXMLNotationInfo notation = {0}; CFXMLElementTypeDeclarationInfo elementDeclaration = {0};
    CFXMLAttributeListDeclarationInfo attributeList = {0}; CFXMLEntityInfo entity = {0};
    CFXMLEntityReferenceInfo entityReference = {0}; CFXMLAttributeDeclarationInfo *attributes = NULL;
    const void *info = NULL;
    if (address) switch (type) {
        case kCFXMLNodeTypeElement: READ_XML_WORDS(3); element.attributes = (__bridge CFDictionaryRef)[self object:words[0]];
            element.attributeOrder = (__bridge CFArrayRef)[self object:words[1]]; element.isEmpty = words[2] != 0;
            info = &element; break;
        case kCFXMLNodeTypeProcessingInstruction: READ_XML_WORDS(1);
            instruction.dataString = (__bridge CFStringRef)[self string:words[0]]; info = &instruction; break;
        case kCFXMLNodeTypeDocument: READ_XML_WORDS(2); document.sourceURL = (__bridge CFURLRef)[self object:words[0]];
            document.encoding = words[1]; info = &document; break;
        case kCFXMLNodeTypeDocumentType: READ_XML_WORDS(2);
            documentType.externalID.systemID = (__bridge CFURLRef)[self object:words[0]];
            documentType.externalID.publicID = (__bridge CFStringRef)[self string:words[1]]; info = &documentType; break;
        case kCFXMLNodeTypeNotation: READ_XML_WORDS(2);
            notation.externalID.systemID = (__bridge CFURLRef)[self object:words[0]];
            notation.externalID.publicID = (__bridge CFStringRef)[self string:words[1]]; info = &notation; break;
        case kCFXMLNodeTypeElementTypeDeclaration: READ_XML_WORDS(1);
            elementDeclaration.contentDescription = (__bridge CFStringRef)[self string:words[0]];
            info = &elementDeclaration; break;
        case kCFXMLNodeTypeAttributeListDeclaration: {
            READ_XML_WORDS(2); attributeList.numberOfAttributes = (CFIndex)(int32_t)words[0];
            if (attributeList.numberOfAttributes < 0 || attributeList.numberOfAttributes > (1 << 20)) return nil;
            if (attributeList.numberOfAttributes) attributes = calloc(
                (size_t)attributeList.numberOfAttributes, sizeof(*attributes));
            if (attributeList.numberOfAttributes && !attributes) return nil;
            for (CFIndex index = 0; index < attributeList.numberOfAttributes; index++) {
                uint32_t values[3] = {0}; for (NSUInteger field = 0; field < 3; field++)
                    if (![_registry.memory readUInt32:&values[field]
                        address:words[1] + (uint32_t)index * 12 + (uint32_t)field * 4]) { free(attributes); return nil; }
                attributes[index].attributeName = (__bridge CFStringRef)[self string:values[0]];
                attributes[index].typeString = (__bridge CFStringRef)[self string:values[1]];
                attributes[index].defaultString = (__bridge CFStringRef)[self string:values[2]];
            }
            attributeList.attributes = attributes; info = &attributeList; break;
        }
        case kCFXMLNodeTypeEntity: READ_XML_WORDS(5); entity.entityType = words[0];
            entity.replacementText = (__bridge CFStringRef)[self string:words[1]];
            entity.entityID.systemID = (__bridge CFURLRef)[self object:words[2]];
            entity.entityID.publicID = (__bridge CFStringRef)[self string:words[3]];
            entity.notationName = (__bridge CFStringRef)[self string:words[4]]; info = &entity; break;
        case kCFXMLNodeTypeEntityReference: READ_XML_WORDS(1); entityReference.entityType = words[0];
            info = &entityReference; break;
        default: break;
    }
    CFXMLNodeRef node = function(kCFAllocatorDefault, type, (__bridge CFStringRef)string, info, version);
    free(attributes); return CFBridgingRelease(node);
    #undef READ_XML_WORDS
}

- (uint32_t)guestInfoForXMLNode:(id)node handle:(uint32_t)handle {
    NSNumber *existing = self.xmlNodeInfoPointers[@(handle)]; if (existing) return existing.unsignedIntValue;
    typedef CFXMLNodeTypeCode (*TypeFunction)(CFXMLNodeRef);
    typedef const void *(*InfoFunction)(CFXMLNodeRef);
    TypeFunction typeFunction = (TypeFunction)dlsym(RTLD_DEFAULT, "CFXMLNodeGetTypeCode");
    InfoFunction infoFunction = (InfoFunction)dlsym(RTLD_DEFAULT, "CFXMLNodeGetInfoPtr");
    if (!node || !typeFunction || !infoFunction) return 0; CFXMLNodeTypeCode type = typeFunction((__bridge CFXMLNodeRef)node);
    const void *info = infoFunction((__bridge CFXMLNodeRef)node); if (!info) return 0;
    uint32_t size = 0, words[5] = {0};
    switch (type) {
        case kCFXMLNodeTypeElement: { CFXMLElementInfo *value = (void *)info; size = 12;
            words[0] = [self handle:(__bridge id)value->attributes];
            words[1] = [self handle:(__bridge id)value->attributeOrder]; words[2] = value->isEmpty; break; }
        case kCFXMLNodeTypeProcessingInstruction: size = 4;
            words[0] = [self handle:(__bridge id)((CFXMLProcessingInstructionInfo *)info)->dataString]; break;
        case kCFXMLNodeTypeDocument: { CFXMLDocumentInfo *value = (void *)info; size = 8;
            words[0] = [self handle:(__bridge id)value->sourceURL]; words[1] = value->encoding; break; }
        case kCFXMLNodeTypeDocumentType: case kCFXMLNodeTypeNotation: { CFXMLExternalID *value =
                type == kCFXMLNodeTypeDocumentType ? &((CFXMLDocumentTypeInfo *)info)->externalID
                                                    : &((CFXMLNotationInfo *)info)->externalID;
            size = 8; words[0] = [self handle:(__bridge id)value->systemID];
            words[1] = [self handle:(__bridge id)value->publicID]; break; }
        case kCFXMLNodeTypeElementTypeDeclaration: size = 4;
            words[0] = [self handle:(__bridge id)((CFXMLElementTypeDeclarationInfo *)info)->contentDescription]; break;
        case kCFXMLNodeTypeAttributeListDeclaration: { CFXMLAttributeListDeclarationInfo *value = (void *)info;
            if (value->numberOfAttributes < 0 || value->numberOfAttributes > (1 << 20)) return 0;
            uint32_t array = value->numberOfAttributes && _registry.guestAllocator
                ? _registry.guestAllocator((uint32_t)value->numberOfAttributes * 12, YES) : 0;
            if (value->numberOfAttributes && !array) return 0;
            for (CFIndex index = 0; index < value->numberOfAttributes; index++) {
                uint32_t values[3] = {[self handle:(__bridge id)value->attributes[index].attributeName],
                    [self handle:(__bridge id)value->attributes[index].typeString],
                    [self handle:(__bridge id)value->attributes[index].defaultString]};
                for (NSUInteger field = 0; field < 3; field++)
                    if (![_registry.memory writeUInt32:values[field]
                        address:array + (uint32_t)index * 12 + (uint32_t)field * 4]) return 0;
            }
            size = 8; words[0] = (uint32_t)value->numberOfAttributes; words[1] = array; break;
        }
        case kCFXMLNodeTypeEntity: { CFXMLEntityInfo *value = (void *)info; size = 20;
            words[0] = (uint32_t)value->entityType; words[1] = [self handle:(__bridge id)value->replacementText];
            words[2] = [self handle:(__bridge id)value->entityID.systemID];
            words[3] = [self handle:(__bridge id)value->entityID.publicID];
            words[4] = [self handle:(__bridge id)value->notationName]; break; }
        case kCFXMLNodeTypeEntityReference: size = 4;
            words[0] = (uint32_t)((CFXMLEntityReferenceInfo *)info)->entityType; break;
        default: return 0;
    }
    uint32_t address = _registry.guestAllocator ? _registry.guestAllocator(size, YES) : 0; if (!address) return 0;
    NSUInteger wordCount = type == kCFXMLNodeTypeElement ? 2 : size / 4;
    for (NSUInteger index = 0; index < wordCount; index++)
        if (![_registry.memory writeUInt32:words[index] address:address + (uint32_t)index * 4]) return 0;
    if (type == kCFXMLNodeTypeElement) { uint8_t isEmpty = words[2] != 0;
        if (![_registry.memory writeBytes:&isEmpty address:address + 8 length:1]) return 0; }
    self.xmlNodeInfoPointers[@(handle)] = @(address); return address;
}

- (BRPPCGuestXMLParserRecord *)XMLParserRecordWithCallbacks:(uint32_t)callbacksAddress
                                                     context:(uint32_t)contextAddress
                                                       state:(BRPPCState)state {
    if (!callbacksAddress) return nil; uint32_t callbacks[6] = {0};
    for (NSUInteger index = 0; index < 6; index++)
        if (![_registry.memory readUInt32:&callbacks[index]
                                  address:callbacksAddress + (uint32_t)index * 4]) return nil;
    if (callbacks[0] || !callbacks[1] || !callbacks[2] || !callbacks[3]) return nil;
    BRPPCGuestXMLParserRecord *record = [BRPPCGuestXMLParserRecord new]; record.resolver = self;
    record.outerState = state; record.createStructure = callbacks[1]; record.addChild = callbacks[2];
    record.endStructure = callbacks[3]; record.resolveEntity = callbacks[4]; record.handleError = callbacks[5];
    if (contextAddress) { uint32_t context[5] = {0};
        for (NSUInteger index = 0; index < 5; index++)
            if (![_registry.memory readUInt32:&context[index]
                                      address:contextAddress + (uint32_t)index * 4]) return nil;
        if (context[0]) return nil; record.info = context[1]; record.retainFunction = context[2];
        record.releaseFunction = context[3]; record.descriptionFunction = context[4];
    }
    return record;
}

- (BOOL)syncExternalStringHandle:(uint32_t)handle {
    BRPPCGuestExternalStringRecord *record = self.externalStringRecords[@(handle)];
    if (!record) return YES; NSString *string = [self string:handle]; uint32_t length = (uint32_t)string.length;
    if (length > record.capacity) {
        uint32_t capacity = MAX(length, record.capacity ? record.capacity * 2 : 16u);
        uint32_t address = self.registry.guestAllocator
            ? self.registry.guestAllocator(MAX(capacity * 2, 2u), NO) : 0;
        if (!address) return NO;
        if (record.ownsBuffer && self.registry.guestDeallocator)
            self.registry.guestDeallocator(record.address);
        record.address = address; record.capacity = capacity; record.ownsBuffer = YES;
    }
    for (uint32_t index = 0; index < length; index++) {
        unichar character = [string characterAtIndex:index]; uint8_t bytes[2] = {character >> 8, character};
        if (![self.registry.memory writeBytes:bytes address:record.address + index * 2 length:2]) return NO;
    }
    return YES;
}

- (NSString *)renderGuestFormat:(NSString *)format state:(BRPPCState *)state
                           cursor:(NSUInteger)cursor error:(NSError **)error {
    if (!format || !self.registry.guestFormatRenderer || !self.registry.guestAllocator) return nil;
    NSData *bytes = [format dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t address = self.registry.guestAllocator((uint32_t)bytes.length + 1, YES); if (!address) return nil;
    BOOL wrote = !bytes.length || [self.registry.memory writeBytes:bytes.bytes
        address:address length:(uint32_t)bytes.length]; NSData *rendered = wrote
        ? self.registry.guestFormatRenderer(address, state, cursor, error) : nil;
    if (self.registry.guestDeallocator) self.registry.guestDeallocator(address);
    return rendered ? [[NSString alloc] initWithData:rendered encoding:NSUTF8StringEncoding] : nil;
}

- (NSString *)renderGuestVAFormat:(NSString *)format argumentsAddress:(uint32_t)argumentsAddress
                             error:(NSError **)error {
    if (!format || !self.registry.guestVAFormatRenderer || !self.registry.guestAllocator ||
        !argumentsAddress) return nil;
    NSData *bytes = [format dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t address = self.registry.guestAllocator((uint32_t)bytes.length + 1, YES); if (!address) return nil;
    BOOL wrote = !bytes.length || [self.registry.memory writeBytes:bytes.bytes
        address:address length:(uint32_t)bytes.length]; NSData *rendered = wrote
        ? self.registry.guestVAFormatRenderer(address, argumentsAddress, error) : nil;
    if (self.registry.guestDeallocator) self.registry.guestDeallocator(address);
    return rendered ? [[NSString alloc] initWithData:rendered encoding:NSUTF8StringEncoding] : nil;
}

- (BOOL)writeGuestObject:(id)object address:(uint32_t)address {
    return !address || [self.registry.memory writeUInt32:[self handle:object] address:address];
}

- (NSData *)plugInUUIDKey:(id)object {
    if (!object || CFGetTypeID((__bridge CFTypeRef)object) != CFUUIDGetTypeID()) return nil;
    CFUUIDBytes bytes = CFUUIDGetUUIDBytes((__bridge CFUUIDRef)object);
    return [NSData dataWithBytes:&bytes length:sizeof(bytes)];
}

- (BRPPCGuestBlockRecord *)guestBlockAtAddress:(uint32_t)address state:(BRPPCState)state {
    uint32_t invoke = 0;
    if (!address || ![self.registry.memory readUInt32:&invoke address:address + 12] || !invoke) return nil;
    BRPPCGuestBlockRecord *record = [BRPPCGuestBlockRecord new];
    record.address = address; record.invoke = invoke; record.outerState = state; return record;
}

- (BOOL)invokeGuestBlock:(BRPPCGuestBlockRecord *)record arguments:(NSArray<NSNumber *> *)arguments
                   result:(uint32_t *)result label:(NSString *)label error:(NSError **)error {
    if (!record) return NO; NSMutableArray<NSNumber *> *blockArguments = [NSMutableArray arrayWithObject:@(record.address)];
    [blockArguments addObjectsFromArray:arguments]; return [self invokeGuestFunction:record.invoke
        outerState:record.outerState arguments:blockArguments result:result label:label error:error];
}

- (NSArray<NSString *> *)formatSignature:(NSString *)format {
    if (!format) return nil; NSMutableArray<NSString *> *signature = [NSMutableArray array];
    static NSCharacterSet *flags;
    static NSCharacterSet *digits;
    static NSCharacterSet *modifiers;
    static NSCharacterSet *conversions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        flags = [NSCharacterSet characterSetWithCharactersInString:@"-+ #0'"];
        digits = [NSCharacterSet decimalDigitCharacterSet];
        modifiers = [NSCharacterSet characterSetWithCharactersInString:@"hljztLq"];
        conversions = [NSCharacterSet characterSetWithCharactersInString:@"diuoxXfFeEgGaAcspn@DUO"];
    });
    NSUInteger length = format.length;
    for (NSUInteger index = 0; index < length; index++) {
        if ([format characterAtIndex:index] != '%') continue;
        if (++index >= length) return nil;
        if ([format characterAtIndex:index] == '%') continue;
        while (index < length && [flags characterIsMember:[format characterAtIndex:index]]) index++;
        while (index < length && [digits characterIsMember:[format characterAtIndex:index]]) index++;
        if (index < length && [format characterAtIndex:index] == '$') index++;
        if (index < length && [format characterAtIndex:index] == '*') {
            [signature addObject:@"d"]; index++;
        }
        if (index < length && [format characterAtIndex:index] == '.') {
            index++;
            if (index < length && [format characterAtIndex:index] == '*') {
                [signature addObject:@"d"]; index++;
            } else while (index < length &&
                          [digits characterIsMember:[format characterAtIndex:index]]) index++;
        }
        NSString *modifier = @"";
        if (index + 1 < length && [format characterAtIndex:index] == 'h' &&
            [format characterAtIndex:index + 1] == 'h') { modifier = @"hh"; index += 2; }
        else if (index + 1 < length && [format characterAtIndex:index] == 'l' &&
            [format characterAtIndex:index + 1] == 'l') { modifier = @"ll"; index += 2; }
        else if (index < length && [modifiers characterIsMember:[format characterAtIndex:index]]) {
            unichar character = [format characterAtIndex:index++];
            modifier = character == 'q' ? @"ll" : [NSString stringWithFormat:@"%C", character];
        }
        if (index >= length) return nil; unichar conversion = [format characterAtIndex:index];
        if (![conversions characterIsMember:conversion]) return nil;
        if (conversion == 'D' || conversion == 'U' || conversion == 'O') {
            modifier = @"l"; conversion = (unichar)tolower(conversion);
        }
        [signature addObject:[modifier stringByAppendingFormat:@"%C", conversion]];
    }
    return signature;
}

- (NSInteger)validateFormat:(NSString *)format expected:(NSString *)expected
               errorAddress:(uint32_t)errorAddress {
    NSArray *actualSignature = [self formatSignature:format];
    NSArray *expectedSignature = [self formatSignature:expected];
    if (actualSignature && [actualSignature isEqual:expectedSignature]) {
        if (errorAddress && ![self.registry.memory writeUInt32:0 address:errorAddress]) return -1;
        return 1;
    }
    NSError *formatError = [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:1
        userInfo:@{NSLocalizedDescriptionKey: @"Format specifiers do not match the validated signature."}];
    if (errorAddress && ![self.registry.memory writeUInt32:[self handle:formatError] address:errorAddress])
        return -1;
    return 0;
}

static NSCalendarUnit CalendarUnitForComponent(char component) {
    switch (component) {
        case 'G': return NSCalendarUnitEra;
        case 'y': return NSCalendarUnitYear;
        case 'Y': return NSCalendarUnitYearForWeekOfYear;
        case 'M': return NSCalendarUnitMonth;
        case 'd': return NSCalendarUnitDay;
        case 'D': return NSCalendarUnitDayOfYear;
        case 'H': return NSCalendarUnitHour;
        case 'm': return NSCalendarUnitMinute;
        case 's': return NSCalendarUnitSecond;
        case 'w': return NSCalendarUnitWeekOfYear;
        case 'W': return NSCalendarUnitWeekOfMonth;
        case 'E': return NSCalendarUnitWeekday;
        case 'F': return NSCalendarUnitWeekdayOrdinal;
        case 'q': case 'Q': return NSCalendarUnitQuarter;
        default: return 0;
    }
}

static void SetCalendarComponent(NSDateComponents *components, char component, NSInteger value) {
    switch (component) {
        case 'G': components.era = value; break;
        case 'y': components.year = value; break;
        case 'Y': components.yearForWeekOfYear = value; break;
        case 'M': components.month = value; break;
        case 'd': components.day = value; break;
        case 'D': components.dayOfYear = value; break;
        case 'H': components.hour = value; break;
        case 'm': components.minute = value; break;
        case 's': components.second = value; break;
        case 'w': components.weekOfYear = value; break;
        case 'W': components.weekOfMonth = value; break;
        case 'E': components.weekday = value; break;
        case 'F': components.weekdayOrdinal = value; break;
        case 'q': case 'Q': components.quarter = value; break;
    }
}

static NSInteger GetCalendarComponent(NSDateComponents *components, char component) {
    switch (component) {
        case 'G': return components.era;
        case 'y': return components.year;
        case 'Y': return components.yearForWeekOfYear;
        case 'M': return components.month;
        case 'd': return components.day;
        case 'D': return components.dayOfYear;
        case 'H': return components.hour;
        case 'm': return components.minute;
        case 's': return components.second;
        case 'w': return components.weekOfYear;
        case 'W': return components.weekOfMonth;
        case 'E': return components.weekday;
        case 'F': return components.weekdayOrdinal;
        case 'q': case 'Q': return components.quarter;
        default: return NSDateComponentUndefined;
    }
}

- (BOOL)installInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    self.registry = registry;
    self.copiedBytePointers = [NSMutableDictionary dictionary];
    self.timerRecords = [NSMutableDictionary dictionary];
    self.observerRecords = [NSMutableDictionary dictionary];
    self.sourceRecords = [NSMutableDictionary dictionary];
    self.notificationRecords = [NSMutableArray array];
    self.heapRecords = [NSMutableDictionary dictionary];
    self.treeRecords = [NSMutableDictionary dictionary];
    self.allocatorSizes = [NSMutableDictionary dictionary];
    self.constantUUIDs = [NSMutableDictionary dictionary];
    self.streamRecords = [NSMutableDictionary dictionary];
    self.streamBufferPointers = [NSMutableDictionary dictionary];
    self.socketRecords = [NSMutableDictionary dictionary];
    self.fileDescriptorRecords = [NSMutableDictionary dictionary];
    self.machPortRecords = [NSMutableDictionary dictionary];
    self.messagePortRecords = [NSMutableDictionary dictionary];
    self.userNotificationRecords = [NSMutableDictionary dictionary];
    self.xmlParserRecords = [NSMutableDictionary dictionary];
    self.aclRecords = [NSMutableDictionary dictionary];
    self.nextACLHandle = BRPPCGuestACLHandleBase;
    self.xmlNodeInfoPointers = [NSMutableDictionary dictionary];
    self.externalStringRecords = [NSMutableDictionary dictionary];
    self.plugInFactories = [NSMutableDictionary dictionary];
    self.plugInInstances = [NSMutableDictionary dictionary];
    self.runLoopBlockRecords = [NSMutableDictionary dictionary];
    if (!registry.guestObjectDecoder || !registry.guestObjectEncoder || !registry.guestAllocator) {
        if (error) *error = [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:2
            userInfo:@{NSLocalizedDescriptionKey: @"CoreFoundation Resolve requires Objective-C and Darwin bridges."}];
        return NO;
    }
    double interval1904 = 3061152000.0; uint64_t intervalBits = 0;
    memcpy(&intervalBits, &interval1904, sizeof(intervalBits));
    uint32_t intervalAddress = registry.guestAllocator(8, YES);
    if (!intervalAddress || ![registry.memory writeUInt32:(uint32_t)(intervalBits >> 32) address:intervalAddress] ||
        ![registry.memory writeUInt32:(uint32_t)intervalBits address:intervalAddress + 4] ||
        ![registry registerSymbol:@"_kCFAbsoluteTimeIntervalSince1904" atAddress:intervalAddress
            handler:^BOOL(BRPPCState *state, NSError **callError) {
                (void)state;
                if (callError) {
                    *callError = [NSError errorWithDomain:BRPPCCoreFoundationErrorDomain code:1
                        userInfo:@{NSLocalizedDescriptionKey: @"kCFAbsoluteTimeIntervalSince1904 is CoreFoundation data."}];
                }
                return NO;
            } error:error]) return NO;
    if (![self writeDataSymbol:@"_kCFBooleanTrue" object:@YES error:error] ||
        ![self writeDataSymbol:@"_kCFBooleanFalse" object:@NO error:error] ||
        ![self writeDataSymbol:@"_kCFNull" object:[NSNull null] error:error] ||
        ![self writeDataSymbol:@"_kCFPreferencesAnyApplication"
                        object:(__bridge NSString *)kCFPreferencesAnyApplication error:error] ||
        ![self writeDataSymbol:@"_kCFPreferencesCurrentApplication"
                        object:(__bridge NSString *)kCFPreferencesCurrentApplication error:error] ||
        ![self writeDataSymbol:@"_kCFPreferencesAnyHost"
                        object:(__bridge NSString *)kCFPreferencesAnyHost error:error] ||
        ![self writeDataSymbol:@"_kCFPreferencesCurrentHost"
                        object:(__bridge NSString *)kCFPreferencesCurrentHost error:error] ||
        ![self writeDataSymbol:@"_kCFPreferencesAnyUser"
                        object:(__bridge NSString *)kCFPreferencesAnyUser error:error] ||
        ![self writeDataSymbol:@"_kCFPreferencesCurrentUser"
                        object:(__bridge NSString *)kCFPreferencesCurrentUser error:error] ||
        ![self writeDataSymbol:@"_kCFRunLoopDefaultMode"
                        object:(__bridge NSString *)kCFRunLoopDefaultMode error:error] ||
        ![self writeDataSymbol:@"_kCFRunLoopCommonModes"
                        object:(__bridge NSString *)kCFRunLoopCommonModes error:error]) return NO;
    NSDictionary<NSString *, NSString *> *localeSymbols = @{
        @"_kCFLocaleIdentifier": (__bridge NSString *)kCFLocaleIdentifier,
        @"_kCFLocaleLanguageCode": (__bridge NSString *)kCFLocaleLanguageCode,
        @"_kCFLocaleCountryCode": (__bridge NSString *)kCFLocaleCountryCode,
        @"_kCFLocaleScriptCode": (__bridge NSString *)kCFLocaleScriptCode,
        @"_kCFLocaleVariantCode": (__bridge NSString *)kCFLocaleVariantCode,
        @"_kCFLocaleExemplarCharacterSet": (__bridge NSString *)kCFLocaleExemplarCharacterSet,
        @"_kCFLocaleCalendarIdentifier": (__bridge NSString *)kCFLocaleCalendarIdentifier,
        @"_kCFLocaleCalendar": (__bridge NSString *)kCFLocaleCalendar,
        @"_kCFLocaleCollationIdentifier": (__bridge NSString *)kCFLocaleCollationIdentifier,
        @"_kCFLocaleUsesMetricSystem": (__bridge NSString *)kCFLocaleUsesMetricSystem,
        @"_kCFLocaleMeasurementSystem": (__bridge NSString *)kCFLocaleMeasurementSystem,
        @"_kCFLocaleDecimalSeparator": (__bridge NSString *)kCFLocaleDecimalSeparator,
        @"_kCFLocaleGroupingSeparator": (__bridge NSString *)kCFLocaleGroupingSeparator,
        @"_kCFLocaleCurrencySymbol": (__bridge NSString *)kCFLocaleCurrencySymbol,
        @"_kCFLocaleCurrencyCode": (__bridge NSString *)kCFLocaleCurrencyCode,
        @"_kCFLocaleCollatorIdentifier": (__bridge NSString *)kCFLocaleCollatorIdentifier,
        @"_kCFLocaleQuotationBeginDelimiterKey": (__bridge NSString *)kCFLocaleQuotationBeginDelimiterKey,
        @"_kCFLocaleQuotationEndDelimiterKey": (__bridge NSString *)kCFLocaleQuotationEndDelimiterKey,
        @"_kCFLocaleAlternateQuotationBeginDelimiterKey": (__bridge NSString *)kCFLocaleAlternateQuotationBeginDelimiterKey,
        @"_kCFLocaleAlternateQuotationEndDelimiterKey": (__bridge NSString *)kCFLocaleAlternateQuotationEndDelimiterKey,
        @"_kCFLocaleCurrentLocaleDidChangeNotification": (__bridge NSString *)kCFLocaleCurrentLocaleDidChangeNotification,
        @"_kCFGregorianCalendar": (__bridge NSString *)kCFGregorianCalendar,
        @"_kCFBuddhistCalendar": (__bridge NSString *)kCFBuddhistCalendar,
        @"_kCFChineseCalendar": (__bridge NSString *)kCFChineseCalendar,
        @"_kCFHebrewCalendar": (__bridge NSString *)kCFHebrewCalendar,
        @"_kCFIslamicCalendar": (__bridge NSString *)kCFIslamicCalendar,
        @"_kCFIslamicCivilCalendar": (__bridge NSString *)kCFIslamicCivilCalendar,
        @"_kCFJapaneseCalendar": (__bridge NSString *)kCFJapaneseCalendar,
        @"_kCFRepublicOfChinaCalendar": (__bridge NSString *)kCFRepublicOfChinaCalendar,
        @"_kCFPersianCalendar": (__bridge NSString *)kCFPersianCalendar,
        @"_kCFIndianCalendar": (__bridge NSString *)kCFIndianCalendar,
        @"_kCFISO8601Calendar": (__bridge NSString *)kCFISO8601Calendar,
        @"_kCFIslamicTabularCalendar": (__bridge NSString *)kCFIslamicTabularCalendar,
        @"_kCFIslamicUmmAlQuraCalendar": (__bridge NSString *)kCFIslamicUmmAlQuraCalendar,
        @"_kCFBanglaCalendar": (__bridge NSString *)kCFBanglaCalendar,
        @"_kCFGujaratiCalendar": (__bridge NSString *)kCFGujaratiCalendar,
        @"_kCFKannadaCalendar": (__bridge NSString *)kCFKannadaCalendar,
        @"_kCFMalayalamCalendar": (__bridge NSString *)kCFMalayalamCalendar,
        @"_kCFMarathiCalendar": (__bridge NSString *)kCFMarathiCalendar,
        @"_kCFOdiaCalendar": (__bridge NSString *)kCFOdiaCalendar,
        @"_kCFTamilCalendar": (__bridge NSString *)kCFTamilCalendar,
        @"_kCFTeluguCalendar": (__bridge NSString *)kCFTeluguCalendar,
        @"_kCFVikramCalendar": (__bridge NSString *)kCFVikramCalendar,
        @"_kCFDangiCalendar": (__bridge NSString *)kCFDangiCalendar,
        @"_kCFVietnameseCalendar": (__bridge NSString *)kCFVietnameseCalendar
    };
    for (NSString *symbol in localeSymbols)
        if (![self writeDataSymbol:symbol object:localeSymbols[symbol] error:error]) return NO;
    NSDictionary<NSString *, NSString *> *errorSymbols = @{
        @"_kCFErrorDomainPOSIX": (__bridge NSString *)kCFErrorDomainPOSIX,
        @"_kCFErrorDomainOSStatus": (__bridge NSString *)kCFErrorDomainOSStatus,
        @"_kCFErrorDomainMach": (__bridge NSString *)kCFErrorDomainMach,
        @"_kCFErrorDomainCocoa": (__bridge NSString *)kCFErrorDomainCocoa,
        @"_kCFErrorLocalizedDescriptionKey": (__bridge NSString *)kCFErrorLocalizedDescriptionKey,
        @"_kCFErrorLocalizedFailureKey": (__bridge NSString *)kCFErrorLocalizedFailureKey,
        @"_kCFErrorLocalizedFailureReasonKey": (__bridge NSString *)kCFErrorLocalizedFailureReasonKey,
        @"_kCFErrorLocalizedRecoverySuggestionKey": (__bridge NSString *)kCFErrorLocalizedRecoverySuggestionKey,
        @"_kCFErrorDescriptionKey": (__bridge NSString *)kCFErrorDescriptionKey,
        @"_kCFErrorUnderlyingErrorKey": (__bridge NSString *)kCFErrorUnderlyingErrorKey,
        @"_kCFErrorURLKey": (__bridge NSString *)kCFErrorURLKey,
        @"_kCFErrorFilePathKey": (__bridge NSString *)kCFErrorFilePathKey
    };
    for (NSString *symbol in errorSymbols)
        if (![self writeDataSymbol:symbol object:errorSymbols[symbol] error:error]) return NO;
    NSDictionary<NSString *, NSString *> *dateFormatterSymbols = @{
        @"_kCFDateFormatterIsLenient": (__bridge NSString *)kCFDateFormatterIsLenient,
        @"_kCFDateFormatterTimeZone": (__bridge NSString *)kCFDateFormatterTimeZone,
        @"_kCFDateFormatterCalendarName": (__bridge NSString *)kCFDateFormatterCalendarName,
        @"_kCFDateFormatterDefaultFormat": (__bridge NSString *)kCFDateFormatterDefaultFormat,
        @"_kCFDateFormatterTwoDigitStartDate": (__bridge NSString *)kCFDateFormatterTwoDigitStartDate,
        @"_kCFDateFormatterDefaultDate": (__bridge NSString *)kCFDateFormatterDefaultDate,
        @"_kCFDateFormatterCalendar": (__bridge NSString *)kCFDateFormatterCalendar,
        @"_kCFDateFormatterEraSymbols": (__bridge NSString *)kCFDateFormatterEraSymbols,
        @"_kCFDateFormatterMonthSymbols": (__bridge NSString *)kCFDateFormatterMonthSymbols,
        @"_kCFDateFormatterShortMonthSymbols": (__bridge NSString *)kCFDateFormatterShortMonthSymbols,
        @"_kCFDateFormatterWeekdaySymbols": (__bridge NSString *)kCFDateFormatterWeekdaySymbols,
        @"_kCFDateFormatterShortWeekdaySymbols": (__bridge NSString *)kCFDateFormatterShortWeekdaySymbols,
        @"_kCFDateFormatterAMSymbol": (__bridge NSString *)kCFDateFormatterAMSymbol,
        @"_kCFDateFormatterPMSymbol": (__bridge NSString *)kCFDateFormatterPMSymbol,
        @"_kCFDateFormatterLongEraSymbols": (__bridge NSString *)kCFDateFormatterLongEraSymbols,
        @"_kCFDateFormatterVeryShortMonthSymbols": (__bridge NSString *)kCFDateFormatterVeryShortMonthSymbols,
        @"_kCFDateFormatterStandaloneMonthSymbols": (__bridge NSString *)kCFDateFormatterStandaloneMonthSymbols,
        @"_kCFDateFormatterShortStandaloneMonthSymbols": (__bridge NSString *)kCFDateFormatterShortStandaloneMonthSymbols,
        @"_kCFDateFormatterVeryShortStandaloneMonthSymbols": (__bridge NSString *)kCFDateFormatterVeryShortStandaloneMonthSymbols,
        @"_kCFDateFormatterVeryShortWeekdaySymbols": (__bridge NSString *)kCFDateFormatterVeryShortWeekdaySymbols,
        @"_kCFDateFormatterStandaloneWeekdaySymbols": (__bridge NSString *)kCFDateFormatterStandaloneWeekdaySymbols,
        @"_kCFDateFormatterShortStandaloneWeekdaySymbols": (__bridge NSString *)kCFDateFormatterShortStandaloneWeekdaySymbols,
        @"_kCFDateFormatterVeryShortStandaloneWeekdaySymbols": (__bridge NSString *)kCFDateFormatterVeryShortStandaloneWeekdaySymbols,
        @"_kCFDateFormatterQuarterSymbols": (__bridge NSString *)kCFDateFormatterQuarterSymbols,
        @"_kCFDateFormatterShortQuarterSymbols": (__bridge NSString *)kCFDateFormatterShortQuarterSymbols,
        @"_kCFDateFormatterStandaloneQuarterSymbols": (__bridge NSString *)kCFDateFormatterStandaloneQuarterSymbols,
        @"_kCFDateFormatterShortStandaloneQuarterSymbols": (__bridge NSString *)kCFDateFormatterShortStandaloneQuarterSymbols,
        @"_kCFDateFormatterGregorianStartDate": (__bridge NSString *)kCFDateFormatterGregorianStartDate,
        @"_kCFDateFormatterDoesRelativeDateFormattingKey": (__bridge NSString *)kCFDateFormatterDoesRelativeDateFormattingKey
    };
    for (NSString *symbol in dateFormatterSymbols)
        if (![self writeDataSymbol:symbol object:dateFormatterSymbols[symbol] error:error]) return NO;
    NSDictionary<NSString *, NSString *> *numberFormatterSymbols = @{
        @"_kCFNumberFormatterCurrencyCode": (__bridge NSString *)kCFNumberFormatterCurrencyCode,
        @"_kCFNumberFormatterDecimalSeparator": (__bridge NSString *)kCFNumberFormatterDecimalSeparator,
        @"_kCFNumberFormatterCurrencyDecimalSeparator": (__bridge NSString *)kCFNumberFormatterCurrencyDecimalSeparator,
        @"_kCFNumberFormatterAlwaysShowDecimalSeparator": (__bridge NSString *)kCFNumberFormatterAlwaysShowDecimalSeparator,
        @"_kCFNumberFormatterGroupingSeparator": (__bridge NSString *)kCFNumberFormatterGroupingSeparator,
        @"_kCFNumberFormatterUseGroupingSeparator": (__bridge NSString *)kCFNumberFormatterUseGroupingSeparator,
        @"_kCFNumberFormatterPercentSymbol": (__bridge NSString *)kCFNumberFormatterPercentSymbol,
        @"_kCFNumberFormatterZeroSymbol": (__bridge NSString *)kCFNumberFormatterZeroSymbol,
        @"_kCFNumberFormatterNaNSymbol": (__bridge NSString *)kCFNumberFormatterNaNSymbol,
        @"_kCFNumberFormatterInfinitySymbol": (__bridge NSString *)kCFNumberFormatterInfinitySymbol,
        @"_kCFNumberFormatterMinusSign": (__bridge NSString *)kCFNumberFormatterMinusSign,
        @"_kCFNumberFormatterPlusSign": (__bridge NSString *)kCFNumberFormatterPlusSign,
        @"_kCFNumberFormatterCurrencySymbol": (__bridge NSString *)kCFNumberFormatterCurrencySymbol,
        @"_kCFNumberFormatterExponentSymbol": (__bridge NSString *)kCFNumberFormatterExponentSymbol,
        @"_kCFNumberFormatterMinIntegerDigits": (__bridge NSString *)kCFNumberFormatterMinIntegerDigits,
        @"_kCFNumberFormatterMaxIntegerDigits": (__bridge NSString *)kCFNumberFormatterMaxIntegerDigits,
        @"_kCFNumberFormatterMinFractionDigits": (__bridge NSString *)kCFNumberFormatterMinFractionDigits,
        @"_kCFNumberFormatterMaxFractionDigits": (__bridge NSString *)kCFNumberFormatterMaxFractionDigits,
        @"_kCFNumberFormatterGroupingSize": (__bridge NSString *)kCFNumberFormatterGroupingSize,
        @"_kCFNumberFormatterSecondaryGroupingSize": (__bridge NSString *)kCFNumberFormatterSecondaryGroupingSize,
        @"_kCFNumberFormatterRoundingMode": (__bridge NSString *)kCFNumberFormatterRoundingMode,
        @"_kCFNumberFormatterRoundingIncrement": (__bridge NSString *)kCFNumberFormatterRoundingIncrement,
        @"_kCFNumberFormatterFormatWidth": (__bridge NSString *)kCFNumberFormatterFormatWidth,
        @"_kCFNumberFormatterPaddingPosition": (__bridge NSString *)kCFNumberFormatterPaddingPosition,
        @"_kCFNumberFormatterPaddingCharacter": (__bridge NSString *)kCFNumberFormatterPaddingCharacter,
        @"_kCFNumberFormatterDefaultFormat": (__bridge NSString *)kCFNumberFormatterDefaultFormat,
        @"_kCFNumberFormatterMultiplier": (__bridge NSString *)kCFNumberFormatterMultiplier,
        @"_kCFNumberFormatterPositivePrefix": (__bridge NSString *)kCFNumberFormatterPositivePrefix,
        @"_kCFNumberFormatterPositiveSuffix": (__bridge NSString *)kCFNumberFormatterPositiveSuffix,
        @"_kCFNumberFormatterNegativePrefix": (__bridge NSString *)kCFNumberFormatterNegativePrefix,
        @"_kCFNumberFormatterNegativeSuffix": (__bridge NSString *)kCFNumberFormatterNegativeSuffix,
        @"_kCFNumberFormatterPerMillSymbol": (__bridge NSString *)kCFNumberFormatterPerMillSymbol,
        @"_kCFNumberFormatterInternationalCurrencySymbol": (__bridge NSString *)kCFNumberFormatterInternationalCurrencySymbol,
        @"_kCFNumberFormatterCurrencyGroupingSeparator": (__bridge NSString *)kCFNumberFormatterCurrencyGroupingSeparator,
        @"_kCFNumberFormatterIsLenient": (__bridge NSString *)kCFNumberFormatterIsLenient,
        @"_kCFNumberFormatterUseSignificantDigits": (__bridge NSString *)kCFNumberFormatterUseSignificantDigits,
        @"_kCFNumberFormatterMinSignificantDigits": (__bridge NSString *)kCFNumberFormatterMinSignificantDigits,
        @"_kCFNumberFormatterMaxSignificantDigits": (__bridge NSString *)kCFNumberFormatterMaxSignificantDigits,
        @"_kCFNumberFormatterMinGroupingDigits": (__bridge NSString *)kCFNumberFormatterMinGroupingDigits
    };
    for (NSString *symbol in numberFormatterSymbols)
        if (![self writeDataSymbol:symbol object:numberFormatterSymbols[symbol] error:error]) return NO;
    if (![self writeDataSymbol:@"_kCFTimeZoneSystemTimeZoneDidChangeNotification"
                        object:(__bridge NSString *)kCFTimeZoneSystemTimeZoneDidChangeNotification
                         error:error]) return NO;
    NSDictionary<NSString *, NSString *> *bundleSymbols = @{
        @"_kCFBundleInfoDictionaryVersionKey": (__bridge NSString *)kCFBundleInfoDictionaryVersionKey,
        @"_kCFBundleExecutableKey": (__bridge NSString *)kCFBundleExecutableKey,
        @"_kCFBundleIdentifierKey": (__bridge NSString *)kCFBundleIdentifierKey,
        @"_kCFBundleVersionKey": (__bridge NSString *)kCFBundleVersionKey,
        @"_kCFBundleDevelopmentRegionKey": (__bridge NSString *)kCFBundleDevelopmentRegionKey,
        @"_kCFBundleNameKey": (__bridge NSString *)kCFBundleNameKey,
        @"_kCFBundleLocalizationsKey": (__bridge NSString *)kCFBundleLocalizationsKey
    };
    for (NSString *symbol in bundleSymbols)
        if (![self writeDataSymbol:symbol object:bundleSymbols[symbol] error:error]) return NO;
    for (NSString *name in @[@"kCFStreamPropertyDataWritten", @"kCFStreamPropertyAppendToFile",
        @"kCFStreamPropertyFileCurrentOffset", @"kCFStreamPropertySocketNativeHandle",
        @"kCFStreamPropertySocketRemoteHostName", @"kCFStreamPropertySocketRemotePortNumber",
        @"kCFStreamPropertySOCKSProxy", @"kCFStreamPropertySOCKSProxyHost",
        @"kCFStreamPropertySOCKSProxyPort", @"kCFStreamPropertySOCKSVersion",
        @"kCFStreamSocketSOCKSVersion4", @"kCFStreamSocketSOCKSVersion5",
        @"kCFStreamPropertySOCKSUser", @"kCFStreamPropertySOCKSPassword",
        @"kCFStreamPropertySocketSecurityLevel", @"kCFStreamSocketSecurityLevelNone",
        @"kCFStreamSocketSecurityLevelSSLv2", @"kCFStreamSocketSecurityLevelSSLv3",
        @"kCFStreamSocketSecurityLevelTLSv1", @"kCFStreamSocketSecurityLevelNegotiatedSSL",
        @"kCFStreamPropertyShouldCloseNativeSocket"])
        if (![self writeDataSymbol:[@"_" stringByAppendingString:name]
                            object:(__bridge id)HostCFStringConstant(name.UTF8String) error:error]) return NO;
    if (![self writeUInt32DataSymbol:@"_kCFStreamErrorDomainSOCKS"
                               value:(uint32_t)kCFStreamErrorDomainSOCKS error:error] ||
        ![self writeUInt32DataSymbol:@"_kCFStreamErrorDomainSSL"
                               value:(uint32_t)kCFStreamErrorDomainSSL error:error]) return NO;
    for (NSString *name in @[@"kCFSocketCommandKey", @"kCFSocketNameKey", @"kCFSocketValueKey",
        @"kCFSocketResultKey", @"kCFSocketErrorKey", @"kCFSocketRegisterCommand",
        @"kCFSocketRetrieveCommand"])
        if (![self writeDataSymbol:[@"_" stringByAppendingString:name]
                            object:(__bridge id)HostCFStringConstant(name.UTF8String) error:error]) return NO;
    for (NSString *name in @[@"kCFURLFileExists", @"kCFURLFileDirectoryContents", @"kCFURLFileLength",
        @"kCFURLFileLastModificationTime", @"kCFURLFilePOSIXMode", @"kCFURLFileOwnerID",
        @"kCFURLHTTPStatusCode", @"kCFURLHTTPStatusLine"])
        if (![self writeDataSymbol:[@"_" stringByAppendingString:name]
                            object:(__bridge id)HostCFStringConstant(name.UTF8String) error:error]) return NO;
    for (NSString *name in @[@"kCFUserNotificationIconURLKey", @"kCFUserNotificationSoundURLKey",
        @"kCFUserNotificationLocalizationURLKey", @"kCFUserNotificationAlertHeaderKey",
        @"kCFUserNotificationAlertMessageKey", @"kCFUserNotificationDefaultButtonTitleKey",
        @"kCFUserNotificationAlternateButtonTitleKey", @"kCFUserNotificationOtherButtonTitleKey",
        @"kCFUserNotificationProgressIndicatorValueKey", @"kCFUserNotificationPopUpTitlesKey",
        @"kCFUserNotificationTextFieldTitlesKey", @"kCFUserNotificationCheckBoxTitlesKey",
        @"kCFUserNotificationTextFieldValuesKey", @"kCFUserNotificationPopUpSelectionKey",
        @"kCFUserNotificationAlertTopMostKey", @"kCFUserNotificationKeyboardTypesKey"])
        if (![self writeDataSymbol:[@"_" stringByAppendingString:name]
                            object:(__bridge id)HostCFStringConstant(name.UTF8String) error:error]) return NO;
    for (NSString *name in @[@"kCFXMLTreeErrorDescription", @"kCFXMLTreeErrorLineNumber",
                               @"kCFXMLTreeErrorLocation", @"kCFXMLTreeErrorStatusCode"])
        if (![self writeDataSymbol:[@"_" stringByAppendingString:name]
                            object:(__bridge id)HostCFStringConstant(name.UTF8String) error:error]) return NO;
    if (![self writeDataSymbol:@"_kCFAllocatorDefault" object:nil error:error] ||
        ![self writeDataSymbol:@"_kCFAllocatorSystemDefault"
                        object:(__bridge id)kCFAllocatorSystemDefault error:error] ||
        ![self writeDataSymbol:@"_kCFAllocatorMalloc"
                        object:(__bridge id)kCFAllocatorMalloc error:error] ||
        ![self writeDataSymbol:@"_kCFAllocatorMallocZone"
                        object:(__bridge id)kCFAllocatorMallocZone error:error] ||
        ![self writeDataSymbol:@"_kCFAllocatorNull"
                        object:(__bridge id)kCFAllocatorNull error:error]) return NO;
    NSObject *allocatorUseContextMarker = [NSObject new];
    if (![self writeDataSymbol:@"_kCFAllocatorUseContext" object:allocatorUseContextMarker error:error]) return NO;
    self.defaultAllocatorHandle = [self handle:(__bridge id)kCFAllocatorSystemDefault];
    self.nullAllocatorHandle = [self handle:(__bridge id)kCFAllocatorNull];
    for (NSString *symbol in @[@"_kCFTypeArrayCallBacks", @"_kCFTypeDictionaryKeyCallBacks",
                                @"_kCFTypeDictionaryValueCallBacks", @"_kCFTypeSetCallBacks",
                                @"_kCFTypeBagCallBacks", @"_kCFCopyStringBagCallBacks"])
        if (![self writeDataSymbol:symbol object:nil error:error]) return NO;
    if (![self writeDataSymbol:@"_kCFStringBinaryHeapCallBacks" object:nil error:error]) return NO;
    if (![self writeDataSymbol:@"_kCFPlugInDynamicRegistrationKey"
                        object:(__bridge id)kCFPlugInDynamicRegistrationKey error:error] ||
        ![self writeDataSymbol:@"_kCFPlugInDynamicRegisterFunctionKey"
                        object:(__bridge id)kCFPlugInDynamicRegisterFunctionKey error:error] ||
        ![self writeDataSymbol:@"_kCFPlugInUnloadFunctionKey"
                        object:(__bridge id)kCFPlugInUnloadFunctionKey error:error] ||
        ![self writeDataSymbol:@"_kCFPlugInFactoriesKey"
                        object:(__bridge id)kCFPlugInFactoriesKey error:error] ||
        ![self writeDataSymbol:@"_kCFPlugInTypesKey"
                        object:(__bridge id)kCFPlugInTypesKey error:error]) return NO;
    __weak typeof(self) weakSelf = self;

    [registry registerSymbol:@"_CFRetain" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf object:state->gpr[3]] ? state->gpr[3] : 0); return YES;
    }];
    [registry registerSymbol:@"___CFStringMakeConstantString"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [registry.memory readCStringAtAddress:state->gpr[3]
                maximumLength:1u << 20]; CFFinish(state, [weakSelf handle:string]); return YES;
        }];
    [registry registerSymbol:@"_CFRelease" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFAutorelease", @"_CFMakeCollectable"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFFinish(state, [weakSelf object:state->gpr[3]] ? state->gpr[3] : 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id object = [weakSelf object:state->gpr[3]];
        uint32_t type = [object isKindOfClass:[BRPPCGuestAllocatorRecord class]]
            ? (uint32_t)CFAllocatorGetTypeID()
            : object ? (uint32_t)CFGetTypeID((__bridge CFTypeRef)object) : 0;
        CFFinish(state, type); return YES;
    }];
    [registry registerSymbol:@"_CFGetRetainCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id object = [weakSelf object:state->gpr[3]];
        CFFinish(state, object ? (uint32_t)CFGetRetainCount((__bridge CFTypeRef)object) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFEqual" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] isEqual:[weakSelf object:state->gpr[4]]]); return YES;
    }];
    [registry registerSymbol:@"_CFHash" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[[weakSelf object:state->gpr[3]] hash]); return YES;
    }];
    [registry registerSymbol:@"_CFCopyDescription" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] description]]); return YES;
    }];
    [registry registerSymbol:@"_CFCopyTypeIDDescription" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFStringRef value = CFCopyTypeIDDescription(state->gpr[3]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFGetAllocator" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; (void)state->gpr[3];
        CFFinish(state, weakSelf.defaultAllocatorHandle); return YES;
    }];
    [registry registerSymbol:@"_CFShow" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSLog(@"%@", [weakSelf object:state->gpr[3]]); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFCopyHomeDirectoryURL" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; typedef CFURLRef (*CopyHomeDirectoryFunction)(void);
        CopyHomeDirectoryFunction function = (CopyHomeDirectoryFunction)dlsym(RTLD_DEFAULT,
            "CFCopyHomeDirectoryURL"); CFURLRef URL = function ? function() : NULL;
        id value = URL ? CFBridgingRelease(URL) : [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
        CFFinish(state, [weakSelf handle:value]); return YES;
    }];
    [registry registerSymbol:@"_CFBooleanGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFBooleanGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFBooleanGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] boolValue]); return YES;
    }];
    [registry registerSymbol:@"_CFNullGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFNullGetTypeID()); return YES;
    }];

    [registry registerSymbol:@"_CFAllocatorGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFAllocatorGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorSetDefault" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; weakSelf.defaultAllocatorHandle = state->gpr[3]
            ? state->gpr[3] : [weakSelf handle:(__bridge id)kCFAllocatorSystemDefault];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorGetDefault" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, weakSelf.defaultAllocatorHandle); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t address = state->gpr[4], words[9] = {0};
        for (NSUInteger index = 0; index < 9; index++)
            if (!address || ![registry.memory readUInt32:&words[index]
                                                   address:address + (uint32_t)index * 4]) return NO;
        if (words[0] != 0) return NO;
        BRPPCGuestAllocatorRecord *record = [BRPPCGuestAllocatorRecord new]; record.resolver = weakSelf;
        record.outerState = *state; record.info = words[1]; record.retainFunction = words[2];
        record.releaseFunction = words[3]; record.descriptionFunction = words[4];
        record.allocateFunction = words[5]; record.reallocateFunction = words[6];
        record.deallocateFunction = words[7]; record.preferredSizeFunction = words[8];
        if (record.retainFunction) {
            uint32_t retained = 0;
            if (![weakSelf invokeGuestFunction:record.retainFunction outerState:*state
                arguments:@[@(record.info)] result:&retained label:@"CFAllocator context retain"
                error:callError]) return NO;
            record.info = retained;
        }
        CFFinish(state, [weakSelf handle:record]); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorAllocate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t allocatorHandle = state->gpr[3] ?: weakSelf.defaultAllocatorHandle;
        BRPPCGuestAllocatorRecord *record = [weakSelf object:allocatorHandle];
        uint32_t size = state->gpr[4], result = 0;
        if (allocatorHandle == weakSelf.nullAllocatorHandle) result = 0;
        else if ([record isKindOfClass:[BRPPCGuestAllocatorRecord class]] && record.allocateFunction) {
            if (![weakSelf invokeGuestFunction:record.allocateFunction outerState:record.outerState
                arguments:@[@(size), @(state->gpr[5]), @(record.info)] result:&result
                label:@"CFAllocator allocate" error:callError]) return NO;
        } else if (registry.guestAllocator) result = registry.guestAllocator(MAX(size, 1u), NO);
        if (result) weakSelf.allocatorSizes[@(result)] = @(size); CFFinish(state, result); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorReallocate" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        uint32_t allocatorHandle = state->gpr[3] ?: weakSelf.defaultAllocatorHandle;
        BRPPCGuestAllocatorRecord *record = [weakSelf object:allocatorHandle];
        uint32_t pointer = state->gpr[4], size = state->gpr[5], result = 0;
        if (allocatorHandle == weakSelf.nullAllocatorHandle) result = 0;
        else if ([record isKindOfClass:[BRPPCGuestAllocatorRecord class]] && record.reallocateFunction) {
            if (![weakSelf invokeGuestFunction:record.reallocateFunction outerState:record.outerState
                arguments:@[@(pointer), @(size), @(state->gpr[6]), @(record.info)] result:&result
                label:@"CFAllocator reallocate" error:callError]) return NO;
        } else if (!pointer && registry.guestAllocator) result = registry.guestAllocator(MAX(size, 1u), NO);
        else if (!size) { if (registry.guestDeallocator) registry.guestDeallocator(pointer); result = 0; }
        else {
            uint32_t oldSize = weakSelf.allocatorSizes[@(pointer)].unsignedIntValue;
            result = registry.guestAllocator ? registry.guestAllocator(size, NO) : 0;
            uint32_t copySize = MIN(oldSize, size); void *bytes = copySize ? malloc(copySize) : NULL;
            if (!result || (copySize && (!bytes || ![registry.memory readBytes:bytes address:pointer length:copySize] ||
                ![registry.memory writeBytes:bytes address:result length:copySize]))) {
                if (result && registry.guestDeallocator) registry.guestDeallocator(result); result = 0;
            } else if (registry.guestDeallocator) registry.guestDeallocator(pointer);
            free(bytes);
        }
        [weakSelf.allocatorSizes removeObjectForKey:@(pointer)];
        if (result) weakSelf.allocatorSizes[@(result)] = @(size); CFFinish(state, result); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorDeallocate" handler:^BOOL(BRPPCState *state,
                                                                       NSError **callError) {
        uint32_t allocatorHandle = state->gpr[3] ?: weakSelf.defaultAllocatorHandle;
        BRPPCGuestAllocatorRecord *record = [weakSelf object:allocatorHandle]; uint32_t pointer = state->gpr[4];
        if ([record isKindOfClass:[BRPPCGuestAllocatorRecord class]] && record.deallocateFunction) {
            if (![weakSelf invokeGuestFunction:record.deallocateFunction outerState:record.outerState
                arguments:@[@(pointer), @(record.info)] result:NULL label:@"CFAllocator deallocate"
                error:callError]) return NO;
        } else if (allocatorHandle != weakSelf.nullAllocatorHandle && registry.guestDeallocator)
            registry.guestDeallocator(pointer);
        [weakSelf.allocatorSizes removeObjectForKey:@(pointer)]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFAllocatorGetPreferredSizeForSize"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            uint32_t allocatorHandle = state->gpr[3] ?: weakSelf.defaultAllocatorHandle;
            BRPPCGuestAllocatorRecord *record = [weakSelf object:allocatorHandle]; uint32_t result = state->gpr[4];
            if ([record isKindOfClass:[BRPPCGuestAllocatorRecord class]] && record.preferredSizeFunction &&
                ![weakSelf invokeGuestFunction:record.preferredSizeFunction outerState:record.outerState
                    arguments:@[@(state->gpr[4]), @(state->gpr[5]), @(record.info)] result:&result
                    label:@"CFAllocator preferred size" error:callError]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFAllocatorGetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestAllocatorRecord *record = [weakSelf object:state->gpr[3]];
        if (![record isKindOfClass:[BRPPCGuestAllocatorRecord class]] || !state->gpr[4]) return NO;
        uint32_t words[9] = {0, record.info, record.retainFunction, record.releaseFunction,
            record.descriptionFunction, record.allocateFunction, record.reallocateFunction,
            record.deallocateFunction, record.preferredSizeFunction};
        for (NSUInteger index = 0; index < 9; index++)
            if (![registry.memory writeUInt32:words[index]
                                      address:state->gpr[4] + (uint32_t)index * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFStringGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFStringGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateWithCString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *bytes = [weakSelf cstringDataAtAddress:state->gpr[4]];
        NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(state->gpr[5]);
        NSString *value = bytes ? [[NSString alloc] initWithData:bytes encoding:encoding] : nil;
        CFFinish(state, [weakSelf handle:value]); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateWithBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5]; NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
        NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(state->gpr[6]);
        NSString *value = [[NSString alloc] initWithData:data encoding:encoding];
        CFFinish(state, [weakSelf handle:value]); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateWithCharacters" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t count = state->gpr[5]; unichar *characters = calloc(count ?: 1, sizeof(*characters));
        if (!characters) return NO;
        BOOL valid = YES;
        for (uint32_t i = 0; i < count; i++) { uint8_t bytes[2];
            if (![registry.memory readBytes:bytes address:state->gpr[4] + i * 2 length:2]) { valid = NO; break; }
            characters[i] = (unichar)((uint16_t)bytes[0] << 8 | bytes[1]);
        }
        NSString *value = valid ? [NSString stringWithCharacters:characters length:count] : nil;
        free(characters); if (!valid) return NO; CFFinish(state, [weakSelf handle:value]); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateWithSubstring" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[4]];
        NSRange range = NSMakeRange(state->gpr[5], state->gpr[6]);
        CFFinish(state, NSMaxRange(range) <= value.length ? [weakSelf handle:[value substringWithRange:range]] : 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf string:state->gpr[4]] copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateMutable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSMutableString stringWithCapacity:state->gpr[4]]]); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf string:state->gpr[5]] mutableCopy]]); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetLength" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[weakSelf string:state->gpr[3]].length); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetCharacterAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[3]];
        CFFinish(state, state->gpr[4] < value.length ? [value characterAtIndex:state->gpr[4]] : 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetCString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[3]];
        NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(state->gpr[6]);
        NSData *data = [value dataUsingEncoding:encoding allowLossyConversion:YES]; uint32_t capacity = state->gpr[5];
        if (!value || !capacity || data.length + 1 > capacity) CFFinish(state, 0);
        else { uint8_t zero = 0; BOOL wrote = [registry.memory writeBytes:data.bytes address:state->gpr[4] length:data.length] &&
                [registry.memory writeBytes:&zero address:state->gpr[4] + (uint32_t)data.length length:1];
               CFFinish(state, wrote); }
        return YES;
    }];
    [registry registerSymbol:@"_CFStringGetCStringPtr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[3]];
        NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(state->gpr[4]);
        NSData *data = [value dataUsingEncoding:encoding allowLossyConversion:YES];
        NSMutableData *terminated = [data mutableCopy]; uint8_t zero = 0; [terminated appendBytes:&zero length:1];
        CFFinish(state, [weakSelf copyBytesToGuest:terminated.bytes length:terminated.length]); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetCharacters" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[3]]; NSUInteger location, length;
        [weakSelf readRangeAtGPR:4 state:state location:&location length:&length];
        if (NSMaxRange(NSMakeRange(location, length)) > value.length) return NO;
        for (NSUInteger i = 0; i < length; i++) {
            unichar character = [value characterAtIndex:location + i];
            uint8_t bytes[] = {character >> 8, character};
            if (![registry.memory writeBytes:bytes address:state->gpr[6] + (uint32_t)i * 2 length:2]) return NO;
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[3]];
        CFRange range = CFRangeMake(state->gpr[4], state->gpr[5]); uint32_t capacity = state->gpr[10];
        if (capacity > (1u << 28)) return NO;
        NSMutableData *buffer = [NSMutableData dataWithLength:capacity]; CFIndex used = 0;
        CFIndex converted = value ? CFStringGetBytes((__bridge CFStringRef)value, range,
            (CFStringEncoding)state->gpr[6], (UInt8)state->gpr[7], state->gpr[8] != 0,
            buffer.mutableBytes, capacity, &used) : 0;
        uint32_t usedAddress = 0;
        if (![registry.memory readUInt32:&usedAddress address:state->gpr[1] + 56]) return NO;
        if ((used && ![registry.memory writeBytes:buffer.bytes address:state->gpr[9] length:(NSUInteger)used]) ||
            (usedAddress && ![registry.memory writeUInt32:(uint32_t)used address:usedAddress])) return NO;
        CFFinish(state, (uint32_t)converted); return YES;
    }];
    [registry registerSymbol:@"_CFStringCompare" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSComparisonResult result = [[weakSelf string:state->gpr[3]]
            compare:[weakSelf string:state->gpr[4]] options:(NSStringCompareOptions)state->gpr[5]];
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFStringCompareWithOptions" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *value = [weakSelf string:state->gpr[3]], *other = [weakSelf string:state->gpr[4]];
        NSRange range = NSMakeRange(state->gpr[5], state->gpr[6]);
        NSComparisonResult result = NSMaxRange(range) <= value.length
            ? [[value substringWithRange:range] compare:other options:(NSStringCompareOptions)state->gpr[7]] : NSOrderedSame;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetSystemEncoding" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, CFStringGetSystemEncoding()); return YES;
    }];
    [registry registerSymbol:@"_CFStringIsEncodingAvailable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, CFStringIsEncodingAvailable(state->gpr[3])); return YES;
    }];
    [registry registerSymbol:@"_CFStringConvertEncodingToNSStringEncoding" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFStringConvertEncodingToNSStringEncoding(state->gpr[3])); return YES;
    }];
    [registry registerSymbol:@"_CFStringConvertNSStringEncodingToEncoding" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, CFStringConvertNSStringEncodingToEncoding(state->gpr[3])); return YES;
    }];
    [registry registerSymbol:@"_CFStringConvertEncodingToIANACharSetName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFStringRef name = CFStringConvertEncodingToIANACharSetName(state->gpr[3]);
        CFFinish(state, [weakSelf handle:(__bridge NSString *)name]); return YES;
    }];
    [registry registerSymbol:@"_CFStringConvertIANACharSetNameToEncoding" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = [weakSelf string:state->gpr[3]];
        CFFinish(state, name ? CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)name) : kCFStringEncodingInvalidId); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetListOfAvailableEncodings" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        if (!weakSelf.availableStringEncodingsAddress) {
            const CFStringEncoding *encodings = CFStringGetListOfAvailableEncodings(); NSUInteger count = 0;
            while (encodings[count] != kCFStringEncodingInvalidId && count < 65536) count++;
            if (count == 65536 || !registry.guestAllocator) return NO;
            uint32_t address = registry.guestAllocator((uint32_t)(count + 1) * 4, NO);
            if (!address) return NO;
            for (NSUInteger i = 0; i <= count; i++)
                if (![registry.memory writeUInt32:encodings[i] address:address + (uint32_t)i * 4]) return NO;
            weakSelf.availableStringEncodingsAddress = address;
        }
        CFFinish(state, weakSelf.availableStringEncodingsAddress); return YES;
    }];
    for (NSString *symbol in @[@"_CFStringHasPrefix", @"_CFStringHasSuffix"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *value = [weakSelf string:state->gpr[3]], *part = [weakSelf string:state->gpr[4]];
            CFFinish(state, [symbol hasSuffix:@"Prefix"] ? [value hasPrefix:part] : [value hasSuffix:part]); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFStringAppend", @"_CFStringAppendString"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableString *value = [weakSelf object:state->gpr[3]];
            [value appendString:[weakSelf string:state->gpr[4]] ?: @""];
            if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringAppendCharacters" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableString *value = [weakSelf object:state->gpr[3]]; uint32_t count = state->gpr[5];
        unichar *characters = calloc(count ?: 1, sizeof(unichar)); if (!characters) return NO;
        BOOL valid = YES; for (uint32_t i = 0; i < count; i++) { uint8_t bytes[2];
            if (![registry.memory readBytes:bytes address:state->gpr[4] + i * 2 length:2]) { valid = NO; break; }
            characters[i] = (unichar)((uint16_t)bytes[0] << 8 | bytes[1]); }
        if (valid) [value appendString:[NSString stringWithCharacters:characters length:count]]; free(characters);
        if (!valid || ![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringDelete" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSUInteger location, length; [weakSelf readRangeAtGPR:4 state:state location:&location length:&length];
        [[weakSelf object:state->gpr[3]] deleteCharactersInRange:NSMakeRange(location, length)];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringReplace" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSUInteger location, length; [weakSelf readRangeAtGPR:4 state:state location:&location length:&length];
        [[weakSelf object:state->gpr[3]] replaceCharactersInRange:NSMakeRange(location, length)
                                                       withString:[weakSelf string:state->gpr[6]] ?: @""];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringFindAndReplace" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableString *value = [weakSelf object:state->gpr[3]];
        NSUInteger count = [value replaceOccurrencesOfString:[weakSelf string:state->gpr[4]] ?: @""
                                                  withString:[weakSelf string:state->gpr[5]] ?: @""
                                                     options:(NSStringCompareOptions)state->gpr[8]
                                                       range:NSMakeRange(state->gpr[6], state->gpr[7])];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, (uint32_t)count); return YES;
    }];
    for (NSString *symbol in @[@"_CFStringUppercase", @"_CFStringLowercase", @"_CFStringCapitalize"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableString *value = [weakSelf object:state->gpr[3]];
            NSLocale *locale = [weakSelf object:state->gpr[4]];
            NSString *result = [symbol hasSuffix:@"Uppercase"] ? [value uppercaseStringWithLocale:locale] :
                ([symbol hasSuffix:@"Lowercase"] ? [value lowercaseStringWithLocale:locale] : [value capitalizedStringWithLocale:locale]);
            [value setString:result]; if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringTrim" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableString *value = [weakSelf object:state->gpr[3]];
        NSString *trim = [weakSelf string:state->gpr[4]] ?: @"";
        while (trim.length && [value hasPrefix:trim]) [value deleteCharactersInRange:NSMakeRange(0, trim.length)];
        while (trim.length && [value hasSuffix:trim]) [value deleteCharactersInRange:NSMakeRange(value.length - trim.length, trim.length)];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringTrimWhitespace" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableString *value = [weakSelf object:state->gpr[3]];
        [value setString:[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFArrayGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFArrayGetTypeID()); return YES;
    }];
    for (NSString *symbol in @[@"_CFArrayCreate", @"_CFArrayCreateMutable"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            NSMutableArray *array = [NSMutableArray array];
            if ([symbol isEqualToString:@"_CFArrayCreate"]) for (uint32_t i = 0; i < state->gpr[5]; i++) {
                uint32_t handle = 0; if (![registry.memory readUInt32:&handle address:state->gpr[4] + i * 4]) return NO;
                [array addObject:[weakSelf object:handle] ?: [NSNull null]];
            }
            CFFinish(state, [weakSelf handle:[symbol isEqualToString:@"_CFArrayCreate"] ? [array copy] : array]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFArrayCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFArrayCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[5]] mutableCopy]]); return YES;
    }];
    [registry registerSymbol:@"_CFArrayGetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[[weakSelf object:state->gpr[3]] count]); return YES;
    }];
    [registry registerSymbol:@"_CFArrayGetCountOfValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSArray *array = [weakSelf object:state->gpr[3]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]); id value = [weakSelf object:state->gpr[6]];
        NSUInteger count = 0;
        if (NSMaxRange(range) <= array.count)
            for (NSUInteger index = range.location; index < NSMaxRange(range); index++)
                if ([array[index] isEqual:value]) count++;
        CFFinish(state, (uint32_t)count); return YES;
    }];
    [registry registerSymbol:@"_CFArrayGetValueAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSArray *array = [weakSelf object:state->gpr[3]]; id value = state->gpr[4] < array.count ? array[state->gpr[4]] : nil;
        CFFinish(state, [weakSelf handle:value == [NSNull null] ? nil : value]); return YES;
    }];
    [registry registerSymbol:@"_CFArrayGetValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSArray *array = [weakSelf object:state->gpr[3]]; NSUInteger location, length;
        [weakSelf readRangeAtGPR:4 state:state location:&location length:&length];
        if (NSMaxRange(NSMakeRange(location, length)) > array.count) return NO;
        for (NSUInteger i = 0; i < length; i++)
            if (![registry.memory writeUInt32:[weakSelf handle:array[location + i]]
                                       address:state->gpr[6] + (uint32_t)i * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArrayContainsValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSArray *array = [weakSelf object:state->gpr[3]]; NSUInteger location, length;
        [weakSelf readRangeAtGPR:4 state:state location:&location length:&length]; id value = [weakSelf object:state->gpr[6]];
        CFFinish(state, NSMaxRange(NSMakeRange(location, length)) <= array.count &&
            [array indexOfObject:value inRange:NSMakeRange(location, length)] != NSNotFound); return YES;
    }];
    for (NSString *symbol in @[@"_CFArrayGetFirstIndexOfValue", @"_CFArrayGetLastIndexOfValue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSArray *array = [weakSelf object:state->gpr[3]]; NSUInteger location, length;
            [weakSelf readRangeAtGPR:4 state:state location:&location length:&length]; id value = [weakSelf object:state->gpr[6]];
            NSUInteger index = NSNotFound;
            if (NSMaxRange(NSMakeRange(location, length)) <= array.count) {
                if ([symbol containsString:@"Last"]) {
                    for (NSUInteger i = location + length; i > location; i--)
                        if ([array[i - 1] isEqual:value]) { index = i - 1; break; }
                } else index = [array indexOfObject:value inRange:NSMakeRange(location, length)];
            }
            CFFinish(state, index == NSNotFound ? UINT32_MAX : (uint32_t)index); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFArrayAppendValue", @"_CFArrayInsertValueAtIndex",
                                @"_CFArraySetValueAtIndex", @"_CFArrayRemoveValueAtIndex"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableArray *array = [weakSelf object:state->gpr[3]];
            if ([symbol hasSuffix:@"AppendValue"]) [array addObject:[weakSelf object:state->gpr[4]] ?: [NSNull null]];
            else if ([symbol hasSuffix:@"InsertValueAtIndex"]) [array insertObject:[weakSelf object:state->gpr[5]] ?: [NSNull null] atIndex:state->gpr[4]];
            else if ([symbol hasSuffix:@"SetValueAtIndex"]) array[state->gpr[4]] = [weakSelf object:state->gpr[5]] ?: [NSNull null];
            else [array removeObjectAtIndex:state->gpr[4]];
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFArrayRemoveAllValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] removeAllObjects]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArrayExchangeValuesAtIndices" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] exchangeObjectAtIndex:state->gpr[4]
                                                         withObjectAtIndex:state->gpr[5]];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArrayReplaceValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableArray *array = [weakSelf object:state->gpr[3]]; NSUInteger location, length;
        [weakSelf readRangeAtGPR:4 state:state location:&location length:&length];
        NSMutableArray *values = [NSMutableArray arrayWithCapacity:state->gpr[7]];
        for (uint32_t i = 0; i < state->gpr[7]; i++) { uint32_t handle = 0;
            if (![registry.memory readUInt32:&handle address:state->gpr[6] + i * 4]) return NO;
            [values addObject:[weakSelf object:handle] ?: [NSNull null]]; }
        [array replaceObjectsInRange:NSMakeRange(location, length) withObjectsFromArray:values];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArrayAppendArray" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableArray *destination = [weakSelf object:state->gpr[3]];
        NSArray *source = [weakSelf object:state->gpr[4]]; NSRange range = NSMakeRange(state->gpr[5], state->gpr[6]);
        if (NSMaxRange(range) > source.count) return NO;
        [destination addObjectsFromArray:[source subarrayWithRange:range]]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArrayApplyFunction" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSArray *array = [weakSelf object:state->gpr[3]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]);
        if (NSMaxRange(range) > array.count || !state->gpr[6]) return NO;
        BRPPCState outer = *state;
        for (NSUInteger index = range.location; index < NSMaxRange(range); index++)
            if (![weakSelf invokeGuestFunction:state->gpr[6] outerState:outer
                                      arguments:@[@([weakSelf handle:array[index]]), @(state->gpr[7])]
                                         result:NULL label:@"CFArray applier" error:callError]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArraySortValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSMutableArray *array = [weakSelf object:state->gpr[3]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]); uint32_t comparator = state->gpr[6];
        if (NSMaxRange(range) > array.count || !comparator) return NO;
        BRPPCState outer = *state;
        for (NSUInteger i = range.location + 1; i < NSMaxRange(range); i++) {
            for (NSUInteger j = i; j > range.location; j--) {
                uint32_t comparison = 0;
                if (![weakSelf invokeGuestFunction:comparator outerState:outer
                    arguments:@[@([weakSelf handle:array[j - 1]]), @([weakSelf handle:array[j]]), @(state->gpr[7])]
                    result:&comparison label:@"CFArray comparator" error:callError]) return NO;
                if ((int32_t)comparison <= 0) break;
                [array exchangeObjectAtIndex:j - 1 withObjectAtIndex:j];
            }
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFArrayBSearchValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSArray *array = [weakSelf object:state->gpr[3]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]);
        id sought = [weakSelf object:state->gpr[6]]; uint32_t comparator = state->gpr[7];
        if (NSMaxRange(range) > array.count || !comparator) return NO;
        BRPPCState outer = *state; NSUInteger low = range.location, high = NSMaxRange(range);
        while (low < high) {
            NSUInteger middle = low + (high - low) / 2; uint32_t comparison = 0;
            if (![weakSelf invokeGuestFunction:comparator outerState:outer
                arguments:@[@([weakSelf handle:array[middle]]), @([weakSelf handle:sought]), @(state->gpr[8])]
                result:&comparison label:@"CFArray comparator" error:callError]) return NO;
            if ((int32_t)comparison < 0) low = middle + 1; else high = middle;
        }
        CFFinish(state, (uint32_t)low); return YES;
    }];

    [registry registerSymbol:@"_CFDictionaryGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFDictionaryGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[5]] mutableCopy]]); return YES;
    }];
    for (NSString *symbol in @[@"_CFDictionaryCreate", @"_CFDictionaryCreateMutable"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            if ([symbol isEqualToString:@"_CFDictionaryCreate"]) for (uint32_t i = 0; i < state->gpr[6]; i++) {
                uint32_t key = 0, value = 0;
                if (![registry.memory readUInt32:&key address:state->gpr[4] + i * 4] ||
                    ![registry.memory readUInt32:&value address:state->gpr[5] + i * 4]) return NO;
                id keyObject = [weakSelf object:key], valueObject = [weakSelf object:value];
                if (keyObject) dictionary[keyObject] = valueObject ?: [NSNull null];
            }
            CFFinish(state, [weakSelf handle:[symbol isEqualToString:@"_CFDictionaryCreate"] ? [dictionary copy] : dictionary]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFDictionaryGetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[[weakSelf object:state->gpr[3]] count]); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id value = [[weakSelf object:state->gpr[3]] objectForKey:[weakSelf object:state->gpr[4]]];
        CFFinish(state, [weakSelf handle:value == [NSNull null] ? nil : value]); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryGetCountOfKey" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]]
            objectForKey:[weakSelf object:state->gpr[4]]] != nil); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryGetCountOfValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDictionary *dictionary = [weakSelf object:state->gpr[3]];
        id sought = [weakSelf object:state->gpr[4]]; NSUInteger count = 0;
        for (id value in dictionary.allValues) if ([value isEqual:sought]) count++;
        CFFinish(state, (uint32_t)count); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryGetValueIfPresent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id value = [[weakSelf object:state->gpr[3]]
            objectForKey:[weakSelf object:state->gpr[4]]];
        if (value && state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:value == [NSNull null] ? nil : value]
                                                           address:state->gpr[5]]) return NO;
        CFFinish(state, value != nil); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryContainsKey" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] objectForKey:[weakSelf object:state->gpr[4]]] != nil); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryContainsValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[[weakSelf object:state->gpr[3]] allValues]
            containsObject:[weakSelf object:state->gpr[4]]]); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryGetKeysAndValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDictionary *dictionary = [weakSelf object:state->gpr[3]];
        NSArray *keys = dictionary.allKeys;
        for (NSUInteger i = 0; i < keys.count; i++) {
            if (state->gpr[4] && ![registry.memory writeUInt32:[weakSelf handle:keys[i]]
                                                       address:state->gpr[4] + (uint32_t)i * 4]) return NO;
            if (state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:dictionary[keys[i]]]
                                                       address:state->gpr[5] + (uint32_t)i * 4]) return NO;
        }
        CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFDictionaryAddValue", @"_CFDictionarySetValue", @"_CFDictionaryReplaceValue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableDictionary *dictionary = [weakSelf object:state->gpr[3]];
            id key = [weakSelf object:state->gpr[4]], value = [weakSelf object:state->gpr[5]] ?: [NSNull null];
            if (key && (![symbol hasSuffix:@"ReplaceValue"] || dictionary[key])) dictionary[key] = value;
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFDictionaryRemoveValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] removeObjectForKey:[weakSelf object:state->gpr[4]]]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryRemoveAllValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] removeAllObjects]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDictionaryApplyFunction" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSDictionary *dictionary = [weakSelf object:state->gpr[3]]; uint32_t function = state->gpr[4];
        if (!function) return NO; BRPPCState outer = *state;
        for (id key in dictionary)
            if (![weakSelf invokeGuestFunction:function outerState:outer
                arguments:@[@([weakSelf handle:key]), @([weakSelf handle:dictionary[key]]), @(state->gpr[5])]
                result:NULL label:@"CFDictionary applier" error:callError]) return NO;
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFDataGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFDataGetTypeID()); return YES;
    }];
    for (NSString *symbol in @[@"_CFDataCreate", @"_CFDataCreateMutable"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableData *data;
            if ([symbol isEqualToString:@"_CFDataCreate"]) {
                data = [NSMutableData dataWithLength:state->gpr[5]];
                if (data.length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:data.length]) return NO;
            } else data = [NSMutableData dataWithCapacity:state->gpr[4]];
            CFFinish(state, [weakSelf handle:[symbol isEqualToString:@"_CFDataCreate"] ? [data copy] : data]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFDataCreateWithBytesNoCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5]; NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
        CFFinish(state, [weakSelf handle:[data copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFDataGetLength" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[[weakSelf object:state->gpr[3]] length]); return YES;
    }];
    [registry registerSymbol:@"_CFDataCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFDataCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[5]] mutableCopy]]); return YES;
    }];
    [registry registerSymbol:@"_CFDataGetBytePtr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *data = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf copyBytesToGuest:data.bytes length:data.length]); return YES;
    }];
    [registry registerSymbol:@"_CFDataGetMutableBytePtr" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *data = [weakSelf object:state->gpr[3]];
        uint32_t pointer = [weakSelf copyBytesToGuest:data.bytes length:data.length];
        if (pointer) weakSelf.copiedBytePointers[@(state->gpr[3])] = @(pointer);
        CFFinish(state, pointer); return YES;
    }];
    [registry registerSymbol:@"_CFDataGetBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *data = [weakSelf object:state->gpr[3]]; NSUInteger location, length;
        [weakSelf readRangeAtGPR:4 state:state location:&location length:&length];
        if (NSMaxRange(NSMakeRange(location, length)) > data.length ||
            ![registry.memory writeBytes:(const uint8_t *)data.bytes + location address:state->gpr[6] length:length]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDataAppendBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *data = [weakSelf object:state->gpr[3]]; uint32_t length = state->gpr[5];
        NSMutableData *bytes = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:bytes.mutableBytes address:state->gpr[4] length:length]) return NO;
        [data appendData:bytes]; [weakSelf.copiedBytePointers removeObjectForKey:@(state->gpr[3])];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDataSetLength" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] setLength:state->gpr[4]];
        [weakSelf.copiedBytePointers removeObjectForKey:@(state->gpr[3])]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDataIncreaseLength" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *data = [weakSelf object:state->gpr[3]];
        [data increaseLengthBy:state->gpr[4]]; [weakSelf.copiedBytePointers removeObjectForKey:@(state->gpr[3])];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDataReplaceBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *data = [weakSelf object:state->gpr[3]]; uint32_t length = state->gpr[7];
        NSMutableData *bytes = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:bytes.mutableBytes address:state->gpr[6] length:length]) return NO;
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]);
        if (NSMaxRange(range) > data.length) return NO;
        [data replaceBytesInRange:range withBytes:bytes.bytes length:length];
        [weakSelf.copiedBytePointers removeObjectForKey:@(state->gpr[3])]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDataDeleteBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSMutableData *data = [weakSelf object:state->gpr[3]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]); if (NSMaxRange(range) > data.length) return NO;
        [data replaceBytesInRange:range withBytes:NULL length:0];
        [weakSelf.copiedBytePointers removeObjectForKey:@(state->gpr[3])]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDataFind" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *data = [weakSelf object:state->gpr[3]], *needle = [weakSelf object:state->gpr[6]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]); NSRange found = NSMakeRange(NSNotFound, 0);
        if (needle && NSMaxRange(range) <= data.length)
            found = [data rangeOfData:needle options:(NSDataSearchOptions)state->gpr[7] range:range];
        state->gpr[3] = found.location == NSNotFound ? UINT32_MAX : (uint32_t)found.location;
        state->gpr[4] = (uint32_t)found.length; state->pc = state->lr; return YES;
    }];

    [registry registerSymbol:@"_CFBitVectorGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFBitVectorGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t bitCount = state->gpr[5], byteCount = (bitCount + 7) / 8;
        NSMutableData *bytes = [NSMutableData dataWithLength:byteCount];
        if (byteCount && ![registry.memory readBytes:bytes.mutableBytes address:state->gpr[4] length:byteCount]) return NO;
        CFBitVectorRef vector = CFBitVectorCreate(kCFAllocatorDefault, bytes.bytes, bitCount);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(vector)]); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[4]];
        CFBitVectorRef copy = vector ? CFBitVectorCreateCopy(kCFAllocatorDefault,
            (__bridge CFBitVectorRef)vector) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorCreateMutable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFMutableBitVectorRef vector = CFBitVectorCreateMutable(kCFAllocatorDefault, state->gpr[4]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(vector)]); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[5]];
        CFMutableBitVectorRef copy = vector ? CFBitVectorCreateMutableCopy(kCFAllocatorDefault,
            state->gpr[4], (__bridge CFBitVectorRef)vector) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorGetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        CFFinish(state, vector ? (uint32_t)CFBitVectorGetCount((__bridge CFBitVectorRef)vector) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorGetCountOfBit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        CFFinish(state, vector ? (uint32_t)CFBitVectorGetCountOfBit((__bridge CFBitVectorRef)vector,
            CFRangeMake(state->gpr[4], state->gpr[5]), state->gpr[6]) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorContainsBit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        CFFinish(state, vector && CFBitVectorContainsBit((__bridge CFBitVectorRef)vector,
            CFRangeMake(state->gpr[4], state->gpr[5]), state->gpr[6])); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorGetBitAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        CFFinish(state, vector ? CFBitVectorGetBitAtIndex((__bridge CFBitVectorRef)vector, state->gpr[4]) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorGetBits" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]]; uint32_t byteCount = (state->gpr[5] + 7) / 8;
        NSMutableData *bytes = [NSMutableData dataWithLength:byteCount];
        if (vector && byteCount) CFBitVectorGetBits((__bridge CFBitVectorRef)vector,
            CFRangeMake(state->gpr[4], state->gpr[5]), bytes.mutableBytes);
        if (byteCount && ![registry.memory writeBytes:bytes.bytes address:state->gpr[6] length:byteCount]) return NO;
        CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFBitVectorGetFirstIndexOfBit", @"_CFBitVectorGetLastIndexOfBit"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id vector = [weakSelf object:state->gpr[3]]; CFIndex index = kCFNotFound;
            if (vector) index = [symbol containsString:@"First"]
                ? CFBitVectorGetFirstIndexOfBit((__bridge CFBitVectorRef)vector,
                    CFRangeMake(state->gpr[4], state->gpr[5]), state->gpr[6])
                : CFBitVectorGetLastIndexOfBit((__bridge CFBitVectorRef)vector,
                    CFRangeMake(state->gpr[4], state->gpr[5]), state->gpr[6]);
            CFFinish(state, (uint32_t)index); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBitVectorSetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        if (vector) CFBitVectorSetCount((__bridge CFMutableBitVectorRef)vector, state->gpr[4]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorFlipBitAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        if (vector) CFBitVectorFlipBitAtIndex((__bridge CFMutableBitVectorRef)vector, state->gpr[4]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorFlipBits" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        if (vector) CFBitVectorFlipBits((__bridge CFMutableBitVectorRef)vector,
            CFRangeMake(state->gpr[4], state->gpr[5]));
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorSetBitAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        if (vector) CFBitVectorSetBitAtIndex((__bridge CFMutableBitVectorRef)vector,
            state->gpr[4], state->gpr[5]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorSetBits" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        if (vector) CFBitVectorSetBits((__bridge CFMutableBitVectorRef)vector,
            CFRangeMake(state->gpr[4], state->gpr[5]), state->gpr[6]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBitVectorSetAllBits" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id vector = [weakSelf object:state->gpr[3]];
        if (vector) CFBitVectorSetAllBits((__bridge CFMutableBitVectorRef)vector, state->gpr[4]);
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFNumberGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFNumberGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFNumberCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; int64_t integer = 0; double floating = 0; BOOL isFloat = NO;
        if (![weakSelf readNumberAtAddress:state->gpr[5] type:(CFNumberType)state->gpr[4]
                                  integer:&integer floating:&floating isFloat:&isFloat]) return NO;
        CFFinish(state, [weakSelf handle:isFloat ? @(floating) : @(integer)]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *number = [weakSelf object:state->gpr[3]];
        CFFinish(state, number && [weakSelf writeNumber:number type:(CFNumberType)state->gpr[4]
                                                   address:state->gpr[5]]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberIsFloatType" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *number = [weakSelf object:state->gpr[3]];
        CFFinish(state, number && CFNumberIsFloatType((__bridge CFNumberRef)number)); return YES;
    }];
    [registry registerSymbol:@"_CFNumberGetType" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *number = [weakSelf object:state->gpr[3]];
        CFFinish(state, number ? (uint32_t)CFNumberGetType((__bridge CFNumberRef)number) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFNumberGetByteSize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *number = [weakSelf object:state->gpr[3]];
        CFFinish(state, number ? (uint32_t)CFNumberGetByteSize((__bridge CFNumberRef)number) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFNumberCompare" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSNumber *first = [weakSelf object:state->gpr[3]], *second = [weakSelf object:state->gpr[4]];
        CFFinish(state, (uint32_t)[first compare:second]); return YES;
    }];

    [registry registerSymbol:@"_CFErrorGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFErrorGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFErrorCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *domain = [weakSelf string:state->gpr[4]];
        NSDictionary *userInfo = [weakSelf object:state->gpr[6]];
        CFErrorRef created = domain ? CFErrorCreate(kCFAllocatorDefault, (__bridge CFStringRef)domain,
            (CFIndex)(int32_t)state->gpr[5], (__bridge CFDictionaryRef)userInfo) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(created)]); return YES;
    }];
    [registry registerSymbol:@"_CFErrorCreateWithUserInfoKeysAndValues" handler:^BOOL(BRPPCState *state,
                                                                                     NSError **callError) {
        (void)callError; NSString *domain = [weakSelf string:state->gpr[4]]; uint32_t count = state->gpr[8];
        const void **keys = calloc(MAX((size_t)count, 1u), sizeof(*keys));
        const void **values = calloc(MAX((size_t)count, 1u), sizeof(*values));
        if (!keys || !values) { free(keys); free(values); return NO; }
        BOOL valid = domain != nil;
        for (uint32_t index = 0; valid && index < count; index++) {
            uint32_t keyHandle = 0, valueHandle = 0;
            valid = [registry.memory readUInt32:&keyHandle address:state->gpr[6] + index * 4] &&
                [registry.memory readUInt32:&valueHandle address:state->gpr[7] + index * 4];
            keys[index] = (__bridge const void *)[weakSelf object:keyHandle];
            values[index] = (__bridge const void *)[weakSelf object:valueHandle];
        }
        CFErrorRef created = valid ? CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault,
            (__bridge CFStringRef)domain, (CFIndex)(int32_t)state->gpr[5], keys, values, count) : NULL;
        free(keys); free(values); if (!valid) return NO;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(created)]); return YES;
    }];
    [registry registerSymbol:@"_CFErrorGetDomain" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSError *errorObject = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:errorObject.domain]); return YES;
    }];
    [registry registerSymbol:@"_CFErrorGetCode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSError *errorObject = [weakSelf object:state->gpr[3]];
        CFFinish(state, (uint32_t)errorObject.code); return YES;
    }];
    [registry registerSymbol:@"_CFErrorCopyUserInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSError *errorObject = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:[errorObject.userInfo copy]]); return YES;
    }];
    for (NSString *symbol in @[@"_CFErrorCopyDescription", @"_CFErrorCopyFailureReason",
                                @"_CFErrorCopyRecoverySuggestion"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSError *errorObject = [weakSelf object:state->gpr[3]]; NSString *value;
            if ([symbol hasSuffix:@"Description"]) value = errorObject.localizedDescription;
            else if ([symbol hasSuffix:@"FailureReason"]) value = errorObject.localizedFailureReason;
            else value = errorObject.localizedRecoverySuggestion;
            CFFinish(state, [weakSelf handle:value]); return YES;
        }];
    }

    [registry registerSymbol:@"_CFAttributedStringGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFAttributedStringGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[4]];
        NSDictionary *attributes = [weakSelf object:state->gpr[5]];
        CFAttributedStringRef created = string ? CFAttributedStringCreate(kCFAllocatorDefault,
            (__bridge CFStringRef)string, (__bridge CFDictionaryRef)attributes) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(created)]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringCreateWithSubstring" handler:^BOOL(BRPPCState *state,
                                                                                      NSError **callError) {
        (void)callError; id value = [weakSelf object:state->gpr[4]];
        CFAttributedStringRef created = value ? CFAttributedStringCreateWithSubstring(kCFAllocatorDefault,
            (__bridge CFAttributedStringRef)value, CFRangeMake(state->gpr[5], state->gpr[6])) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(created)]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringCreateCopy" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; id value = [weakSelf object:state->gpr[4]];
        CFAttributedStringRef copy = value ? CFAttributedStringCreateCopy(kCFAllocatorDefault,
            (__bridge CFAttributedStringRef)value) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringCreateMutable" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        (void)callError; CFMutableAttributedStringRef created = CFAttributedStringCreateMutable(
            kCFAllocatorDefault, state->gpr[4]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(created)]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringCreateMutableCopy" handler:^BOOL(BRPPCState *state,
                                                                                    NSError **callError) {
        (void)callError; id value = [weakSelf object:state->gpr[5]];
        CFMutableAttributedStringRef copy = value ? CFAttributedStringCreateMutableCopy(kCFAllocatorDefault,
            state->gpr[4], (__bridge CFAttributedStringRef)value) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringGetString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSAttributedString *value = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:value.string]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringGetLength" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSAttributedString *value = [weakSelf object:state->gpr[3]];
        CFFinish(state, (uint32_t)value.length); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringGetAttributes" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        (void)callError; NSAttributedString *value = [weakSelf object:state->gpr[3]]; NSRange range = NSMakeRange(0, 0);
        NSDictionary *attributes = value && state->gpr[4] < value.length
            ? [value attributesAtIndex:state->gpr[4] effectiveRange:&range] : nil;
        if (state->gpr[5] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[5]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[5] + 4])) return NO;
        CFFinish(state, [weakSelf handle:attributes]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringGetAttribute" handler:^BOOL(BRPPCState *state,
                                                                               NSError **callError) {
        (void)callError; NSAttributedString *value = [weakSelf object:state->gpr[3]];
        NSString *name = [weakSelf string:state->gpr[5]]; NSRange range = NSMakeRange(0, 0);
        id attribute = value && name && state->gpr[4] < value.length
            ? [value attribute:name atIndex:state->gpr[4] effectiveRange:&range] : nil;
        if (state->gpr[6] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[6]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[6] + 4])) return NO;
        CFFinish(state, [weakSelf handle:attribute]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringGetAttributesAndLongestEffectiveRange"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSAttributedString *value = [weakSelf object:state->gpr[3]];
            NSRange limit = NSMakeRange(state->gpr[5], state->gpr[6]), range = NSMakeRange(0, 0);
            NSDictionary *attributes = value && state->gpr[4] < value.length && NSMaxRange(limit) <= value.length
                ? [value attributesAtIndex:state->gpr[4] longestEffectiveRange:&range inRange:limit] : nil;
            if (state->gpr[7] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[7]] ||
                ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[7] + 4])) return NO;
            CFFinish(state, [weakSelf handle:attributes]); return YES;
        }];
    [registry registerSymbol:@"_CFAttributedStringGetAttributeAndLongestEffectiveRange"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSAttributedString *value = [weakSelf object:state->gpr[3]];
            NSString *name = [weakSelf string:state->gpr[5]];
            NSRange limit = NSMakeRange(state->gpr[6], state->gpr[7]), range = NSMakeRange(0, 0);
            id attribute = value && name && state->gpr[4] < value.length && NSMaxRange(limit) <= value.length
                ? [value attribute:name atIndex:state->gpr[4] longestEffectiveRange:&range inRange:limit] : nil;
            if (state->gpr[8] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[8]] ||
                ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[8] + 4])) return NO;
            CFFinish(state, [weakSelf handle:attribute]); return YES;
        }];
    [registry registerSymbol:@"_CFAttributedStringGetMutableString" handler:^BOOL(BRPPCState *state,
                                                                                  NSError **callError) {
        (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:value.mutableString]); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringReplaceString" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
        NSString *replacement = [weakSelf string:state->gpr[6]];
        [value replaceCharactersInRange:NSMakeRange(state->gpr[4], state->gpr[5]) withString:replacement ?: @""];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringSetAttributes" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
        NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]); NSDictionary *attributes = [weakSelf object:state->gpr[6]];
        if (state->gpr[7]) [value setAttributes:attributes range:range];
        else [value addAttributes:attributes ?: @{} range:range];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringSetAttribute" handler:^BOOL(BRPPCState *state,
                                                                               NSError **callError) {
        (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
        NSString *name = [weakSelf string:state->gpr[6]]; id attribute = [weakSelf object:state->gpr[7]];
        if (name && attribute) [value addAttribute:name value:attribute
            range:NSMakeRange(state->gpr[4], state->gpr[5])];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringRemoveAttribute" handler:^BOOL(BRPPCState *state,
                                                                                  NSError **callError) {
        (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
        NSString *name = [weakSelf string:state->gpr[6]];
        if (name) [value removeAttribute:name range:NSMakeRange(state->gpr[4], state->gpr[5])];
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFAttributedStringReplaceAttributedString" handler:^BOOL(BRPPCState *state,
                                                                                          NSError **callError) {
        (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
        NSAttributedString *replacement = [weakSelf object:state->gpr[6]];
        if (replacement) [value replaceCharactersInRange:NSMakeRange(state->gpr[4], state->gpr[5])
                                      withAttributedString:replacement];
        CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFAttributedStringBeginEditing", @"_CFAttributedStringEndEditing"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableAttributedString *value = [weakSelf object:state->gpr[3]];
            if ([symbol containsString:@"Begin"]) [value beginEditing]; else [value endEditing];
            CFFinish(state, 0); return YES;
        }];
    }

    [registry registerSymbol:@"_CFURLGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFURLGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateWithFileSystemPath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *path = [weakSelf string:state->gpr[4]];
        CFURLRef URL = path ? CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
            (__bridge CFStringRef)path, state->gpr[5], state->gpr[6] != 0) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateWithString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[4]]; NSURL *base = [weakSelf object:state->gpr[5]];
        CFFinish(state, [weakSelf handle:string ? [NSURL URLWithString:string relativeToURL:base] : nil]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateFromFileSystemRepresentation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5]; NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
        CFURLRef URL = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, data.bytes,
            length, state->gpr[6] != 0);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyFileSystemPath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]]; CFFinish(state, [weakSelf handle:URL.path]); return YES;
    }];
    [registry registerSymbol:@"_CFURLGetString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]]; CFFinish(state, [weakSelf handle:URL.absoluteString]); return YES;
    }];
    [registry registerSymbol:@"_CFURLGetBaseURL" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] baseURL]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCanBeDecomposed" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]];
        CFFinish(state, URL && CFURLCanBeDecomposed((__bridge CFURLRef)URL)); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyAbsoluteURL" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] absoluteURL]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLGetFileSystemRepresentation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]]; NSData *data = [URL.path dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t capacity = state->gpr[6];
        if (!URL || !capacity || data.length + 1 > capacity) CFFinish(state, 0);
        else { uint8_t zero = 0; BOOL wrote = [registry.memory writeBytes:data.bytes address:state->gpr[5] length:data.length] &&
                [registry.memory writeBytes:&zero address:state->gpr[5] + (uint32_t)data.length length:1]; CFFinish(state, wrote); }
        return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateCopyAppendingPathComponent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[4]]; NSString *component = [weakSelf string:state->gpr[5]];
        CFFinish(state, [weakSelf handle:[URL URLByAppendingPathComponent:component isDirectory:state->gpr[6] != 0]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateCopyDeletingLastPathComponent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] URLByDeletingLastPathComponent]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateCopyAppendingPathExtension" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[4]]; NSString *extension = [weakSelf string:state->gpr[5]];
        CFFinish(state, [weakSelf handle:[URL URLByAppendingPathExtension:extension ?: @""]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateCopyDeletingPathExtension" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] URLByDeletingPathExtension]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyLastPathComponent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] lastPathComponent]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyPathExtension" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] pathExtension]]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateWithBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint32_t length = state->gpr[5]; if (length > (1u << 28)) return NO;
        NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
        CFURLRef URL = CFURLCreateWithBytes(kCFAllocatorDefault, data.bytes, length, state->gpr[6],
            (__bridge CFURLRef)[weakSelf object:state->gpr[7]]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateAbsoluteURLWithBytes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t length = state->gpr[5]; if (length > (1u << 28)) return NO;
            NSMutableData *data = [NSMutableData dataWithLength:length];
            if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
            CFURLRef URL = CFURLCreateAbsoluteURLWithBytes(kCFAllocatorDefault, data.bytes, length,
                state->gpr[6], (__bridge CFURLRef)[weakSelf object:state->gpr[7]], state->gpr[8] != 0);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[4]];
        CFDataRef data = URL ? CFURLCreateData(kCFAllocatorDefault, (__bridge CFURLRef)URL,
            state->gpr[5], state->gpr[6] != 0) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(data)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateWithFileSystemPathRelativeToBase"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *path = [weakSelf string:state->gpr[4]];
            CFURLRef URL = path ? CFURLCreateWithFileSystemPathRelativeToBase(kCFAllocatorDefault,
                (__bridge CFStringRef)path, state->gpr[5], state->gpr[6] != 0,
                (__bridge CFURLRef)[weakSelf object:state->gpr[7]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateFromFileSystemRepresentationRelativeToBase"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t length = state->gpr[5]; if (length > (1u << 28)) return NO;
            NSMutableData *data = [NSMutableData dataWithLength:length];
            if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
            CFURLRef URL = CFURLCreateFromFileSystemRepresentationRelativeToBase(kCFAllocatorDefault,
                data.bytes, length, state->gpr[6] != 0,
                (__bridge CFURLRef)[weakSelf object:state->gpr[7]]);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLGetBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]]; uint32_t capacity = state->gpr[5];
        NSMutableData *data = state->gpr[4] ? [NSMutableData dataWithLength:capacity] : nil;
        CFIndex count = URL ? CFURLGetBytes((__bridge CFURLRef)URL, data.mutableBytes, capacity) : -1;
        if (count >= 0 && state->gpr[4] && count && ![registry.memory writeBytes:data.bytes
            address:state->gpr[4] length:(uint32_t)count]) return NO;
        CFFinish(state, (uint32_t)count); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyScheme" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyScheme((__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyNetLocation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyNetLocation((__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyPath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyPath((__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyStrictPath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]]; Boolean absolute = false;
        CFStringRef value = URL ? CFURLCopyStrictPath((__bridge CFURLRef)URL,
            state->gpr[4] ? &absolute : NULL) : NULL;
        id valueObject = CFBridgingRelease(value);
        if (state->gpr[4] && ![registry.memory writeBytes:&absolute address:state->gpr[4] length:1]) return NO;
        CFFinish(state, [weakSelf handle:valueObject]); return YES;
    }];
    [registry registerSymbol:@"_CFURLHasDirectoryPath" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFFinish(state, URL && CFURLHasDirectoryPath((__bridge CFURLRef)URL)); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyResourceSpecifier"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]];
            CFStringRef value = URL ? CFURLCopyResourceSpecifier((__bridge CFURLRef)URL) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCopyHostName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyHostName((__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLGetPortNumber" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFFinish(state, URL ? (uint32_t)CFURLGetPortNumber((__bridge CFURLRef)URL) : UINT32_MAX); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyUserName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyUserName((__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyPassword" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyPassword((__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyQuery" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:URL.query]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyFragment" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyFragment((__bridge CFURLRef)URL,
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyQueryString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[3]];
        CFStringRef value = URL ? CFURLCopyQueryString((__bridge CFURLRef)URL,
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyParameters" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]]; NSString *string = URL.relativeString;
        NSRange semicolon = [string rangeOfString:@";"]; NSRange end = [string rangeOfCharacterFromSet:
            [NSCharacterSet characterSetWithCharactersInString:@"?#"] options:0
            range:semicolon.location == NSNotFound ? NSMakeRange(string.length, 0) :
                NSMakeRange(semicolon.location + 1, string.length - semicolon.location - 1)];
        NSString *value = semicolon.location == NSNotFound ? nil : [string substringWithRange:NSMakeRange(
            semicolon.location + 1, (end.location == NSNotFound ? string.length : end.location) - semicolon.location - 1)];
        CFFinish(state, [weakSelf handle:value]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCopyParameterString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCState adapted = *state; adapted.pc = [registry addressForSymbol:@"_CFURLCopyParameters"];
        BOOL handled = NO; if (![registry dispatchState:&adapted handled:&handled error:callError] || !handled) return NO;
        *state = adapted; return YES;
    }];
    [registry registerSymbol:@"_CFURLGetByteRangeForComponent"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; CFRange separators = CFRangeMake(0, 0);
            CFRange range = URL ? CFURLGetByteRangeForComponent((__bridge CFURLRef)URL, state->gpr[4],
                state->gpr[5] ? &separators : NULL) : CFRangeMake(kCFNotFound, 0);
            if (state->gpr[5] && (![registry.memory writeUInt32:(uint32_t)separators.location address:state->gpr[5]] ||
                ![registry.memory writeUInt32:(uint32_t)separators.length address:state->gpr[5] + 4])) return NO;
            state->gpr[3] = (uint32_t)range.location; state->gpr[4] = (uint32_t)range.length;
            state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_CFURLCopyResourcePropertyForKey"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; id key = [weakSelf object:state->gpr[4]];
            CFTypeRef property = NULL; CFErrorRef cfError = NULL;
            Boolean result = URL && key && CFURLCopyResourcePropertyForKey((__bridge CFURLRef)URL,
                (__bridge CFStringRef)key, state->gpr[5] ? &property : NULL,
                state->gpr[6] ? &cfError : NULL);
            id propertyObject = CFBridgingRelease(property); id errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:propertyObject address:state->gpr[5]] ||
                ![weakSelf writeGuestObject:errorObject address:state->gpr[6]]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFURLCopyResourcePropertiesForKeys"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; id keys = [weakSelf object:state->gpr[4]];
            CFErrorRef cfError = NULL; CFDictionaryRef properties = URL && keys
                ? CFURLCopyResourcePropertiesForKeys((__bridge CFURLRef)URL, (__bridge CFArrayRef)keys,
                    state->gpr[5] ? &cfError : NULL) : NULL;
            id propertiesObject = CFBridgingRelease(properties), errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[5]]) return NO;
            CFFinish(state, [weakSelf handle:propertiesObject]); return YES;
        }];
    [registry registerSymbol:@"_CFURLSetResourcePropertyForKey"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; id key = [weakSelf object:state->gpr[4]];
            id value = [weakSelf object:state->gpr[5]]; CFErrorRef cfError = NULL;
            Boolean result = URL && key && CFURLSetResourcePropertyForKey((__bridge CFURLRef)URL,
                (__bridge CFStringRef)key, (__bridge CFTypeRef)value, state->gpr[6] ? &cfError : NULL);
            id errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[6]]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFURLSetResourcePropertiesForKeys"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; id values = [weakSelf object:state->gpr[4]];
            CFErrorRef cfError = NULL; Boolean result = URL && values &&
                CFURLSetResourcePropertiesForKeys((__bridge CFURLRef)URL, (__bridge CFDictionaryRef)values,
                    state->gpr[5] ? &cfError : NULL);
            id errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[5]]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFURLClearResourcePropertyCacheForKey"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; id key = [weakSelf object:state->gpr[4]];
            if (URL && key) {
                CFURLClearResourcePropertyCacheForKey((__bridge CFURLRef)URL, (__bridge CFStringRef)key);
            }
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFURLClearResourcePropertyCache"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]];
            if (URL) CFURLClearResourcePropertyCache((__bridge CFURLRef)URL);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFURLSetTemporaryResourcePropertyForKey"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; id key = [weakSelf object:state->gpr[4]];
            id value = [weakSelf object:state->gpr[5]];
            if (URL && key) CFURLSetTemporaryResourcePropertyForKey((__bridge CFURLRef)URL,
                (__bridge CFStringRef)key, (__bridge CFTypeRef)value);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFURLResourceIsReachable"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]]; CFErrorRef cfError = NULL;
            Boolean result = URL && CFURLResourceIsReachable((__bridge CFURLRef)URL,
                state->gpr[4] ? &cfError : NULL); id errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[4]]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFURLIsFileReferenceURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]];
            CFFinish(state, URL && CFURLIsFileReferenceURL((__bridge CFURLRef)URL)); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateFileReferenceURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[4]]; CFErrorRef cfError = NULL;
            CFURLRef result = URL ? CFURLCreateFileReferenceURL(kCFAllocatorDefault, (__bridge CFURLRef)URL,
                state->gpr[5] ? &cfError : NULL) : NULL; id errorObject = CFBridgingRelease(cfError);
            id resultObject = CFBridgingRelease(result);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[5]]) return NO;
            CFFinish(state, [weakSelf handle:resultObject]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateFilePathURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[4]]; CFErrorRef cfError = NULL;
            CFURLRef result = URL ? CFURLCreateFilePathURL(kCFAllocatorDefault, (__bridge CFURLRef)URL,
                state->gpr[5] ? &cfError : NULL) : NULL; id errorObject = CFBridgingRelease(cfError);
            id resultObject = CFBridgingRelease(result);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[5]]) return NO;
            CFFinish(state, [weakSelf handle:resultObject]); return YES;
        }];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [registry registerSymbol:@"_CFURLCreateStringByReplacingPercentEscapes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id string = [weakSelf object:state->gpr[4]];
            CFStringRef result = string ? CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault,
                (__bridge CFStringRef)string, (__bridge CFStringRef)[weakSelf object:state->gpr[5]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateStringByReplacingPercentEscapesUsingEncoding"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id string = [weakSelf object:state->gpr[4]];
            CFStringRef result = string ? CFURLCreateStringByReplacingPercentEscapesUsingEncoding(
                kCFAllocatorDefault, (__bridge CFStringRef)string,
                (__bridge CFStringRef)[weakSelf object:state->gpr[5]], state->gpr[6]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateStringByAddingPercentEscapes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id string = [weakSelf object:state->gpr[4]];
            CFStringRef result = string ? CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                (__bridge CFStringRef)string, (__bridge CFStringRef)[weakSelf object:state->gpr[5]],
                (__bridge CFStringRef)[weakSelf object:state->gpr[6]], state->gpr[7]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
#pragma clang diagnostic pop
    [registry registerSymbol:@"_CFURLCreateBookmarkData" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[4]]; CFErrorRef cfError = NULL;
        CFDataRef result = URL ? CFURLCreateBookmarkData(kCFAllocatorDefault, (__bridge CFURLRef)URL,
            state->gpr[5], (__bridge CFArrayRef)[weakSelf object:state->gpr[6]],
            (__bridge CFURLRef)[weakSelf object:state->gpr[7]], state->gpr[8] ? &cfError : NULL) : NULL;
        id resultObject = CFBridgingRelease(result), errorObject = CFBridgingRelease(cfError);
        if (![weakSelf writeGuestObject:errorObject address:state->gpr[8]]) return NO;
        CFFinish(state, [weakSelf handle:resultObject]); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateByResolvingBookmarkData"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bookmark = [weakSelf object:state->gpr[4]]; Boolean stale = false;
            CFErrorRef cfError = NULL; CFURLRef result = bookmark ? CFURLCreateByResolvingBookmarkData(
                kCFAllocatorDefault, (__bridge CFDataRef)bookmark, state->gpr[5],
                (__bridge CFURLRef)[weakSelf object:state->gpr[6]],
                (__bridge CFArrayRef)[weakSelf object:state->gpr[7]], state->gpr[8] ? &stale : NULL,
                state->gpr[9] ? &cfError : NULL) : NULL;
            id resultObject = CFBridgingRelease(result), errorObject = CFBridgingRelease(cfError);
            if (state->gpr[8] && ![registry.memory writeBytes:&stale address:state->gpr[8] length:1]) return NO;
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[9]]) return NO;
            CFFinish(state, [weakSelf handle:resultObject]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateResourcePropertiesForKeysFromBookmarkData"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id keys = [weakSelf object:state->gpr[4]];
            id bookmark = [weakSelf object:state->gpr[5]]; CFDictionaryRef result = keys && bookmark
                ? CFURLCreateResourcePropertiesForKeysFromBookmarkData(kCFAllocatorDefault,
                    (__bridge CFArrayRef)keys, (__bridge CFDataRef)bookmark) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateResourcePropertyForKeyFromBookmarkData"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id key = [weakSelf object:state->gpr[4]];
            id bookmark = [weakSelf object:state->gpr[5]]; CFTypeRef result = key && bookmark
                ? CFURLCreateResourcePropertyForKeyFromBookmarkData(kCFAllocatorDefault,
                    (__bridge CFStringRef)key, (__bridge CFDataRef)bookmark) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateBookmarkDataFromFile"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[4]]; CFErrorRef cfError = NULL;
            CFDataRef result = URL ? CFURLCreateBookmarkDataFromFile(kCFAllocatorDefault,
                (__bridge CFURLRef)URL, state->gpr[5] ? &cfError : NULL) : NULL;
            id resultObject = CFBridgingRelease(result), errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[5]]) return NO;
            CFFinish(state, [weakSelf handle:resultObject]); return YES;
        }];
    [registry registerSymbol:@"_CFURLWriteBookmarkDataToFile"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bookmark = [weakSelf object:state->gpr[3]];
            id URL = [weakSelf object:state->gpr[4]]; CFErrorRef cfError = NULL;
            Boolean result = bookmark && URL && CFURLWriteBookmarkDataToFile((__bridge CFDataRef)bookmark,
                (__bridge CFURLRef)URL, state->gpr[5], state->gpr[6] ? &cfError : NULL);
            id errorObject = CFBridgingRelease(cfError);
            if (![weakSelf writeGuestObject:errorObject address:state->gpr[6]]) return NO;
            CFFinish(state, result); return YES;
        }];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [registry registerSymbol:@"_CFURLCreateBookmarkDataFromAliasRecord"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id data = [weakSelf object:state->gpr[4]];
            CFDataRef result = data ? CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault,
                (__bridge CFDataRef)data) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
#pragma clang diagnostic pop
    [registry registerSymbol:@"_CFURLStartAccessingSecurityScopedResource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]];
            CFFinish(state, URL && CFURLStartAccessingSecurityScopedResource((__bridge CFURLRef)URL));
            return YES;
        }];
    [registry registerSymbol:@"_CFURLStopAccessingSecurityScopedResource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[3]];
            if (URL) CFURLStopAccessingSecurityScopedResource((__bridge CFURLRef)URL);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFURLCreateFromFSRef" handler:^BOOL(BRPPCState *state,
                                                                       NSError **callError) {
        (void)callError; NSURL *guestURL = registry.guestFSRefDecoder ? registry.guestFSRefDecoder(state->gpr[4]) : nil;
        if (guestURL) { CFFinish(state, [weakSelf handle:guestURL]); return YES; }
        typedef CFURLRef (*CreateFromFSRefFunction)(CFAllocatorRef, const void *);
        CreateFromFSRefFunction function = (CreateFromFSRefFunction)dlsym(RTLD_DEFAULT,
            "CFURLCreateFromFSRef"); uint8_t bytes[80] = {0};
        if (!function || !state->gpr[4] || ![registry.memory readBytes:bytes
            address:state->gpr[4] length:sizeof(bytes)]) { CFFinish(state, 0); return YES; }
        CFFinish(state, [weakSelf handle:CFBridgingRelease(function(kCFAllocatorDefault, bytes))]);
        return YES;
    }];
    [registry registerSymbol:@"_CFURLGetFSRef" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; typedef Boolean (*GetFSRefFunction)(CFURLRef, void *);
        GetFSRefFunction function = (GetFSRefFunction)dlsym(RTLD_DEFAULT, "CFURLGetFSRef");
        id URL = [weakSelf object:state->gpr[3]];
        if ([URL isKindOfClass:NSURL.class] && registry.guestFSRefWriter) {
            CFFinish(state, registry.guestFSRefWriter(URL, state->gpr[4])); return YES;
        }
        uint8_t bytes[80] = {0};
        Boolean result = function && URL && state->gpr[4] && function((__bridge CFURLRef)URL, bytes);
        if (result && ![registry.memory writeBytes:bytes address:state->gpr[4] length:sizeof(bytes)]) return NO;
        CFFinish(state, result); return YES;
    }];

    [registry registerSymbol:@"_CFBundleGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFBundleGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetMainBundle" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFBundleGetMainBundle()]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSURL *URL = [weakSelf object:state->gpr[4]];
        CFBundleRef bundle = URL ? CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(bundle)]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetIdentifier" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFStringRef identifier = bundle
            ? CFBundleGetIdentifier((__bridge CFBundleRef)bundle) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)identifier]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCopyBundleURL" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]];
        CFURLRef URL = bundle ? CFBundleCopyBundleURL((__bridge CFBundleRef)bundle) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetBundleWithIdentifier" handler:^BOOL(BRPPCState *state,
                                                                                 NSError **callError) {
        (void)callError; NSString *identifier = [weakSelf string:state->gpr[3]];
        CFBundleRef bundle = identifier ? CFBundleGetBundleWithIdentifier((__bridge CFStringRef)identifier) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)bundle]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetAllBundles" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFBundleGetAllBundles()]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCreateBundlesFromDirectory"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[4]];
            NSString *type = [weakSelf string:state->gpr[5]];
            CFArrayRef bundles = URL ? CFBundleCreateBundlesFromDirectory(kCFAllocatorDefault,
                (__bridge CFURLRef)URL, (__bridge CFStringRef)type) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(bundles)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleGetValueForInfoDictionaryKey"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]];
            NSString *key = [weakSelf string:state->gpr[4]]; CFTypeRef value = bundle && key
                ? CFBundleGetValueForInfoDictionaryKey((__bridge CFBundleRef)bundle, (__bridge CFStringRef)key)
                : NULL; CFFinish(state, [weakSelf handle:(__bridge id)value]); return YES;
        }];
    for (NSString *symbol in @[@"_CFBundleGetInfoDictionary", @"_CFBundleGetLocalInfoDictionary"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFDictionaryRef dictionary = NULL;
            if (bundle) dictionary = [symbol isEqualToString:@"_CFBundleGetInfoDictionary"]
                ? CFBundleGetInfoDictionary((__bridge CFBundleRef)bundle)
                : CFBundleGetLocalInfoDictionary((__bridge CFBundleRef)bundle);
            CFFinish(state, [weakSelf handle:(__bridge id)dictionary]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBundleGetPackageInfo" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]]; UInt32 type = 0, creator = 0;
        if (bundle) CFBundleGetPackageInfo((__bridge CFBundleRef)bundle,
            state->gpr[4] ? &type : NULL, state->gpr[5] ? &creator : NULL);
        if ((state->gpr[4] && ![registry.memory writeUInt32:type address:state->gpr[4]]) ||
            (state->gpr[5] && ![registry.memory writeUInt32:creator address:state->gpr[5]])) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetVersionNumber" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]];
        CFFinish(state, bundle ? CFBundleGetVersionNumber((__bridge CFBundleRef)bundle) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetDevelopmentRegion" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFStringRef value = bundle
            ? CFBundleGetDevelopmentRegion((__bridge CFBundleRef)bundle) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)value]); return YES;
    }];
    NSDictionary<NSString *, NSNumber *> *bundleDirectoryFunctions = @{
        @"_CFBundleCopySupportFilesDirectoryURL": @0, @"_CFBundleCopyResourcesDirectoryURL": @1,
        @"_CFBundleCopyPrivateFrameworksURL": @2, @"_CFBundleCopySharedFrameworksURL": @3,
        @"_CFBundleCopySharedSupportURL": @4, @"_CFBundleCopyBuiltInPlugInsURL": @5,
        @"_CFBundleCopyExecutableURL": @6
    };
    [bundleDirectoryFunctions enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *operation, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFURLRef URL = NULL;
            if (bundle) switch (operation.unsignedIntegerValue) {
                case 0: URL = CFBundleCopySupportFilesDirectoryURL((__bridge CFBundleRef)bundle); break;
                case 1: URL = CFBundleCopyResourcesDirectoryURL((__bridge CFBundleRef)bundle); break;
                case 2: URL = CFBundleCopyPrivateFrameworksURL((__bridge CFBundleRef)bundle); break;
                case 3: URL = CFBundleCopySharedFrameworksURL((__bridge CFBundleRef)bundle); break;
                case 4: URL = CFBundleCopySharedSupportURL((__bridge CFBundleRef)bundle); break;
                case 5: URL = CFBundleCopyBuiltInPlugInsURL((__bridge CFBundleRef)bundle); break;
                default: URL = CFBundleCopyExecutableURL((__bridge CFBundleRef)bundle); break;
            }
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    }];
    [registry registerSymbol:@"_CFBundleCopyInfoDictionaryInDirectory"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]];
            CFDictionaryRef dictionary = URL ? CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)URL) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(dictionary)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleGetPackageInfoInDirectory"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]]; UInt32 type = 0, creator = 0;
            Boolean valid = URL && CFBundleGetPackageInfoInDirectory((__bridge CFURLRef)URL,
                state->gpr[4] ? &type : NULL, state->gpr[5] ? &creator : NULL);
            if ((state->gpr[4] && ![registry.memory writeUInt32:type address:state->gpr[4]]) ||
                (state->gpr[5] && ![registry.memory writeUInt32:creator address:state->gpr[5]])) return NO;
            CFFinish(state, valid); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyResourceURL" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]];
        NSString *name = [weakSelf string:state->gpr[4]], *extension = [weakSelf string:state->gpr[5]];
        CFURLRef URL = bundle
            ? CFBundleCopyResourceURL((__bridge CFBundleRef)bundle,
                (__bridge CFStringRef)name, (__bridge CFStringRef)extension,
                (__bridge CFStringRef)[weakSelf string:state->gpr[6]]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCopyResourceURLsOfType" handler:^BOOL(BRPPCState *state,
                                                                                 NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFArrayRef URLs = bundle
            ? CFBundleCopyResourceURLsOfType((__bridge CFBundleRef)bundle,
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[5]]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(URLs)]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCopyLocalizedString" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFStringRef value = bundle
            ? CFBundleCopyLocalizedString((__bridge CFBundleRef)bundle,
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[6]]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCopyResourceURLInDirectory"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *directory = [weakSelf object:state->gpr[3]];
            CFURLRef URL = directory ? CFBundleCopyResourceURLInDirectory((__bridge CFURLRef)directory,
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[6]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyResourceURLsOfTypeInDirectory"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *directory = [weakSelf object:state->gpr[3]];
            CFArrayRef URLs = directory ? CFBundleCopyResourceURLsOfTypeInDirectory(
                (__bridge CFURLRef)directory, (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[5]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URLs)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyBundleLocalizations"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFArrayRef values = bundle
                ? CFBundleCopyBundleLocalizations((__bridge CFBundleRef)bundle) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(values)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyPreferredLocalizationsFromArray"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSArray *values = [weakSelf object:state->gpr[3]]; CFArrayRef result = values
                ? CFBundleCopyPreferredLocalizationsFromArray((__bridge CFArrayRef)values) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyLocalizationsForPreferences"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSArray *values = [weakSelf object:state->gpr[3]];
            NSArray *preferences = [weakSelf object:state->gpr[4]]; CFArrayRef result = values
                ? CFBundleCopyLocalizationsForPreferences((__bridge CFArrayRef)values,
                    (__bridge CFArrayRef)preferences) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyResourceURLForLocalization"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFURLRef URL = bundle
                ? CFBundleCopyResourceURLForLocalization((__bridge CFBundleRef)bundle,
                    (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                    (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
                    (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
                    (__bridge CFStringRef)[weakSelf string:state->gpr[7]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyResourceURLsOfTypeForLocalization"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFArrayRef URLs = bundle
                ? CFBundleCopyResourceURLsOfTypeForLocalization((__bridge CFBundleRef)bundle,
                    (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                    (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
                    (__bridge CFStringRef)[weakSelf string:state->gpr[6]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URLs)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyInfoDictionaryForURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]];
            CFDictionaryRef value = URL ? CFBundleCopyInfoDictionaryForURL((__bridge CFURLRef)URL) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyLocalizationsForURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]];
            CFArrayRef value = URL ? CFBundleCopyLocalizationsForURL((__bridge CFURLRef)URL) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyExecutableArchitecturesForURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[3]]; CFArrayRef value = URL
                ? CFBundleCopyExecutableArchitecturesForURL((__bridge CFURLRef)URL) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCopyExecutableArchitectures"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFArrayRef value = bundle
                ? CFBundleCopyExecutableArchitectures((__bridge CFBundleRef)bundle) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    for (NSString *symbol in @[@"_CFBundlePreflightExecutable", @"_CFBundleLoadExecutableAndReturnError"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFErrorRef createdError = NULL;
            Boolean valid = bundle && ([symbol isEqualToString:@"_CFBundlePreflightExecutable"]
                ? CFBundlePreflightExecutable((__bridge CFBundleRef)bundle, &createdError)
                : CFBundleLoadExecutableAndReturnError((__bridge CFBundleRef)bundle, &createdError));
            if (state->gpr[4] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(createdError)]
                                                        address:state->gpr[4]]) return NO;
            CFFinish(state, valid); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBundleLoadExecutable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]];
        CFFinish(state, bundle && CFBundleLoadExecutable((__bridge CFBundleRef)bundle)); return YES;
    }];
    [registry registerSymbol:@"_CFBundleIsExecutableLoaded" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]];
        CFFinish(state, bundle && CFBundleIsExecutableLoaded((__bridge CFBundleRef)bundle)); return YES;
    }];
    [registry registerSymbol:@"_CFBundleUnloadExecutable" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]];
        if (bundle) CFBundleUnloadExecutable((__bridge CFBundleRef)bundle); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBundleGetFunctionPointerForName"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            id bundle = [weakSelf object:state->gpr[3]]; NSString *name = [weakSelf string:state->gpr[4]];
            void *host = bundle && name ? CFBundleGetFunctionPointerForName((__bridge CFBundleRef)bundle,
                (__bridge CFStringRef)name) : NULL; uint32_t address = 0;
            if (host) { NSString *symbol = [name hasPrefix:@"_"] ? name : [@"_" stringByAppendingString:name];
                address = [registry addressForSymbol:symbol lazy:YES error:callError]; if (!address) return NO; }
            CFFinish(state, address); return YES;
        }];
    [registry registerSymbol:@"_CFBundleGetFunctionPointersForNames"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            id bundle = [weakSelf object:state->gpr[3]]; NSArray<NSString *> *names = [weakSelf object:state->gpr[4]];
            if (!bundle || ![names isKindOfClass:[NSArray class]]) return NO;
            for (NSUInteger index = 0; index < names.count; index++) {
                NSString *name = names[index]; void *host = CFBundleGetFunctionPointerForName(
                    (__bridge CFBundleRef)bundle, (__bridge CFStringRef)name); uint32_t address = 0;
                if (host) { NSString *symbol = [name hasPrefix:@"_"] ? name : [@"_" stringByAppendingString:name];
                    address = [registry addressForSymbol:symbol lazy:YES error:callError]; if (!address) return NO; }
                if (![registry.memory writeUInt32:address address:state->gpr[5] + (uint32_t)index * 4]) return NO;
            }
            CFFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_CFBundleGetDataPointerForName", @"_CFBundleGetDataPointersForNames"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            NSArray<NSString *> *names = [symbol hasSuffix:@"sForNames"]
                ? [weakSelf object:state->gpr[4]] : @[[weakSelf string:state->gpr[4]] ?: @""];
            id bundle = [weakSelf object:state->gpr[3]];
            uint32_t output = [symbol hasSuffix:@"sForNames"] ? state->gpr[5] : 0, first = 0;
            for (NSUInteger index = 0; index < names.count; index++) {
                NSString *name = names[index]; NSString *guestSymbol = [name hasPrefix:@"_"]
                    ? name : [@"_" stringByAppendingString:name]; uint32_t address = [registry addressForSymbol:guestSymbol];
                if (!address && bundle) {
                    void *host = CFBundleGetDataPointerForName((__bridge CFBundleRef)bundle,
                        (__bridge CFStringRef)name);
                    id object = host ? (__bridge id)*(void **)host : nil;
                    if (object && ![weakSelf writeDataSymbol:guestSymbol object:object error:callError]) return NO;
                    address = [registry addressForSymbol:guestSymbol];
                }
                if (!index) first = address;
                if (output && ![registry.memory writeUInt32:address address:output + (uint32_t)index * 4]) return NO;
            }
            CFFinish(state, output ? 0 : first); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBundleCopyAuxiliaryExecutableURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bundle = [weakSelf object:state->gpr[3]]; NSString *name = [weakSelf string:state->gpr[4]];
            CFURLRef URL = bundle && name ? CFBundleCopyAuxiliaryExecutableURL((__bridge CFBundleRef)bundle,
                (__bridge CFStringRef)name) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(URL)]); return YES;
        }];
    [registry registerSymbol:@"_CFBundleGetPlugIn" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bundle = [weakSelf object:state->gpr[3]]; CFPlugInRef plugIn = bundle
            ? CFBundleGetPlugIn((__bridge CFBundleRef)bundle) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)plugIn]); return YES;
    }];
    [registry registerSymbol:@"_CFBundleOpenBundleResourceMap"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef int (*OpenResourceMapFunction)(CFBundleRef);
            OpenResourceMapFunction function = (OpenResourceMapFunction)dlsym(RTLD_DEFAULT,
                "CFBundleOpenBundleResourceMap"); id bundle = [weakSelf object:state->gpr[3]];
            int value = function && bundle ? function((__bridge CFBundleRef)bundle) : -1;
            CFFinish(state, (uint32_t)(int32_t)(int16_t)value); return YES;
        }];
    [registry registerSymbol:@"_CFBundleOpenBundleResourceFiles"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef int32_t (*OpenResourceFilesFunction)(CFBundleRef, int *, int *);
            OpenResourceFilesFunction function = (OpenResourceFilesFunction)dlsym(RTLD_DEFAULT,
                "CFBundleOpenBundleResourceFiles"); id bundle = [weakSelf object:state->gpr[3]];
            int first = -1, localized = -1; int32_t status = function && bundle
                ? function((__bridge CFBundleRef)bundle, &first, &localized) : -4;
            uint16_t firstGuest = CFSwapInt16HostToBig((uint16_t)first);
            uint16_t localizedGuest = CFSwapInt16HostToBig((uint16_t)localized);
            if ((state->gpr[4] && ![registry.memory writeBytes:&firstGuest address:state->gpr[4] length:2]) ||
                (state->gpr[5] && ![registry.memory writeBytes:&localizedGuest address:state->gpr[5] length:2]))
                return NO;
            CFFinish(state, (uint32_t)status); return YES;
        }];
    [registry registerSymbol:@"_CFBundleCloseBundleResourceMap"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef void (*CloseResourceMapFunction)(CFBundleRef, int);
            CloseResourceMapFunction function = (CloseResourceMapFunction)dlsym(RTLD_DEFAULT,
                "CFBundleCloseBundleResourceMap"); id bundle = [weakSelf object:state->gpr[3]];
            if (function && bundle) function((__bridge CFBundleRef)bundle, (int16_t)state->gpr[4]);
            CFFinish(state, 0); return YES;
        }];

    [registry registerSymbol:@"_CFLocaleGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFLocaleGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleCopyCurrent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSLocale currentLocale]]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleGetSystem" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSLocale systemLocale]]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *identifier = [weakSelf string:state->gpr[4]];
        CFFinish(state, [weakSelf handle:identifier ? [[NSLocale alloc] initWithLocaleIdentifier:identifier] : nil]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleGetIdentifier" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] localeIdentifier]]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSLocale *locale = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:[locale objectForKey:[weakSelf object:state->gpr[4]]]]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleCopyDisplayNameForPropertyValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSLocale *locale = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf handle:[locale displayNameForKey:[weakSelf object:state->gpr[4]]
                                                            value:[weakSelf object:state->gpr[5]]]]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleCreateCanonicalLocaleIdentifierFromString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *identifier = [weakSelf string:state->gpr[4]];
        CFFinish(state, [weakSelf handle:[NSLocale canonicalLocaleIdentifierFromString:identifier ?: @""]]); return YES;
    }];
    [registry registerSymbol:@"_CFLocaleCreateCanonicalLanguageIdentifierFromString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *identifier = [weakSelf string:state->gpr[4]];
        CFFinish(state, [weakSelf handle:[NSLocale canonicalLanguageIdentifierFromString:identifier ?: @""]]); return YES;
    }];
    for (NSString *symbol in @[@"_CFLocaleCopyAvailableLocaleIdentifiers", @"_CFLocaleCopyISOLanguageCodes",
                                @"_CFLocaleCopyISOCountryCodes", @"_CFLocaleCopyISOCurrencyCodes",
                                @"_CFLocaleCopyCommonISOCurrencyCodes", @"_CFLocaleCopyPreferredLanguages"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFArrayRef result = NULL;
            if ([symbol hasSuffix:@"AvailableLocaleIdentifiers"]) result = CFLocaleCopyAvailableLocaleIdentifiers();
            else if ([symbol hasSuffix:@"ISOLanguageCodes"]) result = CFLocaleCopyISOLanguageCodes();
            else if ([symbol hasSuffix:@"ISOCountryCodes"]) result = CFLocaleCopyISOCountryCodes();
            else if ([symbol hasSuffix:@"CommonISOCurrencyCodes"]) result = CFLocaleCopyCommonISOCurrencyCodes();
            else if ([symbol hasSuffix:@"ISOCurrencyCodes"]) result = CFLocaleCopyISOCurrencyCodes();
            else result = CFLocaleCopyPreferredLanguages();
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFStringRef result = CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes(
                kCFAllocatorDefault, (LangCode)(int16_t)state->gpr[4], (RegionCode)(int16_t)state->gpr[5]);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFStringRef result = CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode(
                kCFAllocatorDefault, state->gpr[4]);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *identifier = [weakSelf string:state->gpr[3]];
            CFFinish(state, identifier ? CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier(
                (__bridge CFStringRef)identifier) : 0); return YES;
        }];
    for (NSString *symbol in @[@"_CFLocaleGetLanguageCharacterDirection", @"_CFLocaleGetLanguageLineDirection"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *language = [weakSelf string:state->gpr[3]]; uint32_t direction = 0;
            if (language) direction = (uint32_t)([symbol containsString:@"Character"]
                ? CFLocaleGetLanguageCharacterDirection((__bridge CFStringRef)language)
                : CFLocaleGetLanguageLineDirection((__bridge CFStringRef)language));
            CFFinish(state, direction); return YES;
        }];
    }
    [registry registerSymbol:@"_CFLocaleCreateComponentsFromLocaleIdentifier"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *identifier = [weakSelf string:state->gpr[4]];
            CFDictionaryRef result = identifier ? CFLocaleCreateComponentsFromLocaleIdentifier(kCFAllocatorDefault,
                (__bridge CFStringRef)identifier) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFLocaleCreateLocaleIdentifierFromComponents"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSDictionary *components = [weakSelf object:state->gpr[4]];
            CFStringRef result = components ? CFLocaleCreateLocaleIdentifierFromComponents(kCFAllocatorDefault,
                (__bridge CFDictionaryRef)components) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    [registry registerSymbol:@"_CFLocaleCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id locale = [weakSelf object:state->gpr[4]];
        CFLocaleRef copy = locale ? CFLocaleCreateCopy(kCFAllocatorDefault, (__bridge CFLocaleRef)locale) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];

    [registry registerSymbol:@"_CFCharacterSetGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFCharacterSetGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetGetPredefined" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:PredefinedCharacterSet(state->gpr[3])]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateMutable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSMutableCharacterSet new]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateWithCharactersInString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *characters = [weakSelf string:state->gpr[4]];
        CFFinish(state, [weakSelf handle:characters ? [NSCharacterSet characterSetWithCharactersInString:characters] : nil]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateWithCharactersInRange" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSCharacterSet characterSetWithRange:
            NSMakeRange(state->gpr[4], state->gpr[5])]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateWithBitmapRepresentation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *data = [weakSelf object:state->gpr[4]];
        CFFinish(state, [weakSelf handle:data ? [NSCharacterSet characterSetWithBitmapRepresentation:data] : nil]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] mutableCopy]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateInvertedSet" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] invertedSet]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetCreateBitmapRepresentation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] bitmapRepresentation]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetIsCharacterMember" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] characterIsMember:(unichar)state->gpr[4]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetIsLongCharacterMember" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] longCharacterIsMember:state->gpr[4]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetIsSupersetOfSet" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] isSupersetOfSet:[weakSelf object:state->gpr[4]]]); return YES;
    }];
    [registry registerSymbol:@"_CFCharacterSetHasMemberInPlane" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] hasMemberInPlane:(uint8_t)state->gpr[4]]); return YES;
    }];
    for (NSString *symbol in @[@"_CFCharacterSetAddCharactersInRange", @"_CFCharacterSetRemoveCharactersInRange"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableCharacterSet *set = [weakSelf object:state->gpr[3]];
            NSRange range = NSMakeRange(state->gpr[4], state->gpr[5]);
            if ([symbol containsString:@"Remove"]) [set removeCharactersInRange:range]; else [set addCharactersInRange:range];
            CFFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFCharacterSetAddCharactersInString", @"_CFCharacterSetRemoveCharactersInString"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableCharacterSet *set = [weakSelf object:state->gpr[3]];
            NSString *characters = [weakSelf string:state->gpr[4]] ?: @"";
            if ([symbol containsString:@"Remove"]) [set removeCharactersInString:characters]; else [set addCharactersInString:characters];
            CFFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFCharacterSetUnion", @"_CFCharacterSetIntersect"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableCharacterSet *set = [weakSelf object:state->gpr[3]]; NSCharacterSet *other = [weakSelf object:state->gpr[4]];
            if ([symbol hasSuffix:@"Union"]) [set formUnionWithCharacterSet:other]; else [set formIntersectionWithCharacterSet:other];
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFCharacterSetInvert" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] invert]; CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFSetGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFSetGetTypeID()); return YES;
    }];
    for (NSString *symbol in @[@"_CFSetCreate", @"_CFSetCreateMutable"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            NSMutableSet *set = [NSMutableSet set];
            if ([symbol isEqualToString:@"_CFSetCreate"]) for (uint32_t i = 0; i < state->gpr[5]; i++) {
                uint32_t value = 0; if (![registry.memory readUInt32:&value address:state->gpr[4] + i * 4]) return NO;
                id object = [weakSelf object:value]; if (object) [set addObject:object];
            }
            CFFinish(state, [weakSelf handle:[symbol isEqualToString:@"_CFSetCreate"] ? [set copy] : set]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFSetCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[4]] copy]]); return YES;
    }];
    [registry registerSymbol:@"_CFSetCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[5]] mutableCopy]]); return YES;
    }];
    [registry registerSymbol:@"_CFSetGetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[[weakSelf object:state->gpr[3]] count]); return YES;
    }];
    [registry registerSymbol:@"_CFSetGetCountOfValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSSet *set = [weakSelf object:state->gpr[3]]; id value = [weakSelf object:state->gpr[4]];
        CFFinish(state, value && [set containsObject:value] ? 1 : 0); return YES;
    }];
    [registry registerSymbol:@"_CFSetContainsValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [[weakSelf object:state->gpr[3]] containsObject:[weakSelf object:state->gpr[4]]]); return YES;
    }];
    [registry registerSymbol:@"_CFSetGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSSet *set = [weakSelf object:state->gpr[3]]; id candidate = [weakSelf object:state->gpr[4]];
        id value = [set member:candidate]; CFFinish(state, [weakSelf handle:value]); return YES;
    }];
    [registry registerSymbol:@"_CFSetGetValueIfPresent" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; NSSet *set = [weakSelf object:state->gpr[3]];
        id value = [set member:[weakSelf object:state->gpr[4]]];
        if (value && state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:value]
                                                            address:state->gpr[5]]) return NO;
        CFFinish(state, value != nil); return YES;
    }];
    [registry registerSymbol:@"_CFSetGetValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSArray *values = [[weakSelf object:state->gpr[3]] allObjects];
        for (NSUInteger i = 0; i < values.count; i++)
            if (![registry.memory writeUInt32:[weakSelf handle:values[i]]
                                       address:state->gpr[4] + (uint32_t)i * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFSetAddValue", @"_CFSetSetValue", @"_CFSetReplaceValue", @"_CFSetRemoveValue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableSet *set = [weakSelf object:state->gpr[3]]; id value = [weakSelf object:state->gpr[4]];
            if ([symbol hasSuffix:@"RemoveValue"]) [set removeObject:value];
            else if (value && (![symbol hasSuffix:@"ReplaceValue"] || [set containsObject:value])) {
                [set removeObject:value]; [set addObject:value];
            }
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFSetRemoveAllValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; [[weakSelf object:state->gpr[3]] removeAllObjects]; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFSetApplyFunction" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSSet *set = [weakSelf object:state->gpr[3]]; uint32_t function = state->gpr[4];
        if (!function) return NO; BRPPCState outer = *state;
        for (id value in set)
            if (![weakSelf invokeGuestFunction:function outerState:outer
                arguments:@[@([weakSelf handle:value]), @(state->gpr[5])]
                result:NULL label:@"CFSet applier" error:callError]) return NO;
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFBagGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFBagGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFBagCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t count = state->gpr[5], callbacks = state->gpr[6];
        const CFBagCallBacks *hostCallbacks = NULL;
        if (callbacks == [registry addressForSymbol:@"_kCFTypeBagCallBacks"]) hostCallbacks = &kCFTypeBagCallBacks;
        else if (callbacks == [registry addressForSymbol:@"_kCFCopyStringBagCallBacks"])
            hostCallbacks = &kCFCopyStringBagCallBacks;
        else if (callbacks) return NO;
        const void **values = calloc(MAX((size_t)count, 1u), sizeof(*values));
        if (!values) return NO;
        BOOL valid = YES;
        for (uint32_t index = 0; index < count; index++) {
            uint32_t handle = 0;
            if (![registry.memory readUInt32:&handle address:state->gpr[4] + index * 4]) { valid = NO; break; }
            values[index] = (__bridge const void *)[weakSelf object:handle];
        }
        CFBagRef bag = valid ? CFBagCreate(kCFAllocatorDefault, values, count, hostCallbacks) : NULL;
        free(values);
        if (!valid) return NO;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(bag)]); return YES;
    }];
    [registry registerSymbol:@"_CFBagCreateMutable" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        uint32_t callbacks = state->gpr[5]; const CFBagCallBacks *hostCallbacks = NULL;
        if (callbacks == [registry addressForSymbol:@"_kCFTypeBagCallBacks"]) hostCallbacks = &kCFTypeBagCallBacks;
        else if (callbacks == [registry addressForSymbol:@"_kCFCopyStringBagCallBacks"])
            hostCallbacks = &kCFCopyStringBagCallBacks;
        else if (callbacks) return NO;
        CFMutableBagRef bag = CFBagCreateMutable(kCFAllocatorDefault, (CFIndex)state->gpr[4], hostCallbacks);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(bag)]); return YES;
    }];
    [registry registerSymbol:@"_CFBagCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[4]];
        CFBagRef copy = bag ? CFBagCreateCopy(kCFAllocatorDefault, (__bridge CFBagRef)bag) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFBagCreateMutableCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[5]];
        CFMutableBagRef copy = bag ? CFBagCreateMutableCopy(kCFAllocatorDefault,
            (CFIndex)state->gpr[4], (__bridge CFBagRef)bag) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFBagGetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]];
        CFFinish(state, bag ? (uint32_t)CFBagGetCount((__bridge CFBagRef)bag) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFBagGetCountOfValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]], value = [weakSelf object:state->gpr[4]];
        CFFinish(state, bag ? (uint32_t)CFBagGetCountOfValue((__bridge CFBagRef)bag,
            (__bridge const void *)value) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFBagContainsValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]], value = [weakSelf object:state->gpr[4]];
        CFFinish(state, bag && CFBagContainsValue((__bridge CFBagRef)bag,
            (__bridge const void *)value)); return YES;
    }];
    [registry registerSymbol:@"_CFBagGetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]], candidate = [weakSelf object:state->gpr[4]];
        const void *value = bag ? CFBagGetValue((__bridge CFBagRef)bag,
            (__bridge const void *)candidate) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)value]); return YES;
    }];
    [registry registerSymbol:@"_CFBagGetValueIfPresent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]], candidate = [weakSelf object:state->gpr[4]];
        const void *value = NULL;
        BOOL present = bag && CFBagGetValueIfPresent((__bridge CFBagRef)bag,
            (__bridge const void *)candidate, &value);
        if (present && state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:(__bridge id)value]
                                                             address:state->gpr[5]]) return NO;
        CFFinish(state, present); return YES;
    }];
    [registry registerSymbol:@"_CFBagGetValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]];
        CFIndex count = bag ? CFBagGetCount((__bridge CFBagRef)bag) : 0;
        const void **values = calloc(MAX((size_t)count, 1u), sizeof(*values));
        if (!values) return NO;
        if (count) CFBagGetValues((__bridge CFBagRef)bag, values);
        BOOL valid = YES;
        for (CFIndex index = 0; index < count; index++)
            if (![registry.memory writeUInt32:[weakSelf handle:(__bridge id)values[index]]
                                      address:state->gpr[4] + (uint32_t)index * 4]) { valid = NO; break; }
        free(values); if (!valid) return NO; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBagApplyFunction" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id bag = [weakSelf object:state->gpr[3]]; uint32_t function = state->gpr[4];
        if (!bag || !function) return NO;
        CFIndex count = CFBagGetCount((__bridge CFBagRef)bag);
        const void **values = calloc(MAX((size_t)count, 1u), sizeof(*values));
        if (!values) return NO; if (count) CFBagGetValues((__bridge CFBagRef)bag, values);
        BRPPCState outer = *state; BOOL valid = YES;
        for (CFIndex index = 0; index < count; index++)
            if (![weakSelf invokeGuestFunction:function outerState:outer
                arguments:@[@([weakSelf handle:(__bridge id)values[index]]), @(state->gpr[5])]
                result:NULL label:@"CFBag applier" error:callError]) { valid = NO; break; }
        free(values); if (!valid) return NO; CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFBagAddValue", @"_CFBagReplaceValue", @"_CFBagSetValue",
                                @"_CFBagRemoveValue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id bag = [weakSelf object:state->gpr[3]], value = [weakSelf object:state->gpr[4]];
            if (bag) {
                if ([symbol hasSuffix:@"AddValue"])
                    CFBagAddValue((__bridge CFMutableBagRef)bag, (__bridge const void *)value);
                else if ([symbol hasSuffix:@"ReplaceValue"])
                    CFBagReplaceValue((__bridge CFMutableBagRef)bag, (__bridge const void *)value);
                else if ([symbol hasSuffix:@"SetValue"])
                    CFBagSetValue((__bridge CFMutableBagRef)bag, (__bridge const void *)value);
                else CFBagRemoveValue((__bridge CFMutableBagRef)bag, (__bridge const void *)value);
            }
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBagRemoveAllValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id bag = [weakSelf object:state->gpr[3]];
        if (bag) CFBagRemoveAllValues((__bridge CFMutableBagRef)bag); CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFBinaryHeapGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFBinaryHeapGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCGuestHeapRecord *record = [BRPPCGuestHeapRecord new]; record.resolver = weakSelf; record.outerState = *state;
        uint32_t callbacksAddress = state->gpr[5], contextAddress = state->gpr[6];
        if (callbacksAddress == [registry addressForSymbol:@"_kCFStringBinaryHeapCallBacks"])
            record.stringCallbacks = YES;
        else if (callbacksAddress) {
            uint32_t fields[5];
            for (NSUInteger index = 0; index < 5; index++)
                if (![registry.memory readUInt32:&fields[index]
                    address:callbacksAddress + (uint32_t)index * 4]) return NO;
            if (fields[0] != 0) return NO;
            record.valueRetain = fields[1]; record.valueRelease = fields[2];
            record.valueDescription = fields[3]; record.comparator = fields[4];
        }
        if (contextAddress) {
            uint32_t fields[5];
            for (NSUInteger index = 0; index < 5; index++)
                if (![registry.memory readUInt32:&fields[index]
                    address:contextAddress + (uint32_t)index * 4]) return NO;
            if (fields[0] != 0) return NO;
            record.contextInfo = fields[1]; record.contextRetain = fields[2];
            record.contextRelease = fields[3]; record.contextDescription = fields[4];
        }
        CFBinaryHeapCallBacks callbacks = {0, RetainHeapValue, ReleaseHeapValue,
            CopyHeapValueDescription, CompareHeapValues};
        CFBinaryHeapCompareContext context = {0, (__bridge void *)record, RetainHeapContext,
            ReleaseHeapContext, CopyHeapContextDescription};
        weakSelf.pendingCallbackError = nil;
        CFBinaryHeapRef heap = CFBinaryHeapCreate(kCFAllocatorDefault, state->gpr[4], &callbacks, &context);
        if (weakSelf.pendingCallbackError) {
            if (heap) CFRelease(heap); if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        id heapObject = CFBridgingRelease(heap); uint32_t handle = [weakSelf handle:heapObject];
        if (handle) weakSelf.heapRecords[@(handle)] = record; CFFinish(state, handle); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapCreateCopy" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id heap = [weakSelf object:state->gpr[5]]; BRPPCGuestHeapRecord *record = weakSelf.heapRecords[@(state->gpr[5])];
        weakSelf.pendingCallbackError = nil;
        CFBinaryHeapRef copy = heap ? CFBinaryHeapCreateCopy(kCFAllocatorDefault, state->gpr[4],
            (__bridge CFBinaryHeapRef)heap) : NULL;
        if (weakSelf.pendingCallbackError) {
            if (copy) CFRelease(copy); if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        id copyObject = CFBridgingRelease(copy); uint32_t handle = [weakSelf handle:copyObject];
        if (handle && record) weakSelf.heapRecords[@(handle)] = record; CFFinish(state, handle); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapGetCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id heap = [weakSelf object:state->gpr[3]];
        CFFinish(state, heap ? (uint32_t)CFBinaryHeapGetCount((__bridge CFBinaryHeapRef)heap) : 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFBinaryHeapGetCountOfValue", @"_CFBinaryHeapContainsValue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            id heap = [weakSelf object:state->gpr[3]]; BRPPCGuestHeapRecord *record = weakSelf.heapRecords[@(state->gpr[3])];
            if (!heap || !record) { CFFinish(state, 0); return YES; }
            BRPPCGuestHeapValue *candidate = [BRPPCGuestHeapValue new]; candidate.record = record;
            candidate.guestValue = state->gpr[4]; weakSelf.pendingCallbackError = nil;
            uint32_t result = [symbol containsString:@"Count"]
                ? (uint32_t)CFBinaryHeapGetCountOfValue((__bridge CFBinaryHeapRef)heap,
                    (__bridge const void *)candidate)
                : (uint32_t)CFBinaryHeapContainsValue((__bridge CFBinaryHeapRef)heap,
                    (__bridge const void *)candidate);
            if (weakSelf.pendingCallbackError) {
                if (callError) *callError = weakSelf.pendingCallbackError; return NO;
            }
            CFFinish(state, result); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBinaryHeapGetMinimum" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id heap = [weakSelf object:state->gpr[3]];
        const void *pointer = heap ? CFBinaryHeapGetMinimum((__bridge CFBinaryHeapRef)heap) : NULL;
        BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)pointer;
        CFFinish(state, value.guestValue); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapGetMinimumIfPresent" handler:^BOOL(BRPPCState *state,
                                                                               NSError **callError) {
        (void)callError; id heap = [weakSelf object:state->gpr[3]]; const void *pointer = NULL;
        BOOL present = heap && CFBinaryHeapGetMinimumIfPresent((__bridge CFBinaryHeapRef)heap, &pointer);
        BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)pointer;
        if (present && state->gpr[4] && ![registry.memory writeUInt32:value.guestValue address:state->gpr[4]]) return NO;
        CFFinish(state, present); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapGetValues" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id heap = [weakSelf object:state->gpr[3]];
        CFIndex count = heap ? CFBinaryHeapGetCount((__bridge CFBinaryHeapRef)heap) : 0;
        const void **values = calloc(MAX((size_t)count, 1u), sizeof(*values)); if (!values) return NO;
        if (count) CFBinaryHeapGetValues((__bridge CFBinaryHeapRef)heap, values); BOOL valid = YES;
        for (CFIndex index = 0; index < count; index++) {
            BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)values[index];
            if (![registry.memory writeUInt32:value.guestValue
                                      address:state->gpr[4] + (uint32_t)index * 4]) { valid = NO; break; }
        }
        free(values); if (!valid) return NO; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapApplyFunction" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id heap = [weakSelf object:state->gpr[3]]; uint32_t function = state->gpr[4];
        if (!heap || !function) return NO; CFIndex count = CFBinaryHeapGetCount((__bridge CFBinaryHeapRef)heap);
        const void **values = calloc(MAX((size_t)count, 1u), sizeof(*values)); if (!values) return NO;
        if (count) CFBinaryHeapGetValues((__bridge CFBinaryHeapRef)heap, values);
        BRPPCState outer = *state; BOOL valid = YES;
        for (CFIndex index = 0; index < count; index++) {
            BRPPCGuestHeapValue *value = (__bridge BRPPCGuestHeapValue *)values[index];
            if (![weakSelf invokeGuestFunction:function outerState:outer
                arguments:@[@(value.guestValue), @(state->gpr[5])] result:NULL
                label:@"CFBinaryHeap applier" error:callError]) { valid = NO; break; }
        }
        free(values); if (!valid) return NO; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapAddValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id heap = [weakSelf object:state->gpr[3]]; BRPPCGuestHeapRecord *record = weakSelf.heapRecords[@(state->gpr[3])];
        if (!heap || !record) return NO; BRPPCGuestHeapValue *value = [BRPPCGuestHeapValue new];
        value.record = record; value.guestValue = state->gpr[4]; weakSelf.pendingCallbackError = nil;
        CFBinaryHeapAddValue((__bridge CFBinaryHeapRef)heap, (__bridge const void *)value);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapRemoveMinimumValue" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        id heap = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
        if (heap) CFBinaryHeapRemoveMinimumValue((__bridge CFBinaryHeapRef)heap);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFBinaryHeapRemoveAllValues" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        id heap = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
        if (heap) CFBinaryHeapRemoveAllValues((__bridge CFBinaryHeapRef)heap);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFTreeGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFTreeGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFTreeCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCGuestTreeRecord *record = [BRPPCGuestTreeRecord new]; record.resolver = weakSelf;
        record.outerState = *state; uint32_t contextAddress = state->gpr[4];
        uint32_t version = 0, info = 0, retainFunction = 0, releaseFunction = 0, descriptionFunction = 0;
        if (!contextAddress || ![registry.memory readUInt32:&version address:contextAddress] || version != 0 ||
            ![registry.memory readUInt32:&info address:contextAddress + 4] ||
            ![registry.memory readUInt32:&retainFunction address:contextAddress + 8] ||
            ![registry.memory readUInt32:&releaseFunction address:contextAddress + 12] ||
            ![registry.memory readUInt32:&descriptionFunction address:contextAddress + 16]) return NO;
        record.info = info; record.retainFunction = retainFunction; record.releaseFunction = releaseFunction;
        record.descriptionFunction = descriptionFunction;
        CFTreeContext context = {0, (__bridge void *)record, RetainTreeContext,
            ReleaseTreeContext, CopyTreeContextDescription};
        weakSelf.pendingCallbackError = nil;
        CFTreeRef tree = CFTreeCreate(kCFAllocatorDefault, &context);
        if (weakSelf.pendingCallbackError) {
            if (tree) CFRelease(tree); if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        uint32_t handle = [weakSelf handle:CFBridgingRelease(tree)];
        if (handle) weakSelf.treeRecords[@(handle)] = record; CFFinish(state, handle); return YES;
    }];
    NSDictionary<NSString *, NSNumber *> *treeRelations = @{
        @"_CFTreeGetParent": @0, @"_CFTreeGetNextSibling": @1, @"_CFTreeGetFirstChild": @2,
        @"_CFTreeFindRoot": @3
    };
    [treeRelations enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *operation, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tree = [weakSelf object:state->gpr[3]]; CFTreeRef result = NULL;
            if (tree) switch (operation.unsignedIntegerValue) {
                case 0: result = CFTreeGetParent((__bridge CFTreeRef)tree); break;
                case 1: result = CFTreeGetNextSibling((__bridge CFTreeRef)tree); break;
                case 2: result = CFTreeGetFirstChild((__bridge CFTreeRef)tree); break;
                default: result = CFTreeFindRoot((__bridge CFTreeRef)tree); break;
            }
            CFFinish(state, [weakSelf handle:(__bridge id)result]); return YES;
        }];
    }];
    [registry registerSymbol:@"_CFTreeGetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestTreeRecord *record = weakSelf.treeRecords[@(state->gpr[3])];
        uint32_t address = state->gpr[4]; if (!record || !address) return NO;
        if (![registry.memory writeUInt32:0 address:address] ||
            ![registry.memory writeUInt32:record.info address:address + 4] ||
            ![registry.memory writeUInt32:record.retainFunction address:address + 8] ||
            ![registry.memory writeUInt32:record.releaseFunction address:address + 12] ||
            ![registry.memory writeUInt32:record.descriptionFunction address:address + 16]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTreeGetChildCount" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id tree = [weakSelf object:state->gpr[3]];
        CFFinish(state, tree ? (uint32_t)CFTreeGetChildCount((__bridge CFTreeRef)tree) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFTreeGetChildAtIndex" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id tree = [weakSelf object:state->gpr[3]]; CFTreeRef child = tree
            ? CFTreeGetChildAtIndex((__bridge CFTreeRef)tree, (CFIndex)(int32_t)state->gpr[4]) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)child]); return YES;
    }];
    [registry registerSymbol:@"_CFTreeGetChildren" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id tree = [weakSelf object:state->gpr[3]];
        CFIndex count = tree ? CFTreeGetChildCount((__bridge CFTreeRef)tree) : 0;
        CFTreeRef *children = calloc(MAX((size_t)count, 1u), sizeof(*children)); if (!children) return NO;
        if (count) CFTreeGetChildren((__bridge CFTreeRef)tree, children); BOOL valid = YES;
        for (CFIndex index = 0; index < count; index++)
            if (![registry.memory writeUInt32:[weakSelf handle:(__bridge id)children[index]]
                                      address:state->gpr[4] + (uint32_t)index * 4]) { valid = NO; break; }
        free(children); if (!valid) return NO; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTreeApplyFunctionToChildren" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        id tree = [weakSelf object:state->gpr[3]]; uint32_t function = state->gpr[4];
        if (!tree || !function) return NO; CFIndex count = CFTreeGetChildCount((__bridge CFTreeRef)tree);
        CFTreeRef *children = calloc(MAX((size_t)count, 1u), sizeof(*children)); if (!children) return NO;
        if (count) CFTreeGetChildren((__bridge CFTreeRef)tree, children); BRPPCState outer = *state; BOOL valid = YES;
        for (CFIndex index = 0; index < count; index++)
            if (![weakSelf invokeGuestFunction:function outerState:outer
                arguments:@[@([weakSelf handle:(__bridge id)children[index]]), @(state->gpr[5])]
                result:NULL label:@"CFTree child applier" error:callError]) { valid = NO; break; }
        free(children); if (!valid) return NO; CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTreeSetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id tree = [weakSelf object:state->gpr[3]]; uint32_t address = state->gpr[4], version = 0;
        uint32_t info = 0, retainFunction = 0, releaseFunction = 0, descriptionFunction = 0;
        BRPPCGuestTreeRecord *record = [BRPPCGuestTreeRecord new]; record.resolver = weakSelf;
        record.outerState = *state;
        if (!tree || !address || ![registry.memory readUInt32:&version address:address] || version != 0 ||
            ![registry.memory readUInt32:&info address:address + 4] ||
            ![registry.memory readUInt32:&retainFunction address:address + 8] ||
            ![registry.memory readUInt32:&releaseFunction address:address + 12] ||
            ![registry.memory readUInt32:&descriptionFunction address:address + 16]) return NO;
        record.info = info; record.retainFunction = retainFunction; record.releaseFunction = releaseFunction;
        record.descriptionFunction = descriptionFunction;
        CFTreeContext context = {0, (__bridge void *)record, RetainTreeContext,
            ReleaseTreeContext, CopyTreeContextDescription}; weakSelf.pendingCallbackError = nil;
        CFTreeSetContext((__bridge CFTreeRef)tree, &context);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        weakSelf.treeRecords[@(state->gpr[3])] = record; CFFinish(state, 0); return YES;
    }];
    NSDictionary<NSString *, NSNumber *> *treeMutations = @{
        @"_CFTreePrependChild": @0, @"_CFTreeAppendChild": @1, @"_CFTreeInsertSibling": @2
    };
    [treeMutations enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSNumber *operation, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tree = [weakSelf object:state->gpr[3]], child = [weakSelf object:state->gpr[4]];
            if (!tree || !child) return NO;
            switch (operation.unsignedIntegerValue) {
                case 0: CFTreePrependChild((__bridge CFTreeRef)tree, (__bridge CFTreeRef)child); break;
                case 1: CFTreeAppendChild((__bridge CFTreeRef)tree, (__bridge CFTreeRef)child); break;
                default: CFTreeInsertSibling((__bridge CFTreeRef)tree, (__bridge CFTreeRef)child); break;
            }
            CFFinish(state, 0); return YES;
        }];
    }];
    [registry registerSymbol:@"_CFTreeRemove" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id tree = [weakSelf object:state->gpr[3]];
        if (tree) CFTreeRemove((__bridge CFTreeRef)tree); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTreeRemoveAllChildren" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id tree = [weakSelf object:state->gpr[3]];
        if (tree) CFTreeRemoveAllChildren((__bridge CFTreeRef)tree); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTreeSortChildren" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id tree = [weakSelf object:state->gpr[3]]; if (!tree || !state->gpr[4]) return NO;
        BRPPCGuestTreeComparatorContext context = {weakSelf, *state, state->gpr[4], state->gpr[5]};
        weakSelf.pendingCallbackError = nil;
        CFTreeSortChildren((__bridge CFTreeRef)tree, CompareTreeChildren, &context);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFNotificationCenterGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFNotificationCenterGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFNotificationCenterGetLocalCenter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFNotificationCenterGetLocalCenter()]); return YES;
    }];
    [registry registerSymbol:@"_CFNotificationCenterGetDarwinNotifyCenter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFNotificationCenterGetDarwinNotifyCenter()]); return YES;
    }];
    [registry registerSymbol:@"_CFNotificationCenterGetDistributedCenter" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFNotificationCenterGetDistributedCenter()]); return YES;
    }];
    [registry registerSymbol:@"_CFNotificationCenterAddObserver" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        id center = [weakSelf object:state->gpr[3]];
        NSString *name = [weakSelf string:state->gpr[6]];
        id object = [weakSelf object:state->gpr[7]];
        if (!center || !state->gpr[5]) return NO;
        BRPPCGuestNotificationRecord *record = [BRPPCGuestNotificationRecord new];
        record.resolver = weakSelf; record.outerState = *state; record.center = center;
        record.observer = state->gpr[4]; record.callback = state->gpr[5];
        record.name = name; record.object = object;
        [weakSelf.notificationRecords addObject:record];
        CFNotificationCenterAddObserver((__bridge CFNotificationCenterRef)center,
            (__bridge const void *)record, DeliverNotification, (__bridge CFStringRef)name,
            (__bridge const void *)object, (CFNotificationSuspensionBehavior)state->gpr[8]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFNotificationCenterRemoveObserver" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        id center = [weakSelf object:state->gpr[3]];
        uint32_t observer = state->gpr[4]; NSString *name = [weakSelf string:state->gpr[5]];
        id object = [weakSelf object:state->gpr[6]];
        for (NSInteger index = (NSInteger)weakSelf.notificationRecords.count - 1; index >= 0; index--) {
            BRPPCGuestNotificationRecord *record = weakSelf.notificationRecords[(NSUInteger)index];
            if (record.center != center || record.observer != observer ||
                (name && ![record.name isEqual:name]) || (object && record.object != object)) continue;
            CFNotificationCenterRemoveObserver((__bridge CFNotificationCenterRef)center,
                (__bridge const void *)record, (__bridge CFStringRef)name, (__bridge const void *)object);
            [weakSelf.notificationRecords removeObjectAtIndex:(NSUInteger)index];
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFNotificationCenterRemoveEveryObserver" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError;
        id center = [weakSelf object:state->gpr[3]]; uint32_t observer = state->gpr[4];
        for (NSInteger index = (NSInteger)weakSelf.notificationRecords.count - 1; index >= 0; index--) {
            BRPPCGuestNotificationRecord *record = weakSelf.notificationRecords[(NSUInteger)index];
            if (record.center != center || record.observer != observer) continue;
            CFNotificationCenterRemoveEveryObserver((__bridge CFNotificationCenterRef)center,
                (__bridge const void *)record);
            [weakSelf.notificationRecords removeObjectAtIndex:(NSUInteger)index];
        }
        CFFinish(state, 0); return YES;
    }];
    BRPPCResolvedCall postNotification = ^BOOL(BRPPCState *state, NSError **callError) {
        id center = [weakSelf object:state->gpr[3]]; NSString *name = [weakSelf string:state->gpr[4]];
        id object = [weakSelf object:state->gpr[5]]; NSDictionary *userInfo = [weakSelf object:state->gpr[6]];
        if (!center || !name) return NO;
        weakSelf.pendingCallbackError = nil;
        if (state->pc == [weakSelf.registry addressForSymbol:@"_CFNotificationCenterPostNotificationWithOptions"])
            CFNotificationCenterPostNotificationWithOptions((__bridge CFNotificationCenterRef)center,
                (__bridge CFStringRef)name, (__bridge const void *)object,
                (__bridge CFDictionaryRef)userInfo, state->gpr[7]);
        else CFNotificationCenterPostNotification((__bridge CFNotificationCenterRef)center,
                (__bridge CFStringRef)name, (__bridge const void *)object,
                (__bridge CFDictionaryRef)userInfo, state->gpr[7] != 0);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError;
            return NO;
        }
        CFFinish(state, 0); return YES;
    };
    [registry registerSymbol:@"_CFNotificationCenterPostNotification" handler:postNotification];
    [registry registerSymbol:@"_CFNotificationCenterPostNotificationWithOptions" handler:postNotification];

    [registry registerSymbol:@"_CFPlugInGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFPlugInGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFPlugInCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id URL = [weakSelf object:state->gpr[4]];
        CFPlugInRef plugIn = URL ? CFPlugInCreate(kCFAllocatorDefault, (__bridge CFURLRef)URL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(plugIn)]); return YES;
    }];
    [registry registerSymbol:@"_CFPlugInGetBundle" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id plugIn = [weakSelf object:state->gpr[3]]; CFBundleRef bundle = plugIn
            ? CFPlugInGetBundle((__bridge CFPlugInRef)plugIn) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)bundle]); return YES;
    }];
    [registry registerSymbol:@"_CFPlugInSetLoadOnDemand"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id plugIn = [weakSelf object:state->gpr[3]];
            if (plugIn) CFPlugInSetLoadOnDemand((__bridge CFPlugInRef)plugIn, state->gpr[4] != 0);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInIsLoadOnDemand"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id plugIn = [weakSelf object:state->gpr[3]];
            CFFinish(state, plugIn && CFPlugInIsLoadOnDemand((__bridge CFPlugInRef)plugIn)); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInRegisterFactoryFunction"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id factory = [weakSelf object:state->gpr[3]];
            NSData *factoryKey = [weakSelf plugInUUIDKey:factory];
            if (!factoryKey || !state->gpr[4] || weakSelf.plugInFactories[factoryKey]) {
                CFFinish(state, 0); return YES;
            }
            BRPPCGuestPlugInFactoryRecord *record = [BRPPCGuestPlugInFactoryRecord new];
            record.outerState = *state; record.function = state->gpr[4]; record.factoryUUID = factory;
            record.types = [NSMutableSet set]; weakSelf.plugInFactories[factoryKey] = record;
            CFFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInRegisterFactoryFunctionByName"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            id factory = [weakSelf object:state->gpr[3]]; id plugIn = [weakSelf object:state->gpr[4]];
            NSData *factoryKey = [weakSelf plugInUUIDKey:factory];
            NSString *name = [weakSelf string:state->gpr[5]]; uint32_t function = name
                ? [registry addressForSymbol:[@"_" stringByAppendingString:name] lazy:NO error:callError] : 0;
            if (!function && name) function = [registry addressForSymbol:name lazy:NO error:callError];
            if (!factoryKey || !function || weakSelf.plugInFactories[factoryKey]) { CFFinish(state, 0); return YES; }
            BRPPCGuestPlugInFactoryRecord *record = [BRPPCGuestPlugInFactoryRecord new];
            record.outerState = *state; record.function = function; record.factoryUUID = factory;
            record.plugIn = plugIn; record.types = [NSMutableSet set];
            weakSelf.plugInFactories[factoryKey] = record;
            CFFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInUnregisterFactory"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *factoryKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[3]]];
            BRPPCGuestPlugInFactoryRecord *record = factoryKey ? weakSelf.plugInFactories[factoryKey] : nil;
            if (!record || record.instanceCount) { CFFinish(state, 0); return YES; }
            [weakSelf.plugInFactories removeObjectForKey:factoryKey]; CFFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInRegisterPlugInType"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *factoryKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[3]]];
            NSData *typeKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[4]]];
            BRPPCGuestPlugInFactoryRecord *record = factoryKey ? weakSelf.plugInFactories[factoryKey] : nil;
            if (!record || !typeKey || [record.types containsObject:typeKey]) {
                CFFinish(state, 0); return YES;
            }
            [record.types addObject:typeKey]; CFFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInUnregisterPlugInType"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *factoryKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[3]]];
            NSData *typeKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[4]]];
            BRPPCGuestPlugInFactoryRecord *record = factoryKey ? weakSelf.plugInFactories[factoryKey] : nil;
            if (!record || ![record.types containsObject:typeKey]) {
                CFFinish(state, 0); return YES;
            }
            [record.types removeObject:typeKey]; CFFinish(state, 1); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInFindFactoriesForPlugInType"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *typeKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[3]]];
            NSMutableArray *factories = [NSMutableArray array];
            [weakSelf.plugInFactories enumerateKeysAndObjectsUsingBlock:^(id factory,
                BRPPCGuestPlugInFactoryRecord *record, BOOL *stop) {
                (void)factory; (void)stop; if ([record.types containsObject:typeKey])
                    [factories addObject:record.factoryUUID];
            }];
            CFFinish(state, [weakSelf handle:[factories copy]]); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInFindFactoriesForPlugInTypeInPlugIn"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *typeKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[3]]];
            id plugIn = [weakSelf object:state->gpr[4]]; NSMutableArray *factories = [NSMutableArray array];
            [weakSelf.plugInFactories enumerateKeysAndObjectsUsingBlock:^(id factory,
                BRPPCGuestPlugInFactoryRecord *record, BOOL *stop) {
                (void)factory; (void)stop; if ([record.types containsObject:typeKey] &&
                    [record.plugIn isEqual:plugIn]) [factories addObject:record.factoryUUID];
            }];
            CFFinish(state, [weakSelf handle:[factories copy]]); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInInstanceCreate"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            id factory = [weakSelf object:state->gpr[4]]; id type = [weakSelf object:state->gpr[5]];
            NSData *factoryKey = [weakSelf plugInUUIDKey:factory];
            BRPPCGuestPlugInFactoryRecord *record = factoryKey ? weakSelf.plugInFactories[factoryKey] : nil;
            NSData *typeKey = [weakSelf plugInUUIDKey:type]; uint32_t result = 0;
            if (!record || ![record.types containsObject:typeKey] || ![weakSelf invokeGuestFunction:record.function
                outerState:record.outerState arguments:@[@(state->gpr[3]), @(state->gpr[5])]
                result:&result label:@"CFPlugIn factory" error:callError]) return NO;
            CFFinish(state, result); return YES;
        }];
    for (NSString *symbol in @[@"_CFPlugInAddInstanceForFactory", @"_CFPlugInRemoveInstanceForFactory"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *factoryKey = [weakSelf plugInUUIDKey:[weakSelf object:state->gpr[3]]];
            BRPPCGuestPlugInFactoryRecord *record = factoryKey ? weakSelf.plugInFactories[factoryKey] : nil;
            if (record) {
                if ([symbol containsString:@"Add"]) record.instanceCount++;
                else if (record.instanceCount) record.instanceCount--;
            }
            CFFinish(state, 0); return YES;
        }];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [registry registerSymbol:@"_CFPlugInInstanceGetTypeID"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFFinish(state, (uint32_t)CFPlugInInstanceGetTypeID()); return YES;
        }];
#pragma clang diagnostic pop
    [registry registerSymbol:@"_CFPlugInInstanceCreateWithInstanceDataSize"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t size = state->gpr[4]; if (size > (1u << 28)) return NO;
            BRPPCGuestPlugInInstanceRecord *record = [BRPPCGuestPlugInInstanceRecord new];
            record.resolver = weakSelf; record.outerState = *state; record.dataAddress = size
                ? registry.guestAllocator(size, YES) : 0; if (size && !record.dataAddress) return NO;
            record.deallocateFunction = state->gpr[5]; record.factoryName = [weakSelf string:state->gpr[6]];
            record.getInterfaceFunction = state->gpr[7]; record.handle = [weakSelf handle:record];
            weakSelf.plugInInstances[@(record.handle)] = record; CFFinish(state, record.handle); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInInstanceGetFactoryName"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCGuestPlugInInstanceRecord *record = weakSelf.plugInInstances[@(state->gpr[3])];
            CFFinish(state, [weakSelf handle:record.factoryName]); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInInstanceGetInstanceData"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCGuestPlugInInstanceRecord *record = weakSelf.plugInInstances[@(state->gpr[3])];
            CFFinish(state, record.dataAddress); return YES;
        }];
    [registry registerSymbol:@"_CFPlugInInstanceGetInterfaceFunctionTable"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            BRPPCGuestPlugInInstanceRecord *record = weakSelf.plugInInstances[@(state->gpr[3])];
            uint32_t result = 0; if (!record || !record.getInterfaceFunction ||
                ![weakSelf invokeGuestFunction:record.getInterfaceFunction outerState:record.outerState
                    arguments:@[@(record.handle), @(state->gpr[4]), @(state->gpr[5])] result:&result
                    label:@"CFPlugIn interface" error:callError]) return NO;
            CFFinish(state, result); return YES;
        }];

    [registry registerSymbol:@"_CFRunLoopGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFRunLoopGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopGetCurrent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFRunLoopGetCurrent()]); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopGetMain" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFRunLoopGetMain()]); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopCopyCurrentMode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
        CFStringRef mode = runLoop ? CFRunLoopCopyCurrentMode((__bridge CFRunLoopRef)runLoop) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(mode)]); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopCopyAllModes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
        CFArrayRef modes = runLoop ? CFRunLoopCopyAllModes((__bridge CFRunLoopRef)runLoop) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(modes)]); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopAddCommonMode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]]; NSString *mode = [weakSelf string:state->gpr[4]];
        if (runLoop && mode) CFRunLoopAddCommonMode((__bridge CFRunLoopRef)runLoop, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopIsWaiting" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
        CFFinish(state, runLoop && CFRunLoopIsWaiting((__bridge CFRunLoopRef)runLoop)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopRun" handler:^BOOL(BRPPCState *state, NSError **callError) {
        weakSelf.pendingCallbackError = nil; CFRunLoopRun();
        if (weakSelf.pendingCallbackError) { if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopRunInMode" handler:^BOOL(BRPPCState *state, NSError **callError) {
        NSString *mode = [weakSelf string:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
        SInt32 result = mode ? CFRunLoopRunInMode((__bridge CFStringRef)mode, state->fpr[1], state->gpr[6] != 0)
                            : kCFRunLoopRunFinished;
        if (weakSelf.pendingCallbackError) { if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopStop" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
        if (runLoop) CFRunLoopStop((__bridge CFRunLoopRef)runLoop); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopWakeUp" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
        if (runLoop) CFRunLoopWakeUp((__bridge CFRunLoopRef)runLoop); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopGetNextTimerFireDate"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
            NSString *mode = [weakSelf string:state->gpr[4]]; state->fpr[1] = runLoop && mode
                ? CFRunLoopGetNextTimerFireDate((__bridge CFRunLoopRef)runLoop, (__bridge CFStringRef)mode) : 0;
            state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_CFRunLoopPerformBlock"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id runLoop = [weakSelf object:state->gpr[3]];
            id mode = [weakSelf object:state->gpr[4]];
            BRPPCGuestBlockRecord *record = [weakSelf guestBlockAtAddress:state->gpr[5] state:*state];
            if (!runLoop || !mode || !record) return NO; weakSelf.runLoopBlockRecords[@(record.address)] = record;
            CFRunLoopPerformBlock((__bridge CFRunLoopRef)runLoop, (__bridge CFTypeRef)mode, ^{
                NSError *blockError = nil;
                if (![weakSelf invokeGuestBlock:record arguments:@[] result:NULL
                    label:@"CFRunLoop perform block" error:&blockError]) {
                    weakSelf.pendingCallbackError = blockError; CFRunLoopStop(CFRunLoopGetCurrent());
                }
                [weakSelf.runLoopBlockRecords removeObjectForKey:@(record.address)];
            });
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFRunLoopTimerGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFRunLoopTimerGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t contextAddress = 0;
        if (!state->gpr[1] || ![registry.memory readUInt32:&contextAddress address:state->gpr[1] + 56]) return NO;
        BRPPCGuestTimerRecord *record = [BRPPCGuestTimerRecord new]; record.outerState = *state;
        record.callout = state->gpr[10];
        if (!record.callout) return NO;
        if (contextAddress) {
            uint32_t version = 0, info = 0, retainFunction = 0, releaseFunction = 0, descriptionFunction = 0;
            if (![registry.memory readUInt32:&version address:contextAddress] || version != 0 ||
                ![registry.memory readUInt32:&info address:contextAddress + 4] ||
                ![registry.memory readUInt32:&retainFunction address:contextAddress + 8] ||
                ![registry.memory readUInt32:&releaseFunction address:contextAddress + 12] ||
                ![registry.memory readUInt32:&descriptionFunction address:contextAddress + 16]) return NO;
            record.info = info; record.retainFunction = retainFunction;
            record.releaseFunction = releaseFunction; record.descriptionFunction = descriptionFunction;
            if (record.retainFunction) {
                uint32_t retainedInfo = 0;
                if (![weakSelf invokeGuestFunction:record.retainFunction outerState:*state
                    arguments:@[@(record.info)] result:&retainedInfo
                    label:@"CFRunLoopTimer context retain" error:callError]) return NO;
                record.info = retainedInfo;
            }
        }
        __weak BRPPCGuestTimerRecord *weakRecord = record;
        CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
            state->fpr[1], state->fpr[2], state->gpr[8], (CFIndex)(int32_t)state->gpr[9],
            ^(CFRunLoopTimerRef firedTimer) {
                BRPPCGuestTimerRecord *strongRecord = weakRecord;
                if (!strongRecord || strongRecord.released) return;
                NSError *callbackError = nil;
                if (![weakSelf invokeGuestFunction:strongRecord.callout outerState:strongRecord.outerState
                    arguments:@[@(strongRecord.handle), @(strongRecord.info)] result:NULL
                    label:@"CFRunLoopTimer callout" error:&callbackError]) {
                    weakSelf.pendingCallbackError = callbackError;
                    CFRunLoopStop(CFRunLoopGetCurrent());
                }
                if (!CFRunLoopTimerIsValid(firedTimer)) {
                    NSError *releaseError = nil;
                    if (![weakSelf releaseTimerRecord:strongRecord error:&releaseError] && !weakSelf.pendingCallbackError)
                        weakSelf.pendingCallbackError = releaseError;
                }
            });
        if (!timer) { [weakSelf releaseTimerRecord:record error:NULL]; CFFinish(state, 0); return YES; }
        record.timer = CFBridgingRelease(timer); record.handle = [weakSelf handle:record.timer];
        weakSelf.timerRecords[@(record.handle)] = record; CFFinish(state, record.handle); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerCreateWithHandler"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            BRPPCGuestBlockRecord *record = [weakSelf guestBlockAtAddress:state->gpr[10] state:*state];
            if (!record) return NO; __weak BRPPCGuestBlockRecord *weakRecord = record;
            CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, state->fpr[1],
                state->fpr[2], state->gpr[8], (CFIndex)(int32_t)state->gpr[9], ^(CFRunLoopTimerRef timerRef) {
                    BRPPCGuestBlockRecord *strongRecord = weakRecord; if (!strongRecord) return;
                    NSError *blockError = nil;
                    if (![weakSelf invokeGuestBlock:strongRecord arguments:@[@(strongRecord.handle)] result:NULL
                        label:@"CFRunLoopTimer block" error:&blockError]) {
                        weakSelf.pendingCallbackError = blockError; CFRunLoopTimerInvalidate(timerRef);
                        CFRunLoopStop(CFRunLoopGetCurrent());
                    }
                });
            if (!timer) { CFFinish(state, 0); return YES; }
            record.hostObject = CFBridgingRelease(timer); record.handle = [weakSelf handle:record.hostObject];
            weakSelf.runLoopBlockRecords[@(record.handle)] = record; CFFinish(state, record.handle); return YES;
        }];
    [registry registerSymbol:@"_CFRunLoopAddTimer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], timer = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        if (runLoop && timer && mode) CFRunLoopAddTimer((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopTimerRef)timer, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopRemoveTimer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], timer = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        if (runLoop && timer && mode) CFRunLoopRemoveTimer((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopTimerRef)timer, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopContainsTimer" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], timer = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        CFFinish(state, runLoop && timer && mode && CFRunLoopContainsTimer((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopTimerRef)timer, (__bridge CFStringRef)mode)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerInvalidate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id timer = [weakSelf object:state->gpr[3]]; BRPPCGuestTimerRecord *record = weakSelf.timerRecords[@(state->gpr[3])];
        if (timer) CFRunLoopTimerInvalidate((__bridge CFRunLoopTimerRef)timer);
        if (![weakSelf releaseTimerRecord:record error:callError]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerIsValid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id timer = [weakSelf object:state->gpr[3]];
        CFFinish(state, timer && CFRunLoopTimerIsValid((__bridge CFRunLoopTimerRef)timer)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerGetNextFireDate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id timer = [weakSelf object:state->gpr[3]];
        state->fpr[1] = timer ? CFRunLoopTimerGetNextFireDate((__bridge CFRunLoopTimerRef)timer) : 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerSetNextFireDate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id timer = [weakSelf object:state->gpr[3]];
        if (timer) CFRunLoopTimerSetNextFireDate((__bridge CFRunLoopTimerRef)timer, state->fpr[1]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerGetInterval" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id timer = [weakSelf object:state->gpr[3]];
        state->fpr[1] = timer ? CFRunLoopTimerGetInterval((__bridge CFRunLoopTimerRef)timer) : 0;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerGetTolerance"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id timer = [weakSelf object:state->gpr[3]];
            state->fpr[1] = timer ? CFRunLoopTimerGetTolerance((__bridge CFRunLoopTimerRef)timer) : 0;
            state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_CFRunLoopTimerSetTolerance"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id timer = [weakSelf object:state->gpr[3]];
            if (timer) CFRunLoopTimerSetTolerance((__bridge CFRunLoopTimerRef)timer, state->fpr[1]);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFRunLoopTimerDoesRepeat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id timer = [weakSelf object:state->gpr[3]];
        CFFinish(state, timer && CFRunLoopTimerDoesRepeat((__bridge CFRunLoopTimerRef)timer)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerGetOrder" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id timer = [weakSelf object:state->gpr[3]];
        CFFinish(state, timer ? (uint32_t)CFRunLoopTimerGetOrder((__bridge CFRunLoopTimerRef)timer) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopTimerGetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestTimerRecord *record = weakSelf.timerRecords[@(state->gpr[3])]; uint32_t address = state->gpr[4];
        if (!record || !address || ![registry.memory writeUInt32:0 address:address] ||
            ![registry.memory writeUInt32:record.info address:address + 4] ||
            ![registry.memory writeUInt32:record.retainFunction address:address + 8] ||
            ![registry.memory writeUInt32:record.releaseFunction address:address + 12] ||
            ![registry.memory writeUInt32:record.descriptionFunction address:address + 16]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFRunLoopObserverGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCGuestTimerRecord *record = [BRPPCGuestTimerRecord new]; record.outerState = *state;
        record.callout = state->gpr[7]; uint32_t contextAddress = state->gpr[8];
        if (!record.callout) return NO;
        if (contextAddress) {
            uint32_t version = 0, info = 0, retainFunction = 0, releaseFunction = 0, descriptionFunction = 0;
            if (![registry.memory readUInt32:&version address:contextAddress] || version != 0 ||
                ![registry.memory readUInt32:&info address:contextAddress + 4] ||
                ![registry.memory readUInt32:&retainFunction address:contextAddress + 8] ||
                ![registry.memory readUInt32:&releaseFunction address:contextAddress + 12] ||
                ![registry.memory readUInt32:&descriptionFunction address:contextAddress + 16]) return NO;
            record.info = info; record.retainFunction = retainFunction;
            record.releaseFunction = releaseFunction; record.descriptionFunction = descriptionFunction;
            if (record.retainFunction) {
                uint32_t retainedInfo = 0;
                if (![weakSelf invokeGuestFunction:record.retainFunction outerState:*state
                    arguments:@[@(record.info)] result:&retainedInfo
                    label:@"CFRunLoopObserver context retain" error:callError]) return NO;
                record.info = retainedInfo;
            }
        }
        __weak BRPPCGuestTimerRecord *weakRecord = record;
        CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,
            state->gpr[4], state->gpr[5] != 0, (CFIndex)(int32_t)state->gpr[6],
            ^(CFRunLoopObserverRef firedObserver, CFRunLoopActivity activity) {
                BRPPCGuestTimerRecord *strongRecord = weakRecord;
                if (!strongRecord || strongRecord.released) return;
                NSError *callbackError = nil;
                if (![weakSelf invokeGuestFunction:strongRecord.callout outerState:strongRecord.outerState
                    arguments:@[@(strongRecord.handle), @((uint32_t)activity), @(strongRecord.info)] result:NULL
                    label:@"CFRunLoopObserver callout" error:&callbackError]) {
                    weakSelf.pendingCallbackError = callbackError; CFRunLoopStop(CFRunLoopGetCurrent());
                }
                if (!CFRunLoopObserverIsValid(firedObserver)) {
                    NSError *releaseError = nil;
                    if (![weakSelf releaseTimerRecord:strongRecord error:&releaseError] && !weakSelf.pendingCallbackError)
                        weakSelf.pendingCallbackError = releaseError;
                }
            });
        if (!observer) { [weakSelf releaseTimerRecord:record error:NULL]; CFFinish(state, 0); return YES; }
        record.timer = CFBridgingRelease(observer); record.handle = [weakSelf handle:record.timer];
        weakSelf.observerRecords[@(record.handle)] = record; CFFinish(state, record.handle); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverCreateWithHandler"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError;
            BRPPCGuestBlockRecord *record = [weakSelf guestBlockAtAddress:state->gpr[7] state:*state];
            if (!record) return NO; __weak BRPPCGuestBlockRecord *weakRecord = record;
            CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault,
                state->gpr[4], state->gpr[5] != 0, (CFIndex)(int32_t)state->gpr[6],
                ^(CFRunLoopObserverRef observerRef, CFRunLoopActivity activity) {
                    BRPPCGuestBlockRecord *strongRecord = weakRecord; if (!strongRecord) return;
                    NSError *blockError = nil;
                    if (![weakSelf invokeGuestBlock:strongRecord arguments:@[@(strongRecord.handle),
                        @((uint32_t)activity)] result:NULL label:@"CFRunLoopObserver block" error:&blockError]) {
                        weakSelf.pendingCallbackError = blockError; CFRunLoopObserverInvalidate(observerRef);
                        CFRunLoopStop(CFRunLoopGetCurrent());
                    }
                });
            if (!observer) { CFFinish(state, 0); return YES; }
            record.hostObject = CFBridgingRelease(observer); record.handle = [weakSelf handle:record.hostObject];
            weakSelf.runLoopBlockRecords[@(record.handle)] = record; CFFinish(state, record.handle); return YES;
        }];
    [registry registerSymbol:@"_CFRunLoopAddObserver" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], observer = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        if (runLoop && observer && mode) CFRunLoopAddObserver((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopObserverRef)observer, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopRemoveObserver" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], observer = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        if (runLoop && observer && mode) CFRunLoopRemoveObserver((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopObserverRef)observer, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopContainsObserver" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], observer = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        CFFinish(state, runLoop && observer && mode && CFRunLoopContainsObserver((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopObserverRef)observer, (__bridge CFStringRef)mode)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverInvalidate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id observer = [weakSelf object:state->gpr[3]];
        BRPPCGuestTimerRecord *record = weakSelf.observerRecords[@(state->gpr[3])];
        if (observer) CFRunLoopObserverInvalidate((__bridge CFRunLoopObserverRef)observer);
        if (![weakSelf releaseTimerRecord:record error:callError]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverIsValid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id observer = [weakSelf object:state->gpr[3]];
        CFFinish(state, observer && CFRunLoopObserverIsValid((__bridge CFRunLoopObserverRef)observer)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverGetActivities" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id observer = [weakSelf object:state->gpr[3]];
        CFFinish(state, observer ? (uint32_t)CFRunLoopObserverGetActivities((__bridge CFRunLoopObserverRef)observer) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverDoesRepeat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id observer = [weakSelf object:state->gpr[3]];
        CFFinish(state, observer && CFRunLoopObserverDoesRepeat((__bridge CFRunLoopObserverRef)observer)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverGetOrder" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id observer = [weakSelf object:state->gpr[3]];
        CFFinish(state, observer ? (uint32_t)CFRunLoopObserverGetOrder((__bridge CFRunLoopObserverRef)observer) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopObserverGetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestTimerRecord *record = weakSelf.observerRecords[@(state->gpr[3])]; uint32_t address = state->gpr[4];
        if (!record || !address || ![registry.memory writeUInt32:0 address:address] ||
            ![registry.memory writeUInt32:record.info address:address + 4] ||
            ![registry.memory writeUInt32:record.retainFunction address:address + 8] ||
            ![registry.memory writeUInt32:record.releaseFunction address:address + 12] ||
            ![registry.memory writeUInt32:record.descriptionFunction address:address + 16]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFRunLoopSourceGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        uint32_t contextAddress = state->gpr[5];
        if (!contextAddress) return NO;
        uint32_t fields[10];
        for (NSUInteger i = 0; i < 10; i++)
            if (![registry.memory readUInt32:&fields[i] address:contextAddress + (uint32_t)i * 4]) return NO;
        if (fields[0] != 0 || !fields[9]) return NO;
        BRPPCGuestSourceRecord *record = [BRPPCGuestSourceRecord new];
        record.resolver = weakSelf; record.outerState = *state; record.info = fields[1];
        record.retainFunction = fields[2]; record.releaseFunction = fields[3];
        record.descriptionFunction = fields[4]; record.equalFunction = fields[5];
        record.hashFunction = fields[6]; record.scheduleFunction = fields[7];
        record.cancelFunction = fields[8]; record.performFunction = fields[9];
        if (record.retainFunction) {
            uint32_t retainedInfo = 0;
            if (![weakSelf invokeGuestFunction:record.retainFunction outerState:*state
                arguments:@[@(record.info)] result:&retainedInfo
                label:@"CFRunLoopSource context retain" error:callError]) return NO;
            record.info = retainedInfo;
        }
        CFRunLoopSourceContext context = {0}; context.info = (__bridge void *)record;
        context.retain = RetainSourceRecord; context.release = ReleaseSourceRecord;
        context.copyDescription = CopySourceDescription; context.equal = EqualSourceRecords;
        context.hash = HashSourceRecord; context.schedule = ScheduleSource;
        context.cancel = CancelSource; context.perform = PerformSource;
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(kCFAllocatorDefault,
            (CFIndex)(int32_t)state->gpr[4], &context);
        if (!source) { [weakSelf releaseSourceRecord:record error:NULL]; CFFinish(state, 0); return YES; }
        record.source = CFBridgingRelease(source); record.handle = [weakSelf handle:record.source];
        weakSelf.sourceRecords[@(record.handle)] = record; CFFinish(state, record.handle); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopAddSource" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], source = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        if (runLoop && source && mode) CFRunLoopAddSource((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopSourceRef)source, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopRemoveSource" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], source = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        if (runLoop && source && mode) CFRunLoopRemoveSource((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopSourceRef)source, (__bridge CFStringRef)mode);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopContainsSource" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id runLoop = [weakSelf object:state->gpr[3]], source = [weakSelf object:state->gpr[4]];
        NSString *mode = [weakSelf string:state->gpr[5]];
        CFFinish(state, runLoop && source && mode && CFRunLoopContainsSource((__bridge CFRunLoopRef)runLoop,
            (__bridge CFRunLoopSourceRef)source, (__bridge CFStringRef)mode)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceSignal" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id source = [weakSelf object:state->gpr[3]];
        if (source) CFRunLoopSourceSignal((__bridge CFRunLoopSourceRef)source); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceInvalidate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id source = [weakSelf object:state->gpr[3]];
        BRPPCGuestSourceRecord *record = weakSelf.sourceRecords[@(state->gpr[3])];
        if (source) CFRunLoopSourceInvalidate((__bridge CFRunLoopSourceRef)source);
        if (![weakSelf releaseSourceRecord:record error:callError]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceIsValid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id source = [weakSelf object:state->gpr[3]];
        CFFinish(state, source && CFRunLoopSourceIsValid((__bridge CFRunLoopSourceRef)source)); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceGetOrder" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id source = [weakSelf object:state->gpr[3]];
        CFFinish(state, source ? (uint32_t)CFRunLoopSourceGetOrder((__bridge CFRunLoopSourceRef)source) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFRunLoopSourceGetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestSourceRecord *record = weakSelf.sourceRecords[@(state->gpr[3])]; uint32_t address = state->gpr[4];
        uint32_t fields[] = {0, record.info, record.retainFunction, record.releaseFunction,
            record.descriptionFunction, record.equalFunction, record.hashFunction,
            record.scheduleFunction, record.cancelFunction, record.performFunction};
        if (!record || !address) return NO;
        for (NSUInteger i = 0; i < 10; i++)
            if (![registry.memory writeUInt32:fields[i] address:address + (uint32_t)i * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];

    [registry registerSymbol:@"_CFCalendarGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFCalendarGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarCopyCurrent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:CFBridgingRelease(CFCalendarCopyCurrent())]); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarCreateWithIdentifier" handler:^BOOL(BRPPCState *state,
                                                                               NSError **callError) {
        (void)callError; NSString *identifier = [weakSelf string:state->gpr[4]];
        CFCalendarRef calendar = identifier ? CFCalendarCreateWithIdentifier(kCFAllocatorDefault,
            (__bridge CFStringRef)identifier) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(calendar)]); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarGetIdentifier" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]];
        CFStringRef identifier = calendar ? CFCalendarGetIdentifier((__bridge CFCalendarRef)calendar) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)identifier]); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarCopyLocale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]];
        CFLocaleRef locale = calendar ? CFCalendarCopyLocale((__bridge CFCalendarRef)calendar) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(locale)]); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarSetLocale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]], locale = [weakSelf object:state->gpr[4]];
        if (calendar && locale) CFCalendarSetLocale((__bridge CFCalendarRef)calendar, (__bridge CFLocaleRef)locale);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarCopyTimeZone" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]];
        CFTimeZoneRef zone = calendar ? CFCalendarCopyTimeZone((__bridge CFCalendarRef)calendar) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(zone)]); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarSetTimeZone" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]], zone = [weakSelf object:state->gpr[4]];
        if (calendar && zone) CFCalendarSetTimeZone((__bridge CFCalendarRef)calendar, (__bridge CFTimeZoneRef)zone);
        CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFCalendarGetFirstWeekday", @"_CFCalendarGetMinimumDaysInFirstWeek"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id calendar = [weakSelf object:state->gpr[3]]; uint32_t value = 0;
            if (calendar) value = [symbol containsString:@"FirstWeekday"]
                ? (uint32_t)CFCalendarGetFirstWeekday((__bridge CFCalendarRef)calendar)
                : (uint32_t)CFCalendarGetMinimumDaysInFirstWeek((__bridge CFCalendarRef)calendar);
            CFFinish(state, value); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFCalendarSetFirstWeekday", @"_CFCalendarSetMinimumDaysInFirstWeek"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id calendar = [weakSelf object:state->gpr[3]];
            if (calendar) {
                if ([symbol containsString:@"FirstWeekday"])
                    CFCalendarSetFirstWeekday((__bridge CFCalendarRef)calendar, state->gpr[4]);
                else CFCalendarSetMinimumDaysInFirstWeek((__bridge CFCalendarRef)calendar, state->gpr[4]);
            }
            CFFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFCalendarGetMinimumRangeOfUnit", @"_CFCalendarGetMaximumRangeOfUnit"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id calendar = [weakSelf object:state->gpr[3]]; CFRange range = CFRangeMake(kCFNotFound, 0);
            if (calendar) range = [symbol containsString:@"Minimum"]
                ? CFCalendarGetMinimumRangeOfUnit((__bridge CFCalendarRef)calendar, state->gpr[4])
                : CFCalendarGetMaximumRangeOfUnit((__bridge CFCalendarRef)calendar, state->gpr[4]);
            state->gpr[3] = (uint32_t)range.location; state->gpr[4] = (uint32_t)range.length;
            state->pc = state->lr; return YES;
        }];
    }
    [registry registerSymbol:@"_CFCalendarGetRangeOfUnit" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]]; CFRange range = CFRangeMake(kCFNotFound, 0);
        if (calendar) range = CFCalendarGetRangeOfUnit((__bridge CFCalendarRef)calendar,
            state->gpr[4], state->gpr[5], state->fpr[1]);
        state->gpr[3] = (uint32_t)range.location; state->gpr[4] = (uint32_t)range.length;
        state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CFCalendarGetOrdinalityOfUnit" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]];
        CFIndex result = calendar ? CFCalendarGetOrdinalityOfUnit((__bridge CFCalendarRef)calendar,
            state->gpr[4], state->gpr[5], state->fpr[1]) : kCFNotFound;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarGetTimeRangeOfUnit" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; id calendar = [weakSelf object:state->gpr[3]]; CFAbsoluteTime start = 0;
        CFTimeInterval interval = 0; BOOL valid = calendar && CFCalendarGetTimeRangeOfUnit(
            (__bridge CFCalendarRef)calendar, state->gpr[4], state->fpr[1], &start, &interval);
        if (valid && state->gpr[7] && ![weakSelf writeDouble:start address:state->gpr[7]]) return NO;
        if (valid && state->gpr[8] && ![weakSelf writeDouble:interval address:state->gpr[8]]) return NO;
        CFFinish(state, valid); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarComposeAbsoluteTime" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; NSCalendar *calendar = [weakSelf object:state->gpr[3]];
        NSString *descriptor = [registry.memory readCStringAtAddress:state->gpr[5] maximumLength:64];
        if (!calendar || !state->gpr[4] || !descriptor) return NO;
        NSDateComponents *components = [NSDateComponents new]; NSUInteger cursor = 6;
        for (NSUInteger index = 0; index < descriptor.length; index++) {
            char component = [descriptor characterAtIndex:index]; uint32_t value = 0;
            if (!CalendarUnitForComponent(component) || ![weakSelf readGuestWord:&value state:state cursor:&cursor]) return NO;
            SetCalendarComponent(components, component, (int32_t)value);
        }
        NSDate *date = [calendar dateFromComponents:components];
        BOOL valid = date && [weakSelf writeDouble:date.timeIntervalSinceReferenceDate address:state->gpr[4]];
        CFFinish(state, valid); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarDecomposeAbsoluteTime" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        (void)callError; NSCalendar *calendar = [weakSelf object:state->gpr[3]];
        NSString *descriptor = [registry.memory readCStringAtAddress:state->gpr[7] maximumLength:64];
        if (!calendar || !descriptor) return NO; NSCalendarUnit units = 0;
        for (NSUInteger index = 0; index < descriptor.length; index++) {
            NSCalendarUnit unit = CalendarUnitForComponent([descriptor characterAtIndex:index]);
            if (!unit) return NO; units |= unit;
        }
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:state->fpr[1]];
        NSDateComponents *components = [calendar components:units fromDate:date]; NSUInteger cursor = 8;
        for (NSUInteger index = 0; index < descriptor.length; index++) {
            uint32_t address = 0; char component = [descriptor characterAtIndex:index];
            if (![weakSelf readGuestWord:&address state:state cursor:&cursor] || !address ||
                ![registry.memory writeUInt32:(uint32_t)GetCalendarComponent(components, component) address:address]) return NO;
        }
        CFFinish(state, 1); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarAddComponents" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSCalendar *calendar = [weakSelf object:state->gpr[3]];
        NSString *descriptor = [registry.memory readCStringAtAddress:state->gpr[6] maximumLength:64];
        double absoluteTime = 0;
        if (!calendar || !descriptor || ![weakSelf readDouble:&absoluteTime address:state->gpr[4]]) return NO;
        NSDateComponents *components = [NSDateComponents new]; NSUInteger cursor = 7;
        for (NSUInteger index = 0; index < descriptor.length; index++) {
            char component = [descriptor characterAtIndex:index]; uint32_t value = 0;
            if (!CalendarUnitForComponent(component) || ![weakSelf readGuestWord:&value state:state cursor:&cursor]) return NO;
            SetCalendarComponent(components, component, (int32_t)value);
        }
        NSDate *date = [calendar dateByAddingComponents:components
            toDate:[NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime]
            options:(state->gpr[5] & kCFCalendarComponentsWrap) ? NSCalendarWrapComponents : 0];
        BOOL valid = date && [weakSelf writeDouble:date.timeIntervalSinceReferenceDate address:state->gpr[4]];
        CFFinish(state, valid); return YES;
    }];
    [registry registerSymbol:@"_CFCalendarGetComponentDifference" handler:^BOOL(BRPPCState *state,
                                                                                 NSError **callError) {
        (void)callError; NSCalendar *calendar = [weakSelf object:state->gpr[3]];
        NSString *descriptor = [registry.memory readCStringAtAddress:state->gpr[10] maximumLength:64];
        if (!calendar || !descriptor) return NO; NSCalendarUnit units = 0;
        for (NSUInteger index = 0; index < descriptor.length; index++) {
            NSCalendarUnit unit = CalendarUnitForComponent([descriptor characterAtIndex:index]);
            if (!unit) return NO; units |= unit;
        }
        NSDate *start = [NSDate dateWithTimeIntervalSinceReferenceDate:state->fpr[1]];
        NSDate *result = [NSDate dateWithTimeIntervalSinceReferenceDate:state->fpr[2]];
        NSDateComponents *components = [calendar components:units fromDate:start toDate:result
            options:(state->gpr[9] & kCFCalendarComponentsWrap) ? NSCalendarWrapComponents : 0];
        NSUInteger cursor = 11;
        for (NSUInteger index = 0; index < descriptor.length; index++) {
            uint32_t address = 0; char component = [descriptor characterAtIndex:index];
            if (![weakSelf readGuestWord:&address state:state cursor:&cursor] || !address ||
                ![registry.memory writeUInt32:(uint32_t)GetCalendarComponent(components, component) address:address]) return NO;
        }
        CFFinish(state, 1); return YES;
    }];

    [registry registerSymbol:@"_CFDateGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFDateGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFDateCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:state->fpr[1]];
        CFFinish(state, [weakSelf handle:date]); return YES;
    }];
    [registry registerSymbol:@"_CFDateGetAbsoluteTime" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDate *date = [weakSelf object:state->gpr[3]];
        state->fpr[1] = date.timeIntervalSinceReferenceDate; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CFAbsoluteTimeGetCurrent" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; state->fpr[1] = CFAbsoluteTimeGetCurrent(); state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CFGregorianDateIsValid" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; typedef Boolean (*GregorianDateIsValidFunction)(BRHostGregorianDate, CFOptionFlags);
        GregorianDateIsValidFunction function = (GregorianDateIsValidFunction)dlsym(RTLD_DEFAULT,
            "CFGregorianDateIsValid"); uint32_t packed = state->gpr[4];
        BRHostGregorianDate date = {(int32_t)state->gpr[3], (int8_t)(packed >> 24),
            (int8_t)(packed >> 16), (int8_t)(packed >> 8), (int8_t)packed,
            DoubleFromGuestWords(state->gpr[5], state->gpr[6])};
        CFFinish(state, function ? function(date, state->gpr[7]) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFGregorianDateGetAbsoluteTime"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef double (*GregorianDateGetTimeFunction)(BRHostGregorianDate, CFTimeZoneRef);
            GregorianDateGetTimeFunction function = (GregorianDateGetTimeFunction)dlsym(RTLD_DEFAULT,
                "CFGregorianDateGetAbsoluteTime"); uint32_t packed = state->gpr[4];
            BRHostGregorianDate date = {(int32_t)state->gpr[3], (int8_t)(packed >> 24),
                (int8_t)(packed >> 16), (int8_t)(packed >> 8), (int8_t)packed,
                DoubleFromGuestWords(state->gpr[5], state->gpr[6])};
            id zone = [weakSelf object:state->gpr[7]]; state->fpr[1] = function
                ? function(date, (__bridge CFTimeZoneRef)zone) : 0; state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_CFAbsoluteTimeGetGregorianDate"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef BRHostGregorianDate (*GetGregorianDateFunction)(double, CFTimeZoneRef);
            GetGregorianDateFunction function = (GetGregorianDateFunction)dlsym(RTLD_DEFAULT,
                "CFAbsoluteTimeGetGregorianDate"); id zone = [weakSelf object:state->gpr[6]];
            BRHostGregorianDate date = function ? function(state->fpr[1], (__bridge CFTimeZoneRef)zone)
                : (BRHostGregorianDate){0}; uint32_t packed = (uint32_t)(uint8_t)date.month << 24 |
                    (uint32_t)(uint8_t)date.day << 16 | (uint32_t)(uint8_t)date.hour << 8 |
                    (uint8_t)date.minute;
            if (!state->gpr[3] || ![registry.memory writeUInt32:(uint32_t)date.year address:state->gpr[3]] ||
                ![registry.memory writeUInt32:packed address:state->gpr[3] + 4] ||
                ![weakSelf writeDouble:date.second address:state->gpr[3] + 8]) return NO;
            CFFinish(state, state->gpr[3]); return YES;
        }];
    [registry registerSymbol:@"_CFAbsoluteTimeAddGregorianUnits"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef double (*AddGregorianUnitsFunction)(double, CFTimeZoneRef,
                BRHostGregorianUnits); AddGregorianUnitsFunction function = (AddGregorianUnitsFunction)dlsym(
                    RTLD_DEFAULT, "CFAbsoluteTimeAddGregorianUnits"); NSUInteger cursor = 6;
            uint32_t words[8] = {0};
            for (NSUInteger index = 0; index < 8; index++)
                if (![weakSelf readGuestWord:&words[index] state:state cursor:&cursor]) return NO;
            BRHostGregorianUnits units = {(int32_t)words[0], (int32_t)words[1], (int32_t)words[2],
                (int32_t)words[3], (int32_t)words[4], DoubleFromGuestWords(words[6], words[7])};
            id zone = [weakSelf object:state->gpr[5]]; state->fpr[1] = function
                ? function(state->fpr[1], (__bridge CFTimeZoneRef)zone, units) : 0;
            state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_CFAbsoluteTimeGetDifferenceAsGregorianUnits"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef BRHostGregorianUnits (*DifferenceFunction)(double, double,
                CFTimeZoneRef, CFOptionFlags); DifferenceFunction function = (DifferenceFunction)dlsym(
                    RTLD_DEFAULT, "CFAbsoluteTimeGetDifferenceAsGregorianUnits");
            id zone = [weakSelf object:state->gpr[8]]; BRHostGregorianUnits units = function
                ? function(state->fpr[1], state->fpr[2], (__bridge CFTimeZoneRef)zone, state->gpr[9])
                : (BRHostGregorianUnits){0}; uint32_t output = state->gpr[3];
            if (!output || ![registry.memory writeUInt32:(uint32_t)units.years address:output] ||
                ![registry.memory writeUInt32:(uint32_t)units.months address:output + 4] ||
                ![registry.memory writeUInt32:(uint32_t)units.days address:output + 8] ||
                ![registry.memory writeUInt32:(uint32_t)units.hours address:output + 12] ||
                ![registry.memory writeUInt32:(uint32_t)units.minutes address:output + 16] ||
                ![registry.memory writeUInt32:0 address:output + 20] ||
                ![weakSelf writeDouble:units.seconds address:output + 24]) return NO;
            CFFinish(state, output); return YES;
        }];
    NSDictionary<NSString *, NSString *> *absoluteTimeParts = @{
        @"_CFAbsoluteTimeGetDayOfWeek": @"CFAbsoluteTimeGetDayOfWeek",
        @"_CFAbsoluteTimeGetDayOfYear": @"CFAbsoluteTimeGetDayOfYear",
        @"_CFAbsoluteTimeGetWeekOfYear": @"CFAbsoluteTimeGetWeekOfYear"
    };
    [absoluteTimeParts enumerateKeysAndObjectsUsingBlock:^(NSString *symbol, NSString *hostName, BOOL *stop) {
        (void)stop; [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef int32_t (*AbsoluteTimePartFunction)(double, CFTimeZoneRef);
            AbsoluteTimePartFunction function = (AbsoluteTimePartFunction)dlsym(RTLD_DEFAULT,
                hostName.UTF8String); id zone = [weakSelf object:state->gpr[5]];
            CFFinish(state, function ? (uint32_t)function(state->fpr[1], (__bridge CFTimeZoneRef)zone) : 0);
            return YES;
        }];
    }];
    [registry registerSymbol:@"_CFDateCompare" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)[[weakSelf object:state->gpr[3]] compare:[weakSelf object:state->gpr[4]]]); return YES;
    }];
    [registry registerSymbol:@"_CFDateGetTimeIntervalSinceDate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSDate *first = [weakSelf object:state->gpr[3]], *second = [weakSelf object:state->gpr[4]];
        state->fpr[1] = [first timeIntervalSinceDate:second]; state->pc = state->lr; return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFDateFormatterGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id locale = [weakSelf object:state->gpr[4]];
        CFDateFormatterRef formatter = CFDateFormatterCreate(kCFAllocatorDefault,
            locale ? (__bridge CFLocaleRef)locale : NULL, (CFDateFormatterStyle)state->gpr[5],
            (CFDateFormatterStyle)state->gpr[6]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(formatter)]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCreateISO8601Formatter" handler:^BOOL(BRPPCState *state,
                                                                                      NSError **callError) {
        (void)callError; CFDateFormatterRef formatter = CFDateFormatterCreateISO8601Formatter(
            kCFAllocatorDefault, state->gpr[4]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(formatter)]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCreateDateFormatFromTemplate" handler:^BOOL(BRPPCState *state,
                                                                                            NSError **callError) {
        (void)callError; NSString *template = [weakSelf string:state->gpr[4]];
        id locale = [weakSelf object:state->gpr[6]];
        CFStringRef format = template ? CFDateFormatterCreateDateFormatFromTemplate(kCFAllocatorDefault,
            (__bridge CFStringRef)template, state->gpr[5], locale ? (__bridge CFLocaleRef)locale : NULL) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(format)]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterGetLocale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]];
        CFLocaleRef locale = formatter ? CFDateFormatterGetLocale((__bridge CFDateFormatterRef)formatter) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)locale]); return YES;
    }];
    for (NSString *symbol in @[@"_CFDateFormatterGetDateStyle", @"_CFDateFormatterGetTimeStyle"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id formatter = [weakSelf object:state->gpr[3]]; uint32_t style = 0;
            if (formatter) style = (uint32_t)([symbol containsString:@"DateStyle"]
                ? CFDateFormatterGetDateStyle((__bridge CFDateFormatterRef)formatter)
                : CFDateFormatterGetTimeStyle((__bridge CFDateFormatterRef)formatter));
            CFFinish(state, style); return YES;
        }];
    }
    [registry registerSymbol:@"_CFDateFormatterGetFormat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]];
        CFStringRef format = formatter ? CFDateFormatterGetFormat((__bridge CFDateFormatterRef)formatter) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)format]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterSetFormat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *format = [weakSelf string:state->gpr[4]];
        if (formatter && format) CFDateFormatterSetFormat((__bridge CFDateFormatterRef)formatter,
            (__bridge CFStringRef)format);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCreateStringWithDate" handler:^BOOL(BRPPCState *state,
                                                                                    NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[4]], date = [weakSelf object:state->gpr[5]];
        CFStringRef string = formatter && date ? CFDateFormatterCreateStringWithDate(kCFAllocatorDefault,
            (__bridge CFDateFormatterRef)formatter, (__bridge CFDateRef)date) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCreateStringWithAbsoluteTime" handler:^BOOL(BRPPCState *state,
                                                                                            NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[4]];
        CFStringRef string = formatter ? CFDateFormatterCreateStringWithAbsoluteTime(kCFAllocatorDefault,
            (__bridge CFDateFormatterRef)formatter, state->fpr[1]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCreateDateFromString" handler:^BOOL(BRPPCState *state,
                                                                                   NSError **callError) {
        (void)callError; NSDateFormatter *formatter = [weakSelf object:state->gpr[4]];
        NSString *string = [weakSelf string:state->gpr[5]]; NSRange range = NSMakeRange(0, string.length);
        uint32_t location = 0, length = 0;
        if (state->gpr[6] && (![registry.memory readUInt32:&location address:state->gpr[6]] ||
            ![registry.memory readUInt32:&length address:state->gpr[6] + 4])) return NO;
        if (state->gpr[6]) range = NSMakeRange(location, length);
        NSDate *date = nil;
        if (formatter && string) [formatter getObjectValue:&date forString:string range:&range error:NULL];
        if (state->gpr[6] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[6]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[6] + 4])) return NO;
        CFFinish(state, [weakSelf handle:date]); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterGetAbsoluteTimeFromString" handler:^BOOL(BRPPCState *state,
                                                                                         NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *string = [weakSelf string:state->gpr[4]];
        CFRange range = CFRangeMake(0, string.length); CFAbsoluteTime absoluteTime = 0;
        uint32_t location = 0, length = 0;
        if (state->gpr[5] && (![registry.memory readUInt32:&location address:state->gpr[5]] ||
            ![registry.memory readUInt32:&length address:state->gpr[5] + 4])) return NO;
        if (state->gpr[5]) range = CFRangeMake(location, length);
        BOOL converted = formatter && string && CFDateFormatterGetAbsoluteTimeFromString(
            (__bridge CFDateFormatterRef)formatter, (__bridge CFStringRef)string, &range, &absoluteTime);
        if (state->gpr[5] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[5]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[5] + 4])) return NO;
        if (converted && state->gpr[6] && ![weakSelf writeDouble:absoluteTime address:state->gpr[6]]) return NO;
        CFFinish(state, converted); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *key = [weakSelf string:state->gpr[4]];
        id value = [weakSelf object:state->gpr[5]];
        if (formatter && key) CFDateFormatterSetProperty((__bridge CFDateFormatterRef)formatter,
            (__bridge CFStringRef)key, (__bridge CFTypeRef)value);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFDateFormatterCopyProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *key = [weakSelf string:state->gpr[4]];
        CFTypeRef value = formatter && key ? CFDateFormatterCopyProperty((__bridge CFDateFormatterRef)formatter,
            (__bridge CFStringRef)key) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFNumberFormatterGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id locale = [weakSelf object:state->gpr[4]];
        CFNumberFormatterRef formatter = CFNumberFormatterCreate(kCFAllocatorDefault,
            locale ? (__bridge CFLocaleRef)locale : NULL, (CFNumberFormatterStyle)state->gpr[5]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(formatter)]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterGetLocale" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]];
        CFLocaleRef locale = formatter ? CFNumberFormatterGetLocale((__bridge CFNumberFormatterRef)formatter) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)locale]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterGetStyle" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]];
        CFFinish(state, formatter ? (uint32_t)CFNumberFormatterGetStyle((__bridge CFNumberFormatterRef)formatter) : 0);
        return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterGetFormat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]];
        CFStringRef format = formatter ? CFNumberFormatterGetFormat((__bridge CFNumberFormatterRef)formatter) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)format]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterSetFormat" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *format = [weakSelf string:state->gpr[4]];
        if (formatter && format) CFNumberFormatterSetFormat((__bridge CFNumberFormatterRef)formatter,
            (__bridge CFStringRef)format);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterCreateStringWithNumber" handler:^BOOL(BRPPCState *state,
                                                                                       NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[4]], number = [weakSelf object:state->gpr[5]];
        CFStringRef string = formatter && number ? CFNumberFormatterCreateStringWithNumber(kCFAllocatorDefault,
            (__bridge CFNumberFormatterRef)formatter, (__bridge CFNumberRef)number) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterCreateStringWithValue" handler:^BOOL(BRPPCState *state,
                                                                                      NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[4]]; int64_t integer = 0;
        double floating = 0; BOOL isFloat = NO;
        if (!formatter || ![weakSelf readNumberAtAddress:state->gpr[6] type:(CFNumberType)state->gpr[5]
                                                integer:&integer floating:&floating isFloat:&isFloat]) return NO;
        NSNumber *number = isFloat ? @(floating) : @(integer);
        CFStringRef string = CFNumberFormatterCreateStringWithNumber(kCFAllocatorDefault,
            (__bridge CFNumberFormatterRef)formatter, (__bridge CFNumberRef)number);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterCreateNumberFromString" handler:^BOOL(BRPPCState *state,
                                                                                       NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[4]]; NSString *string = [weakSelf string:state->gpr[5]];
        uint32_t location = 0, length = (uint32_t)string.length;
        if (state->gpr[6] && (![registry.memory readUInt32:&location address:state->gpr[6]] ||
            ![registry.memory readUInt32:&length address:state->gpr[6] + 4])) return NO;
        CFRange range = CFRangeMake(location, length);
        CFNumberRef number = formatter && string ? CFNumberFormatterCreateNumberFromString(kCFAllocatorDefault,
            (__bridge CFNumberFormatterRef)formatter, (__bridge CFStringRef)string, &range, state->gpr[7]) : NULL;
        if (state->gpr[6] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[6]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[6] + 4])) {
            if (number) CFRelease(number); return NO;
        }
        uint32_t numberHandle = [weakSelf handle:(__bridge id)number]; if (number) CFRelease(number);
        CFFinish(state, numberHandle); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterGetValueFromString" handler:^BOOL(BRPPCState *state,
                                                                                    NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]];
        NSString *string = [weakSelf string:state->gpr[4]]; uint32_t location = 0, length = (uint32_t)string.length;
        if (state->gpr[5] && (![registry.memory readUInt32:&location address:state->gpr[5]] ||
            ![registry.memory readUInt32:&length address:state->gpr[5] + 4])) return NO;
        CFRange range = CFRangeMake(location, length); CFNumberType requestedType = (CFNumberType)state->gpr[6];
        BOOL floatingType = requestedType == kCFNumberFloat32Type || requestedType == kCFNumberFloat64Type ||
            requestedType == kCFNumberFloatType || requestedType == kCFNumberDoubleType ||
            requestedType == kCFNumberCGFloatType;
        int64_t integer = 0; double floating = 0;
        void *output = floatingType ? (void *)&floating : (void *)&integer;
        BOOL converted = formatter && string && CFNumberFormatterGetValueFromString(
            (__bridge CFNumberFormatterRef)formatter, (__bridge CFStringRef)string, &range,
            floatingType ? kCFNumberFloat64Type : kCFNumberSInt64Type, output);
        if (state->gpr[5] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[5]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[5] + 4])) return NO;
        NSNumber *number = floatingType ? @(floating) : @(integer);
        if (converted && state->gpr[7] && ![weakSelf writeNumber:number type:requestedType address:state->gpr[7]]) return NO;
        CFFinish(state, converted); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterSetProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *key = [weakSelf string:state->gpr[4]];
        id value = [weakSelf object:state->gpr[5]];
        if (formatter && key) CFNumberFormatterSetProperty((__bridge CFNumberFormatterRef)formatter,
            (__bridge CFStringRef)key, (__bridge CFTypeRef)value);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterCopyProperty" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id formatter = [weakSelf object:state->gpr[3]]; NSString *key = [weakSelf string:state->gpr[4]];
        CFTypeRef value = formatter && key ? CFNumberFormatterCopyProperty((__bridge CFNumberFormatterRef)formatter,
            (__bridge CFStringRef)key) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFNumberFormatterGetDecimalInfoForCurrencyCode"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *code = [weakSelf string:state->gpr[3]]; int32_t digits = 0;
            double increment = 0; BOOL found = code && CFNumberFormatterGetDecimalInfoForCurrencyCode(
                (__bridge CFStringRef)code, &digits, &increment);
            if (found && state->gpr[4] && ![registry.memory writeUInt32:(uint32_t)digits address:state->gpr[4]]) return NO;
            if (found && state->gpr[5] && ![weakSelf writeDouble:increment address:state->gpr[5]]) return NO;
            CFFinish(state, found); return YES;
        }];
    [registry registerSymbol:@"_CFTimeZoneGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFTimeZoneGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCopySystem" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSTimeZone systemTimeZone]]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCopyDefault" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[NSTimeZone defaultTimeZone]]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneResetSystem" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFTimeZoneResetSystem(); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneSetDefault" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id zone = [weakSelf object:state->gpr[3]];
        if (zone) CFTimeZoneSetDefault((__bridge CFTimeZoneRef)zone); CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCopyKnownNames" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:CFBridgingRelease(CFTimeZoneCopyKnownNames())]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCopyAbbreviationDictionary" handler:^BOOL(BRPPCState *state,
                                                                                     NSError **callError) {
        (void)callError; CFFinish(state,
            [weakSelf handle:CFBridgingRelease(CFTimeZoneCopyAbbreviationDictionary())]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneSetAbbreviationDictionary" handler:^BOOL(BRPPCState *state,
                                                                                    NSError **callError) {
        (void)callError; NSDictionary *dictionary = [weakSelf object:state->gpr[3]];
        if (dictionary) CFTimeZoneSetAbbreviationDictionary((__bridge CFDictionaryRef)dictionary);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *name = [weakSelf string:state->gpr[4]]; NSData *data = [weakSelf object:state->gpr[5]];
        CFTimeZoneRef zone = name && data ? CFTimeZoneCreate(kCFAllocatorDefault,
            (__bridge CFStringRef)name, (__bridge CFDataRef)data) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(zone)]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCreateWithTimeIntervalFromGMT" handler:^BOOL(BRPPCState *state,
                                                                                       NSError **callError) {
        (void)callError; CFTimeZoneRef zone = CFTimeZoneCreateWithTimeIntervalFromGMT(kCFAllocatorDefault,
            state->fpr[1]); CFFinish(state, [weakSelf handle:CFBridgingRelease(zone)]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCreateWithName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSTimeZone *zone = [NSTimeZone timeZoneWithName:[weakSelf string:state->gpr[4]] ?: @""];
        CFFinish(state, [weakSelf handle:zone]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneGetName" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:[[weakSelf object:state->gpr[3]] name]]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneGetData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id zone = [weakSelf object:state->gpr[3]];
        CFFinish(state, zone ? [weakSelf handle:(__bridge id)CFTimeZoneGetData((__bridge CFTimeZoneRef)zone)] : 0);
        return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneGetSecondsFromGMT" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSTimeZone *zone = [weakSelf object:state->gpr[3]];
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:state->fpr[1]];
        CFFinish(state, (uint32_t)[zone secondsFromGMTForDate:date]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneCopyAbbreviation" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id zone = [weakSelf object:state->gpr[3]];
        CFStringRef value = zone ? CFTimeZoneCopyAbbreviation((__bridge CFTimeZoneRef)zone, state->fpr[1]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFTimeZoneIsDaylightSavingTime" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; id zone = [weakSelf object:state->gpr[3]];
        CFFinish(state, zone && CFTimeZoneIsDaylightSavingTime((__bridge CFTimeZoneRef)zone, state->fpr[1]));
        return YES;
    }];
    for (NSString *symbol in @[@"_CFTimeZoneGetDaylightSavingTimeOffset",
                                @"_CFTimeZoneGetNextDaylightSavingTimeTransition"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id zone = [weakSelf object:state->gpr[3]]; double value = 0;
            if (zone) value = [symbol containsString:@"Offset"]
                ? CFTimeZoneGetDaylightSavingTimeOffset((__bridge CFTimeZoneRef)zone, state->fpr[1])
                : CFTimeZoneGetNextDaylightSavingTimeTransition((__bridge CFTimeZoneRef)zone, state->fpr[1]);
            state->fpr[1] = value; state->pc = state->lr; return YES;
        }];
    }
    [registry registerSymbol:@"_CFTimeZoneCopyLocalizedName" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; id zone = [weakSelf object:state->gpr[3]], locale = [weakSelf object:state->gpr[5]];
        CFStringRef name = zone && locale ? CFTimeZoneCopyLocalizedName((__bridge CFTimeZoneRef)zone,
            (CFTimeZoneNameStyle)state->gpr[4], (__bridge CFLocaleRef)locale) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(name)]); return YES;
    }];

    [registry registerSymbol:@"_CFUUIDGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFUUIDGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFUUIDCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:CFBridgingRelease(
            CFUUIDCreate(kCFAllocatorDefault))]); return YES;
    }];
    [registry registerSymbol:@"_CFUUIDCreateFromString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFUUIDRef UUID = CFUUIDCreateFromString(kCFAllocatorDefault,
            (__bridge CFStringRef)([weakSelf string:state->gpr[4]] ?: @""));
        CFFinish(state, [weakSelf handle:CFBridgingRelease(UUID)]); return YES;
    }];
    [registry registerSymbol:@"_CFUUIDCreateString" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id UUID = [weakSelf object:state->gpr[4]]; CFStringRef string = UUID
            ? CFUUIDCreateString(kCFAllocatorDefault, (__bridge CFUUIDRef)UUID) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
    }];
    [registry registerSymbol:@"_CFUUIDGetUUIDBytes" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id UUID = [weakSelf object:state->gpr[4]]; if (!UUID) return NO;
        CFUUIDBytes value = CFUUIDGetUUIDBytes((__bridge CFUUIDRef)UUID);
        uint8_t bytes[16] = {value.byte0, value.byte1, value.byte2, value.byte3, value.byte4, value.byte5,
            value.byte6, value.byte7, value.byte8, value.byte9, value.byte10, value.byte11, value.byte12,
            value.byte13, value.byte14, value.byte15};
        if (![registry.memory writeBytes:bytes address:state->gpr[3] length:sizeof(bytes)]) return NO;
        state->gpr[3] = state->gpr[3]; state->pc = state->lr; return YES;
    }];
    BRPPCResolvedCall UUIDWithByteArguments = ^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; uint8_t bytes[16] = {0}; NSUInteger cursor = 4;
        for (NSUInteger index = 0; index < 16; index++) { uint32_t value = 0;
            if (![weakSelf readGuestWord:&value state:state cursor:&cursor]) return NO; bytes[index] = value; }
        CFUUIDRef UUID = NULL;
        if (state->pc == [registry addressForSymbol:@"_CFUUIDGetConstantUUIDWithBytes"]) {
            NSData *key = [NSData dataWithBytes:bytes length:16]; id existing = weakSelf.constantUUIDs[key];
            if (existing) { CFFinish(state, [weakSelf handle:existing]); return YES; }
            UUID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12],
                bytes[13], bytes[14], bytes[15]); id object = (__bridge id)UUID;
            weakSelf.constantUUIDs[key] = object; CFFinish(state, [weakSelf handle:object]); return YES;
        }
        UUID = CFUUIDCreateWithBytes(kCFAllocatorDefault, bytes[0], bytes[1], bytes[2], bytes[3], bytes[4],
            bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13],
            bytes[14], bytes[15]); CFFinish(state, [weakSelf handle:CFBridgingRelease(UUID)]); return YES;
    };
    [registry registerSymbol:@"_CFUUIDCreateWithBytes" handler:UUIDWithByteArguments];
    [registry registerSymbol:@"_CFUUIDGetConstantUUIDWithBytes" handler:UUIDWithByteArguments];
    [registry registerSymbol:@"_CFUUIDCreateFromUUIDBytes" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; uint8_t bytes[16];
        for (NSUInteger index = 0; index < 4; index++) {
            uint32_t word = state->gpr[4 + index]; bytes[index * 4] = (uint8_t)(word >> 24);
            bytes[index * 4 + 1] = (uint8_t)(word >> 16); bytes[index * 4 + 2] = (uint8_t)(word >> 8);
            bytes[index * 4 + 3] = (uint8_t)word;
        }
        CFUUIDBytes value = {bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]};
        CFFinish(state, [weakSelf handle:CFBridgingRelease(
            CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, value))]); return YES;
    }];

    [registry registerSymbol:@"_CFPreferencesCopyAppValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFPropertyListRef value = CFPreferencesCopyAppValue(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesSetAppValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id value = [weakSelf object:state->gpr[4]];
        CFPreferencesSetAppValue((__bridge CFStringRef)[weakSelf string:state->gpr[3]],
                                 (__bridge CFPropertyListRef)value,
                                 (__bridge CFStringRef)[weakSelf string:state->gpr[5]]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesGetAppBooleanValue"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; Boolean valid = false; CFIndex value = CFPreferencesGetAppBooleanValue(
                (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]], &valid);
            if (state->gpr[5] && ![registry.memory writeBytes:&valid address:state->gpr[5] length:1]) return NO;
            CFFinish(state, (uint32_t)value); return YES;
        }];
    [registry registerSymbol:@"_CFPreferencesGetAppIntegerValue"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; Boolean valid = false; CFIndex value = CFPreferencesGetAppIntegerValue(
                (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]], &valid);
            if (state->gpr[5] && ![registry.memory writeBytes:&valid address:state->gpr[5] length:1]) return NO;
            CFFinish(state, (uint32_t)value); return YES;
        }];
    for (NSString *symbol in @[@"_CFPreferencesAddSuitePreferencesToApp",
                                 @"_CFPreferencesRemoveSuitePreferencesFromApp"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFStringRef application = (__bridge CFStringRef)[weakSelf string:state->gpr[3]];
            CFStringRef suite = (__bridge CFStringRef)[weakSelf string:state->gpr[4]];
            if ([symbol containsString:@"Remove"]) CFPreferencesRemoveSuitePreferencesFromApp(application, suite);
            else CFPreferencesAddSuitePreferencesToApp(application, suite);
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFPreferencesAppSynchronize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, CFPreferencesAppSynchronize(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]])); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesCopyValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFPropertyListRef value = CFPreferencesCopyValue(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[6]]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesCopyMultiple" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; CFDictionaryRef values = CFPreferencesCopyMultiple(
            (__bridge CFArrayRef)[weakSelf object:state->gpr[3]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[6]]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(values)]); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesSetValue" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFPreferencesSetValue(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
            (__bridge CFPropertyListRef)[weakSelf object:state->gpr[4]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[7]]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesSetMultiple" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; CFPreferencesSetMultiple(
            (__bridge CFDictionaryRef)[weakSelf object:state->gpr[3]],
            (__bridge CFArrayRef)[weakSelf object:state->gpr[4]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[7]]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesSynchronize" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, CFPreferencesSynchronize(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]])); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesCopyApplicationList"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFArrayRef (*CopyApplicationListFunction)(CFStringRef, CFStringRef);
            CopyApplicationListFunction function = (CopyApplicationListFunction)dlsym(RTLD_DEFAULT,
                "CFPreferencesCopyApplicationList"); CFArrayRef values = function ? function(
                    (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
                    (__bridge CFStringRef)[weakSelf string:state->gpr[4]]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(values)]); return YES;
        }];
    [registry registerSymbol:@"_CFPreferencesCopyKeyList" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; CFArrayRef values = CFPreferencesCopyKeyList(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]]);
        CFFinish(state, [weakSelf handle:CFBridgingRelease(values)]); return YES;
    }];
    [registry registerSymbol:@"_CFPreferencesAppValueIsForced" handler:^BOOL(BRPPCState *state,
                                                                                NSError **callError) {
        (void)callError; CFFinish(state, CFPreferencesAppValueIsForced(
            (__bridge CFStringRef)[weakSelf string:state->gpr[3]],
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]])); return YES;
    }];

    [registry registerSymbol:@"_CFSocketGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFSocketGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFSocketCreate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        BRPPCGuestSocketRecord *record = [weakSelf socketRecordAtAddress:state->gpr[9]
                                                                 callout:state->gpr[8] state:*state];
        if (!record) return NO; CFSocketContext context = {0, (__bridge void *)record,
            RetainSocketContext, ReleaseSocketContext, CopySocketContextDescription};
        weakSelf.pendingCallbackError = nil; CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault,
            (SInt32)state->gpr[4], (SInt32)state->gpr[5], (SInt32)state->gpr[6], state->gpr[7],
            record.callout ? DeliverSocketEvent : NULL, (record.callout || state->gpr[9]) ? &context : NULL);
        if (weakSelf.pendingCallbackError) { if (socket) CFRelease(socket);
            if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        uint32_t handle = [weakSelf handle:CFBridgingRelease(socket)]; record.handle = handle;
        if (handle) weakSelf.socketRecords[@(handle)] = record; CFFinish(state, handle); return YES;
    }];
    [registry registerSymbol:@"_CFSocketCreateWithNative" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        BRPPCGuestSocketRecord *record = [weakSelf socketRecordAtAddress:state->gpr[7]
                                                                 callout:state->gpr[6] state:*state];
        if (!record) return NO; CFSocketContext context = {0, (__bridge void *)record,
            RetainSocketContext, ReleaseSocketContext, CopySocketContextDescription};
        weakSelf.pendingCallbackError = nil; CFSocketRef socket = CFSocketCreateWithNative(kCFAllocatorDefault,
            (CFSocketNativeHandle)(int32_t)state->gpr[4], state->gpr[5],
            record.callout ? DeliverSocketEvent : NULL, (record.callout || state->gpr[7]) ? &context : NULL);
        if (weakSelf.pendingCallbackError) { if (socket) CFRelease(socket);
            if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        uint32_t handle = [weakSelf handle:CFBridgingRelease(socket)]; record.handle = handle;
        if (handle) weakSelf.socketRecords[@(handle)] = record; CFFinish(state, handle); return YES;
    }];
    for (NSString *symbol in @[@"_CFSocketCreateWithSocketSignature",
                                 @"_CFSocketCreateConnectedToSocketSignature"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            CFSocketSignature signature = {0}; if (![weakSelf readSocketSignature:&signature
                                                                          address:state->gpr[4]]) return NO;
            BRPPCGuestSocketRecord *record = [weakSelf socketRecordAtAddress:state->gpr[7]
                                                                     callout:state->gpr[6] state:*state];
            if (!record) return NO; CFSocketContext context = {0, (__bridge void *)record,
                RetainSocketContext, ReleaseSocketContext, CopySocketContextDescription};
            weakSelf.pendingCallbackError = nil; CFSocketRef socket = [symbol containsString:@"Connected"]
                ? CFSocketCreateConnectedToSocketSignature(kCFAllocatorDefault, &signature, state->gpr[5],
                    record.callout ? DeliverSocketEvent : NULL,
                    (record.callout || state->gpr[7]) ? &context : NULL, state->fpr[1])
                : CFSocketCreateWithSocketSignature(kCFAllocatorDefault, &signature, state->gpr[5],
                    record.callout ? DeliverSocketEvent : NULL,
                    (record.callout || state->gpr[7]) ? &context : NULL);
            if (weakSelf.pendingCallbackError) { if (socket) CFRelease(socket);
                if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
            uint32_t handle = [weakSelf handle:CFBridgingRelease(socket)]; record.handle = handle;
            if (handle) weakSelf.socketRecords[@(handle)] = record; CFFinish(state, handle); return YES;
        }];
    }
    [registry registerSymbol:@"_CFSocketSetAddress" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]], address = [weakSelf object:state->gpr[4]];
        CFFinish(state, socket && address ? (uint32_t)CFSocketSetAddress((__bridge CFSocketRef)socket,
            (__bridge CFDataRef)address) : (uint32_t)kCFSocketError); return YES;
    }];
    [registry registerSymbol:@"_CFSocketConnectToAddress" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]], address = [weakSelf object:state->gpr[4]];
        CFFinish(state, socket && address ? (uint32_t)CFSocketConnectToAddress((__bridge CFSocketRef)socket,
            (__bridge CFDataRef)address, state->fpr[1]) : (uint32_t)kCFSocketError); return YES;
    }];
    [registry registerSymbol:@"_CFSocketInvalidate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        id socket = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
        if (socket) CFSocketInvalidate((__bridge CFSocketRef)socket);
        if (weakSelf.pendingCallbackError) { if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFSocketIsValid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]];
        CFFinish(state, socket && CFSocketIsValid((__bridge CFSocketRef)socket)); return YES;
    }];
    for (NSString *symbol in @[@"_CFSocketCopyAddress", @"_CFSocketCopyPeerAddress"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id socket = [weakSelf object:state->gpr[3]]; CFDataRef address = NULL;
            if (socket) address = [symbol containsString:@"Peer"]
                ? CFSocketCopyPeerAddress((__bridge CFSocketRef)socket)
                : CFSocketCopyAddress((__bridge CFSocketRef)socket);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(address)]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFSocketGetContext" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; BRPPCGuestSocketRecord *record = weakSelf.socketRecords[@(state->gpr[3])];
        uint32_t address = state->gpr[4]; if (!record || !address) return NO;
        uint32_t words[5] = {0, record.info, record.retainFunction,
            record.releaseFunction, record.descriptionFunction};
        for (NSUInteger index = 0; index < 5; index++)
            if (![registry.memory writeUInt32:words[index] address:address + (uint32_t)index * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFSocketGetNative" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]];
        CFFinish(state, socket ? (uint32_t)CFSocketGetNative((__bridge CFSocketRef)socket) : UINT32_MAX); return YES;
    }];
    [registry registerSymbol:@"_CFSocketCreateRunLoopSource" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[4]]; CFRunLoopSourceRef source = socket
            ? CFSocketCreateRunLoopSource(kCFAllocatorDefault, (__bridge CFSocketRef)socket,
                (CFIndex)(int32_t)state->gpr[5]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(source)]); return YES;
    }];
    [registry registerSymbol:@"_CFSocketGetSocketFlags" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]];
        CFFinish(state, socket ? (uint32_t)CFSocketGetSocketFlags((__bridge CFSocketRef)socket) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFSocketSetSocketFlags" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]];
        if (socket) CFSocketSetSocketFlags((__bridge CFSocketRef)socket, state->gpr[4]);
        CFFinish(state, 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFSocketDisableCallBacks", @"_CFSocketEnableCallBacks"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id socket = [weakSelf object:state->gpr[3]];
            if (socket && [symbol containsString:@"Disable"])
                CFSocketDisableCallBacks((__bridge CFSocketRef)socket, state->gpr[4]);
            else if (socket) CFSocketEnableCallBacks((__bridge CFSocketRef)socket, state->gpr[4]);
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFSocketSendData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id socket = [weakSelf object:state->gpr[3]], address = [weakSelf object:state->gpr[4]];
        id data = [weakSelf object:state->gpr[5]]; CFSocketError result = socket && data
            ? CFSocketSendData((__bridge CFSocketRef)socket, (__bridge CFDataRef)address,
                (__bridge CFDataRef)data, state->fpr[1]) : kCFSocketError;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFSocketRegisterValue" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; CFSocketSignature server = {0}; CFSocketSignature *serverPointer = NULL;
        if (state->gpr[3]) { if (![weakSelf readSocketSignature:&server address:state->gpr[3]]) return NO;
            serverPointer = &server; }
        CFSocketError result = CFSocketRegisterValue(serverPointer, state->fpr[1],
            (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
            (__bridge CFPropertyListRef)[weakSelf object:state->gpr[7]]);
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFSocketCopyRegisteredValue" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; CFSocketSignature server = {0}; CFSocketSignature *serverPointer = NULL;
        if (state->gpr[3]) { if (![weakSelf readSocketSignature:&server address:state->gpr[3]]) return NO;
            serverPointer = &server; }
        CFPropertyListRef value = NULL; CFDataRef address = NULL; CFSocketError result =
            CFSocketCopyRegisteredValue(serverPointer, state->fpr[1],
                (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
                state->gpr[7] ? &value : NULL, state->gpr[8] ? &address : NULL);
        id valueObject = CFBridgingRelease(value), addressObject = CFBridgingRelease(address);
        if ((state->gpr[7] && ![registry.memory writeUInt32:[weakSelf handle:valueObject] address:state->gpr[7]]) ||
            (state->gpr[8] && ![registry.memory writeUInt32:[weakSelf handle:addressObject] address:state->gpr[8]]))
            return NO;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFSocketRegisterSocketSignature"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFSocketSignature server = {0}, value = {0};
            CFSocketSignature *serverPointer = NULL;
            if (state->gpr[3]) { if (![weakSelf readSocketSignature:&server address:state->gpr[3]]) return NO;
                serverPointer = &server; }
            if (![weakSelf readSocketSignature:&value address:state->gpr[7]]) return NO;
            CFFinish(state, (uint32_t)CFSocketRegisterSocketSignature(serverPointer, state->fpr[1],
                (__bridge CFStringRef)[weakSelf string:state->gpr[6]], &value)); return YES;
        }];
    [registry registerSymbol:@"_CFSocketCopyRegisteredSocketSignature"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFSocketSignature server = {0}, value = {0};
            CFSocketSignature *serverPointer = NULL;
            if (state->gpr[3]) { if (![weakSelf readSocketSignature:&server address:state->gpr[3]]) return NO;
                serverPointer = &server; }
            CFDataRef serverAddress = NULL; CFSocketError result = CFSocketCopyRegisteredSocketSignature(
                serverPointer, state->fpr[1], (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
                state->gpr[7] ? &value : NULL, state->gpr[8] ? &serverAddress : NULL);
            id valueAddress = value.address ? CFBridgingRelease(value.address) : nil;
            id serverAddressObject = CFBridgingRelease(serverAddress);
            if (state->gpr[7]) { uint32_t words[4] = {(uint32_t)value.protocolFamily,
                (uint32_t)value.socketType, (uint32_t)value.protocol, [weakSelf handle:valueAddress]};
                for (NSUInteger index = 0; index < 4; index++)
                    if (![registry.memory writeUInt32:words[index]
                                              address:state->gpr[7] + (uint32_t)index * 4]) return NO; }
            if (state->gpr[8] && ![registry.memory writeUInt32:[weakSelf handle:serverAddressObject]
                                                        address:state->gpr[8]]) return NO;
            CFFinish(state, (uint32_t)result); return YES;
        }];
    [registry registerSymbol:@"_CFSocketUnregister" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFSocketSignature server = {0}; CFSocketSignature *serverPointer = NULL;
        if (state->gpr[3]) { if (![weakSelf readSocketSignature:&server address:state->gpr[3]]) return NO;
            serverPointer = &server; }
        CFFinish(state, (uint32_t)CFSocketUnregister(serverPointer, state->fpr[1],
            (__bridge CFStringRef)[weakSelf string:state->gpr[6]])); return YES;
    }];
    [registry registerSymbol:@"_CFSocketSetDefaultNameRegistryPortNumber"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFSocketSetDefaultNameRegistryPortNumber((UInt16)state->gpr[3]);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFSocketGetDefaultNameRegistryPortNumber"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFFinish(state, CFSocketGetDefaultNameRegistryPortNumber()); return YES;
        }];
    [registry registerSymbol:@"_CFFileDescriptorGetTypeID"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFFinish(state, (uint32_t)CFFileDescriptorGetTypeID()); return YES;
        }];
    [registry registerSymbol:@"_CFFileDescriptorCreate" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        BRPPCGuestFileDescriptorRecord *record = [weakSelf
            fileDescriptorRecordAtAddress:state->gpr[7] callout:state->gpr[6] state:*state];
        if (!record) return NO;
        CFFileDescriptorContext context = {0, (__bridge void *)record, RetainFileDescriptorContext,
            ReleaseFileDescriptorContext, CopyFileDescriptorContextDescription};
        weakSelf.pendingCallbackError = nil;
        CFFileDescriptorRef descriptor = CFFileDescriptorCreate(kCFAllocatorDefault,
            (CFFileDescriptorNativeDescriptor)(int32_t)state->gpr[4], state->gpr[5] != 0,
            record.callout ? DeliverFileDescriptorEvent : NULL,
            (record.callout || state->gpr[7]) ? &context : NULL);
        if (weakSelf.pendingCallbackError) { if (descriptor) CFRelease(descriptor);
            if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        uint32_t handle = [weakSelf handle:CFBridgingRelease(descriptor)]; record.handle = handle;
        if (handle) weakSelf.fileDescriptorRecords[@(handle)] = record;
        CFFinish(state, handle); return YES;
    }];
    [registry registerSymbol:@"_CFFileDescriptorGetNativeDescriptor"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id descriptor = [weakSelf object:state->gpr[3]];
            CFFinish(state, descriptor ? (uint32_t)CFFileDescriptorGetNativeDescriptor(
                (__bridge CFFileDescriptorRef)descriptor) : UINT32_MAX); return YES;
        }];
    [registry registerSymbol:@"_CFFileDescriptorGetContext"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCGuestFileDescriptorRecord *record =
                weakSelf.fileDescriptorRecords[@(state->gpr[3])]; uint32_t address = state->gpr[4];
            if (!record || !address) return NO;
            uint32_t words[5] = {0, record.info, record.retainFunction,
                record.releaseFunction, record.descriptionFunction};
            for (NSUInteger index = 0; index < 5; index++)
                if (![registry.memory writeUInt32:words[index]
                                          address:address + (uint32_t)index * 4]) return NO;
            CFFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_CFFileDescriptorEnableCallBacks",
                                 @"_CFFileDescriptorDisableCallBacks"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id descriptor = [weakSelf object:state->gpr[3]];
            if (descriptor && [symbol containsString:@"Enable"])
                CFFileDescriptorEnableCallBacks((__bridge CFFileDescriptorRef)descriptor, state->gpr[4]);
            else if (descriptor)
                CFFileDescriptorDisableCallBacks((__bridge CFFileDescriptorRef)descriptor, state->gpr[4]);
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFFileDescriptorInvalidate"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            id descriptor = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
            if (descriptor) CFFileDescriptorInvalidate((__bridge CFFileDescriptorRef)descriptor);
            if (weakSelf.pendingCallbackError) {
                if (callError) *callError = weakSelf.pendingCallbackError; return NO;
            }
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFFileDescriptorIsValid"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id descriptor = [weakSelf object:state->gpr[3]];
            CFFinish(state, descriptor && CFFileDescriptorIsValid(
                (__bridge CFFileDescriptorRef)descriptor)); return YES;
        }];
    [registry registerSymbol:@"_CFFileDescriptorCreateRunLoopSource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id descriptor = [weakSelf object:state->gpr[4]];
            CFRunLoopSourceRef source = descriptor ? CFFileDescriptorCreateRunLoopSource(
                kCFAllocatorDefault, (__bridge CFFileDescriptorRef)descriptor,
                (CFIndex)(int32_t)state->gpr[5]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(source)]); return YES;
        }];
    [registry registerSymbol:@"_CFFileSecurityGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFFileSecurityGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFFileSecurityCreate" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:CFBridgingRelease(
            CFFileSecurityCreate(kCFAllocatorDefault))]); return YES;
    }];
    [registry registerSymbol:@"_CFFileSecurityCreateCopy" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; id security = [weakSelf object:state->gpr[4]];
        CFFileSecurityRef copy = security ? CFFileSecurityCreateCopy(kCFAllocatorDefault,
            (__bridge CFFileSecurityRef)security) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    for (NSString *symbol in @[@"_CFFileSecurityCopyOwnerUUID", @"_CFFileSecurityCopyGroupUUID"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]]; CFUUIDRef UUID = NULL;
            Boolean result = security && ([symbol containsString:@"Owner"]
                ? CFFileSecurityCopyOwnerUUID((__bridge CFFileSecurityRef)security, &UUID)
                : CFFileSecurityCopyGroupUUID((__bridge CFFileSecurityRef)security, &UUID));
            if (state->gpr[4] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(UUID)]
                                                    address:state->gpr[4]]) return NO;
            CFFinish(state, result); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFFileSecuritySetOwnerUUID", @"_CFFileSecuritySetGroupUUID"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]], UUID = [weakSelf object:state->gpr[4]];
            Boolean result = security && UUID && ([symbol containsString:@"Owner"]
                ? CFFileSecuritySetOwnerUUID((__bridge CFFileSecurityRef)security, (__bridge CFUUIDRef)UUID)
                : CFFileSecuritySetGroupUUID((__bridge CFFileSecurityRef)security, (__bridge CFUUIDRef)UUID));
            CFFinish(state, result); return YES;
        }];
    }
    [registry registerSymbol:@"_CFFileSecurityCopyAccessControlList"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]]; acl_t ACL = NULL;
            Boolean result = security && CFFileSecurityCopyAccessControlList(
                (__bridge CFFileSecurityRef)security, &ACL); uint32_t handle = result ? [weakSelf registerACL:ACL] : 0;
            if (state->gpr[4] && ![registry.memory writeUInt32:handle address:state->gpr[4]]) {
                if (handle) { acl_free(ACL); [weakSelf.aclRecords removeObjectForKey:@(handle)]; } return NO;
            }
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFFileSecuritySetAccessControlList"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]];
            acl_t ACL = [weakSelf ACLForHandle:state->gpr[4]];
            CFFinish(state, security && (state->gpr[4] == 0 || ACL) && CFFileSecuritySetAccessControlList(
                (__bridge CFFileSecurityRef)security, ACL)); return YES;
        }];
    for (NSString *symbol in @[@"_CFFileSecurityGetOwner", @"_CFFileSecurityGetGroup",
                                 @"_CFFileSecurityGetMode"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]]; uint32_t value = 0;
            Boolean result = NO; if (security) result = [symbol containsString:@"Owner"]
                ? CFFileSecurityGetOwner((__bridge CFFileSecurityRef)security, (uid_t *)&value)
                : [symbol containsString:@"Group"]
                    ? CFFileSecurityGetGroup((__bridge CFFileSecurityRef)security, (gid_t *)&value)
                    : CFFileSecurityGetMode((__bridge CFFileSecurityRef)security, (mode_t *)&value);
            if (result && state->gpr[4] && ![registry.memory writeUInt32:value address:state->gpr[4]]) return NO;
            CFFinish(state, result); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFFileSecuritySetOwner", @"_CFFileSecuritySetGroup",
                                 @"_CFFileSecuritySetMode"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]]; Boolean result = NO;
            if (security) result = [symbol containsString:@"Owner"]
                ? CFFileSecuritySetOwner((__bridge CFFileSecurityRef)security, (uid_t)state->gpr[4])
                : [symbol containsString:@"Group"]
                    ? CFFileSecuritySetGroup((__bridge CFFileSecurityRef)security, (gid_t)state->gpr[4])
                    : CFFileSecuritySetMode((__bridge CFFileSecurityRef)security, (mode_t)state->gpr[4]);
            CFFinish(state, result); return YES;
        }];
    }
    [registry registerSymbol:@"_CFFileSecurityClearProperties"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id security = [weakSelf object:state->gpr[3]];
            CFFinish(state, security && CFFileSecurityClearProperties((__bridge CFFileSecurityRef)security,
                state->gpr[4])); return YES;
        }];
    [registry registerSymbol:@"_acl_free" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; acl_t ACL = [weakSelf ACLForHandle:state->gpr[3]];
        if (!ACL || state->gpr[3] == UINT32_MAX) { CFFinish(state, UINT32_MAX); return YES; }
        int result = acl_free(ACL); if (!result) [weakSelf.aclRecords removeObjectForKey:@(state->gpr[3])];
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreateDataAndPropertiesFromResource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef Boolean (*Function)(CFAllocatorRef, CFURLRef, CFDataRef *,
                CFDictionaryRef *, CFArrayRef, SInt32 *); Function function = (Function)dlsym(
                    RTLD_DEFAULT, "CFURLCreateDataAndPropertiesFromResource");
            id URL = [weakSelf object:state->gpr[4]], desired = [weakSelf object:state->gpr[7]];
            CFDataRef data = NULL; CFDictionaryRef properties = NULL; SInt32 code = 0;
            Boolean result = function && URL && function(kCFAllocatorDefault, (__bridge CFURLRef)URL,
                state->gpr[5] ? &data : NULL, state->gpr[6] ? &properties : NULL,
                (__bridge CFArrayRef)desired, state->gpr[8] ? &code : NULL);
            id dataObject = CFBridgingRelease(data), propertiesObject = CFBridgingRelease(properties);
            if ((state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:dataObject]
                                                        address:state->gpr[5]]) ||
                (state->gpr[6] && ![registry.memory writeUInt32:[weakSelf handle:propertiesObject]
                                                        address:state->gpr[6]]) ||
                (state->gpr[8] && ![registry.memory writeUInt32:(uint32_t)code address:state->gpr[8]])) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFURLWriteDataAndPropertiesToResource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef Boolean (*Function)(CFURLRef, CFDataRef, CFDictionaryRef, SInt32 *);
            Function function = (Function)dlsym(RTLD_DEFAULT, "CFURLWriteDataAndPropertiesToResource");
            id URL = [weakSelf object:state->gpr[3]], data = [weakSelf object:state->gpr[4]];
            id properties = [weakSelf object:state->gpr[5]]; SInt32 code = 0;
            Boolean result = function && URL && function((__bridge CFURLRef)URL, (__bridge CFDataRef)data,
                (__bridge CFDictionaryRef)properties, state->gpr[6] ? &code : NULL);
            if (state->gpr[6] && ![registry.memory writeUInt32:(uint32_t)code address:state->gpr[6]]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFURLDestroyResource" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        (void)callError; typedef Boolean (*Function)(CFURLRef, SInt32 *);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFURLDestroyResource");
        id URL = [weakSelf object:state->gpr[3]]; SInt32 code = 0; Boolean result = function && URL &&
            function((__bridge CFURLRef)URL, state->gpr[4] ? &code : NULL);
        if (state->gpr[4] && ![registry.memory writeUInt32:(uint32_t)code address:state->gpr[4]]) return NO;
        CFFinish(state, result); return YES;
    }];
    [registry registerSymbol:@"_CFURLCreatePropertyFromResource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFTypeRef (*Function)(CFAllocatorRef, CFURLRef, CFStringRef, SInt32 *);
            Function function = (Function)dlsym(RTLD_DEFAULT, "CFURLCreatePropertyFromResource");
            id URL = [weakSelf object:state->gpr[4]]; SInt32 code = 0; CFTypeRef property = function && URL
                ? function(kCFAllocatorDefault, (__bridge CFURLRef)URL,
                    (__bridge CFStringRef)[weakSelf string:state->gpr[5]], state->gpr[6] ? &code : NULL) : NULL;
            if (state->gpr[6] && ![registry.memory writeUInt32:(uint32_t)code address:state->gpr[6]]) {
                if (property) CFRelease(property); return NO; }
            CFFinish(state, [weakSelf handle:CFBridgingRelease(property)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLEnumeratorGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFURLEnumeratorGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFURLEnumeratorCreateForDirectoryURL"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id URL = [weakSelf object:state->gpr[4]], keys = [weakSelf object:state->gpr[6]];
            CFURLEnumeratorRef enumerator = URL ? CFURLEnumeratorCreateForDirectoryURL(kCFAllocatorDefault,
                (__bridge CFURLRef)URL, state->gpr[5], (__bridge CFArrayRef)keys) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(enumerator)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLEnumeratorCreateForMountedVolumes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id keys = [weakSelf object:state->gpr[5]];
            CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForMountedVolumes(kCFAllocatorDefault,
                state->gpr[4], (__bridge CFArrayRef)keys);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(enumerator)]); return YES;
        }];
    [registry registerSymbol:@"_CFURLEnumeratorGetNextURL" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; id enumerator = [weakSelf object:state->gpr[3]]; CFURLRef URL = NULL;
        CFErrorRef createdError = NULL; CFURLEnumeratorResult result = enumerator
            ? CFURLEnumeratorGetNextURL((__bridge CFURLEnumeratorRef)enumerator,
                state->gpr[4] ? &URL : NULL, state->gpr[5] ? &createdError : NULL)
            : kCFURLEnumeratorError;
        id URLObject = (__bridge id)URL, errorObject = CFBridgingRelease(createdError);
        if ((state->gpr[4] && ![registry.memory writeUInt32:[weakSelf handle:URLObject]
                                                    address:state->gpr[4]]) ||
            (state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:errorObject]
                                                    address:state->gpr[5]])) return NO;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFURLEnumeratorSkipDescendents"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id enumerator = [weakSelf object:state->gpr[3]];
            if (enumerator) CFURLEnumeratorSkipDescendents((__bridge CFURLEnumeratorRef)enumerator);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFURLEnumeratorGetDescendentLevel"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id enumerator = [weakSelf object:state->gpr[3]];
            CFFinish(state, enumerator ? (uint32_t)CFURLEnumeratorGetDescendentLevel(
                (__bridge CFURLEnumeratorRef)enumerator) : 0); return YES;
        }];
    [registry registerSymbol:@"_CFURLEnumeratorGetSourceDidChange"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef Boolean (*Function)(CFURLEnumeratorRef);
            Function function = (Function)dlsym(RTLD_DEFAULT, "CFURLEnumeratorGetSourceDidChange");
            id enumerator = [weakSelf object:state->gpr[3]];
            CFFinish(state, function && enumerator && function((__bridge CFURLEnumeratorRef)enumerator));
            return YES;
        }];
    [registry registerSymbol:@"_CFStringTokenizerCopyBestStringLanguage"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
            CFStringRef language = string ? CFStringTokenizerCopyBestStringLanguage(
                (__bridge CFStringRef)string, CFRangeMake((CFIndex)(int32_t)state->gpr[4],
                    (CFIndex)(int32_t)state->gpr[5])) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(language)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringTokenizerGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFStringTokenizerGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFStringTokenizerCreate" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[4]];
        id locale = [weakSelf object:state->gpr[8]]; CFStringTokenizerRef tokenizer = string
            ? CFStringTokenizerCreate(kCFAllocatorDefault, (__bridge CFStringRef)string,
                CFRangeMake((CFIndex)(int32_t)state->gpr[5], (CFIndex)(int32_t)state->gpr[6]),
                state->gpr[7], (__bridge CFLocaleRef)locale) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(tokenizer)]); return YES;
    }];
    [registry registerSymbol:@"_CFStringTokenizerSetString" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; id tokenizer = [weakSelf object:state->gpr[3]];
        NSString *string = [weakSelf string:state->gpr[4]];
        if (tokenizer && string) CFStringTokenizerSetString((__bridge CFStringTokenizerRef)tokenizer,
            (__bridge CFStringRef)string, CFRangeMake((CFIndex)(int32_t)state->gpr[5],
                (CFIndex)(int32_t)state->gpr[6]));
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringTokenizerGoToTokenAtIndex"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tokenizer = [weakSelf object:state->gpr[3]];
            CFFinish(state, tokenizer ? (uint32_t)CFStringTokenizerGoToTokenAtIndex(
                (__bridge CFStringTokenizerRef)tokenizer, (CFIndex)(int32_t)state->gpr[4]) : 0); return YES;
        }];
    [registry registerSymbol:@"_CFStringTokenizerAdvanceToNextToken"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tokenizer = [weakSelf object:state->gpr[3]];
            CFFinish(state, tokenizer ? (uint32_t)CFStringTokenizerAdvanceToNextToken(
                (__bridge CFStringTokenizerRef)tokenizer) : 0); return YES;
        }];
    [registry registerSymbol:@"_CFStringTokenizerGetCurrentTokenRange"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tokenizer = [weakSelf object:state->gpr[3]];
            CFRange range = tokenizer ? CFStringTokenizerGetCurrentTokenRange(
                (__bridge CFStringTokenizerRef)tokenizer) : CFRangeMake(kCFNotFound, 0);
            state->gpr[3] = (uint32_t)range.location; state->gpr[4] = (uint32_t)range.length;
            state->pc = state->lr; return YES;
        }];
    [registry registerSymbol:@"_CFStringTokenizerCopyCurrentTokenAttribute"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tokenizer = [weakSelf object:state->gpr[3]]; CFTypeRef attribute = tokenizer
                ? CFStringTokenizerCopyCurrentTokenAttribute((__bridge CFStringTokenizerRef)tokenizer,
                    state->gpr[4]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(attribute)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringTokenizerGetCurrentSubTokens"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id tokenizer = [weakSelf object:state->gpr[3]];
            CFIndex capacity = (CFIndex)(int32_t)state->gpr[5]; if (capacity < 0 || capacity > (1 << 20)) return NO;
            CFRange *ranges = capacity ? calloc((size_t)capacity, sizeof(*ranges)) : NULL;
            if (capacity && !ranges) return NO; id derived = [weakSelf object:state->gpr[6]];
            CFIndex count = tokenizer ? CFStringTokenizerGetCurrentSubTokens(
                (__bridge CFStringTokenizerRef)tokenizer, state->gpr[4] ? ranges : NULL,
                capacity, (__bridge CFMutableArrayRef)derived) : 0;
            CFIndex written = MIN(MAX(count, 0), capacity); BOOL success = YES;
            for (CFIndex index = 0; success && index < written; index++)
                success = [registry.memory writeUInt32:(uint32_t)ranges[index].location
                    address:state->gpr[4] + (uint32_t)index * 8] &&
                    [registry.memory writeUInt32:(uint32_t)ranges[index].length
                    address:state->gpr[4] + (uint32_t)index * 8 + 4];
            free(ranges); if (!success) return NO; CFFinish(state, (uint32_t)count); return YES;
        }];
    [registry registerSymbol:@"_CFUserNotificationGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                               NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFUserNotificationGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFUserNotificationCreate" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; SInt32 code = 0; id dictionary = [weakSelf object:state->gpr[8]];
        CFUserNotificationRef notification = CFUserNotificationCreate(kCFAllocatorDefault,
            state->fpr[1], state->gpr[6], state->gpr[7] ? &code : NULL,
            (__bridge CFDictionaryRef)dictionary);
        if (state->gpr[7] && ![registry.memory writeUInt32:(uint32_t)code address:state->gpr[7]]) {
            if (notification) CFRelease(notification); return NO; }
        CFFinish(state, [weakSelf handle:CFBridgingRelease(notification)]); return YES;
    }];
    [registry registerSymbol:@"_CFUserNotificationReceiveResponse"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            id notification = [weakSelf object:state->gpr[3]]; CFOptionFlags flags = 0;
            weakSelf.pendingCallbackError = nil; SInt32 result = notification
                ? CFUserNotificationReceiveResponse((__bridge CFUserNotificationRef)notification,
                    state->fpr[1], state->gpr[6] ? &flags : NULL) : -1;
            if (state->gpr[6] && ![registry.memory writeUInt32:(uint32_t)flags address:state->gpr[6]]) return NO;
            if (weakSelf.pendingCallbackError) {
                if (callError) *callError = weakSelf.pendingCallbackError; return NO;
            }
            CFFinish(state, (uint32_t)result); return YES;
        }];
    [registry registerSymbol:@"_CFUserNotificationGetResponseValue"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id notification = [weakSelf object:state->gpr[3]];
            CFStringRef value = notification ? CFUserNotificationGetResponseValue(
                (__bridge CFUserNotificationRef)notification,
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]], (CFIndex)(int32_t)state->gpr[5]) : NULL;
            CFFinish(state, [weakSelf handle:(__bridge id)value]); return YES;
        }];
    [registry registerSymbol:@"_CFUserNotificationGetResponseDictionary"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id notification = [weakSelf object:state->gpr[3]];
            CFDictionaryRef dictionary = notification ? CFUserNotificationGetResponseDictionary(
                (__bridge CFUserNotificationRef)notification) : NULL;
            CFFinish(state, [weakSelf handle:(__bridge id)dictionary]); return YES;
        }];
    [registry registerSymbol:@"_CFUserNotificationUpdate" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; id notification = [weakSelf object:state->gpr[3]];
        id dictionary = [weakSelf object:state->gpr[7]]; SInt32 result = notification
            ? CFUserNotificationUpdate((__bridge CFUserNotificationRef)notification,
                state->fpr[1], state->gpr[6], (__bridge CFDictionaryRef)dictionary) : -1;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFUserNotificationCancel" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; id notification = [weakSelf object:state->gpr[3]];
        CFFinish(state, (uint32_t)(notification ? CFUserNotificationCancel(
            (__bridge CFUserNotificationRef)notification) : -1)); return YES;
    }];
    [registry registerSymbol:@"_CFUserNotificationCreateRunLoopSource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id notification = [weakSelf object:state->gpr[4]];
            if (!notification) { CFFinish(state, 0); return YES; }
            BRPPCGuestUserNotificationRecord *record = weakSelf.userNotificationRecords[@(state->gpr[4])];
            if (!record) { record = [BRPPCGuestUserNotificationRecord new]; record.resolver = weakSelf;
                record.handle = state->gpr[4]; weakSelf.userNotificationRecords[@(state->gpr[4])] = record;
                objc_setAssociatedObject(notification, &BRPPCUserNotificationRecordAssociation,
                    record, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            record.outerState = *state; record.callout = state->gpr[5];
            CFRunLoopSourceRef source = CFUserNotificationCreateRunLoopSource(kCFAllocatorDefault,
                (__bridge CFUserNotificationRef)notification,
                record.callout ? DeliverUserNotificationResponse : NULL, (CFIndex)(int32_t)state->gpr[6]);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(source)]); return YES;
        }];
    [registry registerSymbol:@"_CFUserNotificationDisplayNotice"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t defaultTitle = 0; NSUInteger cursor = 11;
            if (![weakSelf readGuestWord:&defaultTitle state:state cursor:&cursor]) return NO;
            SInt32 result = CFUserNotificationDisplayNotice(state->fpr[1], state->gpr[5],
                (__bridge CFURLRef)[weakSelf object:state->gpr[6]],
                (__bridge CFURLRef)[weakSelf object:state->gpr[7]],
                (__bridge CFURLRef)[weakSelf object:state->gpr[8]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[9]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[10]],
                (__bridge CFStringRef)[weakSelf string:defaultTitle]);
            CFFinish(state, (uint32_t)result); return YES;
        }];
    [registry registerSymbol:@"_CFUserNotificationDisplayAlert"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t defaultTitle = 0, alternateTitle = 0, otherTitle = 0, responseAddress = 0;
            NSUInteger cursor = 11; if (![weakSelf readGuestWord:&defaultTitle state:state cursor:&cursor] ||
                ![weakSelf readGuestWord:&alternateTitle state:state cursor:&cursor] ||
                ![weakSelf readGuestWord:&otherTitle state:state cursor:&cursor] ||
                ![weakSelf readGuestWord:&responseAddress state:state cursor:&cursor]) return NO;
            CFOptionFlags response = 0; SInt32 result = CFUserNotificationDisplayAlert(state->fpr[1],
                state->gpr[5], (__bridge CFURLRef)[weakSelf object:state->gpr[6]],
                (__bridge CFURLRef)[weakSelf object:state->gpr[7]],
                (__bridge CFURLRef)[weakSelf object:state->gpr[8]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[9]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[10]],
                (__bridge CFStringRef)[weakSelf string:defaultTitle],
                (__bridge CFStringRef)[weakSelf string:alternateTitle],
                (__bridge CFStringRef)[weakSelf string:otherTitle], responseAddress ? &response : NULL);
            if (responseAddress && ![registry.memory writeUInt32:(uint32_t)response address:responseAddress]) return NO;
            CFFinish(state, (uint32_t)result); return YES;
        }];
    [registry registerSymbol:@"_CFXMLNodeGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                      NSError **callError) {
        (void)callError; typedef CFTypeID (*Function)(void); Function function =
            (Function)dlsym(RTLD_DEFAULT, "CFXMLNodeGetTypeID");
        CFFinish(state, function ? (uint32_t)function() : 0); return YES;
    }];
    [registry registerSymbol:@"_CFXMLNodeCreate" handler:^BOOL(BRPPCState *state,
                                                                   NSError **callError) {
        (void)callError; id node = [weakSelf createXMLNodeType:(CFXMLNodeTypeCode)(int32_t)state->gpr[4]
            dataString:[weakSelf string:state->gpr[5]] infoAddress:state->gpr[6]
            version:(CFIndex)(int32_t)state->gpr[7]];
        CFFinish(state, [weakSelf handle:node]); return YES;
    }];
    [registry registerSymbol:@"_CFXMLNodeCreateCopy" handler:^BOOL(BRPPCState *state,
                                                                       NSError **callError) {
        (void)callError; typedef CFXMLNodeRef (*Function)(CFAllocatorRef, CFXMLNodeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLNodeCreateCopy");
        id node = [weakSelf object:state->gpr[4]]; CFXMLNodeRef copy = function && node
            ? function(kCFAllocatorDefault, (__bridge CFXMLNodeRef)node) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFXMLNodeGetTypeCode" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; typedef CFXMLNodeTypeCode (*Function)(CFXMLNodeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLNodeGetTypeCode");
        id node = [weakSelf object:state->gpr[3]];
        CFFinish(state, function && node ? (uint32_t)function((__bridge CFXMLNodeRef)node) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFXMLNodeGetString" handler:^BOOL(BRPPCState *state,
                                                                      NSError **callError) {
        (void)callError; typedef CFStringRef (*Function)(CFXMLNodeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLNodeGetString");
        id node = [weakSelf object:state->gpr[3]]; CFStringRef string = function && node
            ? function((__bridge CFXMLNodeRef)node) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)string]); return YES;
    }];
    [registry registerSymbol:@"_CFXMLNodeGetInfoPtr" handler:^BOOL(BRPPCState *state,
                                                                       NSError **callError) {
        (void)callError; id node = [weakSelf object:state->gpr[3]];
        CFFinish(state, [weakSelf guestInfoForXMLNode:node handle:state->gpr[3]]); return YES;
    }];
    [registry registerSymbol:@"_CFXMLNodeGetVersion" handler:^BOOL(BRPPCState *state,
                                                                       NSError **callError) {
        (void)callError; typedef CFIndex (*Function)(CFXMLNodeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLNodeGetVersion");
        id node = [weakSelf object:state->gpr[3]];
        CFFinish(state, function && node ? (uint32_t)function((__bridge CFXMLNodeRef)node) : 0); return YES;
    }];
    [registry registerSymbol:@"_CFXMLTreeCreateWithNode" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; typedef CFXMLTreeRef (*Function)(CFAllocatorRef, CFXMLNodeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLTreeCreateWithNode");
        id node = [weakSelf object:state->gpr[4]]; CFXMLTreeRef tree = function && node
            ? function(kCFAllocatorDefault, (__bridge CFXMLNodeRef)node) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(tree)]); return YES;
    }];
    [registry registerSymbol:@"_CFXMLTreeGetNode" handler:^BOOL(BRPPCState *state,
                                                                    NSError **callError) {
        (void)callError; typedef CFXMLNodeRef (*Function)(CFXMLTreeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLTreeGetNode");
        id tree = [weakSelf object:state->gpr[3]]; CFXMLNodeRef node = function && tree
            ? function((__bridge CFXMLTreeRef)tree) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)node]); return YES;
    }];
    for (NSString *symbol in @[@"_CFXMLTreeCreateFromData", @"_CFXMLTreeCreateWithDataFromURL"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id dataOrURL = [weakSelf object:state->gpr[4]]; CFXMLTreeRef tree = NULL;
            if ([symbol containsString:@"WithDataFromURL"]) { typedef CFXMLTreeRef (*Function)(
                    CFAllocatorRef, CFURLRef, CFOptionFlags, CFIndex); Function function =
                    (Function)dlsym(RTLD_DEFAULT, "CFXMLTreeCreateWithDataFromURL");
                if (function && dataOrURL) tree = function(kCFAllocatorDefault,
                    (__bridge CFURLRef)dataOrURL, state->gpr[5], (CFIndex)(int32_t)state->gpr[6]);
            } else { typedef CFXMLTreeRef (*Function)(CFAllocatorRef, CFDataRef, CFURLRef,
                    CFOptionFlags, CFIndex); Function function = (Function)dlsym(RTLD_DEFAULT,
                    "CFXMLTreeCreateFromData"); id URL = [weakSelf object:state->gpr[5]];
                if (function && dataOrURL) tree = function(kCFAllocatorDefault, (__bridge CFDataRef)dataOrURL,
                    (__bridge CFURLRef)URL, state->gpr[6], (CFIndex)(int32_t)state->gpr[7]); }
            CFFinish(state, [weakSelf handle:CFBridgingRelease(tree)]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFXMLTreeCreateFromDataWithError"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFXMLTreeRef (*Function)(CFAllocatorRef, CFDataRef, CFURLRef,
                CFOptionFlags, CFIndex, CFDictionaryRef *); Function function = (Function)dlsym(
                    RTLD_DEFAULT, "CFXMLTreeCreateFromDataWithError");
            id data = [weakSelf object:state->gpr[4]], URL = [weakSelf object:state->gpr[5]];
            CFDictionaryRef errorDictionary = NULL; CFXMLTreeRef tree = function && data
                ? function(kCFAllocatorDefault, (__bridge CFDataRef)data, (__bridge CFURLRef)URL,
                    state->gpr[6], (CFIndex)(int32_t)state->gpr[7],
                    state->gpr[8] ? &errorDictionary : NULL) : NULL;
            if (state->gpr[8] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(errorDictionary)]
                                                    address:state->gpr[8]]) { if (tree) CFRelease(tree); return NO; }
            CFFinish(state, [weakSelf handle:CFBridgingRelease(tree)]); return YES;
        }];
    [registry registerSymbol:@"_CFXMLTreeCreateXMLData" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; typedef CFDataRef (*Function)(CFAllocatorRef, CFXMLTreeRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLTreeCreateXMLData");
        id tree = [weakSelf object:state->gpr[4]]; CFDataRef data = function && tree
            ? function(kCFAllocatorDefault, (__bridge CFXMLTreeRef)tree) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(data)]); return YES;
    }];
    for (NSString *symbol in @[@"_CFXMLCreateStringByEscapingEntities",
                                 @"_CFXMLCreateStringByUnescapingEntities"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFStringRef (*Function)(CFAllocatorRef, CFStringRef, CFDictionaryRef);
            Function function = (Function)dlsym(RTLD_DEFAULT, [symbol substringFromIndex:1].UTF8String);
            NSString *string = [weakSelf string:state->gpr[4]]; id entities = [weakSelf object:state->gpr[5]];
            CFStringRef result = function && string ? function(kCFAllocatorDefault,
                (__bridge CFStringRef)string, (__bridge CFDictionaryRef)entities) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFXMLParserGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; typedef CFTypeID (*Function)(void); Function function =
            (Function)dlsym(RTLD_DEFAULT, "CFXMLParserGetTypeID");
        CFFinish(state, function ? (uint32_t)function() : 0); return YES;
    }];
    for (NSString *symbol in @[@"_CFXMLParserCreate", @"_CFXMLParserCreateWithDataFromURL"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            BOOL fromURL = [symbol containsString:@"WithDataFromURL"];
            uint32_t callbacksAddress = state->gpr[fromURL ? 7 : 8];
            uint32_t contextAddress = state->gpr[fromURL ? 8 : 9];
            BRPPCGuestXMLParserRecord *record = [weakSelf XMLParserRecordWithCallbacks:callbacksAddress
                context:contextAddress state:*state]; if (!record) return NO;
            CFXMLParserCallBacks callbacks = {0, CreateXMLParserStructure, AddXMLParserChild,
                EndXMLParserStructure, record.resolveEntity ? ResolveXMLParserEntity : NULL,
                record.handleError ? HandleXMLParserError : NULL};
            CFXMLParserContext context = {0, (__bridge void *)record, RetainXMLParserContext,
                ReleaseXMLParserContext, CopyXMLParserContextDescription}; weakSelf.pendingCallbackError = nil;
            CFXMLParserRef parser = NULL;
            if (fromURL) { typedef CFXMLParserRef (*Function)(CFAllocatorRef, CFURLRef, CFOptionFlags,
                    CFIndex, CFXMLParserCallBacks *, CFXMLParserContext *); Function function =
                    (Function)dlsym(RTLD_DEFAULT, "CFXMLParserCreateWithDataFromURL");
                id URL = [weakSelf object:state->gpr[4]]; if (function && URL) parser = function(
                    kCFAllocatorDefault, (__bridge CFURLRef)URL, state->gpr[5],
                    (CFIndex)(int32_t)state->gpr[6], &callbacks, &context);
            } else { typedef CFXMLParserRef (*Function)(CFAllocatorRef, CFDataRef, CFURLRef,
                    CFOptionFlags, CFIndex, CFXMLParserCallBacks *, CFXMLParserContext *);
                Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLParserCreate");
                id data = [weakSelf object:state->gpr[4]], URL = [weakSelf object:state->gpr[5]];
                if (function && data) parser = function(kCFAllocatorDefault, (__bridge CFDataRef)data,
                    (__bridge CFURLRef)URL, state->gpr[6], (CFIndex)(int32_t)state->gpr[7],
                    &callbacks, &context);
            }
            if (weakSelf.pendingCallbackError) { if (parser) CFRelease(parser);
                if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
            uint32_t handle = [weakSelf handle:CFBridgingRelease(parser)]; record.handle = handle;
            if (handle) weakSelf.xmlParserRecords[@(handle)] = record; CFFinish(state, handle); return YES;
        }];
    }
    [registry registerSymbol:@"_CFXMLParserGetContext" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        (void)callError; BRPPCGuestXMLParserRecord *record = weakSelf.xmlParserRecords[@(state->gpr[3])];
        uint32_t address = state->gpr[4]; if (!record || !address) return NO;
        uint32_t words[5] = {0, record.info, record.retainFunction,
            record.releaseFunction, record.descriptionFunction};
        for (NSUInteger index = 0; index < 5; index++)
            if (![registry.memory writeUInt32:words[index]
                                      address:address + (uint32_t)index * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFXMLParserGetCallBacks" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; BRPPCGuestXMLParserRecord *record = weakSelf.xmlParserRecords[@(state->gpr[3])];
        uint32_t address = state->gpr[4]; if (!record || !address) return NO;
        uint32_t words[6] = {0, record.createStructure, record.addChild, record.endStructure,
            record.resolveEntity, record.handleError};
        for (NSUInteger index = 0; index < 6; index++)
            if (![registry.memory writeUInt32:words[index]
                                      address:address + (uint32_t)index * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFXMLParserGetSourceURL" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; typedef CFURLRef (*Function)(CFXMLParserRef); Function function =
            (Function)dlsym(RTLD_DEFAULT, "CFXMLParserGetSourceURL"); id parser = [weakSelf object:state->gpr[3]];
        CFURLRef URL = function && parser ? function((__bridge CFXMLParserRef)parser) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)URL]); return YES;
    }];
    for (NSString *symbol in @[@"_CFXMLParserGetLocation", @"_CFXMLParserGetLineNumber",
                                 @"_CFXMLParserGetStatusCode"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id parser = [weakSelf object:state->gpr[3]]; uint32_t result = 0;
            if (parser && [symbol containsString:@"Location"]) { typedef CFIndex (*Function)(CFXMLParserRef);
                Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLParserGetLocation");
                if (function) result = (uint32_t)function((__bridge CFXMLParserRef)parser);
            } else if (parser && [symbol containsString:@"LineNumber"]) {
                typedef CFIndex (*Function)(CFXMLParserRef); Function function =
                    (Function)dlsym(RTLD_DEFAULT, "CFXMLParserGetLineNumber");
                if (function) result = (uint32_t)function((__bridge CFXMLParserRef)parser);
            } else if (parser) { typedef CFXMLParserStatusCode (*Function)(CFXMLParserRef);
                Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLParserGetStatusCode");
                if (function) result = (uint32_t)function((__bridge CFXMLParserRef)parser); }
            CFFinish(state, result); return YES;
        }];
    }
    [registry registerSymbol:@"_CFXMLParserGetDocument" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; typedef void *(*Function)(CFXMLParserRef); Function function =
            (Function)dlsym(RTLD_DEFAULT, "CFXMLParserGetDocument"); id parser = [weakSelf object:state->gpr[3]];
        void *document = function && parser ? function((__bridge CFXMLParserRef)parser) : NULL;
        CFFinish(state, (uint32_t)(uintptr_t)document); return YES;
    }];
    [registry registerSymbol:@"_CFXMLParserCopyErrorDescription"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFStringRef (*Function)(CFXMLParserRef); Function function =
                (Function)dlsym(RTLD_DEFAULT, "CFXMLParserCopyErrorDescription");
            id parser = [weakSelf object:state->gpr[3]]; CFStringRef string = function && parser
                ? function((__bridge CFXMLParserRef)parser) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
        }];
    [registry registerSymbol:@"_CFXMLParserAbort" handler:^BOOL(BRPPCState *state,
                                                                    NSError **callError) {
        (void)callError; typedef void (*Function)(CFXMLParserRef, CFXMLParserStatusCode, CFStringRef);
        Function function = (Function)dlsym(RTLD_DEFAULT, "CFXMLParserAbort");
        id parser = [weakSelf object:state->gpr[3]]; if (function && parser) function(
            (__bridge CFXMLParserRef)parser, (CFXMLParserStatusCode)(int32_t)state->gpr[4],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]]);
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFXMLParserParse" handler:^BOOL(BRPPCState *state,
                                                                    NSError **callError) {
        typedef Boolean (*Function)(CFXMLParserRef); Function function =
            (Function)dlsym(RTLD_DEFAULT, "CFXMLParserParse"); id parser = [weakSelf object:state->gpr[3]];
        weakSelf.pendingCallbackError = nil; Boolean result = function && parser
            ? function((__bridge CFXMLParserRef)parser) : false;
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, result); return YES;
    }];
    [registry registerSymbol:@"_CFMachPortGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                       NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFMachPortGetTypeID()); return YES;
    }];
    for (NSString *symbol in @[@"_CFMachPortCreate", @"_CFMachPortCreateWithPort"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            BOOL withPort = [symbol containsString:@"WithPort"];
            uint32_t callout = state->gpr[withPort ? 5 : 4];
            uint32_t contextAddress = state->gpr[withPort ? 6 : 5];
            uint32_t shouldFreeAddress = state->gpr[withPort ? 7 : 6];
            BRPPCGuestMachPortRecord *record = [weakSelf machPortRecordAtAddress:contextAddress
                callout:callout state:*state]; if (!record) return NO;
            CFMachPortContext context = {0, (__bridge void *)record, RetainMachPortContext,
                ReleaseMachPortContext, CopyMachPortContextDescription}; Boolean shouldFree = false;
            weakSelf.pendingCallbackError = nil; CFMachPortRef port = withPort
                ? CFMachPortCreateWithPort(kCFAllocatorDefault, state->gpr[4],
                    record.callout ? DeliverMachPortEvent : NULL, &context, &shouldFree)
                : CFMachPortCreate(kCFAllocatorDefault, record.callout ? DeliverMachPortEvent : NULL,
                    &context, &shouldFree);
            if (weakSelf.pendingCallbackError) { if (port) CFRelease(port);
                if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
            if (shouldFreeAddress && ![registry.memory writeBytes:&shouldFree
                address:shouldFreeAddress length:sizeof(shouldFree)]) { if (port) CFRelease(port); return NO; }
            id portObject = CFBridgingRelease(port); uint32_t handle = [weakSelf handle:portObject];
            record.handle = handle; if (handle) { weakSelf.machPortRecords[@(handle)] = record;
                objc_setAssociatedObject(portObject, &BRPPCMachPortRecordAssociation,
                    record, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            CFFinish(state, handle); return YES;
        }];
    }
    [registry registerSymbol:@"_CFMachPortGetPort" handler:^BOOL(BRPPCState *state,
                                                                      NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]];
        CFFinish(state, port ? CFMachPortGetPort((__bridge CFMachPortRef)port) : MACH_PORT_NULL); return YES;
    }];
    [registry registerSymbol:@"_CFMachPortGetContext" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        (void)callError; BRPPCGuestMachPortRecord *record = weakSelf.machPortRecords[@(state->gpr[3])];
        uint32_t address = state->gpr[4]; if (!record || !address) return NO;
        uint32_t words[5] = {0, record.info, record.retainFunction,
            record.releaseFunction, record.descriptionFunction};
        for (NSUInteger index = 0; index < 5; index++)
            if (![registry.memory writeUInt32:words[index]
                                      address:address + (uint32_t)index * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFMachPortInvalidate" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        id port = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
        if (port) CFMachPortInvalidate((__bridge CFMachPortRef)port);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFMachPortIsValid" handler:^BOOL(BRPPCState *state,
                                                                      NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]];
        CFFinish(state, port && CFMachPortIsValid((__bridge CFMachPortRef)port)); return YES;
    }];
    [registry registerSymbol:@"_CFMachPortGetInvalidationCallBack"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCGuestMachPortRecord *record = weakSelf.machPortRecords[@(state->gpr[3])];
            CFFinish(state, record.invalidationCallout); return YES;
        }];
    [registry registerSymbol:@"_CFMachPortSetInvalidationCallBack"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id port = [weakSelf object:state->gpr[3]];
            BRPPCGuestMachPortRecord *record = weakSelf.machPortRecords[@(state->gpr[3])];
            if (!port || !record) return NO; record.invalidationCallout = state->gpr[4];
            CFMachPortSetInvalidationCallBack((__bridge CFMachPortRef)port,
                record.invalidationCallout ? InvalidateMachPort : NULL);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFMachPortCreateRunLoopSource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id port = [weakSelf object:state->gpr[4]];
            CFRunLoopSourceRef source = port ? CFMachPortCreateRunLoopSource(kCFAllocatorDefault,
                (__bridge CFMachPortRef)port, (CFIndex)(int32_t)state->gpr[5]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(source)]); return YES;
        }];
    [registry registerSymbol:@"_CFMessagePortGetTypeID" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFMessagePortGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortCreateLocal" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        BRPPCGuestMessagePortRecord *record = [weakSelf messagePortRecordAtAddress:state->gpr[6]
            callout:state->gpr[5] state:*state]; if (!record) return NO;
        CFMessagePortContext context = {0, (__bridge void *)record, RetainMessagePortContext,
            ReleaseMessagePortContext, CopyMessagePortContextDescription}; Boolean shouldFree = false;
        weakSelf.pendingCallbackError = nil; CFMessagePortRef port = CFMessagePortCreateLocal(
            kCFAllocatorDefault, (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
            record.callout ? DeliverMessagePortEvent : NULL, &context, &shouldFree);
        if (weakSelf.pendingCallbackError) { if (port) CFRelease(port);
            if (callError) *callError = weakSelf.pendingCallbackError; return NO; }
        if (state->gpr[7] && ![registry.memory writeBytes:&shouldFree
            address:state->gpr[7] length:sizeof(shouldFree)]) { if (port) CFRelease(port); return NO; }
        id portObject = CFBridgingRelease(port); uint32_t handle = [weakSelf handle:portObject];
        record.handle = handle; if (handle) { weakSelf.messagePortRecords[@(handle)] = record;
            objc_setAssociatedObject(portObject, &BRPPCMessagePortRecordAssociation,
                record, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        CFFinish(state, handle); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortCreateRemote" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault,
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]]); id portObject = CFBridgingRelease(port);
        uint32_t handle = [weakSelf handle:portObject]; if (handle) {
            BRPPCGuestMessagePortRecord *record = [weakSelf messagePortRecordAtAddress:0 callout:0 state:*state];
            record.handle = handle; weakSelf.messagePortRecords[@(handle)] = record;
            objc_setAssociatedObject(portObject, &BRPPCMessagePortRecordAssociation,
                record, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        CFFinish(state, handle); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortIsRemote" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]];
        CFFinish(state, port && CFMessagePortIsRemote((__bridge CFMessagePortRef)port)); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortGetName" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]]; CFStringRef name = port
            ? CFMessagePortGetName((__bridge CFMessagePortRef)port) : NULL;
        CFFinish(state, [weakSelf handle:(__bridge id)name]); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortSetName" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]]; NSString *name = [weakSelf string:state->gpr[4]];
        CFFinish(state, port && name && CFMessagePortSetName((__bridge CFMessagePortRef)port,
            (__bridge CFStringRef)name)); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortGetContext" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; BRPPCGuestMessagePortRecord *record = weakSelf.messagePortRecords[@(state->gpr[3])];
        uint32_t address = state->gpr[4]; if (!record || !address) return NO;
        uint32_t words[5] = {0, record.info, record.retainFunction,
            record.releaseFunction, record.descriptionFunction};
        for (NSUInteger index = 0; index < 5; index++)
            if (![registry.memory writeUInt32:words[index]
                                      address:address + (uint32_t)index * 4]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortInvalidate" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        id port = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
        if (port) CFMessagePortInvalidate((__bridge CFMessagePortRef)port);
        if (weakSelf.pendingCallbackError) {
            if (callError) *callError = weakSelf.pendingCallbackError; return NO;
        }
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortIsValid" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]];
        CFFinish(state, port && CFMessagePortIsValid((__bridge CFMessagePortRef)port)); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortGetInvalidationCallBack"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BRPPCGuestMessagePortRecord *record = weakSelf.messagePortRecords[@(state->gpr[3])];
            CFFinish(state, record.invalidationCallout); return YES;
        }];
    [registry registerSymbol:@"_CFMessagePortSetInvalidationCallBack"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id port = [weakSelf object:state->gpr[3]];
            BRPPCGuestMessagePortRecord *record = weakSelf.messagePortRecords[@(state->gpr[3])];
            if (!port || !record) return NO; record.invalidationCallout = state->gpr[4];
            CFMessagePortSetInvalidationCallBack((__bridge CFMessagePortRef)port,
                record.invalidationCallout ? InvalidateMessagePort : NULL);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFMessagePortSendRequest" handler:^BOOL(BRPPCState *state,
                                                                            NSError **callError) {
        (void)callError; id port = [weakSelf object:state->gpr[3]], data = [weakSelf object:state->gpr[5]];
        uint32_t returnAddress = 0; NSUInteger cursor = 11;
        if (![weakSelf readGuestWord:&returnAddress state:state cursor:&cursor]) return NO;
        CFDataRef returnedData = NULL; SInt32 result = port ? CFMessagePortSendRequest(
            (__bridge CFMessagePortRef)port, (SInt32)state->gpr[4], (__bridge CFDataRef)data,
            state->fpr[1], state->fpr[2], (__bridge CFStringRef)[weakSelf string:state->gpr[10]],
            returnAddress ? &returnedData : NULL) : kCFMessagePortIsInvalid;
        if (returnAddress && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(returnedData)]
                                                  address:returnAddress]) return NO;
        CFFinish(state, (uint32_t)result); return YES;
    }];
    [registry registerSymbol:@"_CFMessagePortCreateRunLoopSource"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id port = [weakSelf object:state->gpr[4]];
            CFRunLoopSourceRef source = port ? CFMessagePortCreateRunLoopSource(kCFAllocatorDefault,
                (__bridge CFMessagePortRef)port, (CFIndex)(int32_t)state->gpr[5]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(source)]); return YES;
        }];
    [registry registerSymbol:@"_CFMessagePortSetDispatchQueue"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id port = [weakSelf object:state->gpr[3]];
            id queueObject = [weakSelf object:state->gpr[4]];
            dispatch_queue_t queue = queueObject
                ? (__bridge dispatch_queue_t)(__bridge void *)queueObject : NULL;
            if (port) CFMessagePortSetDispatchQueue((__bridge CFMessagePortRef)port, queue);
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFReadStreamGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFReadStreamGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFWriteStreamGetTypeID" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, (uint32_t)CFWriteStreamGetTypeID()); return YES;
    }];
    [registry registerSymbol:@"_CFReadStreamCreateWithBytesNoCopy"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t length = state->gpr[5]; void *bytes = malloc(MAX(length, 1u));
            if (!bytes || (length && ![registry.memory readBytes:bytes address:state->gpr[4] length:length])) {
                free(bytes); return NO;
            }
            CFReadStreamRef stream = CFReadStreamCreateWithBytesNoCopy(kCFAllocatorDefault,
                bytes, length, kCFAllocatorMalloc); if (!stream) free(bytes);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(stream)]); return YES;
        }];
    [registry registerSymbol:@"_CFWriteStreamCreateWithBuffer"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t capacity = state->gpr[5];
            NSMutableData *buffer = [NSMutableData dataWithLength:MAX(capacity, 1u)];
            CFWriteStreamRef stream = CFWriteStreamCreateWithBuffer(kCFAllocatorDefault,
                buffer.mutableBytes, capacity); id streamObject = CFBridgingRelease(stream);
            uint32_t handle = [weakSelf handle:streamObject];
            if (handle) { BRPPCGuestStreamRecord *record = [BRPPCGuestStreamRecord new];
                record.resolver = weakSelf; record.handle = handle; record.writeBuffer = buffer;
                record.guestBufferAddress = state->gpr[4]; record.bufferCapacity = capacity;
                weakSelf.streamRecords[@(handle)] = record; }
            CFFinish(state, handle); return YES;
        }];
    [registry registerSymbol:@"_CFWriteStreamCreateWithAllocatedBuffers"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFWriteStreamRef stream = CFWriteStreamCreateWithAllocatedBuffers(
                kCFAllocatorDefault, kCFAllocatorDefault);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(stream)]); return YES;
        }];
    for (NSString *symbol in @[@"_CFReadStreamCreateWithFile", @"_CFWriteStreamCreateWithFile"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSURL *URL = [weakSelf object:state->gpr[4]]; id stream = nil;
            if (URL) stream = [symbol containsString:@"Read"]
                ? CFBridgingRelease(CFReadStreamCreateWithFile(kCFAllocatorDefault, (__bridge CFURLRef)URL))
                : CFBridgingRelease(CFWriteStreamCreateWithFile(kCFAllocatorDefault, (__bridge CFURLRef)URL));
            CFFinish(state, [weakSelf handle:stream]); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStreamCreateBoundPair" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        (void)callError; CFReadStreamRef readStream = NULL; CFWriteStreamRef writeStream = NULL;
        CFStreamCreateBoundPair(kCFAllocatorDefault, state->gpr[4] ? &readStream : NULL,
            state->gpr[5] ? &writeStream : NULL, (CFIndex)(int32_t)state->gpr[6]);
        id readObject = CFBridgingRelease(readStream), writeObject = CFBridgingRelease(writeStream);
        if ((state->gpr[4] && ![registry.memory writeUInt32:[weakSelf handle:readObject] address:state->gpr[4]]) ||
            (state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:writeObject] address:state->gpr[5]]))
            return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStreamCreatePairWithSocket" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; CFReadStreamRef readStream = NULL; CFWriteStreamRef writeStream = NULL;
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, (CFSocketNativeHandle)(int32_t)state->gpr[4],
            state->gpr[5] ? &readStream : NULL, state->gpr[6] ? &writeStream : NULL);
        id readObject = CFBridgingRelease(readStream), writeObject = CFBridgingRelease(writeStream);
        if ((state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:readObject] address:state->gpr[5]]) ||
            (state->gpr[6] && ![registry.memory writeUInt32:[weakSelf handle:writeObject] address:state->gpr[6]]))
            return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStreamCreatePairWithSocketToHost"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *host = [weakSelf string:state->gpr[4]];
            CFReadStreamRef readStream = NULL; CFWriteStreamRef writeStream = NULL;
            CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (__bridge CFStringRef)host,
                state->gpr[5], state->gpr[6] ? &readStream : NULL, state->gpr[7] ? &writeStream : NULL);
            id readObject = CFBridgingRelease(readStream), writeObject = CFBridgingRelease(writeStream);
            if ((state->gpr[6] && ![registry.memory writeUInt32:[weakSelf handle:readObject] address:state->gpr[6]]) ||
                (state->gpr[7] && ![registry.memory writeUInt32:[weakSelf handle:writeObject] address:state->gpr[7]]))
                return NO;
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFStreamCreatePairWithPeerSocketSignature"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t words[4] = {0};
            for (NSUInteger index = 0; index < 4; index++)
                if (!state->gpr[4] || ![registry.memory readUInt32:&words[index]
                                                             address:state->gpr[4] + (uint32_t)index * 4]) return NO;
            NSData *address = [weakSelf object:words[3]]; CFSocketSignature signature = {
                (SInt32)words[0], (SInt32)words[1], (SInt32)words[2], (__bridge CFDataRef)address};
            CFReadStreamRef readStream = NULL; CFWriteStreamRef writeStream = NULL;
            CFStreamCreatePairWithPeerSocketSignature(kCFAllocatorDefault, &signature,
                state->gpr[5] ? &readStream : NULL, state->gpr[6] ? &writeStream : NULL);
            id readObject = CFBridgingRelease(readStream), writeObject = CFBridgingRelease(writeStream);
            if ((state->gpr[5] && ![registry.memory writeUInt32:[weakSelf handle:readObject] address:state->gpr[5]]) ||
                (state->gpr[6] && ![registry.memory writeUInt32:[weakSelf handle:writeObject] address:state->gpr[6]]))
                return NO;
            CFFinish(state, 0); return YES;
        }];
    for (NSString *symbol in @[@"_CFReadStreamGetStatus", @"_CFWriteStreamGetStatus"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]]; CFStreamStatus status = 0;
            if (stream) status = [symbol containsString:@"Read"]
                ? CFReadStreamGetStatus((__bridge CFReadStreamRef)stream)
                : CFWriteStreamGetStatus((__bridge CFWriteStreamRef)stream);
            CFFinish(state, (uint32_t)status); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamCopyError", @"_CFWriteStreamCopyError"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]]; CFErrorRef streamError = NULL;
            if (stream) streamError = [symbol containsString:@"Read"]
                ? CFReadStreamCopyError((__bridge CFReadStreamRef)stream)
                : CFWriteStreamCopyError((__bridge CFWriteStreamRef)stream);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(streamError)]); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamOpen", @"_CFWriteStreamOpen"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            id stream = [weakSelf object:state->gpr[3]]; weakSelf.pendingCallbackError = nil;
            Boolean valid = stream && ([symbol containsString:@"Read"]
                ? CFReadStreamOpen((__bridge CFReadStreamRef)stream)
                : CFWriteStreamOpen((__bridge CFWriteStreamRef)stream));
            if (weakSelf.pendingCallbackError) {
                if (callError) *callError = weakSelf.pendingCallbackError; return NO;
            }
            CFFinish(state, valid); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamClose", @"_CFWriteStreamClose"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]];
            if (stream && [symbol containsString:@"Read"]) CFReadStreamClose((__bridge CFReadStreamRef)stream);
            else if (stream) CFWriteStreamClose((__bridge CFWriteStreamRef)stream);
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFReadStreamHasBytesAvailable"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]];
            CFFinish(state, stream && CFReadStreamHasBytesAvailable((__bridge CFReadStreamRef)stream)); return YES;
        }];
    [registry registerSymbol:@"_CFReadStreamRead" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id stream = [weakSelf object:state->gpr[3]]; int32_t requested = (int32_t)state->gpr[5];
        if (!stream || requested < 0) return NO; uint8_t *bytes = malloc(MAX((size_t)requested, 1u));
        if (!bytes) return NO; CFIndex count = CFReadStreamRead((__bridge CFReadStreamRef)stream, bytes, requested);
        BOOL valid = count <= 0 || [registry.memory writeBytes:bytes address:state->gpr[4] length:(NSUInteger)count];
        free(bytes); if (!valid) return NO; CFFinish(state, (uint32_t)count); return YES;
    }];
    [registry registerSymbol:@"_CFReadStreamGetBuffer" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; id stream = [weakSelf object:state->gpr[3]]; int32_t maximum = (int32_t)state->gpr[4];
        if (!stream || maximum < 0) return NO; CFIndex count = 0;
        const UInt8 *bytes = CFReadStreamGetBuffer((__bridge CFReadStreamRef)stream, maximum, &count);
        NSNumber *oldPointer = weakSelf.streamBufferPointers[@(state->gpr[3])];
        if (oldPointer && registry.guestDeallocator) registry.guestDeallocator(oldPointer.unsignedIntValue);
        uint32_t pointer = bytes && count >= 0 ? [weakSelf copyBytesToGuest:bytes length:(NSUInteger)count] : 0;
        if (pointer) weakSelf.streamBufferPointers[@(state->gpr[3])] = @(pointer);
        else [weakSelf.streamBufferPointers removeObjectForKey:@(state->gpr[3])];
        if (state->gpr[5] && ![registry.memory writeUInt32:(uint32_t)MAX(count, 0) address:state->gpr[5]]) return NO;
        CFFinish(state, pointer); return YES;
    }];
    [registry registerSymbol:@"_CFWriteStreamCanAcceptBytes"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]];
            CFFinish(state, stream && CFWriteStreamCanAcceptBytes((__bridge CFWriteStreamRef)stream)); return YES;
        }];
    [registry registerSymbol:@"_CFWriteStreamWrite" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id stream = [weakSelf object:state->gpr[3]]; int32_t requested = (int32_t)state->gpr[5];
        if (!stream || requested < 0) return NO; uint8_t *bytes = malloc(MAX((size_t)requested, 1u));
        if (!bytes || (requested && ![registry.memory readBytes:bytes address:state->gpr[4]
                                                           length:(NSUInteger)requested])) { free(bytes); return NO; }
        CFIndex count = CFWriteStreamWrite((__bridge CFWriteStreamRef)stream, bytes, requested); free(bytes);
        BRPPCGuestStreamRecord *record = weakSelf.streamRecords[@(state->gpr[3])];
        if (count > 0 && record.writeBuffer) {
            if (![registry.memory writeBytes:record.writeBuffer.bytes address:record.guestBufferAddress
                                      length:record.bufferCapacity]) return NO;
        }
        CFFinish(state, (uint32_t)count); return YES;
    }];
    for (NSString *symbol in @[@"_CFReadStreamCopyProperty", @"_CFWriteStreamCopyProperty"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]], key = [weakSelf object:state->gpr[4]];
            CFTypeRef value = stream && key ? ([symbol containsString:@"Read"]
                ? CFReadStreamCopyProperty((__bridge CFReadStreamRef)stream, (__bridge CFStringRef)key)
                : CFWriteStreamCopyProperty((__bridge CFWriteStreamRef)stream, (__bridge CFStringRef)key)) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamSetProperty", @"_CFWriteStreamSetProperty"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]], key = [weakSelf object:state->gpr[4]];
            id value = [weakSelf object:state->gpr[5]]; Boolean valid = stream && key && ([symbol containsString:@"Read"]
                ? CFReadStreamSetProperty((__bridge CFReadStreamRef)stream, (__bridge CFStringRef)key,
                    (__bridge CFTypeRef)value)
                : CFWriteStreamSetProperty((__bridge CFWriteStreamRef)stream, (__bridge CFStringRef)key,
                    (__bridge CFTypeRef)value));
            CFFinish(state, valid); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamSetClient", @"_CFWriteStreamSetClient"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            id stream = [weakSelf object:state->gpr[3]]; if (!stream) return NO;
            BRPPCGuestStreamRecord *oldRecord = weakSelf.streamRecords[@(state->gpr[3])];
            BRPPCGuestStreamRecord *record = [BRPPCGuestStreamRecord new]; record.resolver = weakSelf;
            record.handle = state->gpr[3]; record.writeBuffer = oldRecord.writeBuffer;
            record.guestBufferAddress = oldRecord.guestBufferAddress; record.bufferCapacity = oldRecord.bufferCapacity;
            record.outerState = *state; record.callback = state->gpr[5]; uint32_t contextAddress = state->gpr[6];
            CFStreamClientContext context = {0}; CFStreamClientContext *contextPointer = NULL;
            if (record.callback) {
                uint32_t version = 0, info = 0, retain = 0, release = 0, description = 0;
                if (!contextAddress || ![registry.memory readUInt32:&version address:contextAddress] || version ||
                    ![registry.memory readUInt32:&info address:contextAddress + 4] ||
                    ![registry.memory readUInt32:&retain address:contextAddress + 8] ||
                    ![registry.memory readUInt32:&release address:contextAddress + 12] ||
                    ![registry.memory readUInt32:&description address:contextAddress + 16]) return NO;
                record.info = info; record.retainFunction = retain; record.releaseFunction = release;
                record.descriptionFunction = description; context.info = (__bridge void *)record;
                context.retain = RetainStreamContext; context.release = ReleaseStreamContext;
                context.copyDescription = CopyStreamContextDescription; contextPointer = &context;
            }
            weakSelf.pendingCallbackError = nil; Boolean valid = [symbol containsString:@"Read"]
                ? CFReadStreamSetClient((__bridge CFReadStreamRef)stream, state->gpr[4],
                    record.callback ? DeliverReadStreamEvent : NULL, contextPointer)
                : CFWriteStreamSetClient((__bridge CFWriteStreamRef)stream, state->gpr[4],
                    record.callback ? DeliverWriteStreamEvent : NULL, contextPointer);
            if (weakSelf.pendingCallbackError) {
                if (callError) *callError = weakSelf.pendingCallbackError; return NO;
            }
            if (valid && (record.callback || record.writeBuffer)) weakSelf.streamRecords[@(state->gpr[3])] = record;
            else if (valid) [weakSelf.streamRecords removeObjectForKey:@(state->gpr[3])];
            CFFinish(state, valid); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamScheduleWithRunLoop", @"_CFWriteStreamScheduleWithRunLoop",
        @"_CFReadStreamUnscheduleFromRunLoop", @"_CFWriteStreamUnscheduleFromRunLoop"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]], runLoop = [weakSelf object:state->gpr[4]];
            NSString *mode = [weakSelf string:state->gpr[5]]; if (!stream || !runLoop || !mode) return NO;
            BOOL read = [symbol containsString:@"Read"], unschedule = [symbol containsString:@"Unschedule"];
            if (read && unschedule) CFReadStreamUnscheduleFromRunLoop((__bridge CFReadStreamRef)stream,
                (__bridge CFRunLoopRef)runLoop, (__bridge CFStringRef)mode);
            else if (read) CFReadStreamScheduleWithRunLoop((__bridge CFReadStreamRef)stream,
                (__bridge CFRunLoopRef)runLoop, (__bridge CFStringRef)mode);
            else if (unschedule) CFWriteStreamUnscheduleFromRunLoop((__bridge CFWriteStreamRef)stream,
                (__bridge CFRunLoopRef)runLoop, (__bridge CFStringRef)mode);
            else CFWriteStreamScheduleWithRunLoop((__bridge CFWriteStreamRef)stream,
                (__bridge CFRunLoopRef)runLoop, (__bridge CFStringRef)mode);
            CFFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamGetError", @"_CFWriteStreamGetError"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[4]]; CFStreamError streamError = {0, 0};
            if (stream) streamError = [symbol containsString:@"Read"]
                ? CFReadStreamGetError((__bridge CFReadStreamRef)stream)
                : CFWriteStreamGetError((__bridge CFWriteStreamRef)stream);
            if (!state->gpr[3] || ![registry.memory writeUInt32:(uint32_t)streamError.domain address:state->gpr[3]] ||
                ![registry.memory writeUInt32:(uint32_t)streamError.error address:state->gpr[3] + 4]) return NO;
            CFFinish(state, state->gpr[3]); return YES;
        }];
    }

    [registry registerSymbol:@"_CFPropertyListCreateWithData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSData *data = [weakSelf object:state->gpr[4]]; CFPropertyListFormat format = 0;
        CFErrorRef createdError = NULL; CFPropertyListRef value = CFPropertyListCreateWithData(
            kCFAllocatorDefault, (__bridge CFDataRef)data, state->gpr[5], &format, &createdError);
        if (state->gpr[6]) [registry.memory writeUInt32:(uint32_t)format address:state->gpr[6]];
        if (state->gpr[7]) [registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(createdError)] address:state->gpr[7]];
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListCreateData" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFErrorRef createdError = NULL; CFDataRef data = CFPropertyListCreateData(
            kCFAllocatorDefault, (__bridge CFPropertyListRef)[weakSelf object:state->gpr[4]],
            (CFPropertyListFormat)state->gpr[5], state->gpr[6], &createdError);
        if (state->gpr[7]) [registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(createdError)] address:state->gpr[7]];
        CFFinish(state, [weakSelf handle:CFBridgingRelease(data)]); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListIsValid" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; CFFinish(state, CFPropertyListIsValid(
            (__bridge CFPropertyListRef)[weakSelf object:state->gpr[3]],
            (CFPropertyListFormat)state->gpr[4])); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListCreateFromXMLData"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFPropertyListRef (*CreateFromXMLFunction)(
                CFAllocatorRef, CFDataRef, CFOptionFlags, CFStringRef *);
            CreateFromXMLFunction function = (CreateFromXMLFunction)dlsym(RTLD_DEFAULT,
                "CFPropertyListCreateFromXMLData"); NSData *data = [weakSelf object:state->gpr[4]];
            CFStringRef errorString = NULL; CFPropertyListRef value = function && data ? function(
                kCFAllocatorDefault, (__bridge CFDataRef)data, state->gpr[5], &errorString) : NULL;
            if (state->gpr[6] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(errorString)]
                                                        address:state->gpr[6]]) return NO;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
        }];
    [registry registerSymbol:@"_CFPropertyListCreateXMLData" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; typedef CFDataRef (*CreateXMLDataFunction)(CFAllocatorRef, CFPropertyListRef);
        CreateXMLDataFunction function = (CreateXMLDataFunction)dlsym(RTLD_DEFAULT,
            "CFPropertyListCreateXMLData"); id value = [weakSelf object:state->gpr[4]];
        CFDataRef data = function && value ? function(kCFAllocatorDefault,
            (__bridge CFPropertyListRef)value) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(data)]); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListCreateDeepCopy" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; id value = [weakSelf object:state->gpr[4]]; CFPropertyListRef copy = value
            ? CFPropertyListCreateDeepCopy(kCFAllocatorDefault, (__bridge CFPropertyListRef)value,
                state->gpr[5]) : NULL;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(copy)]); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListWriteToStream" handler:^BOOL(BRPPCState *state,
                                                                              NSError **callError) {
        (void)callError; typedef CFIndex (*WriteToStreamFunction)(
            CFPropertyListRef, CFWriteStreamRef, CFPropertyListFormat, CFStringRef *);
        WriteToStreamFunction function = (WriteToStreamFunction)dlsym(RTLD_DEFAULT,
            "CFPropertyListWriteToStream"); id value = [weakSelf object:state->gpr[3]];
        id stream = [weakSelf object:state->gpr[4]]; CFStringRef errorString = NULL;
        CFIndex count = function && value && stream ? function((__bridge CFPropertyListRef)value,
            (__bridge CFWriteStreamRef)stream, state->gpr[5], &errorString) : 0;
        if (state->gpr[6] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(errorString)]
                                                    address:state->gpr[6]]) return NO;
        CFFinish(state, (uint32_t)count); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListCreateFromStream" handler:^BOOL(BRPPCState *state,
                                                                                 NSError **callError) {
        (void)callError; typedef CFPropertyListRef (*CreateFromStreamFunction)(CFAllocatorRef,
            CFReadStreamRef, CFIndex, CFOptionFlags, CFPropertyListFormat *, CFStringRef *);
        CreateFromStreamFunction function = (CreateFromStreamFunction)dlsym(RTLD_DEFAULT,
            "CFPropertyListCreateFromStream"); id stream = [weakSelf object:state->gpr[4]];
        CFPropertyListFormat format = 0; CFStringRef errorString = NULL; CFPropertyListRef value =
            function && stream ? function(kCFAllocatorDefault, (__bridge CFReadStreamRef)stream,
                (CFIndex)(int32_t)state->gpr[5], state->gpr[6], &format, &errorString) : NULL;
        if ((state->gpr[7] && ![registry.memory writeUInt32:(uint32_t)format address:state->gpr[7]]) ||
            (state->gpr[8] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(errorString)]
                                                        address:state->gpr[8]])) return NO;
        CFFinish(state, [weakSelf handle:CFBridgingRelease(value)]); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListCreateWithStream" handler:^BOOL(BRPPCState *state,
                                                                                 NSError **callError) {
        (void)callError; id stream = [weakSelf object:state->gpr[4]]; CFPropertyListFormat format = 0;
        CFErrorRef createdError = NULL; CFPropertyListRef value = stream ? CFPropertyListCreateWithStream(
            kCFAllocatorDefault, (__bridge CFReadStreamRef)stream, (CFIndex)(int32_t)state->gpr[5],
            state->gpr[6], &format, &createdError) : NULL;
        id bridgedValue = CFBridgingRelease(value), bridgedError = CFBridgingRelease(createdError);
        if ((state->gpr[7] && ![registry.memory writeUInt32:(uint32_t)format address:state->gpr[7]]) ||
            (state->gpr[8] && ![registry.memory writeUInt32:[weakSelf handle:bridgedError]
                                                        address:state->gpr[8]])) return NO;
        CFFinish(state, [weakSelf handle:bridgedValue]); return YES;
    }];
    [registry registerSymbol:@"_CFPropertyListWrite" handler:^BOOL(BRPPCState *state,
                                                                      NSError **callError) {
        (void)callError; id value = [weakSelf object:state->gpr[3]], stream = [weakSelf object:state->gpr[4]];
        CFErrorRef createdError = NULL; CFIndex count = value && stream ? CFPropertyListWrite(
            (__bridge CFPropertyListRef)value, (__bridge CFWriteStreamRef)stream,
            state->gpr[5], state->gpr[6], &createdError) : 0;
        if (state->gpr[7] && ![registry.memory writeUInt32:[weakSelf handle:CFBridgingRelease(createdError)]
                                                    address:state->gpr[7]]) return NO;
        CFFinish(state, (uint32_t)count); return YES;
    }];
    [registry registerSymbol:@"_CFBundleCopyLocalizedStringForLocalizations"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef CFStringRef (*Function)(CFBundleRef, CFStringRef, CFStringRef,
                CFStringRef, CFArrayRef); Function function = (Function)dlsym(
                    RTLD_DEFAULT, "CFBundleCopyLocalizedStringForLocalizations");
            id bundle = [weakSelf object:state->gpr[3]], localizations = [weakSelf object:state->gpr[7]];
            CFStringRef result = function && bundle ? function((__bridge CFBundleRef)bundle,
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
                (__bridge CFStringRef)[weakSelf string:state->gpr[6]],
                (__bridge CFArrayRef)localizations) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(result)]); return YES;
        }];
    for (NSString *symbol in @[@"_CFBundleIsExecutableLoadable",
                                 @"_CFBundleIsExecutableLoadableForURL"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef Boolean (*Function)(CFTypeRef); Function function =
                (Function)dlsym(RTLD_DEFAULT, [symbol substringFromIndex:1].UTF8String);
            id value = [weakSelf object:state->gpr[3]];
            CFFinish(state, function && value && function((__bridge CFTypeRef)value)); return YES;
        }];
    }
    [registry registerSymbol:@"_CFBundleIsArchitectureLoadable"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef Boolean (*Function)(cpu_type_t); Function function =
                (Function)dlsym(RTLD_DEFAULT, "CFBundleIsArchitectureLoadable");
            CFFinish(state, function && function((cpu_type_t)state->gpr[3])); return YES;
        }];
    for (NSString *symbol in @[@"_CFAttributedStringGetBidiLevelsAndResolvedDirections",
                                 @"_CFAttributedStringGetStatisticalWritingDirections"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; typedef bool (*Function)(CFAttributedStringRef, CFRange, int8_t,
                uint8_t *, uint8_t *); Function function = (Function)dlsym(
                    RTLD_DEFAULT, [symbol substringFromIndex:1].UTF8String);
            id value = [weakSelf object:state->gpr[3]]; uint32_t length = state->gpr[5];
            if (length > (1u << 24)) return NO; NSMutableData *levels = state->gpr[7]
                ? [NSMutableData dataWithLength:length] : nil;
            NSMutableData *directions = state->gpr[8] ? [NSMutableData dataWithLength:length] : nil;
            bool result = function && value && function((__bridge CFAttributedStringRef)value,
                CFRangeMake((CFIndex)(int32_t)state->gpr[4], length), (int8_t)state->gpr[6],
                levels.mutableBytes, directions.mutableBytes);
            if ((levels && ![registry.memory writeBytes:levels.bytes address:state->gpr[7] length:length]) ||
                (directions && ![registry.memory writeBytes:directions.bytes
                    address:state->gpr[8] length:length])) return NO;
            CFFinish(state, result); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFAllocatorAllocateBytes", @"_CFAllocatorAllocateTyped",
                                 @"_CFAllocatorReallocateBytes", @"_CFAllocatorReallocateTyped"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            BOOL reallocate = [symbol containsString:@"Reallocate"];
            BOOL typed = [symbol containsString:@"Typed"];
            BRPPCState adapted = *state; adapted.pc = [registry addressForSymbol:
                reallocate ? @"_CFAllocatorReallocate" : @"_CFAllocatorAllocate"];
            if (!reallocate && typed) adapted.gpr[5] = state->gpr[7];
            if (reallocate && typed) adapted.gpr[6] = state->gpr[8];
            BOOL handled = NO;
            if (![registry dispatchState:&adapted handled:&handled error:callError] || !handled) return NO;
            *state = adapted; return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamSetDispatchQueue", @"_CFWriteStreamSetDispatchQueue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]], queueObject = [weakSelf object:state->gpr[4]];
            dispatch_queue_t queue = queueObject
                ? (__bridge dispatch_queue_t)(__bridge void *)queueObject : NULL;
            if (stream && [symbol containsString:@"Read"])
                CFReadStreamSetDispatchQueue((__bridge CFReadStreamRef)stream, queue);
            else if (stream) CFWriteStreamSetDispatchQueue((__bridge CFWriteStreamRef)stream, queue);
            CFFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFReadStreamCopyDispatchQueue", @"_CFWriteStreamCopyDispatchQueue"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id stream = [weakSelf object:state->gpr[3]]; dispatch_queue_t queue = NULL;
            if (stream && [symbol containsString:@"Read"])
                queue = CFReadStreamCopyDispatchQueue((__bridge CFReadStreamRef)stream);
            else if (stream) queue = CFWriteStreamCopyDispatchQueue((__bridge CFWriteStreamRef)stream);
            id queueObject = queue ? (__bridge id)(__bridge void *)queue : nil;
            CFFinish(state, [weakSelf handle:queueObject]); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFStringConvertEncodingToWindowsCodepage",
                                 @"_CFStringConvertWindowsCodepageToEncoding"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t value = [symbol containsString:@"ToWindows"]
                ? CFStringConvertEncodingToWindowsCodepage(state->gpr[3])
                : CFStringConvertWindowsCodepageToEncoding(state->gpr[3]);
            CFFinish(state, value); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringCompareWithOptionsAndLocale"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *first = [weakSelf string:state->gpr[3]];
            NSString *second = [weakSelf string:state->gpr[4]]; id locale = [weakSelf object:state->gpr[8]];
            CFComparisonResult result = first && second ? CFStringCompareWithOptionsAndLocale(
                (__bridge CFStringRef)first, (__bridge CFStringRef)second,
                CFRangeMake((CFIndex)(int32_t)state->gpr[5], (CFIndex)(int32_t)state->gpr[6]),
                state->gpr[7], (__bridge CFLocaleRef)locale) : kCFCompareEqualTo;
            CFFinish(state, (uint32_t)result); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateArrayBySeparatingStrings"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[4]];
            NSString *separator = [weakSelf string:state->gpr[5]]; CFArrayRef array = string && separator
                ? CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault, (__bridge CFStringRef)string,
                    (__bridge CFStringRef)separator) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(array)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateByCombiningStrings"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id array = [weakSelf object:state->gpr[4]];
            NSString *separator = [weakSelf string:state->gpr[5]]; CFStringRef string = array && separator
                ? CFStringCreateByCombiningStrings(kCFAllocatorDefault, (__bridge CFArrayRef)array,
                    (__bridge CFStringRef)separator) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateArrayWithFindResults"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[4]];
            NSString *find = [weakSelf string:state->gpr[5]]; CFArrayRef array = string && find
                ? CFStringCreateArrayWithFindResults(kCFAllocatorDefault, (__bridge CFStringRef)string,
                    (__bridge CFStringRef)find, CFRangeMake((CFIndex)(int32_t)state->gpr[6],
                    (CFIndex)(int32_t)state->gpr[7]), state->gpr[8]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(array)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateExternalRepresentation"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[4]]; CFDataRef data = string
                ? CFStringCreateExternalRepresentation(kCFAllocatorDefault, (__bridge CFStringRef)string,
                    state->gpr[5], (UInt8)state->gpr[6]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(data)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateFromExternalRepresentation"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id data = [weakSelf object:state->gpr[4]]; CFStringRef string = data
                ? CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (__bridge CFDataRef)data,
                    state->gpr[5]) : NULL;
            CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateWithFileSystemRepresentation"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *data = [weakSelf cstringDataAtAddress:state->gpr[4]];
            NSString *string = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            CFFinish(state, [weakSelf handle:string]); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetFileSystemRepresentation"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]]; uint32_t capacity = state->gpr[5];
            if (capacity > (1u << 28)) return NO; NSMutableData *buffer = [NSMutableData dataWithLength:capacity];
            Boolean result = string && CFStringGetFileSystemRepresentation((__bridge CFStringRef)string,
                buffer.mutableBytes, capacity); if (result && ![registry.memory writeBytes:buffer.bytes
                    address:state->gpr[4] length:strnlen(buffer.bytes, capacity) + 1]) return NO;
            CFFinish(state, result); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetMaximumSizeOfFileSystemRepresentation"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
            CFFinish(state, string ? (uint32_t)CFStringGetMaximumSizeOfFileSystemRepresentation(
                (__bridge CFStringRef)string) : 0); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetMaximumSizeForEncoding"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFFinish(state, (uint32_t)CFStringGetMaximumSizeForEncoding(
                (CFIndex)(int32_t)state->gpr[3], state->gpr[4])); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetIntValue" handler:^BOOL(BRPPCState *state,
                                                                        NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
        CFFinish(state, (uint32_t)(string ? CFStringGetIntValue((__bridge CFStringRef)string) : 0)); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetDoubleValue" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
        state->fpr[1] = string ? CFStringGetDoubleValue((__bridge CFStringRef)string) : 0;
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_CFStringGetFastestEncoding", @"_CFStringGetSmallestEncoding"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]]; uint32_t result = 0;
            if (string) result = [symbol containsString:@"Fastest"]
                ? CFStringGetFastestEncoding((__bridge CFStringRef)string)
                : CFStringGetSmallestEncoding((__bridge CFStringRef)string);
            CFFinish(state, result); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringGetNameOfEncoding" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; CFFinish(state, [weakSelf handle:(__bridge id)CFStringGetNameOfEncoding(
            state->gpr[3])]); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetMostCompatibleMacStringEncoding"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; CFFinish(state, CFStringGetMostCompatibleMacStringEncoding(state->gpr[3])); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateWithPascalString"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint8_t length = 0;
            if (![registry.memory readBytes:&length address:state->gpr[4] length:1]) return NO;
            NSMutableData *data = [NSMutableData dataWithLength:length];
            if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] + 1 length:length]) return NO;
            NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(state->gpr[5]);
            CFFinish(state, [weakSelf handle:[[NSString alloc] initWithData:data encoding:encoding]]); return YES;
        }];
    [registry registerSymbol:@"_CFStringAppendCString" handler:^BOOL(BRPPCState *state,
                                                                          NSError **callError) {
        (void)callError; NSMutableString *string = [weakSelf object:state->gpr[3]];
        NSData *data = [weakSelf cstringDataAtAddress:state->gpr[4]];
        NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(state->gpr[5]);
        NSString *append = data ? [[NSString alloc] initWithData:data encoding:encoding] : nil;
        if (string && append) [string appendString:append];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringAppendPascalString" handler:^BOOL(BRPPCState *state,
                                                                               NSError **callError) {
        (void)callError; uint8_t length = 0;
        if (![registry.memory readBytes:&length address:state->gpr[4] length:1]) return NO;
        NSMutableData *data = [NSMutableData dataWithLength:length];
        if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] + 1 length:length]) return NO;
        NSString *append = [[NSString alloc] initWithData:data encoding:
            CFStringConvertEncodingToNSStringEncoding(state->gpr[5])];
        NSMutableString *string = [weakSelf object:state->gpr[3]]; if (string && append) [string appendString:append];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringGetPascalString" handler:^BOOL(BRPPCState *state,
                                                                           NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[3]]; uint32_t capacity = state->gpr[5];
        NSData *data = [string dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(state->gpr[6])
                            allowLossyConversion:NO];
        if (!data || data.length > 255 || data.length + 1 > capacity) { CFFinish(state, 0); return YES; }
        uint8_t length = (uint8_t)data.length;
        if (![registry.memory writeBytes:&length address:state->gpr[4] length:1] ||
            (length && ![registry.memory writeBytes:data.bytes
                address:state->gpr[4] + 1 length:length])) return NO;
        CFFinish(state, 1); return YES;
    }];
    [registry registerSymbol:@"_CFStringFind" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; NSString *string = [weakSelf string:state->gpr[3]], *find = [weakSelf string:state->gpr[4]];
        CFRange range = string && find ? CFStringFind((__bridge CFStringRef)string,
            (__bridge CFStringRef)find, state->gpr[5]) : CFRangeMake(kCFNotFound, 0);
        state->gpr[3] = (uint32_t)range.location; state->gpr[4] = (uint32_t)range.length;
        state->pc = state->lr; return YES;
    }];
    for (NSString *symbol in @[@"_CFStringFindWithOptions", @"_CFStringFindWithOptionsAndLocale"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; BOOL withLocale = [symbol containsString:@"Locale"];
            NSString *string = [weakSelf string:state->gpr[3]], *find = [weakSelf string:state->gpr[4]];
            CFRange result = CFRangeMake(kCFNotFound, 0); Boolean found = NO;
            if (string && find) found = withLocale ? CFStringFindWithOptionsAndLocale(
                (__bridge CFStringRef)string, (__bridge CFStringRef)find,
                CFRangeMake((CFIndex)(int32_t)state->gpr[5], (CFIndex)(int32_t)state->gpr[6]),
                state->gpr[7], (__bridge CFLocaleRef)[weakSelf object:state->gpr[8]], &result)
                : CFStringFindWithOptions((__bridge CFStringRef)string, (__bridge CFStringRef)find,
                CFRangeMake((CFIndex)(int32_t)state->gpr[5], (CFIndex)(int32_t)state->gpr[6]),
                state->gpr[7], &result);
            uint32_t address = state->gpr[withLocale ? 9 : 8];
            if (address && (![registry.memory writeUInt32:(uint32_t)result.location address:address] ||
                ![registry.memory writeUInt32:(uint32_t)result.length address:address + 4])) return NO;
            CFFinish(state, found); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringFindCharacterFromSet"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
            id set = [weakSelf object:state->gpr[4]]; CFRange result = CFRangeMake(kCFNotFound, 0);
            Boolean found = string && set && CFStringFindCharacterFromSet((__bridge CFStringRef)string,
                (__bridge CFCharacterSetRef)set, CFRangeMake((CFIndex)(int32_t)state->gpr[5],
                (CFIndex)(int32_t)state->gpr[6]), state->gpr[7], &result);
            if (state->gpr[8] && (![registry.memory writeUInt32:(uint32_t)result.location address:state->gpr[8]] ||
                ![registry.memory writeUInt32:(uint32_t)result.length address:state->gpr[8] + 4])) return NO;
            CFFinish(state, found); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetRangeOfComposedCharactersAtIndex"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]]; CFRange range = string
                ? CFStringGetRangeOfComposedCharactersAtIndex((__bridge CFStringRef)string,
                    (CFIndex)(int32_t)state->gpr[4]) : CFRangeMake(kCFNotFound, 0);
            state->gpr[3] = (uint32_t)range.location; state->gpr[4] = (uint32_t)range.length;
            state->pc = state->lr; return YES;
        }];
    for (NSString *symbol in @[@"_CFStringGetLineBounds", @"_CFStringGetParagraphBounds"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
            CFIndex begin = 0, end = 0, contentsEnd = 0; if (string) {
                CFRange range = CFRangeMake((CFIndex)(int32_t)state->gpr[4], (CFIndex)(int32_t)state->gpr[5]);
                if ([symbol containsString:@"Line"]) CFStringGetLineBounds((__bridge CFStringRef)string,
                    range, &begin, &end, &contentsEnd); else CFStringGetParagraphBounds(
                    (__bridge CFStringRef)string, range, &begin, &end, &contentsEnd); }
            uint32_t values[3] = {(uint32_t)begin, (uint32_t)end, (uint32_t)contentsEnd};
            for (NSUInteger index = 0; index < 3; index++) if (state->gpr[6 + index] &&
                ![registry.memory writeUInt32:values[index] address:state->gpr[6 + index]]) return NO;
            CFFinish(state, 0); return YES;
        }];
    }
    for (NSString *symbol in @[@"_CFStringCreateWithCharactersNoCopy",
                                 @"_CFStringCreateMutableWithExternalCharactersNoCopy"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t count = state->gpr[5]; unichar *characters = calloc(
                MAX(count, 1u), sizeof(*characters)); if (!characters) return NO;
            BOOL valid = YES; for (uint32_t index = 0; index < count; index++) { uint8_t bytes[2] = {0};
                if (![registry.memory readBytes:bytes address:state->gpr[4] + index * 2 length:2]) {
                    valid = NO; break; } characters[index] = (unichar)((uint16_t)bytes[0] << 8 | bytes[1]); }
            BOOL mutable = [symbol containsString:@"Mutable"]; id string = valid
                ? (mutable ? [NSMutableString stringWithCharacters:characters length:count]
                           : [NSString stringWithCharacters:characters length:count]) : nil;
            free(characters); if (!valid) return NO; uint32_t handle = [weakSelf handle:string];
            if (handle) { BRPPCGuestExternalStringRecord *record = [BRPPCGuestExternalStringRecord new];
                record.address = state->gpr[4]; record.capacity = mutable ? state->gpr[6] : count;
                weakSelf.externalStringRecords[@(handle)] = record; }
            CFFinish(state, handle); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringSetExternalCharactersNoCopy"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t count = state->gpr[5]; unichar *characters = calloc(
                MAX(count, 1u), sizeof(*characters)); if (!characters) return NO;
            BOOL valid = YES; for (uint32_t index = 0; index < count; index++) { uint8_t bytes[2] = {0};
                if (![registry.memory readBytes:bytes address:state->gpr[4] + index * 2 length:2]) {
                    valid = NO; break; } characters[index] = (unichar)((uint16_t)bytes[0] << 8 | bytes[1]); }
            NSMutableString *string = [weakSelf object:state->gpr[3]];
            if (valid && string) [string setString:[NSString stringWithCharacters:characters length:count]];
            free(characters); if (!valid || !string) return NO;
            BRPPCGuestExternalStringRecord *record = weakSelf.externalStringRecords[@(state->gpr[3])];
            if (!record) { record = [BRPPCGuestExternalStringRecord new];
                weakSelf.externalStringRecords[@(state->gpr[3])] = record; }
            record.address = state->gpr[4]; record.capacity = state->gpr[6]; record.ownsBuffer = NO;
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetCharactersPtr" handler:^BOOL(BRPPCState *state,
                                                                             NSError **callError) {
        (void)callError; BRPPCGuestExternalStringRecord *record = weakSelf.externalStringRecords[@(state->gpr[3])];
        if (!record) { NSString *string = [weakSelf string:state->gpr[3]]; if (!string) {
                CFFinish(state, 0); return YES; }
            record = [BRPPCGuestExternalStringRecord new]; record.capacity = (uint32_t)string.length;
            record.address = registry.guestAllocator ? registry.guestAllocator(
                MAX(record.capacity * 2, 2u), NO) : 0; record.ownsBuffer = YES;
            if (!record.address) return NO; weakSelf.externalStringRecords[@(state->gpr[3])] = record;
            if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        }
        CFFinish(state, record.address); return YES;
    }];
    for (NSString *symbol in @[@"_CFStringFold", @"_CFStringNormalize", @"_CFStringReplaceAll"]) {
        [registry registerSymbol:symbol handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSMutableString *string = [weakSelf object:state->gpr[3]];
            if (!string) return NO;
            if ([symbol containsString:@"Fold"]) CFStringFold((__bridge CFMutableStringRef)string,
                state->gpr[4], (__bridge CFLocaleRef)[weakSelf object:state->gpr[5]]);
            else if ([symbol containsString:@"Normalize"])
                CFStringNormalize((__bridge CFMutableStringRef)string, state->gpr[4]);
            else CFStringReplaceAll((__bridge CFMutableStringRef)string,
                (__bridge CFStringRef)[weakSelf string:state->gpr[4]]);
            if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
            CFFinish(state, 0); return YES;
        }];
    }
    [registry registerSymbol:@"_CFStringInsert" handler:^BOOL(BRPPCState *state,
                                                                   NSError **callError) {
        (void)callError; NSMutableString *string = [weakSelf object:state->gpr[3]];
        if (string) CFStringInsert((__bridge CFMutableStringRef)string, (CFIndex)(int32_t)state->gpr[4],
            (__bridge CFStringRef)[weakSelf string:state->gpr[5]]);
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringPad" handler:^BOOL(BRPPCState *state,
                                                                NSError **callError) {
        (void)callError; NSMutableString *string = [weakSelf object:state->gpr[3]];
        if (string) CFStringPad((__bridge CFMutableStringRef)string,
            (__bridge CFStringRef)[weakSelf string:state->gpr[4]],
            (CFIndex)(int32_t)state->gpr[5], (CFIndex)(int32_t)state->gpr[6]);
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringTransform" handler:^BOOL(BRPPCState *state,
                                                                      NSError **callError) {
        (void)callError; NSMutableString *string = [weakSelf object:state->gpr[3]]; CFRange range = {0};
        uint32_t location = 0, length = 0;
        if (state->gpr[4] && (![registry.memory readUInt32:&location address:state->gpr[4]] ||
            ![registry.memory readUInt32:&length address:state->gpr[4] + 4])) return NO;
        range.location = (CFIndex)(int32_t)location; range.length = (CFIndex)(int32_t)length;
        Boolean result = string && CFStringTransform((__bridge CFMutableStringRef)string,
            state->gpr[4] ? &range : NULL, (__bridge CFStringRef)[weakSelf string:state->gpr[5]],
            state->gpr[6] != 0);
        if (state->gpr[4] && (![registry.memory writeUInt32:(uint32_t)range.location address:state->gpr[4]] ||
            ![registry.memory writeUInt32:(uint32_t)range.length address:state->gpr[4] + 4])) return NO;
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, result); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateWithBytesNoCopy"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t length = state->gpr[5]; if (length > (1u << 28)) return NO;
            NSMutableData *data = [NSMutableData dataWithLength:length];
            if (length && ![registry.memory readBytes:data.mutableBytes address:state->gpr[4] length:length]) return NO;
            CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault, data.bytes, length,
                state->gpr[6], state->gpr[7] != 0);
            CFFinish(state, [weakSelf handle:CFBridgingRelease(string)]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateWithCStringNoCopy"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSData *data = [weakSelf cstringDataAtAddress:state->gpr[4]];
            NSString *string = data ? [[NSString alloc] initWithData:data encoding:
                CFStringConvertEncodingToNSStringEncoding(state->gpr[5])] : nil;
            CFFinish(state, [weakSelf handle:string]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateWithPascalStringNoCopy"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            BRPPCState adapted = *state; adapted.pc = [registry addressForSymbol:@"_CFStringCreateWithPascalString"];
            BOOL handled = NO;
            if (![registry dispatchState:&adapted handled:&handled error:callError] || !handled) return NO;
            *state = adapted; return YES;
        }];
    [registry registerSymbol:@"_CFStringGetPascalStringPtr"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
            NSData *data = [string dataUsingEncoding:CFStringConvertEncodingToNSStringEncoding(state->gpr[4])
                                allowLossyConversion:NO];
            if (!data || data.length > 255) { CFFinish(state, 0); return YES; }
            NSMutableData *pascalData = [NSMutableData dataWithLength:data.length + 1];
            ((uint8_t *)pascalData.mutableBytes)[0] = (uint8_t)data.length;
            if (data.length) memcpy((uint8_t *)pascalData.mutableBytes + 1, data.bytes, data.length);
            CFFinish(state, [weakSelf copyBytesToGuest:pascalData.bytes length:pascalData.length]); return YES;
        }];
    [registry registerSymbol:@"_CFStringIsHyphenationAvailableForLocale"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id locale = [weakSelf object:state->gpr[3]];
            CFFinish(state, locale && CFStringIsHyphenationAvailableForLocale(
                (__bridge CFLocaleRef)locale)); return YES;
        }];
    [registry registerSymbol:@"_CFStringGetHyphenationLocationBeforeIndex"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSString *string = [weakSelf string:state->gpr[3]];
            id locale = [weakSelf object:state->gpr[8]]; UTF32Char character = 0;
            CFIndex location = string && locale ? CFStringGetHyphenationLocationBeforeIndex(
                (__bridge CFStringRef)string, (CFIndex)(int32_t)state->gpr[4],
                CFRangeMake((CFIndex)(int32_t)state->gpr[5], (CFIndex)(int32_t)state->gpr[6]),
                state->gpr[7], (__bridge CFLocaleRef)locale, state->gpr[9] ? &character : NULL) : kCFNotFound;
            if (state->gpr[9] && ![registry.memory writeUInt32:character address:state->gpr[9]]) return NO;
            CFFinish(state, (uint32_t)location); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateWithFormat"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            NSString *rendered = [weakSelf renderGuestFormat:[weakSelf string:state->gpr[5]]
                state:state cursor:6 error:callError]; if (!rendered) return NO;
            CFFinish(state, [weakSelf handle:rendered]); return YES;
        }];
    [registry registerSymbol:@"_CFStringAppendFormat" handler:^BOOL(BRPPCState *state,
                                                                         NSError **callError) {
        NSString *rendered = [weakSelf renderGuestFormat:[weakSelf string:state->gpr[5]]
            state:state cursor:6 error:callError]; if (!rendered) return NO;
        NSMutableString *string = [weakSelf object:state->gpr[3]]; [string appendString:rendered];
        if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
        CFFinish(state, 0); return YES;
    }];
    [registry registerSymbol:@"_CFStringCreateWithFormatAndArguments"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            NSString *rendered = [weakSelf renderGuestVAFormat:[weakSelf string:state->gpr[5]]
                argumentsAddress:state->gpr[6] error:callError]; if (!rendered) return NO;
            CFFinish(state, [weakSelf handle:rendered]); return YES;
        }];
    [registry registerSymbol:@"_CFStringAppendFormatAndArguments"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            NSString *rendered = [weakSelf renderGuestVAFormat:[weakSelf string:state->gpr[5]]
                argumentsAddress:state->gpr[6] error:callError]; if (!rendered) return NO;
            NSMutableString *string = [weakSelf object:state->gpr[3]]; if (!string) return NO;
            [string appendString:rendered];
            if (![weakSelf syncExternalStringHandle:state->gpr[3]]) return NO;
            CFFinish(state, 0); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateStringWithValidatedFormat"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; NSInteger validation = [weakSelf validateFormat:[weakSelf string:state->gpr[6]]
                expected:[weakSelf string:state->gpr[5]] errorAddress:state->gpr[7]];
            if (validation < 0) return NO;
            if (!validation) { CFFinish(state, 0); return YES; }
            NSString *rendered = [weakSelf renderGuestFormat:[weakSelf string:state->gpr[6]]
                state:state cursor:8 error:callError]; if (!rendered) return NO;
            CFFinish(state, [weakSelf handle:rendered]); return YES;
        }];
    [registry registerSymbol:@"_CFStringCreateStringWithValidatedFormatAndArguments"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            NSInteger validation = [weakSelf validateFormat:[weakSelf string:state->gpr[6]]
                expected:[weakSelf string:state->gpr[5]] errorAddress:state->gpr[8]];
            if (validation < 0) return NO;
            if (!validation) { CFFinish(state, 0); return YES; }
            NSString *rendered = [weakSelf renderGuestVAFormat:[weakSelf string:state->gpr[6]]
                argumentsAddress:state->gpr[7] error:callError]; if (!rendered) return NO;
            CFFinish(state, [weakSelf handle:rendered]); return YES;
        }];
    return YES;
}

@end
