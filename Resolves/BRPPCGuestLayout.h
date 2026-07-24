#import <stdint.h>

static const uint32_t BRPPCGuestSyntheticHandlerBase = 0xfff00000u;
static const uint32_t BRPPCGuestLegacyObjCDispatchAddress = 0xfffeff00u;
static const uint32_t BRPPCGuestScarletDataBase = 0xffe00000u;
static const uint32_t BRPPCGuestScarletDataSize = 0x00010000u;
static const uint32_t BRPPCGuestObjectHandleBase = 0xffd00000u;
static const uint32_t BRPPCGuestObjectStorageSize = 0x00100000u;
static const uint32_t BRPPCGuestObjectiveCDataBase = 0xffc00000u;
static const uint32_t BRPPCGuestObjectiveCDataSize = 0x00001000u;
static const uint32_t BRPPCGuestObjectiveCSelectorOffset = 0x00000800u;
static const uint32_t BRPPCGuestDarwinDataBase = 0xffb00000u;
static const uint32_t BRPPCGuestDarwinDataSize = 0x00001000u;
static const uint32_t BRPPCGuestStreamHandleBase = 0xffa00000u;
static const uint32_t BRPPCGuestCallbackDataBase = 0xff900000u;
static const uint32_t BRPPCGuestCallbackDataSize = 0x00100000u;
static const uint32_t BRPPCGuestDirectoryHandleBase = 0xff800000u;
static const uint32_t BRPPCGuestQuickTimeHandleBase = 0xff700000u;
static const uint32_t BRPPCGuestACLHandleBase = 0xff600000u;
static const uint32_t BRPPCGuestFrameworkDataBase = 0xff500000u;
static const uint32_t BRPPCGuestFrameworkDataSize = 0x00100000u;
static const uint32_t BRPPCGuestCallbackStackBase = 0xff400000u;
static const uint32_t BRPPCGuestCallbackStackSize = 0x00100000u;
static const uint32_t BRPPCGuestCallbackSlotSize = 0x00004000u;
static const uint32_t BRPPCGuestCallbackScratchOffset = 0x00000100u;
static const uint32_t BRPPCGuestStackFrameReserve = 32u;
static const uint32_t BRPPCGuestProcessStackBase = 0x70000000u;
static const uint32_t BRPPCGuestProcessStackSize = 0x00100000u;
static const uint32_t BRPPCGuestHeapSize = 0x04000000u;
static const uint32_t BRPPCGuestHeapSearchStart = 0x60000000u;
static const uint32_t BRPPCGuestHeapSearchEnd = 0x10000000u;
static const uint32_t BRPPCGuestHeapSearchStride = 0x10000000u;
static const uint32_t BRPPCGuestHeapFallback = 0x08000000u;

enum { BRPPCGuestCallbackSlotCount = 64 };
