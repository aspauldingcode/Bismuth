#import "BRPPCAddressBookResolve.h"

@implementation BRPPCAddressBookResolve
- (instancetype)init { return [super initWithFrameworkName:@"AddressBook"]; }
- (BOOL)installFrameworkSymbolsInRegistry:(BRPPCResolveRegistry *)registry error:(NSError **)error {
    return [self registerStringConstants:@[@"_kABFirstNameProperty", @"_kABLastNameProperty"]
                                    registry:registry error:error];
}
@end
