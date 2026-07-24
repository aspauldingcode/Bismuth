#import "BRPowerPC32.h"
#import "BRPPCAltiVec.h"
#include <fenv.h>
#include <math.h>
#include <string.h>

enum { XER_SO = 0x80000000u, XER_OV = 0x40000000u, XER_CA = 0x20000000u };

#if defined(__aarch64__)
static inline uint64_t readHostFPCR(void) {
  uint64_t value;
  __asm__ volatile("mrs %0, fpcr" : "=r"(value));
  return value;
}
static inline void writeHostFPCR(uint64_t value) {
  __asm__ volatile("msr fpcr, %0" : : "r"(value));
}
static inline uint64_t readHostFPSR(void) {
  uint64_t value;
  __asm__ volatile("mrs %0, fpsr" : "=r"(value));
  return value;
}
static inline void writeHostFPSR(uint64_t value) {
  __asm__ volatile("msr fpsr, %0" : : "r"(value));
}
static inline int hostGetRound(void) {
  static const int modes[4] = {FE_TONEAREST, FE_UPWARD, FE_DOWNWARD, FE_TOWARDZERO};
  return modes[(readHostFPCR() >> 22) & 3];
}
static inline void hostSetRound(int mode) {
  unsigned encoded = mode == FE_UPWARD ? 1 : mode == FE_DOWNWARD ? 2 :
                     mode == FE_TOWARDZERO ? 3 : 0;
  uint64_t fpcr = readHostFPCR();
  writeHostFPCR((fpcr & ~(UINT64_C(3) << 22)) | ((uint64_t)encoded << 22));
}
static inline void hostClearFPExceptions(void) {
  writeHostFPSR(readHostFPSR() & ~UINT64_C(0x1f));
}
static inline int hostTestFPExceptions(void) {
  uint64_t flags = readHostFPSR();
  int result = 0;
  if (flags & (1u << 0)) result |= FE_INVALID;
  if (flags & (1u << 1)) result |= FE_DIVBYZERO;
  if (flags & (1u << 2)) result |= FE_OVERFLOW;
  if (flags & (1u << 3)) result |= FE_UNDERFLOW;
  if (flags & (1u << 4)) result |= FE_INEXACT;
  return result;
}
static inline void hostRaiseFPInvalid(void) {
  writeHostFPSR(readHostFPSR() | 1u);
}
#else
static inline int hostGetRound(void) { return fegetround(); }
static inline void hostSetRound(int mode) { fesetround(mode); }
static inline void hostClearFPExceptions(void) { feclearexcept(FE_ALL_EXCEPT); }
static inline int hostTestFPExceptions(void) { return fetestexcept(FE_ALL_EXCEPT); }
static inline void hostRaiseFPInvalid(void) { feraiseexcept(FE_INVALID); }
#endif

@interface BRPPCLinearMemory () {
  BRPPCInstructionCacheInvalidationHandler _instructionCacheInvalidationHandler;
}
@end

@implementation BRPPCLinearMemory
- (instancetype)initWithBaseAddress:(uint32_t)baseAddress
                               size:(NSUInteger)size {
  if ((self = [super init])) {
    _baseAddress = baseAddress;
    _data = [NSMutableData dataWithLength:size];
  }
  return self;
}
- (BOOL)readBytes:(void *)dst address:(uint32_t)a length:(size_t)n {
  uint64_t o = (uint64_t)a - _baseAddress;
  if (a < _baseAddress || n > _data.length || o > _data.length - n)
    return NO;
  memcpy(dst, (const uint8_t *)_data.bytes + o, n);
  return YES;
}
- (BOOL)writeBytes:(const void *)src address:(uint32_t)a length:(size_t)n {
  uint64_t o = (uint64_t)a - _baseAddress;
  if (a < _baseAddress || n > _data.length || o > _data.length - n)
    return NO;
  memcpy((uint8_t *)_data.mutableBytes + o, src, n);
  if (_instructionCacheInvalidationHandler)
    _instructionCacheInvalidationHandler(a, n);
  return YES;
}
- (void)setInstructionCacheInvalidationHandler:
    (BRPPCInstructionCacheInvalidationHandler)handler {
  _instructionCacheInvalidationHandler = [handler copy];
}
@end



typedef BRPPCStopReason (*BRExec)(uint32_t, BRPPCState *,
                                  id<BRPPCMemory> __unsafe_unretained,
                                  BRPowerPC32 * __unsafe_unretained);
typedef struct {
  uint32_t pc, word;
  BRExec exec;
} BRCacheEntry;

@interface BRPowerPC32 () {
  id<BRPPCMemory> _memory;
  BRPPCState _state;
  BRPPCStopReason _stopReason;
  BRCacheEntry _cache[4096];
}
- (BRPPCStopReason)executePrivilegedInstruction:(uint32_t)instruction;
- (void)invalidateTranslationCacheAtAddress:(uint32_t)address length:(size_t)length;
@end

static inline uint32_t rd(uint32_t w) { return (w >> 21) & 31; }
static inline uint32_t ra(uint32_t w) { return (w >> 16) & 31; }
static inline uint32_t rb(uint32_t w) { return (w >> 11) & 31; }
static inline int32_t sx16(uint32_t w) { return (int16_t)w; }
static inline uint32_t rotl32(uint32_t x, unsigned n) {
  n &= 31;
  return (x << n) | (x >> ((32 - n) & 31));
}
static inline uint32_t rotr32(uint32_t x, unsigned n) {
  return rotl32(x, 32 - (n & 31));
}
static inline uint32_t mask32(unsigned mb, unsigned me) {
  uint32_t fromMB = UINT32_MAX >> (mb & 31);
  uint32_t throughME = UINT32_MAX << (31 - (me & 31));
  return mb <= me ? fromMB & throughME : fromMB | throughME;
}
static inline void crbit(BRPPCState *s, unsigned bit, BOOL v) {
  uint32_t m = 1u << (31 - (bit & 31));
  s->cr = v ? s->cr | m : s->cr & ~m;
}
static inline BOOL getcr(const BRPPCState *s, unsigned bit) {
  return (s->cr >> (31 - (bit & 31))) & 1;
}
static void setcr0(BRPPCState *s, uint32_t v) {
  uint32_t f = (int32_t)v < 0 ? 8 : v ? 4 : 2;
  if (s->xer & XER_SO)
    f |= 1;
  s->cr = (s->cr & 0x0fffffff) | (f << 28);
}
static void setcmp(BRPPCState *s, unsigned f, int64_t a, int64_t b) {
  uint32_t x = a < b ? 8 : a > b ? 4 : 2;
  if (s->xer & XER_SO)
    x |= 1;
  unsigned sh = 28 - 4 * (f & 7);
  s->cr = (s->cr & ~(15u << sh)) | (x << sh);
}
static inline void setca(BRPPCState *s, BOOL v) {
  s->xer = v ? s->xer | XER_CA : s->xer & ~XER_CA;
}
static inline void setov(BRPPCState *s, BOOL v) {
  if (v)
    s->xer |= XER_OV | XER_SO;
  else
    s->xer &= ~XER_OV;
}
static inline BOOL addov32(uint32_t a, uint32_t b, uint32_t r) {
  return ((~(a ^ b) & (a ^ r)) >> 31) != 0;
}
static inline BOOL subov32(uint32_t a, uint32_t b, uint32_t r) {
  return (((a ^ b) & (b ^ r)) >> 31) != 0;
}
static inline BOOL outOfSignedWord(int64_t x) {
  return x < INT32_MIN || x > INT32_MAX;
}
static inline uint32_t ea0(BRPPCState *s, unsigned a) {
  return a ? s->gpr[a] : 0;
}
static BOOL memread(id<BRPPCMemory> __unsafe_unretained m, uint32_t a, void *p, size_t n) {
  return [m readBytes:p address:a length:n];
}
static BOOL memwrite(id<BRPPCMemory> __unsafe_unretained m, uint32_t a, const void *p, size_t n) {
  return [m writeBytes:p address:a length:n];
}
static BOOL loadbe(id<BRPPCMemory> __unsafe_unretained m, uint32_t a, unsigned n, uint32_t *out) {
  uint8_t b[4];
  if (!memread(m, a, b, n))
    return NO;
  uint32_t v = 0;
  for (unsigned i = 0; i < n; i++)
    v = (v << 8) | b[i];
  *out = v;
  return YES;
}
static BOOL storebe(id<BRPPCMemory> __unsafe_unretained m, uint32_t a, unsigned n, uint32_t v) {
  uint8_t b[4];
  for (unsigned i = 0; i < n; i++)
    b[n - 1 - i] = (uint8_t)(v >> (8 * i));
  return memwrite(m, a, b, n);
}
static BOOL loadString(id<BRPPCMemory> __unsafe_unretained m, BRPPCState *s, uint32_t addr,
                       unsigned reg, unsigned count) {
  for (unsigned i = 0; i < count; i++) {
    uint8_t q;
    if (!memread(m, addr + i, &q, 1))
      return NO;
    unsigned r = (reg + i / 4) & 31, sh = 24 - 8 * (i & 3);
    if ((i & 3) == 0)
      s->gpr[r] = 0;
    s->gpr[r] = (s->gpr[r] & ~(0xffu << sh)) | ((uint32_t)q << sh);
  }
  return YES;
}
static BOOL storeString(id<BRPPCMemory> __unsafe_unretained m, BRPPCState *s, uint32_t addr,
                        unsigned reg, unsigned count) {
  for (unsigned i = 0; i < count; i++) {
    unsigned r = (reg + i / 4) & 31, sh = 24 - 8 * (i & 3);
    uint8_t q = (uint8_t)(s->gpr[r] >> sh);
    if (!memwrite(m, addr + i, &q, 1))
      return NO;
  }
  return YES;
}
static BRPPCStopReason okadvance(BRPPCState *s) {
  s->pc += 4;
  return BRPPCStopNone;
}
static BRPPCStopReason illegal(uint32_t w, BRPPCState *s,
                               id<BRPPCMemory> __unsafe_unretained m,
                               BRPowerPC32 * __unsafe_unretained e) {
  (void)w;
  (void)s;
  (void)m;
  (void)e;
  return BRPPCStopIllegalInstruction;
}
static BRPPCStopReason privileged(uint32_t w, BRPPCState *s,
                                  id<BRPPCMemory> __unsafe_unretained m,
                                  BRPowerPC32 * __unsafe_unretained e) {
  (void)s;
  (void)m;
  return [e executePrivilegedInstruction:w];
}

