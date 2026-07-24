#import <Foundation/Foundation.h>
#import "../Core/BRPowerPC32.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(uint8_t, BRPPCMemoryProtection) {
    BRPPCMemoryRead = 1 << 0,
    BRPPCMemoryWrite = 1 << 1,
    BRPPCMemoryExecute = 1 << 2,
};


@interface BRPPCAddressSpace : NSObject <BRPPCMemory>
- (BOOL)mapAddress:(uint32_t)address
              size:(uint32_t)size
        protection:(BRPPCMemoryProtection)protection
              name:(NSString *)name
             error:(NSError **)error;
- (BOOL)copyData:(NSData *)data toAddress:(uint32_t)address error:(NSError **)error;
- (BOOL)readUInt32:(uint32_t *)value address:(uint32_t)address;
- (BOOL)writeUInt32:(uint32_t)value address:(uint32_t)address;
- (nullable NSString *)readCStringAtAddress:(uint32_t)address maximumLength:(NSUInteger)limit;
@end

NS_ASSUME_NONNULL_END
