#import "BRPowerPC32.h"
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>

static NSString * const BRPPCSecurityErrorDomain = @"theoderoy.Bismuth.SecurityAuthorizer";

@implementation BRPPCSecurityAuthorizer
- (BOOL)authorizeInstruction:(uint32_t)instruction
                 description:(NSString *)description
                       error:(NSError **)error {
    AuthorizationRef authorization = NULL;
    OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                          kAuthorizationFlagDefaults, &authorization);
    if (status == errAuthorizationSuccess) {
        const char *prompt = description.UTF8String;
        AuthorizationItem environmentItem = {
            kAuthorizationEnvironmentPrompt, strlen(prompt) + 1, (void *)prompt, 0
        };
        AuthorizationEnvironment environment = { 1, &environmentItem };
        AuthorizationItem rightItem = { kAuthorizationRightExecute, 0, NULL, 0 };
        AuthorizationRights rights = { 1, &rightItem };
        status = AuthorizationCopyRights(authorization, &rights, &environment,
                                         kAuthorizationFlagInteractionAllowed |
                                         kAuthorizationFlagExtendRights,
                                         NULL);
    }
    if (authorization) AuthorizationFree(authorization, kAuthorizationFlagDestroyRights);
    if (status == errAuthorizationSuccess) return YES;
    if (error) {
        *error = [NSError errorWithDomain:BRPPCSecurityErrorDomain code:status userInfo:@{
            NSLocalizedDescriptionKey: status == errAuthorizationCanceled
                ? @"The administrator authorization was cancelled."
                : [NSString stringWithFormat:@"Administrator authorization failed (%d) for PowerPC instruction 0x%08x.", (int)status, instruction]
        }];
    }
    return NO;
}
@end