static BRPPCStopReason execImm(uint32_t w, BRPPCState *s,
                               id<BRPPCMemory> __unsafe_unretained m,
                               BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  (void)e;
  unsigned op = w >> 26, d = rd(w), a = ra(w);
  uint32_t av = s->gpr[a], u = (uint16_t)w, r = 0;
  int32_t si = sx16(w);
  switch (op) {
  case 7:
    r = (uint32_t)((int64_t)(int32_t)av * si);
    s->gpr[d] = r;
    break;
  case 8: {
    uint64_t z = (uint64_t)(uint32_t)si + (uint64_t)~av + 1;
    s->gpr[d] = (uint32_t)z;
    setca(s, z >> 32);
    break;
  }
  case 10:
    if (w & (1u << 21))
      return BRPPCStopIllegalInstruction;
    setcmp(s, (w >> 23) & 7, (uint32_t)av, u);
    break;
  case 11:
    if (w & (1u << 21))
      return BRPPCStopIllegalInstruction;
    setcmp(s, (w >> 23) & 7, (int32_t)av, si);
    break;
  case 12:
  case 13: {
    uint64_t z = (uint64_t)av + (uint32_t)si;
    s->gpr[d] = (uint32_t)z;
    setca(s, z >> 32);
    if (op == 13)
      setcr0(s, s->gpr[d]);
    break;
  }
  case 14:
    s->gpr[d] = ea0(s, a) + (uint32_t)si;
    break;
  case 15:
    s->gpr[d] = ea0(s, a) + ((uint32_t)si << 16);
    break;
  case 24:
    s->gpr[a] = s->gpr[d] | u;
    break;
  case 25:
    s->gpr[a] = s->gpr[d] | (u << 16);
    break;
  case 26:
    s->gpr[a] = s->gpr[d] ^ u;
    break;
  case 27:
    s->gpr[a] = s->gpr[d] ^ (u << 16);
    break;
  case 28:
    s->gpr[a] = s->gpr[d] & u;
    setcr0(s, s->gpr[a]);
    break;
  case 29:
    s->gpr[a] = s->gpr[d] & (u << 16);
    setcr0(s, s->gpr[a]);
    break;
  default:
    return BRPPCStopIllegalInstruction;
  }
  return okadvance(s);
}
static BRPPCStopReason exec601Imm(uint32_t w, BRPPCState *s,
                                  id<BRPPCMemory> __unsafe_unretained m,
                                  BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  if (e.model != BRPPCCPU601)
    return BRPPCStopIllegalInstruction;
  unsigned d = rd(w), a = ra(w);
  int32_t x = (int32_t)s->gpr[a], imm = sx16(w);
  s->gpr[d] = x < imm ? 0 : (uint32_t)(imm - x);
  return okadvance(s);
}

static BRPPCStopReason execRotate(uint32_t w, BRPPCState *s,
                                  id<BRPPCMemory> __unsafe_unretained m,
                                  BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  unsigned op = w >> 26, a = ra(w), ss = rd(w), mb = (w >> 6) & 31,
           me = (w >> 1) & 31,
           sh = (op == 23 || op == 22 ? s->gpr[rb(w)] : (w >> 11) & 31);
  if (op == 22 && e.model != BRPPCCPU601)
    return BRPPCStopIllegalInstruction;
  uint32_t x = rotl32(s->gpr[ss], sh) & mask32(mb, me);
  if (op == 20)
    s->gpr[a] = (s->gpr[a] & ~mask32(mb, me)) | x;
  else
    s->gpr[a] = x;
  if (w & 1)
    setcr0(s, s->gpr[a]);
  return okadvance(s);
}

static BOOL branchOK(uint32_t w, BRPPCState *s, BOOL ctrAllowed) {
  unsigned bo = (w >> 21) & 31, bi = (w >> 16) & 31;
  BOOL ctr = YES, cond = YES;
  if (!(bo & 4)) {
    if (!ctrAllowed)
      return NO;
    s->ctr--;
    ctr = ((s->ctr != 0) ^ ((bo & 2) != 0));
  }
  if (!(bo & 16))
    cond = (getcr(s, bi) == ((bo & 8) != 0));
  return ctr && cond;
}
static BRPPCStopReason execBranch(uint32_t w, BRPPCState *s,
                                  id<BRPPCMemory> __unsafe_unretained m,
                                  BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  (void)e;
  unsigned op = w >> 26;
  uint32_t old = s->pc, next = old + 4, target;
  BOOL take = YES;
  if (op == 18) {
    int32_t d = (int32_t)(w & 0x03fffffc);
    if (d & 0x02000000)
      d |= 0xfc000000;
    target = (w & 2) ? (uint32_t)d : old + d;
  } else {
    int32_t d = (int16_t)(w & 0xfffc);
    take = branchOK(w, s, YES);
    target = (w & 2) ? (uint32_t)d : old + d;
  }
  if (w & 1)
    s->lr = next;
  s->pc = take ? target : next;
  return BRPPCStopNone;
}

