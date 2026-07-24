#import <AppKit/AppKit.h>
#import "../Resolves/BRPPCApplicationRunner.h"
#import <mach-o/dyld.h>
#import <paths.h>
#import <unistd.h>

static NSString * const BRGuestPathEnvironment = @"BISMUTH_GUEST_PATH";
static NSString * const BRGuestArgumentsEnvironment = @"BISMUTH_GUEST_ARGUMENTS";
static NSString * const BRRunnerPathEnvironment = @"BISMUTH_RUNNER_PATH";

static NSString *BRSystemExecutable(NSString *name) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *systemPath = [NSString stringWithUTF8String:_PATH_STDPATH];
    for (NSString *directory in [systemPath componentsSeparatedByString:@":"]) {
        NSString *candidate = [directory stringByAppendingPathComponent:name];
        if ([files isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

static uint64_t BRHostIdentityHash(NSString *path, NSArray<NSString *> *arguments) {
    NSData *data = [[NSString stringWithFormat:@"%@\n%@", path.stringByStandardizingPath,
        [arguments componentsJoinedByString:@"\n"]] dataUsingEncoding:NSUTF8StringEncoding];
    uint64_t hash = UINT64_C(14695981039346656037);
    for (NSUInteger index = 0; index < data.length; index++) {
        hash ^= ((const uint8_t *)data.bytes)[index];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static BOOL BRRelaunchFromApplicationBundle(NSString *path, NSArray<NSString *> *arguments) {
    if (getenv("BISMUTH_APP_HOST")) return YES;
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL directory = NO;
    [files fileExistsAtPath:path isDirectory:&directory];
    NSBundle *guestBundle = directory ? [NSBundle bundleWithPath:path] : nil;
    NSDictionary *guestInfo = guestBundle.infoDictionary;
    NSString *presentationName = guestInfo[@"CFBundleDisplayName"] ?: guestInfo[@"CFBundleName"];
    if (!presentationName.length) presentationName = path.lastPathComponent.stringByDeletingPathExtension;
    if (!presentationName.length) presentationName = @"Bismuth";
    NSString *bundleFileName = [[presentationName stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
        stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    uint64_t identity = BRHostIdentityHash(path, arguments);
    NSString *suffix = [NSString stringWithFormat:@"%016llx", identity];
    uint32_t runnerSize = 0;
    _NSGetExecutablePath(NULL, &runnerSize);
    char *runnerBytes = malloc(runnerSize);
    if (!runnerBytes || _NSGetExecutablePath(runnerBytes, &runnerSize)) {
        free(runnerBytes); return NO;
    }
    NSString *runnerPath = [[NSFileManager defaultManager]
        stringWithFileSystemRepresentation:runnerBytes length:strlen(runnerBytes)];
    free(runnerBytes);
    NSString *hostName = runnerPath.lastPathComponent;

    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"Bismuth-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *bundlePath = [root stringByAppendingPathComponent:
        [bundleFileName stringByAppendingPathExtension:@"app"]];
    NSString *contents = [bundlePath stringByAppendingPathComponent:@"Contents"];
    NSString *macOS = [contents stringByAppendingPathComponent:@"MacOS"];
    NSString *resources = [contents stringByAppendingPathComponent:@"Resources"];
    NSError *error = nil;
    NSString *hostGuestPath = path;
    NSMutableDictionary *info = nil;
    NSData *json = nil;
    NSMutableDictionary *environment = nil;
    NSString *codesignPath = nil;
    NSTask *signTask = nil;
    NSTask *retrySignTask = nil;
    NSTask *host = nil;
    NSString *guestResources = directory
        ? [path stringByAppendingPathComponent:@"Contents/Resources"] : nil;
    if (![files createDirectoryAtPath:macOS withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![files copyItemAtPath:runnerPath toPath:[macOS stringByAppendingPathComponent:hostName]
                         error:&error]) goto fail;

    if (guestResources.length && [files fileExistsAtPath:guestResources]) {
        if (![files createSymbolicLinkAtPath:resources withDestinationPath:guestResources error:&error])
            goto fail;
    } else if (![files createDirectoryAtPath:resources withIntermediateDirectories:YES
                                   attributes:nil error:&error]) goto fail;

    info = [NSMutableDictionary dictionaryWithDictionary:@{
        @"CFBundleIdentifier": [@"theoderoy.BismuthInterpreter." stringByAppendingString:suffix],
        @"CFBundleExecutable": hostName, @"CFBundleName": presentationName,
        @"CFBundleDisplayName": presentationName, @"CFBundlePackageType": @"APPL",
        @"CFBundleVersion": @"1"
    }];
    for (NSString *key in @[@"CFBundleIconFile", @"CFBundleIconName", @"CFBundleIcons",
                             @"CFBundleDevelopmentRegion", @"CFBundleLocalizations"]) {
        if (guestInfo[key]) info[key] = guestInfo[key];
    }
    if (![info writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES]) {
        fprintf(stderr, "BismuthInterpreter: cannot write host metadata\n"); return NO;
    }
    signTask = [NSTask new];
    codesignPath = BRSystemExecutable(@"codesign");
    if (!codesignPath) {
        fprintf(stderr, "BismuthInterpreter: cannot locate codesign\n");
        return NO;
    }
    signTask.executableURL = [NSURL fileURLWithPath:codesignPath];
    signTask.arguments = @[@"--force", @"--sign", @"-", bundlePath];
    signTask.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    signTask.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![signTask launchAndReturnError:&error]) goto fail;
    [signTask waitUntilExit];
    if (signTask.terminationStatus != 0) {
        retrySignTask = [NSTask new];
        retrySignTask.executableURL = signTask.executableURL;
        retrySignTask.arguments = signTask.arguments;
        retrySignTask.standardOutput = [NSFileHandle fileHandleWithNullDevice];
        retrySignTask.standardError = [NSFileHandle fileHandleWithNullDevice];
        if (![retrySignTask launchAndReturnError:&error]) goto fail;
        [retrySignTask waitUntilExit];
        if (retrySignTask.terminationStatus != 0) {
            error = [NSError errorWithDomain:@"theoderoy.BismuthInterpreterGuest" code:3
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Could not ad-hoc sign generated application host."}];
            goto fail;
        }
    }
    if (!directory) {
        NSImage *fileIcon = [NSWorkspace.sharedWorkspace iconForFile:path];
        if (fileIcon) [NSWorkspace.sharedWorkspace setIcon:fileIcon forFile:bundlePath options:0];
    }
    json = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:&error];
    if (!json) goto fail;
    environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"BISMUTH_APP_HOST"] = @"1";
    environment[BRRunnerPathEnvironment] = runnerPath;
    environment[BRGuestPathEnvironment] = hostGuestPath;
    environment[BRGuestArgumentsEnvironment] = [json base64EncodedStringWithOptions:0];
    host = [NSTask new];
    host.executableURL = [NSURL fileURLWithPath:[macOS stringByAppendingPathComponent:hostName]];
    host.environment = environment;
    host.standardInput = NSFileHandle.fileHandleWithStandardInput;
    host.standardOutput = NSFileHandle.fileHandleWithStandardOutput;
    host.standardError = NSFileHandle.fileHandleWithStandardError;
    if (![host launchAndReturnError:&error]) goto fail;
    [host waitUntilExit];
    _exit(host.terminationStatus);
fail:
    fprintf(stderr, "BismuthInterpreter: cannot create or launch application host: %s\n",
            error.localizedDescription.UTF8String); return NO;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *path = nil;
        NSMutableArray<NSString *> *arguments = nil;
        int pathIndex = 1;
        BOOL traceTranslations = NO;
        while (pathIndex < argc) {
            if (strcmp(argv[pathIndex], "--trace") == 0) {
                traceTranslations = YES;
                pathIndex++;
                continue;
            }
            if (strcmp(argv[pathIndex], "--") == 0) pathIndex++;
            break;
        }
        const char *hostPath = getenv(BRGuestPathEnvironment.UTF8String);
        const char *hostArguments = getenv(BRGuestArgumentsEnvironment.UTF8String);
        if (getenv("BISMUTH_APP_HOST") && hostPath && hostArguments) {
            path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:hostPath
                                                                               length:strlen(hostPath)];
            NSData *encoded = [[NSData alloc] initWithBase64EncodedString:@(hostArguments) options:0];
            NSArray *decoded = encoded ? [NSJSONSerialization JSONObjectWithData:encoded options:0
                                                                            error:nil] : nil;
            if (![decoded isKindOfClass:NSArray.class]) return 64;
            arguments = [decoded mutableCopy];
        } else if (pathIndex >= argc) {
            fprintf(stderr, "usage: BismuthInterpreter [--trace]");
            return 64;
        } else {
            path = [[NSFileManager defaultManager]
                stringWithFileSystemRepresentation:argv[pathIndex] length:strlen(argv[pathIndex])];
            arguments = [NSMutableArray arrayWithObject:path];
            for (int i = pathIndex + 1; i < argc; i++)
                [arguments addObject:[[NSFileManager defaultManager]
                    stringWithFileSystemRepresentation:argv[i] length:strlen(argv[i])]];
        }
        if (traceTranslations) {
            setenv("BISMUTH_OBJC_TRACE", "1", 1);
            setenv("BISMUTH_SCARLET_TRACE", "1", 1);
        }
        BOOL directory = NO;
        if (!getenv("BISMUTH_APP_HOST") &&
            [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] &&
            !BRRelaunchFromApplicationBundle(path, arguments)) return 1;
        BRPPCApplicationRunner *runner = [BRPPCApplicationRunner new];
        if (getenv("BISMUTH_APP_HOST") &&
            ![[NSFileManager defaultManager] changeCurrentDirectoryPath:path.stringByDeletingLastPathComponent]) {
            fprintf(stderr, "BismuthInterpreter: cannot enter staged guest directory\n");
            return 1;
        }
        NSError *error = nil;
        int status = 0;
        if (![runner runApplicationAtURL:[NSURL fileURLWithPath:path]
                               arguments:arguments exitStatus:&status error:&error]) {
            fprintf(stderr, "BismuthInterpreter: %s\n", error.localizedDescription.UTF8String);
            const char *errorLogPath = getenv("BISMUTH_ERROR_LOG");
            if (errorLogPath && *errorLogPath) {
                FILE *errorLog = fopen(errorLogPath, "a");
                if (errorLog) {
                    fprintf(errorLog, "BismuthInterpreter: %s\n", error.localizedDescription.UTF8String);
                    fclose(errorLog);
                }
            }
            return 1;
        }
        return status;
    }
}
