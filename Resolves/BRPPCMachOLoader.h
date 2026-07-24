#import <Foundation/Foundation.h>

@class BRPPCAddressSpace;
@class BRPPCResolveRegistry;

NS_ASSUME_NONNULL_BEGIN

@interface BRPPCMachOSection : NSObject
@property(nonatomic, copy) NSString *segmentName;
@property(nonatomic, copy) NSString *sectionName;
@property(nonatomic) uint32_t address;
@property(nonatomic) uint32_t size;
@property(nonatomic) uint32_t flags;
@property(nonatomic) uint32_t reserved1;
@end

@interface BRPPCMachOImage : NSObject
@property(nonatomic, readonly) uint32_t entryPoint;
@property(nonatomic, readonly) uint32_t mainAddress;
@property(nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *symbols;
@property(nonatomic, readonly) NSArray<NSString *> *dependencies;
@property(nonatomic, readonly) NSArray<BRPPCMachOSection *> *sections;
@property(nonatomic, readonly) NSArray<NSString *> *undefinedSymbols;
@property(nonatomic, readonly) NSSet<NSString *> *weakUndefinedSymbols;
- (nullable BRPPCMachOSection *)sectionInSegment:(NSString *)segment name:(NSString *)name;
@end


@interface BRPPCMachOLoader : NSObject
- (nullable BRPPCMachOImage *)loadURL:(NSURL *)URL
                            intoMemory:(BRPPCAddressSpace *)memory
                                 error:(NSError **)error;
- (BOOL)bindImage:(BRPPCMachOImage *)image
         registry:(BRPPCResolveRegistry *)registry
            error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