static BRPPCStopReason execLoadStore(uint32_t w, BRPPCState *s,
                                     id<BRPPCMemory> __unsafe_unretained m,
                                     BRPowerPC32 * __unsafe_unretained e) {
  (void)e;
  unsigned op = w >> 26, d = rd(w), a = ra(w);
  BOOL upd = (op & 1);
  BOOL load = op == 32 || op == 33 || op == 34 || op == 35 || op == 40 ||
              op == 41 || op == 42 || op == 43;
  if (upd && (!a || (load && a == d)))
    return BRPPCStopIllegalInstruction;
  if (op == 46 && a && a >= d)
    return BRPPCStopIllegalInstruction;
  uint32_t addr = ea0(s, a) + (uint32_t)sx16(w), v;
  BOOL good = YES;
  switch (op) {
  case 32:
  case 33:
    good = loadbe(m, addr, 4, &v);
    if (good)
      s->gpr[d] = v;
    break;
  case 34:
  case 35:
    good = loadbe(m, addr, 1, &v);
    if (good)
      s->gpr[d] = v;
    break;
  case 40:
  case 41:
    good = loadbe(m, addr, 2, &v);
    if (good)
      s->gpr[d] = v;
    break;
  case 42:
  case 43:
    good = loadbe(m, addr, 2, &v);
    if (good)
      s->gpr[d] = (uint32_t)(int32_t)(int16_t)v;
    break;
  case 36:
  case 37:
    good = storebe(m, addr, 4, s->gpr[d]);
    break;
  case 38:
  case 39:
    good = storebe(m, addr, 1, s->gpr[d]);
    break;
  case 44:
  case 45:
    good = storebe(m, addr, 2, s->gpr[d]);
    break;
  case 46:
    for (unsigned i = d; i < 32 && good; i++, addr += 4)
      good = loadbe(m, addr, 4, &s->gpr[i]);
    upd = NO;
    break;
  case 47:
    for (unsigned i = d; i < 32 && good; i++, addr += 4)
      good = storebe(m, addr, 4, s->gpr[i]);
    upd = NO;
    break;
  default:
    return BRPPCStopIllegalInstruction;
  }
  if (!good)
    return BRPPCStopFault;
  if (upd)
    s->gpr[a] = addr;
  return okadvance(s);
}

static BRPPCStopReason execFPLoadStore(uint32_t w, BRPPCState *s,
                                       id<BRPPCMemory> __unsafe_unretained m,
                                       BRPowerPC32 * __unsafe_unretained e) {
  (void)e;
  unsigned op = w >> 26, d = rd(w), a = ra(w);
  BOOL upd = op & 1, store = op >= 52,
       dbl = (op == 50 || op == 51 || op == 54 || op == 55);
  if (upd && !a)
    return BRPPCStopIllegalInstruction;
  uint32_t addr = ea0(s, a) + (uint32_t)sx16(w);
  uint8_t q[8];
  if (store) {
    if (dbl) {
      uint64_t bits;
      memcpy(&bits, &s->fpr[d], 8);
      for (unsigned i = 0; i < 8; i++)
        q[7 - i] = (uint8_t)(bits >> (8 * i));
      if (!memwrite(m, addr, q, 8))
        return BRPPCStopFault;
    } else {
      float f = (float)s->fpr[d];
      uint32_t bits;
      memcpy(&bits, &f, 4);
      if (!storebe(m, addr, 4, bits))
        return BRPPCStopFault;
    }
  } else {
    if (dbl) {
      if (!memread(m, addr, q, 8))
        return BRPPCStopFault;
      uint64_t bits = 0;
      for (unsigned i = 0; i < 8; i++)
        bits = (bits << 8) | q[i];
      memcpy(&s->fpr[d], &bits, 8);
    } else {
      uint32_t bits;
      if (!loadbe(m, addr, 4, &bits))
        return BRPPCStopFault;
      float f;
      memcpy(&f, &bits, 4);
      s->fpr[d] = f;
    }
  }
  if (upd)
    s->gpr[a] = addr;
  return okadvance(s);
}
static BOOL fpLoadIndexed(id<BRPPCMemory> __unsafe_unretained m, BRPPCState *s, unsigned d,
                          uint32_t addr, BOOL dbl) {
  if (dbl) {
    uint8_t q[8];
    if (!memread(m, addr, q, 8))
      return NO;
    uint64_t bits = 0;
    for (unsigned i = 0; i < 8; i++)
      bits = (bits << 8) | q[i];
    memcpy(&s->fpr[d], &bits, 8);
  } else {
    uint32_t bits;
    if (!loadbe(m, addr, 4, &bits))
      return NO;
    float f;
    memcpy(&f, &bits, 4);
    s->fpr[d] = f;
  }
  return YES;
}
static BOOL fpStoreIndexed(id<BRPPCMemory> __unsafe_unretained m, BRPPCState *s, unsigned d,
                           uint32_t addr, BOOL dbl) {
  if (dbl) {
    uint64_t bits;
    uint8_t q[8];
    memcpy(&bits, &s->fpr[d], 8);
    for (unsigned i = 0; i < 8; i++)
      q[7 - i] = (uint8_t)(bits >> (8 * i));
    return memwrite(m, addr, q, 8);
  }
  float f = (float)s->fpr[d];
  uint32_t bits;
  memcpy(&bits, &f, 4);
  return storebe(m, addr, 4, bits);
}

