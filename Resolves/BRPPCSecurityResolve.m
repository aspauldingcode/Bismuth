#import "BRPPCSecurityResolve.h"
#import "BRPPCAddressSpace.h"
#import <Security/Security.h>

static void BRSecurityFinish(BRPPCState *state, uint32_t value) {
    state->gpr[3] = value; state->pc = state->lr;
}

@implementation BRPPCSecurityResolve
- (instancetype)init { return [super initWithFrameworkName:@"Security"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    uint8_t oid[8] = {0};
    if (![self registerDataConstant:@"_CSSMOID_APPLE_X509_BASIC"
        data:[NSData dataWithBytes:oid length:sizeof(oid)] alignment:4 registry:registry error:error]) return NO;
    [registry registerSymbol:@"_SecCertificateCreateFromData"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; uint32_t length = 0, address = 0;
            if (!state->gpr[3] || ![registry.memory readUInt32:&length address:state->gpr[3]] ||
                ![registry.memory readUInt32:&address address:state->gpr[3] + 4] || length > (1u << 26)) {
                BRSecurityFinish(state, 0); return YES;
            }
            NSMutableData *data = [NSMutableData dataWithLength:length];
            if (length && ![registry.memory readBytes:data.mutableBytes address:address length:length]) {
                BRSecurityFinish(state, 0); return YES;
            }
            SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
            id certificateObject = CFBridgingRelease(certificate);
            uint32_t handle = certificateObject && registry.guestObjectEncoder
                ? registry.guestObjectEncoder(certificateObject) : 0;
            BRSecurityFinish(state, handle); return YES;
        }];
    [registry registerSymbol:@"_SecPolicySearchCreate"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; SecPolicyRef policy = SecPolicyCreateBasicX509();
            id policyObject = CFBridgingRelease(policy);
            uint32_t handle = policyObject && registry.guestObjectEncoder
                ? registry.guestObjectEncoder(policyObject) : 0;
            if (!state->gpr[6] || ![registry.memory writeUInt32:handle address:state->gpr[6]])
                BRSecurityFinish(state, (uint32_t)errSecParam);
            else BRSecurityFinish(state, handle ? 0 : (uint32_t)errSecAllocate);
            return YES;
        }];
    [registry registerSymbol:@"_SecPolicySearchCopyNext"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id policy = registry.guestObjectDecoder
                ? registry.guestObjectDecoder(state->gpr[3]) : nil;
            uint32_t handle = policy && registry.guestObjectEncoder
                ? registry.guestObjectEncoder(policy) : 0;
            if (!state->gpr[4] || ![registry.memory writeUInt32:handle address:state->gpr[4]])
                BRSecurityFinish(state, (uint32_t)errSecParam);
            else BRSecurityFinish(state, handle ? 0 : (uint32_t)errSecItemNotFound);
            return YES;
        }];
    [registry registerSymbol:@"_SecTrustCreateWithCertificates"
        handler:^BOOL(BRPPCState *state, NSError **callError) {
            (void)callError; id certificates = registry.guestObjectDecoder
                ? registry.guestObjectDecoder(state->gpr[3]) : nil;
            id policy = registry.guestObjectDecoder ? registry.guestObjectDecoder(state->gpr[4]) : nil;
            SecTrustRef trust = NULL;
            OSStatus status = certificates && policy
                ? SecTrustCreateWithCertificates((__bridge CFTypeRef)certificates,
                    (__bridge SecPolicyRef)policy, &trust) : errSecParam;
            id trustObject = CFBridgingRelease(trust);
            uint32_t handle = trustObject && registry.guestObjectEncoder
                ? registry.guestObjectEncoder(trustObject) : 0;
            if (!status && (!state->gpr[5] || ![registry.memory writeUInt32:handle address:state->gpr[5]]))
                status = errSecParam;
            BRSecurityFinish(state, (uint32_t)status); return YES;
        }];
    [registry registerSymbol:@"_SecTrustEvaluate" handler:^BOOL(BRPPCState *state, NSError **callError) {
        (void)callError; id trust = registry.guestObjectDecoder
            ? registry.guestObjectDecoder(state->gpr[3]) : nil;
        SecTrustResultType result = kSecTrustResultInvalid;
        OSStatus status = errSecParam;
        if (trust) {
            CFErrorRef evaluationError = NULL;
            BOOL trusted = SecTrustEvaluateWithError((__bridge SecTrustRef)trust, &evaluationError);
            result = trusted ? kSecTrustResultUnspecified : kSecTrustResultRecoverableTrustFailure;
            if (evaluationError) CFRelease(evaluationError);
            status = errSecSuccess;
        }
        if (!status && (!state->gpr[4] || ![registry.memory writeUInt32:(uint32_t)result
                                                                   address:state->gpr[4]])) status = errSecParam;
        BRSecurityFinish(state, (uint32_t)status); return YES;
    }];
    return YES;
}
@end