static BOOL signalingNaN(double x) {
  uint64_t q;
  memcpy(&q, &x, 8);
  return (q & 0x7ff0000000000000ull) == 0x7ff0000000000000ull &&
         (q & 0x000fffffffffffffull) && !(q & 0x0008000000000000ull);
}
static void fpInvalid(BRPPCState *s, uint32_t detail) {
  s->fpscr |= 0xa0000000u | detail;
  if (s->fpscr & 0x80)
    s->fpscr |= 0x40000000u;
}
static void fpFusedInvalid(BRPPCState *s, double a, double c, double b,
                           BOOL subtractB) {
  if ((isinf(a) && c == 0) || (a == 0 && isinf(c))) {
    fpInvalid(s, 0x00100000u);
    return;
  }
  if ((isinf(a) || isinf(c)) && isinf(b)) {
    BOOL productSign = signbit(a) != signbit(c);
    if (productSign == signbit(b) ? subtractB : !subtractB)
      fpInvalid(s, 0x00800000u);
  }
}
static void recomputeFPSCR(BRPPCState *s) {
  const uint32_t invalidCauses = 0x01f80700u;
  if (s->fpscr & invalidCauses)
    s->fpscr |= 0x20000000u;
  else
    s->fpscr &= ~0x20000000u;
  BOOL enabled = ((s->fpscr & 0x20000000u) && (s->fpscr & 0x80)) ||
                 ((s->fpscr & 0x10000000u) && (s->fpscr & 0x40)) ||
                 ((s->fpscr & 0x08000000u) && (s->fpscr & 0x20)) ||
                 ((s->fpscr & 0x04000000u) && (s->fpscr & 0x10)) ||
                 ((s->fpscr & 0x02000000u) && (s->fpscr & 0x08));
  if (enabled)
    s->fpscr |= 0x40000000u;
  else
    s->fpscr &= ~0x40000000u;
}
static void setfpresult(BRPPCState *s, double x, BOOL rc) {
  uint32_t f;
  int cls = fpclassify(x);
  if (cls == FP_NAN)
    f = signalingNaN(x) ? 0 : 17;
  else if (cls == FP_INFINITE)
    f = signbit(x) ? 9 : 5;
  else if (cls == FP_ZERO)
    f = signbit(x) ? 18 : 2;
  else if (cls == FP_SUBNORMAL)
    f = signbit(x) ? 24 : 20;
  else
    f = signbit(x) ? 8 : 4;
  s->fpscr = (s->fpscr & ~0x0001f000u) | (f << 12);
  if (rc)
    s->cr = (s->cr & 0xf0ffffff) | (((s->fpscr >> 28) & 15) << 24);
}
static BOOL applyFPExceptions(BRPPCState *s, int flags) {
  uint32_t raised = 0;
  if (flags & FE_INVALID)
    raised |= 0x20000000u;
  if (flags & FE_DIVBYZERO)
    raised |= 0x04000000u;
  if (flags & FE_OVERFLOW)
    raised |= 0x10000000u;
  if (flags & FE_UNDERFLOW)
    raised |= 0x08000000u;
  if (flags & FE_INEXACT) {
    raised |= 0x02000000u;
    s->fpscr |= 0x00020000u;
  }
  if (raised)
    s->fpscr |= 0x80000000u | raised;
  if (((raised & 0x20000000u) && (s->fpscr & 0x80)) ||
      ((raised & 0x10000000u) && (s->fpscr & 0x40)) ||
      ((raised & 0x08000000u) && (s->fpscr & 0x20)) ||
      ((raised & 0x04000000u) && (s->fpscr & 0x10)) ||
      ((raised & 0x02000000u) && (s->fpscr & 0x08)))
    s->fpscr |= 0x40000000u;
  return ((flags & FE_INVALID) && (s->fpscr & 0x80)) ||
         ((flags & FE_OVERFLOW) && (s->fpscr & 0x40)) ||
         ((flags & FE_UNDERFLOW) && (s->fpscr & 0x20)) ||
         ((flags & FE_DIVBYZERO) && (s->fpscr & 0x10)) ||
         ((flags & FE_INEXACT) && (s->fpscr & 0x08));
}
static BRPPCStopReason execFP(uint32_t w, BRPPCState *s,
                              id<BRPPCMemory> __unsafe_unretained m,
                              BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  (void)e;
  unsigned op = w >> 26, d = rd(w), a = ra(w), b = rb(w), c = (w >> 6) & 31,
           xo10 = (w >> 1) & 1023, xo5 = (w >> 1) & 31;
  double A = s->fpr[a], B = s->fpr[b], C = s->fpr[c], r = 0;
  BOOL write = YES;
  int oldRound = hostGetRound(),
      rounds[4] = {FE_TONEAREST, FE_TOWARDZERO, FE_UPWARD, FE_DOWNWARD};
  int guestRound = rounds[s->fpscr & 3];
  BOOL changedRound = guestRound != oldRound;
  if (changedRound) hostSetRound(guestRound);
  hostClearFPExceptions();
  BOOL aform = NO;
  if (op == 59) {
    switch (xo5) {
    case 18:
    case 20:
    case 21:
      aform = c == 0;
      break;
    case 22:
    case 24:
      aform = a == 0 && c == 0;
      break;
    case 25:
      aform = b == 0;
      break;
    case 28:
    case 29:
    case 30:
    case 31:
      aform = YES;
      break;
    default:
      break;
    }
  } else if (op == 63) {
    switch (xo5) {
    case 18:
    case 20:
    case 21:
      aform = c == 0;
      break;
    case 22:
    case 24:
    case 26:
      aform = a == 0 && c == 0;
      break;
    case 23:
    case 28:
    case 29:
    case 30:
    case 31:
      aform = YES;
      break;
    case 25:
      aform = b == 0;
      break;
    default:
      break;
    }
  }
  if (aform) {
    BOOL snan = NO;
    switch (xo5) {
    case 18:
      snan = signalingNaN(A) || signalingNaN(B);
      if ((A == 0 && B == 0))
        fpInvalid(s, 0x00200000u);
      else if (isinf(A) && isinf(B))
        fpInvalid(s, 0x00400000u);
      r = A / B;
      break;
    case 20:
      snan = signalingNaN(A) || signalingNaN(B);
      if (isinf(A) && isinf(B) && signbit(A) == signbit(B))
        fpInvalid(s, 0x00800000u);
      r = A - B;
      break;
    case 21:
      snan = signalingNaN(A) || signalingNaN(B);
      if (isinf(A) && isinf(B) && signbit(A) != signbit(B))
        fpInvalid(s, 0x00800000u);
      r = A + B;
      break;
    case 22:
      snan = signalingNaN(B);
      if (B < 0)
        fpInvalid(s, 0x00000200u);
      r = sqrt(B);
      break;
    case 23:
      snan = signalingNaN(A) || signalingNaN(B) || signalingNaN(C);
      r = A >= 0 ? C : B;
      break;
    case 24:
      snan = signalingNaN(B);
      r = 1.0 / B;
      break;
    case 25:
      snan = signalingNaN(A) || signalingNaN(C);
      if ((isinf(A) && C == 0) || (A == 0 && isinf(C)))
        fpInvalid(s, 0x00100000u);
      r = A * C;
      break;
    case 26:
      snan = signalingNaN(B);
      if (B < 0)
        fpInvalid(s, 0x00000200u);
      r = 1.0 / sqrt(B);
      break;
    case 28:
      fpFusedInvalid(s, A, C, B, YES);
      r = fma(A, C, -B);
      snan = signalingNaN(A) || signalingNaN(B) || signalingNaN(C);
      break;
    case 29:
      fpFusedInvalid(s, A, C, B, NO);
      r = fma(A, C, B);
      snan = signalingNaN(A) || signalingNaN(B) || signalingNaN(C);
      break;
    case 30:
      fpFusedInvalid(s, A, C, B, YES);
      r = -fma(A, C, -B);
      snan = signalingNaN(A) || signalingNaN(B) || signalingNaN(C);
      break;
    case 31:
      fpFusedInvalid(s, A, C, B, NO);
      r = -fma(A, C, B);
      snan = signalingNaN(A) || signalingNaN(B) || signalingNaN(C);
      break;
    default:
      goto bad;
    }
    if (snan)
      fpInvalid(s, 0x01000000u);
    if (op == 59)
      r = (double)(float)r;
  } else {
    if (op != 63)
      goto bad;
    switch (xo10) {
    case 0:
    case 32: {
      unsigned f = (w >> 23) & 7;
      BOOL nan = isnan(A) || isnan(B),
           snan = signalingNaN(A) || signalingNaN(B);
      uint32_t v = nan ? 1 : A < B ? 8 : A > B ? 4 : 2, sh = 28 - 4 * f;
      s->cr = (s->cr & ~(15u << sh)) | (v << sh);
      if (snan)
        fpInvalid(s, 0x01000000u);
      if (xo10 == 32 && nan)
        fpInvalid(s, 0x00080000u);
      if (snan || (xo10 == 32 && nan))
        hostRaiseFPInvalid();
      write = NO;
      break;
    }
    case 12:
      r = (double)(float)B;
      break;
    case 14:
    case 15: {
      double x = xo10 == 15 ? trunc(B) : nearbyint(B);
      if (isnan(x) || x > INT32_MAX || x < INT32_MIN) {
        fpInvalid(s, 0x00000100u);
        if (signalingNaN(B))
          fpInvalid(s, 0x01000000u);
        hostRaiseFPInvalid();
      }
      int32_t i = x > INT32_MAX   ? INT32_MAX
                  : x < INT32_MIN ? INT32_MIN
                  : isnan(x)      ? INT32_MIN
                                  : (int32_t)x;
      uint64_t bits = 0xfff8000000000000ull | (uint32_t)i;
      memcpy(&r, &bits, 8);
      break;
    }
    case 38:
    case 70: {
      uint32_t mask = 1u << (31 - d);
      if (mask != 0x40000000u && mask != 0x20000000u)
        s->fpscr = xo10 == 38 ? s->fpscr | mask : s->fpscr & ~mask;
      recomputeFPSCR(s);
      write = NO;
      break;
    }
    case 40:
      r = -B;
      break;
    case 64: {
      unsigned fd = (w >> 23) & 7, fs = (w >> 18) & 7, shd = 28 - 4 * fd,
               shs = 28 - 4 * fs;
      s->cr = (s->cr & ~(15u << shd)) | (((s->fpscr >> shs) & 15) << shd);
      s->fpscr &= ~((15u << shs) & 0x9ff80700u);
      recomputeFPSCR(s);
      write = NO;
      break;
    }
    case 72:
      r = B;
      break;
    case 134: {
      unsigned f = (w >> 23) & 7, sh = 28 - 4 * f;
      uint32_t mask = (15u << sh) & ~0x60000000u;
      s->fpscr = (s->fpscr & ~mask) | ((((w >> 12) & 15) << sh) & mask);
      recomputeFPSCR(s);
      write = NO;
      break;
    }
    case 136:
      r = -fabs(B);
      break;
    case 264:
      r = fabs(B);
      break;
    case 583: {
      uint64_t bits = s->fpscr;
      memcpy(&r, &bits, 8);
      break;
    }
    case 711: {
      uint64_t bits;
      memcpy(&bits, &B, 8);
      uint32_t src = (uint32_t)bits, mask = 0;
      unsigned fm = (w >> 17) & 255;
      for (unsigned i = 0; i < 8; i++)
        if (fm & (1u << (7 - i)))
          mask |= 15u << (28 - 4 * i);
      mask &= ~0x60000000u;
      s->fpscr = (s->fpscr & ~mask) | (src & mask);
      recomputeFPSCR(s);
      write = NO;
      break;
    }
    default:
      goto bad;
    }
  }
  {
    int flags = hostTestFPExceptions();
    if (changedRound) hostSetRound(oldRound);
    BOOL enabledException = applyFPExceptions(s, flags);
    if (enabledException)
      return BRPPCStopFloatingPointException;
  }
  if (write) {
    s->fpr[d] = r;
    setfpresult(s, r, w & 1);
  }
  return okadvance(s);
bad:
  if (changedRound) hostSetRound(oldRound);
  return BRPPCStopIllegalInstruction;
}

static BRPPCStopReason execCR(uint32_t w, BRPPCState *s,
                              id<BRPPCMemory> __unsafe_unretained m,
                              BRPowerPC32 * __unsafe_unretained e) {
  unsigned xo = (w >> 1) & 1023, d = rd(w), a = ra(w), b = rb(w);
  if (xo == 50)
    return privileged(w, s, m, e);
  if (xo == 150)
    return okadvance(s);
  if (xo == 16 || xo == 528) {
    if (xo == 528 && !(((w >> 21) & 31) & 4))
      return BRPPCStopIllegalInstruction;
    uint32_t n = s->pc + 4, t = (xo == 16 ? s->lr : s->ctr) & ~3u;
    BOOL q = branchOK(w, s, xo == 16);
    if (w & 1)
      s->lr = n;
    s->pc = q ? t : n;
    return BRPPCStopNone;
  }
  if (xo == 0) {
    unsigned shD = 28 - 4 * ((w >> 23) & 7), shS = 28 - 4 * ((w >> 18) & 7);
    s->cr = (s->cr & ~(15u << shD)) | (((s->cr >> shS) & 15) << shD);
  } else {
    BOOL x = getcr(s, a), y = getcr(s, b), r;
    switch (xo) {
    case 33:
      r = !(x | y);
      break;
    case 129:
      r = x & !y;
      break;
    case 193:
      r = x ^ y;
      break;
    case 225:
      r = !(x & y);
      break;
    case 257:
      r = x & y;
      break;
    case 289:
      r = !(x ^ y);
      break;
    case 417:
      r = x | !y;
      break;
    case 449:
      r = x | y;
      break;
    default:
      return BRPPCStopIllegalInstruction;
    }
    crbit(s, d, r);
  }
  return okadvance(s);
}

static BRPPCStopReason execX(uint32_t w, BRPPCState *s,
                             id<BRPPCMemory> __unsafe_unretained m,
                             BRPowerPC32 * __unsafe_unretained e) {
  unsigned xo = (w >> 1) & 1023, d = rd(w), a = ra(w), b = rb(w);
  uint32_t A = s->gpr[a], B = s->gpr[b], S = s->gpr[d], r = 0;
  BOOL rc = w & 1, write = YES;
  uint64_t z;
  int64_t sz;
  uint32_t addr;
  unsigned axo = xo & 511;
  BOOL arithmetic =
      (axo == 8 || axo == 10 || axo == 40 || axo == 104 || axo == 136 ||
       axo == 138 || axo == 200 || axo == 202 || axo == 232 || axo == 234 ||
       axo == 235 || axo == 266 || axo == 459 || axo == 491);
  if (arithmetic) {
    BOOL oe = (w >> 10) & 1, ov = NO, ca = NO, setsCarry = NO;
    switch (axo) {
    case 8:
      z = (uint64_t)B + (uint64_t)~A + 1;
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = subov32(A, B, r);
      break;
    case 10:
      z = (uint64_t)A + B;
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = addov32(A, B, r);
      break;
    case 40:
      r = B - A;
      ov = subov32(A, B, r);
      break;
    case 104:
      r = 0 - A;
      ov = A == 0x80000000u;
      break;
    case 136: {
      uint32_t ci = !!(s->xer & XER_CA);
      z = (uint64_t)B + (uint64_t)~A + ci;
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = outOfSignedWord((int64_t)(int32_t)B - (int32_t)A + ci - 1);
      break;
    }
    case 138: {
      uint32_t ci = !!(s->xer & XER_CA);
      z = (uint64_t)A + B + ci;
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = outOfSignedWord((int64_t)(int32_t)A + (int32_t)B + ci);
      break;
    }
    case 200:
      z = (uint64_t)~A + !!(s->xer & XER_CA);
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = outOfSignedWord(-(int64_t)(int32_t)A + !!(s->xer & XER_CA) - 1);
      break;
    case 202:
      z = (uint64_t)A + !!(s->xer & XER_CA);
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = outOfSignedWord((int64_t)(int32_t)A + !!(s->xer & XER_CA));
      break;
    case 232:
      z = (uint64_t)~A + !!(s->xer & XER_CA) + UINT32_MAX;
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = outOfSignedWord(-(int64_t)(int32_t)A + !!(s->xer & XER_CA) - 2);
      break;
    case 234:
      z = (uint64_t)A + !!(s->xer & XER_CA) + UINT32_MAX;
      r = (uint32_t)z;
      ca = z >> 32;
      setsCarry = YES;
      ov = outOfSignedWord((int64_t)(int32_t)A + !!(s->xer & XER_CA) - 1);
      break;
    case 235:
      r = (uint32_t)((uint64_t)A * B);
      ov = ((int64_t)(int32_t)A * (int64_t)(int32_t)B) != (int64_t)(int32_t)r;
      break;
    case 266:
      r = A + B;
      ov = addov32(A, B, r);
      break;
    case 459:
      if (B == 0) {
        r = 0;
        ov = YES;
      } else
        r = A / B;
      break;
    case 491:
      if (B == 0 || (A == 0x80000000u && B == UINT32_MAX)) {
        r = 0;
        ov = YES;
      } else
        r = (uint32_t)((int32_t)A / (int32_t)B);
      break;
    default:
      __builtin_unreachable();
    }
    if (setsCarry)
      setca(s, ca);
    if (oe)
      setov(s, ov);
    s->gpr[d] = r;
    if (rc)
      setcr0(s, r);
    return okadvance(s);
  }
  if (e.model == BRPPCCPUG4) {
    addr = ea0(s, a) + B;
    switch (xo) {
    case 6:
    case 38: {
      unsigned off = addr & 15;
      for (unsigned i = 0; i < 16; i++)
        s->vr[d].byte[i] = (uint8_t)(xo == 6 ? off + i : (16 - off + i) & 31);
      return okadvance(s);
    }
    case 7: {
      uint8_t q;
      if (!memread(m, addr, &q, 1))
        return BRPPCStopFault;
      s->vr[d].byte[addr & 15] = q;
      return okadvance(s);
    }
    case 39: {
      uint8_t q[2];
      if (!memread(m, addr, q, 2))
        return BRPPCStopFault;
      unsigned i = addr & 14;
      s->vr[d].byte[i] = q[0];
      s->vr[d].byte[i + 1] = q[1];
      return okadvance(s);
    }
    case 71: {
      uint8_t q[4];
      if (!memread(m, addr, q, 4))
        return BRPPCStopFault;
      unsigned i = addr & 12;
      memcpy(&s->vr[d].byte[i], q, 4);
      return okadvance(s);
    }
    case 103:
    case 359:
      if (!memread(m, addr & ~15u, s->vr[d].byte, 16))
        return BRPPCStopFault;
      return okadvance(s);
    case 135:
      if (!memwrite(m, addr, &s->vr[d].byte[addr & 15], 1))
        return BRPPCStopFault;
      return okadvance(s);
    case 167:
      if (!memwrite(m, addr, &s->vr[d].byte[addr & 14], 2))
        return BRPPCStopFault;
      return okadvance(s);
    case 199:
      if (!memwrite(m, addr, &s->vr[d].byte[addr & 12], 4))
        return BRPPCStopFault;
      return okadvance(s);
    case 231:
    case 487:
      if (!memwrite(m, addr & ~15u, s->vr[d].byte, 16))
        return BRPPCStopFault;
      return okadvance(s);
    case 342:
    case 374:
    case 822:
      return okadvance(s);
    default:
      break;
    }
  }
  if (e.model == BRPPCCPU601) {
    unsigned px = xo & 511;
    BOOL poe = (w >> 10) & 1;
    if (px == 107 || px == 264 || px == 331 || px == 360 || px == 363) {
      BOOL pov = NO;
      switch (px) {
      case 107: {
        uint64_t p = (uint64_t)A * B;
        s->mq = (uint32_t)p;
        r = (uint32_t)(p >> 32);
        pov = (int64_t)p != (int64_t)(int32_t)r;
        break;
      }
      case 264:
        r = (int32_t)B >= (int32_t)A ? 0 : B - A;
        pov = subov32(A, B, r);
        break;
      case 331: {
        int64_t dividend =
            (int64_t)(int32_t)A * 0x100000000ll + (uint64_t)s->mq;
        if (B == 0 || (dividend == INT64_MIN && B == UINT32_MAX)) {
          r = 0x80000000u;
          s->mq = 0;
          pov = YES;
        } else {
          int64_t q = dividend / (int32_t)B;
          s->mq = (uint32_t)(dividend % (int32_t)B);
          r = (uint32_t)q;
          pov = q != (int64_t)(int32_t)r;
        }
        break;
      }
      case 363:
        if (B == 0 || (A == 0x80000000u && B == UINT32_MAX)) {
          r = 0x80000000u;
          s->mq = 0;
          pov = YES;
        } else {
          r = (uint32_t)((int32_t)A / (int32_t)B);
          s->mq = (uint32_t)((int32_t)A % (int32_t)B);
        }
        break;
      case 360:
        r = (int32_t)A < 0 ? 0u - A : A;
        pov = A == 0x80000000u;
        break;
      }
      if (poe)
        setov(s, pov);
      s->gpr[d] = r;
      if (rc)
        setcr0(s, r);
      return okadvance(s);
    }
    switch (xo) {
    case 29:
      r = mask32(S & 31, B & 31);
      d = a;
      break;
    case 153: {
      unsigned n = B & 31;
      r = S << n;
      s->mq = rotl32(S, n);
      d = a;
      break;
    }
    case 217: {
      unsigned n = B & 31, mask = UINT32_MAX << n, rot = rotl32(S, n),
               old = s->mq;
      s->mq = rot;
      r = (rot & mask) | (old & ~mask);
      d = a;
      break;
    }
    case 277: {
      unsigned n = s->xer & 0x7f, cmp = (s->xer >> 8) & 255, reg = d,
               shift = 24, i = 0;
      addr = ea0(s, a) + B;
      for (; i < n; i++, addr++) {
        uint8_t q;
        if (!memread(m, addr, &q, 1))
          return BRPPCStopFault;
        if (reg != b && (!a || reg != a))
          s->gpr[reg] =
              (s->gpr[reg] & ~(0xffu << shift)) | ((uint32_t)q << shift);
        if (q == cmp)
          break;
        if (shift)
          shift -= 8;
        else {
          shift = 24;
          reg = (reg + 1) & 31;
        }
      }
      s->xer = (s->xer & ~0x7fu) | i;
      if (rc)
        setcr0(s, i);
      return okadvance(s);
    }
    case 488:
      r = (int32_t)A > 0 ? (uint32_t)-(int32_t)A : A;
      break;
    case 531:
      r = a >= 12 && a <= 15 ? 32 : 0;
      break;
    case 537: {
      unsigned n = B & 31;
      uint32_t bit = S & (1u << (31 - n));
      r = (s->gpr[a] & ~(1u << (31 - n))) | bit;
      d = a;
      break;
    }
    case 541:
      r = (S & B) | (s->gpr[a] & ~B);
      d = a;
      break;
    case 184: {
      unsigned n = b;
      r = S << n;
      s->mq = rotl32(S, n);
      d = a;
      break;
    }
    case 248: {
      unsigned n = b, mask = UINT32_MAX << n, rot = rotl32(S, n), old = s->mq;
      s->mq = rot;
      r = (rot & mask) | (old & ~mask);
      d = a;
      break;
    }
    case 216: {
      unsigned n = B & 31, mask = UINT32_MAX << n;
      r = (B & 32) ? s->mq & mask : (S << n) | (s->mq & ~mask);
      d = a;
      break;
    }
    case 152: {
      unsigned n = B & 31;
      r = (B & 32) ? 0 : S << n;
      s->mq = rotl32(S, n);
      d = a;
      break;
    }
    case 665:
    case 696: {
      unsigned n = xo == 696 ? b : B & 31;
      r = S >> n;
      s->mq = rotr32(S, n);
      d = a;
      break;
    }
    case 729:
    case 760: {
      unsigned n = xo == 760 ? b : B & 31, mask = UINT32_MAX >> n,
               rot = rotr32(S, n), old = s->mq;
      s->mq = rot;
      r = (rot & mask) | (old & ~mask);
      d = a;
      break;
    }
    case 728: {
      unsigned n = B & 31, mask = UINT32_MAX >> n;
      r = (B & 32) ? s->mq & mask : ((S >> n) & mask) | (s->mq & ~mask);
      d = a;
      break;
    }
    case 664: {
      unsigned n = B & 31;
      r = (B & 32) ? 0 : S >> n;
      s->mq = rotr32(S, n);
      d = a;
      break;
    }
    case 921: {
      unsigned n = B & 31;
      r = (uint32_t)((int32_t)S >> n);
      s->mq = rotr32(S, n);
      d = a;
      break;
    }
    case 920:
    case 952: {
      unsigned n = xo == 952 ? b : B & 31;
      BOOL wide = xo == 920 && (B & 32),
           lost = wide ? S != 0 : n && (S & ((1u << n) - 1));
      r = wide ? ((int32_t)S < 0 ? UINT32_MAX : 0)
               : (uint32_t)((int32_t)S >> n);
      s->mq = rotr32(S, n);
      setca(s, (int32_t)S < 0 && lost);
      d = a;
      break;
    }
    default:
      goto not601;
    }
    s->gpr[d] = r;
    if (rc)
      setcr0(s, r);
    return okadvance(s);
  }
not601:
  switch (xo) {
  case 0:
    if (w & (1u << 21))
      return BRPPCStopIllegalInstruction;
    setcmp(s, (w >> 23) & 7, (int32_t)A, (int32_t)B);
    write = NO;
    break;
  case 32:
    if (w & (1u << 21))
      return BRPPCStopIllegalInstruction;
    setcmp(s, (w >> 23) & 7, A, B);
    write = NO;
    break;
  case 4: {
    int32_t aa = (int32_t)A, bb = (int32_t)B;
    unsigned to = d;
    BOOL t = ((to & 16) && aa < bb) || ((to & 8) && aa > bb) ||
             ((to & 4) && aa == bb) || ((to & 2) && A < B) ||
             ((to & 1) && A > B);
    return t ? BRPPCStopTrap : okadvance(s);
  }
  case 20:
  case 23:
  case 55:
  case 87:
  case 119:
  case 279:
  case 311:
  case 343:
  case 375: {
    unsigned n = (xo == 87 || xo == 119                              ? 1
                  : xo == 279 || xo == 311 || xo == 343 || xo == 375 ? 2
                                                                     : 4);
    BOOL upd = xo == 55 || xo == 119 || xo == 311 || xo == 375;
    if (upd && (!a || a == d))
      return BRPPCStopIllegalInstruction;
    addr = ea0(s, a) + B;
    if (xo == 20 && (addr & (n - 1)))
      return BRPPCStopFault;
    uint32_t v;
    if (!loadbe(m, addr, n, &v))
      return BRPPCStopFault;
    if (xo == 20) {
      s->reservationValid = YES;
      s->reservationAddress = addr;
    }
    if (xo == 343 || xo == 375)
      v = (uint32_t)(int32_t)(int16_t)v;
    s->gpr[d] = v;
    if (upd)
      s->gpr[a] = addr;
    write = NO;
    break;
  }
  case 24:
    r = (B & 0x20) ? 0 : S << (B & 31);
    d = a;
    break;
  case 536:
    r = (B & 0x20) ? 0 : S >> (B & 31);
    d = a;
    break;
  case 26:
    r = S ? __builtin_clz(S) : 32;
    d = a;
    break;
  case 28:
    r = S & B;
    d = a;
    break;
  case 60:
    r = S & ~B;
    d = a;
    break;
  case 75:
    r = (uint32_t)(((int64_t)(int32_t)A * (int64_t)(int32_t)B) >> 32);
    break;
  case 11:
    r = (uint32_t)(((uint64_t)A * B) >> 32);
    break;
  case 19:
    r = s->cr;
    break;
  case 83:
  case 146:
    return privileged(w, s, m, e);
  case 144: {
    uint32_t mask = (w >> 12) & 255;
    for (unsigned i = 0; i < 8; i++)
      if (mask & (1u << (7 - i))) {
        unsigned sh = 28 - 4 * i;
        s->cr = (s->cr & ~(15u << sh)) | (((s->gpr[d] >> sh) & 15) << sh);
      }
    write = NO;
    break;
  }
  case 124:
    r = ~(S | B);
    d = a;
    break;
  case 150:
    if (!rc)
      return BRPPCStopIllegalInstruction;
    addr = ea0(s, a) + B;
    if (addr & 3)
      return BRPPCStopFault;
    if (s->reservationValid && s->reservationAddress == addr) {
      if (!storebe(m, addr, 4, s->gpr[d]))
        return BRPPCStopFault;
      s->cr = (s->cr & 0x0fffffff) | (2u << 28) |
              ((s->xer & XER_SO) ? 0x10000000 : 0);
    } else {
      s->cr = (s->cr & 0x0fffffff) | ((s->xer & XER_SO) ? 0x10000000 : 0);
    }
    s->reservationValid = NO;
    write = NO;
    break;
  case 512: {
    unsigned f = (w >> 23) & 7, sh = 28 - 4 * f, flags = (s->xer >> 28) & 15;
    s->cr = (s->cr & ~(15u << sh)) | (flags << sh);
    s->xer &= 0x0fffffff;
    write = NO;
    break;
  }
  case 210:
  case 242:
  case 339:
  case 467: {
    unsigned spr = ((w >> 16) & 31) | ((w >> 6) & 0x3e0);
    if (xo == 339) {
      switch (spr) {
      case 1:
        r = s->xer;
        break;
      case 8:
        r = s->lr;
        break;
      case 9:
        r = s->ctr;
        break;
      case 256:
        r = s->vrsave;
        break;
      default:
        return privileged(w, s, m, e);
      }
    } else if (xo == 467) {
      switch (spr) {
      case 1:
        s->xer = s->gpr[d];
        break;
      case 8:
        s->lr = s->gpr[d];
        break;
      case 9:
        s->ctr = s->gpr[d];
        break;
      case 256:
        s->vrsave = s->gpr[d];
        break;
      default:
        return privileged(w, s, m, e);
      }
      write = NO;
    } else
      return privileged(w, s, m, e);
    break;
  }
  case 306:
  case 310:
  case 370:
  case 438:
  case 470:
  case 566:
  case 595:
  case 659:
    return privileged(w, s, m, e);
  case 371: {
    unsigned tbr = ((w >> 16) & 31) | ((w >> 6) & 0x3e0);
    if (tbr != 268 && tbr != 269)
      return privileged(w, s, m, e);
    r = tbr == 269 ? (uint32_t)(s->timeBase >> 32) : (uint32_t)s->timeBase;
    break;
  }
  case 151:
  case 183:
  case 215:
  case 247:
  case 407:
  case 439: {
    unsigned n = (xo == 151 || xo == 183)   ? 4
                 : (xo == 215 || xo == 247) ? 1
                                            : 2;
    BOOL upd = xo == 183 || xo == 247 || xo == 439;
    if (upd && !a)
      return BRPPCStopIllegalInstruction;
    addr = ea0(s, a) + B;
    if (!storebe(m, addr, n, s->gpr[d]))
      return BRPPCStopFault;
    if (upd)
      s->gpr[a] = addr;
    write = NO;
    break;
  }
  case 284:
    r = ~(S ^ B);
    d = a;
    break;
  case 316:
    r = S ^ B;
    d = a;
    break;
  case 412:
    r = S | ~B;
    d = a;
    break;
  case 444:
    r = S | B;
    d = a;
    break;
  case 476:
    r = ~(S & B);
    d = a;
    break;
  case 792:
    sz = (int32_t)S;
    {
      unsigned n = B & 63;
      r = n >= 32 ? (uint32_t)(sz >> 31) : (uint32_t)(sz >> n);
      BOOL lost = n >= 32 ? S != 0 : n && (S & ((1u << n) - 1));
      setca(s, sz < 0 && lost);
    }
    d = a;
    break;
  case 824:
    sz = (int32_t)S;
    {
      unsigned n = b;
      r = (uint32_t)(sz >> n);
      setca(s, n && sz < 0 && ((S & ((1u << n) - 1)) != 0));
    }
    d = a;
    break;
  case 662:
  case 918: {
    unsigned n = xo == 662 ? 4 : 2;
    addr = ea0(s, a) + B;
    uint32_t v = s->gpr[d];
    uint8_t q[4];
    for (unsigned i = 0; i < n; i++)
      q[i] = (uint8_t)(v >> (8 * i));
    if (!memwrite(m, addr, q, n))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  case 533: {
    if (a == d || b == d)
      return BRPPCStopIllegalInstruction;
    unsigned n = s->xer & 0x7f;
    if (!loadString(m, s, ea0(s, a) + B, d, n))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  case 597: {
    if (a == d)
      return BRPPCStopIllegalInstruction;
    unsigned n = b ? b : 32;
    if (!loadString(m, s, ea0(s, a), d, n))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  case 661: {
    unsigned n = s->xer & 0x7f;
    if (!storeString(m, s, ea0(s, a) + B, d, n))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  case 725: {
    unsigned n = b ? b : 32;
    if (!storeString(m, s, ea0(s, a), d, n))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  case 534:
  case 790: {
    unsigned n = xo == 534 ? 4 : 2;
    addr = ea0(s, a) + B;
    uint8_t q[4];
    if (!memread(m, addr, q, n))
      return BRPPCStopFault;
    r = 0;
    for (unsigned i = 0; i < n; i++)
      r |= (uint32_t)q[i] << (8 * i);
    break;
  }
  case 535:
  case 567:
  case 599:
  case 631: {
    BOOL dbl = xo == 599 || xo == 631, upd = xo == 567 || xo == 631;
    if (upd && !a)
      return BRPPCStopIllegalInstruction;
    addr = ea0(s, a) + B;
    if (addr & (dbl ? 7 : 3))
      return BRPPCStopFault;
    if (!fpLoadIndexed(m, s, d, addr, dbl))
      return BRPPCStopFault;
    if (upd)
      s->gpr[a] = addr;
    write = NO;
    break;
  }
  case 663:
  case 695:
  case 727:
  case 759: {
    BOOL dbl = xo == 727 || xo == 759, upd = xo == 695 || xo == 759;
    if (upd && !a)
      return BRPPCStopIllegalInstruction;
    addr = ea0(s, a) + B;
    if (addr & (dbl ? 7 : 3))
      return BRPPCStopFault;
    if (!fpStoreIndexed(m, s, d, addr, dbl))
      return BRPPCStopFault;
    if (upd)
      s->gpr[a] = addr;
    write = NO;
    break;
  }
  case 983: {
    addr = ea0(s, a) + B;
    if (addr & 3)
      return BRPPCStopFault;
    uint64_t bits;
    memcpy(&bits, &s->fpr[d], 8);
    if (!storebe(m, addr, 4, (uint32_t)bits))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  case 54:
  case 86:
  case 246:
  case 278:
  case 598:
  case 758:
  case 854:
    write = NO;
    break;
  case 922:
    r = (uint32_t)(int32_t)(int16_t)S;
    d = a;
    break;
  case 954:
    r = (uint32_t)(int32_t)(int8_t)S;
    d = a;
    break;
  case 982:
    if ([m respondsToSelector:@selector(synchronizeInstructionCacheAtAddress:)])
      [m synchronizeInstructionCacheAtAddress:ea0(s, a) + B];
    [e invalidateTranslationCache];
    write = NO;
    break;
  case 1014: {
    uint8_t zero[32] = {0};
    addr = (ea0(s, a) + B) & ~31u;
    if (!memwrite(m, addr, zero, sizeof zero))
      return BRPPCStopFault;
    write = NO;
    break;
  }
  default:
    return illegal(w, s, m, e);
  }
  if (write) {
    s->gpr[d] = r;
    if (rc)
      setcr0(s, r);
  }
  return okadvance(s);
}

static BRPPCStopReason execSC(uint32_t w, BRPPCState *s,
                              id<BRPPCMemory> __unsafe_unretained m,
                              BRPowerPC32 * __unsafe_unretained e) {
  (void)w;
  (void)m;
  BRPPCStopReason stop = BRPPCStopSystemCall;
  if (e.systemCallHandler)
    e.systemCallHandler(s, &stop);
  if (stop == BRPPCStopNone)
    s->pc += 4;
  return stop;
}
static BRPPCStopReason execTrapI(uint32_t w, BRPPCState *s,
                                 id<BRPPCMemory> __unsafe_unretained m,
                                 BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  (void)e;
  int32_t a = (int32_t)s->gpr[ra(w)], b = sx16(w);
  uint32_t ua = (uint32_t)a, ub = (uint32_t)b, to = rd(w);
  BOOL t = ((to & 16) && a < b) || ((to & 8) && a > b) ||
           ((to & 4) && a == b) || ((to & 2) && ua < ub) ||
           ((to & 1) && ua > ub);
  return t ? BRPPCStopTrap : okadvance(s);
}
static BRPPCStopReason execVector(uint32_t w, BRPPCState *s,
                                  id<BRPPCMemory> __unsafe_unretained m,
                                  BRPowerPC32 * __unsafe_unretained e) {
  (void)m;
  return e.model == BRPPCCPUG4 ? BRPPCExecuteAltiVec(w, s)
                               : BRPPCStopIllegalInstruction;
}

static BRExec decode(uint32_t w) {
  switch (w >> 26) {
  case 3:
    return execTrapI;
  case 4:
    return execVector;
  case 7:
  case 8:
  case 10:
  case 11:
  case 12:
  case 13:
  case 14:
  case 15:
  case 24:
  case 25:
  case 26:
  case 27:
  case 28:
  case 29:
    return execImm;
  case 9:
    return exec601Imm;
  case 16:
  case 18:
    return execBranch;
  case 17:
    return execSC;
  case 19:
    return execCR;
  case 20:
  case 21:
  case 22:
  case 23:
    return execRotate;
  case 31:
    return execX;
  case 32:
  case 33:
  case 34:
  case 35:
  case 36:
  case 37:
  case 38:
  case 39:
  case 40:
  case 41:
  case 42:
  case 43:
  case 44:
  case 45:
  case 46:
  case 47:
    return execLoadStore;
  case 48:
  case 49:
  case 50:
  case 51:
  case 52:
  case 53:
  case 54:
  case 55:
    return execFPLoadStore;
  case 59:
  case 63:
    return execFP;
  default:
    return illegal;
  }
}

@implementation BRPowerPC32
@synthesize state = _state, stopReason = _stopReason;
- (uint32_t)programCounter { return _state.pc; }
- (BRPPCState *)mutableState { return &_state; }
- (void)setState:(BRPPCState)state {
  _state = state;
  _stopReason = BRPPCStopNone;
}
- (instancetype)initWithMemory:(id<BRPPCMemory>)memory {
  if ((self = [super init])) {
    _memory = memory;
    _model = BRPPCCPUCommon;
    _privilegeAuthorizer = [BRPPCSecurityAuthorizer new];
    [self invalidateTranslationCache];
    if ([_memory respondsToSelector:@selector(setInstructionCacheInvalidationHandler:)]) {
      __weak typeof(self) weakSelf = self;
      [_memory setInstructionCacheInvalidationHandler:^(uint32_t address, size_t length) {
        [weakSelf invalidateTranslationCacheAtAddress:address length:length];
      }];
    }
  }
  return self;
}
- (void)resetAtProgramCounter:(uint32_t)pc {
  memset(&_state, 0, sizeof _state);
  _state.pc = pc;
  _stopReason = BRPPCStopNone;
  [self invalidateTranslationCache];
}
- (void)invalidateTranslationCache {
  memset(_cache, 0, sizeof _cache);
}
- (void)invalidateTranslationCacheAtAddress:(uint32_t)address length:(size_t)length {
  if (!length) return;
  uint64_t lastByte = (uint64_t)address + length - 1;
  uint64_t firstPC = address & ~UINT64_C(3);
  uint64_t lastPC = lastByte & ~UINT64_C(3);
  if (lastByte > UINT32_MAX || (lastPC - firstPC) / 4 >= 4096) {
    [self invalidateTranslationCache];
    return;
  }
  for (uint32_t pc = (uint32_t)firstPC;; pc += 4) {
    BRCacheEntry *entry = &_cache[(pc >> 2) & 4095];
    if (entry->exec && entry->pc == pc) memset(entry, 0, sizeof(*entry));
    if (pc == (uint32_t)lastPC) break;
  }
}
- (BRPPCStopReason)executePrivilegedInstruction:(uint32_t)instruction {
  if (!_supervisorHandler)
    return BRPPCStopPrivilegedInstruction;
  if (_privilegeAuthorizer) {
    NSString *message = [NSString
        stringWithFormat:@"Bismuth needs administrator approval to emulate "
                         @"privileged PowerPC instruction 0x%08x.",
                         instruction];
    if (![_privilegeAuthorizer authorizeInstruction:instruction
                                        description:message
                                              error:NULL])
      return BRPPCStopPrivilegedInstruction;
  }
  BRPPCStopReason result = BRPPCStopPrivilegedInstruction;
  _supervisorHandler(instruction, &_state, _memory, &result);
  if (result == BRPPCStopNone)
    _state.pc += 4;
  return result;
}
- (BRPPCStopReason)step {
  if (_stopReason != BRPPCStopNone)
    return _stopReason;
  if (_state.pc & 3)
    return _stopReason = BRPPCStopFault;
  BRCacheEntry *c = &_cache[(_state.pc >> 2) & 4095];
  uint32_t w;
  if (c->pc == _state.pc && c->exec) {
    w = c->word;
  } else {
    uint8_t b[4];
    if (![_memory readBytes:b address:_state.pc length:4])
      return _stopReason = BRPPCStopFault;
    w = (uint32_t)b[0] << 24 | (uint32_t)b[1] << 16 |
        (uint32_t)b[2] << 8 | b[3];
    c->pc = _state.pc;
    c->word = w;
    c->exec = decode(w);
  }
  BRPPCStopReason r = c->exec(w, &_state, _memory, self);
  if (r != BRPPCStopNone)
    _stopReason = r;
  return r;
}
- (BRPPCStopReason)runWithInstructionLimit:(uint64_t)n {
  return [self runWithInstructionLimit:n
      stoppingBeforeProgramCounterFrom:UINT32_MAX through:0];
}
- (BRPPCStopReason)runWithInstructionLimit:(uint64_t)n
          stoppingBeforeProgramCounterFrom:(uint32_t)firstAddress
                                    through:(uint32_t)lastAddress {
  return [self runWithInstructionLimit:n
      stoppingBeforeProgramCounterFrom:firstAddress
                                through:lastAddress
               executedInstructionCount:NULL];
}
- (BRPPCStopReason)runWithInstructionLimit:(uint64_t)n
          stoppingBeforeProgramCounterFrom:(uint32_t)firstAddress
                                    through:(uint32_t)lastAddress
                   executedInstructionCount:(uint64_t *)executedInstructionCount {
  uint64_t executed = 0;
  while (n-- && _stopReason == BRPPCStopNone) {
    if (_state.pc >= firstAddress && _state.pc <= lastAddress)
      break;
    if (_state.pc & 3) {
      _stopReason = BRPPCStopFault;
      break;
    }
    BRCacheEntry *c = &_cache[(_state.pc >> 2) & 4095];
    uint32_t w;
    if (c->pc == _state.pc && c->exec) {
      w = c->word;
    } else {
      uint8_t b[4];
      if (![_memory readBytes:b address:_state.pc length:4]) {
        _stopReason = BRPPCStopFault;
        break;
      }
      w = (uint32_t)b[0] << 24 | (uint32_t)b[1] << 16 |
          (uint32_t)b[2] << 8 | b[3];
      c->pc = _state.pc;
      c->word = w;
      c->exec = decode(w);
    }
    BRPPCStopReason reason = c->exec(w, &_state, _memory, self);
    executed++;
    if (reason != BRPPCStopNone)
      _stopReason = reason;
  }
  if (executedInstructionCount)
    *executedInstructionCount = executed;
  return _stopReason;
}
@end
