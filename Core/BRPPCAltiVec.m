#import "BRPPCAltiVec.h"
#include <math.h>

static uint16_t g16(const BRPPCVector *v, unsigned i) {
  return (uint16_t)v->byte[i * 2] << 8 | v->byte[i * 2 + 1];
}
static uint32_t g32(const BRPPCVector *v, unsigned i) {
  return (uint32_t)v->byte[i * 4] << 24 | (uint32_t)v->byte[i * 4 + 1] << 16 |
         (uint32_t)v->byte[i * 4 + 2] << 8 | v->byte[i * 4 + 3];
}
static void p16(BRPPCVector *v, unsigned i, uint16_t x) {
  v->byte[i * 2] = x >> 8;
  v->byte[i * 2 + 1] = x;
}
static void p32(BRPPCVector *v, unsigned i, uint32_t x) {
  v->byte[i * 4] = x >> 24;
  v->byte[i * 4 + 1] = x >> 16;
  v->byte[i * 4 + 2] = x >> 8;
  v->byte[i * 4 + 3] = x;
}
static float gf(const BRPPCVector *v, unsigned i) {
  uint32_t x = g32(v, i);
  float f;
  memcpy(&f, &x, 4);
  return f;
}
static void pf(BRPPCVector *v, unsigned i, float f) {
  uint32_t x;
  memcpy(&x, &f, 4);
  p32(v, i, x);
}
static float fpMinMax(float a, float b, BOOL maximum) {
  if (isnan(a) || isnan(b)) {
    float q = isnan(a) ? a : b;
    uint32_t bits;
    memcpy(&bits, &q, 4);
    bits |= 0x00400000u;
    memcpy(&q, &bits, 4);
    return q;
  }
  return maximum ? fmaxf(a, b) : fminf(a, b);
}
static int64_t sclip(int64_t x, unsigned bits, BOOL *sat) {
  int64_t lo = -(1ll << (bits - 1)), hi = (1ll << (bits - 1)) - 1;
  if (x < lo) {
    *sat = YES;
    return lo;
  }
  if (x > hi) {
    *sat = YES;
    return hi;
  }
  return x;
}
static uint64_t uclip(int64_t x, unsigned bits, BOOL *sat) {
  uint64_t hi = bits == 32 ? UINT32_MAX : (1ull << bits) - 1;
  if (x < 0) {
    *sat = YES;
    return 0;
  }
  if ((uint64_t)x > hi) {
    *sat = YES;
    return hi;
  }
  return (uint64_t)x;
}
static uint32_t fpToWord(float x, unsigned scale, BOOL sign, BOOL *sat) {
  if (isnan(x))
    return 0;
  double q = ldexp((double)x, scale);
  if (sign) {
    if (q < (double)INT32_MIN) {
      *sat = YES;
      return INT32_MIN;
    }
    if (q > (double)INT32_MAX) {
      *sat = YES;
      return INT32_MAX;
    }
    return (uint32_t)(int32_t)trunc(q);
  }
  if (q < 0) {
    *sat = YES;
    return 0;
  }
  if (q > (double)UINT32_MAX) {
    *sat = YES;
    return UINT32_MAX;
  }
  return (uint32_t)trunc(q);
}
static void summary(BRPPCState *s, const BRPPCVector *v) {
  BOOL all = YES, none = YES;
  for (unsigned i = 0; i < 16; i++) {
    all &= v->byte[i] == 255;
    none &= v->byte[i] == 0;
  }
  uint32_t f = all ? 8 : none ? 2 : 0;
  s->cr = (s->cr & ~0x00f00000) | (f << 20);
}

BRPPCStopReason BRPPCExecuteAltiVec(uint32_t w, BRPPCState *s) {
  unsigned d = (w >> 21) & 31, a = (w >> 16) & 31, b = (w >> 11) & 31,
           c = (w >> 6) & 31, x = w & 2047, base = x & 1023;
  BOOL comparison = base == 6 || base == 70 || base == 134 || base == 198 ||
                    base == 454 || base == 518 || base == 582 || base == 646 ||
                    base == 710 || base == 774 || base == 838 || base == 902 ||
                    base == 966;
  if (comparison)
    x = base;
  BRPPCVector A = s->vr[a], B = s->vr[b], C = s->vr[c], R = {{0}};
  BOOL record = comparison && ((w >> 10) & 1), sat = NO,
       fp = x == 10 || x == 74 || x == 198 || x == 266 || x == 330 ||
            x == 394 || x == 454 || x == 458 || x == 522 || x == 586 ||
            x == 650 || x == 710 || x == 714 || x == 778 || x == 842 ||
            x == 906 || x == 966 || x == 970 || x == 1034 || x == 1098 ||
            (w & 63) == 46 || (w & 63) == 47;
  if (fp && (s->vscr & 0x10000)) {
    BRPPCVector *vv[3] = {&A, &B, &C};
    for (unsigned v = 0; v < 3; v++)
      for (unsigned i = 0; i < 4; i++) {
        float q = gf(vv[v], i);
        if (fpclassify(q) == FP_SUBNORMAL)
          p32(vv[v], i, g32(vv[v], i) & 0x80000000u);
      }
  }
  switch (x) {
  case 0:
  case 1024:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] = x ? A.byte[i] - B.byte[i] : A.byte[i] + B.byte[i];
    break;
  case 64:
  case 1088:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i, x == 64 ? g16(&A, i) + g16(&B, i) : g16(&A, i) - g16(&B, i));
    break;
  case 128:
  case 1152:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, x == 128 ? g32(&A, i) + g32(&B, i) : g32(&A, i) - g32(&B, i));
    break;
  case 512:
  case 1536:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] = (uint8_t)uclip(x == 512 ? (int64_t)A.byte[i] + B.byte[i]
                                          : (int64_t)A.byte[i] - B.byte[i],
                                 8, &sat);
    break;
  case 576:
  case 1600:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i,
          (uint16_t)uclip(x == 576 ? (int64_t)g16(&A, i) + g16(&B, i)
                                   : (int64_t)g16(&A, i) - g16(&B, i),
                          16, &sat));
    break;
  case 640:
  case 1664:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i,
          (uint32_t)uclip(x == 640 ? (int64_t)g32(&A, i) + g32(&B, i)
                                   : (int64_t)g32(&A, i) - g32(&B, i),
                          32, &sat));
    break;
  case 768:
  case 1792:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] =
          (uint8_t)sclip(x == 768 ? (int8_t)A.byte[i] + (int8_t)B.byte[i]
                                  : (int8_t)A.byte[i] - (int8_t)B.byte[i],
                         8, &sat);
    break;
  case 832:
  case 1856:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i,
          (uint16_t)sclip(x == 832 ? (int16_t)g16(&A, i) + (int16_t)g16(&B, i)
                                   : (int16_t)g16(&A, i) - (int16_t)g16(&B, i),
                          16, &sat));
    break;
  case 896:
  case 1920:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i,
          (uint32_t)sclip(
              x == 896 ? (int64_t)(int32_t)g32(&A, i) + (int32_t)g32(&B, i)
                       : (int64_t)(int32_t)g32(&A, i) - (int32_t)g32(&B, i),
              32, &sat));
    break;
  case 1026:
  case 1282:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] =
          x == 1026
              ? (A.byte[i] + B.byte[i] + 1u) >> 1
              : (uint8_t)(((int8_t)A.byte[i] + (int8_t)B.byte[i] + 1) >> 1);
    break;
  case 1090:
  case 1346:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i,
          x == 1090
              ? (g16(&A, i) + g16(&B, i) + 1u) >> 1
              : (uint16_t)(((int16_t)g16(&A, i) + (int16_t)g16(&B, i) + 1) >>
                           1));
    break;
  case 1154:
  case 1410:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i,
          x == 1154 ? (uint32_t)(((uint64_t)g32(&A, i) + g32(&B, i) + 1) >> 1)
                    : (uint32_t)(((int64_t)(int32_t)g32(&A, i) +
                                  (int32_t)g32(&B, i) + 1) >>
                                 1));
    break;
  case 384:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, (uint64_t)g32(&A, i) + g32(&B, i) > UINT32_MAX ? 1 : 0);
    break;
  case 1408:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, g32(&A, i) >= g32(&B, i) ? 1 : 0);
    break;
  case 2:
  case 514:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] =
          x == 2 ? MAX(A.byte[i], B.byte[i]) : MIN(A.byte[i], B.byte[i]);
    break;
  case 66:
  case 578:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i,
          x == 66 ? MAX(g16(&A, i), g16(&B, i)) : MIN(g16(&A, i), g16(&B, i)));
    break;
  case 130:
  case 642:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i,
          x == 130 ? MAX(g32(&A, i), g32(&B, i)) : MIN(g32(&A, i), g32(&B, i)));
    break;
  case 258:
  case 770:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] =
          (uint8_t)(x == 258 ? MAX((int8_t)A.byte[i], (int8_t)B.byte[i])
                             : MIN((int8_t)A.byte[i], (int8_t)B.byte[i]));
    break;
  case 322:
  case 834:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i,
          (uint16_t)(x == 322 ? MAX((int16_t)g16(&A, i), (int16_t)g16(&B, i))
                              : MIN((int16_t)g16(&A, i), (int16_t)g16(&B, i))));
    break;
  case 386:
  case 898:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i,
          (uint32_t)(x == 386 ? MAX((int32_t)g32(&A, i), (int32_t)g32(&B, i))
                              : MIN((int32_t)g32(&A, i), (int32_t)g32(&B, i))));
    break;
  case 1028:
  case 1092:
  case 1156:
  case 1220:
  case 1284:
    for (unsigned i = 0; i < 16; i++) {
      switch (x) {
      case 1028:
        R.byte[i] = A.byte[i] & B.byte[i];
        break;
      case 1092:
        R.byte[i] = A.byte[i] & ~B.byte[i];
        break;
      case 1156:
        R.byte[i] = A.byte[i] | B.byte[i];
        break;
      case 1220:
        R.byte[i] = A.byte[i] ^ B.byte[i];
        break;
      default:
        R.byte[i] = ~(A.byte[i] | B.byte[i]);
      }
    }
    break;
  case 6:
  case 518:
  case 774:
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] = (x == 6     ? A.byte[i] == B.byte[i]
                   : x == 518 ? A.byte[i] > B.byte[i]
                              : (int8_t)A.byte[i] > (int8_t)B.byte[i])
                      ? 255
                      : 0;
    break;
  case 70:
  case 582:
  case 838:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i,
          (x == 70    ? g16(&A, i) == g16(&B, i)
           : x == 582 ? g16(&A, i) > g16(&B, i)
                      : (int16_t)g16(&A, i) > (int16_t)g16(&B, i))
              ? UINT16_MAX
              : 0);
    break;
  case 134:
  case 646:
  case 902:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i,
          (x == 134   ? g32(&A, i) == g32(&B, i)
           : x == 646 ? g32(&A, i) > g32(&B, i)
                      : (int32_t)g32(&A, i) > (int32_t)g32(&B, i))
              ? UINT32_MAX
              : 0);
    break;
  case 198:
  case 454:
  case 710:
    for (unsigned i = 0; i < 4; i++) {
      float q = gf(&A, i), r = gf(&B, i);
      p32(&R, i,
          (x == 198   ? q == r
           : x == 454 ? q >= r
                      : q > r)
              ? UINT32_MAX
              : 0);
    }
    break;
  case 966: {
    BOOL in = YES;
    for (unsigned i = 0; i < 4; i++) {
      float q = gf(&A, i), limit = gf(&B, i);
      uint32_t v =
          isnan(q) || isnan(limit)
              ? 0xc0000000u
              : (q > limit ? 0x80000000u : 0) | (q < -limit ? 0x40000000u : 0);
      p32(&R, i, v);
      in &= v == 0;
    }
    if (record)
      s->cr = (s->cr & ~0x00f00000) | (in ? 2u << 20 : 0);
    record = NO;
    break;
  }
  case 10:
  case 74:
    for (unsigned i = 0; i < 4; i++)
      pf(&R, i, x == 10 ? gf(&A, i) + gf(&B, i) : gf(&A, i) - gf(&B, i));
    break;
  case 1034:
  case 1098:
    for (unsigned i = 0; i < 4; i++)
      pf(&R, i, fpMinMax(gf(&A, i), gf(&B, i), x == 1034));
    break;
  case 266:
  case 330:
  case 394:
  case 458:
    for (unsigned i = 0; i < 4; i++) {
      float q = gf(&B, i);
      pf(&R, i,
         x == 266   ? 1.0f / q
         : x == 330 ? 1.0f / sqrtf(q)
         : x == 394 ? exp2f(q)
                    : log2f(q));
    }
    break;
  case 8:
  case 264:
  case 520:
  case 776:
    for (unsigned i = 0; i < 8; i++) {
      unsigned j = i * 2 + ((x == 8 || x == 264) ? 1 : 0);
      BOOL sign = x == 264 || x == 776;
      p16(&R, i,
          (uint16_t)(sign ? (int16_t)((int8_t)A.byte[j] * (int8_t)B.byte[j])
                          : (uint16_t)A.byte[j] * B.byte[j]));
    }
    break;
  case 72:
  case 328:
  case 584:
  case 840:
    for (unsigned i = 0; i < 4; i++) {
      unsigned j = i * 2 + ((x == 72 || x == 328) ? 1 : 0);
      BOOL sign = x == 328 || x == 840;
      p32(&R, i,
          (uint32_t)(sign ? (int32_t)((int16_t)g16(&A, j) * (int16_t)g16(&B, j))
                          : (uint32_t)g16(&A, j) * g16(&B, j)));
    }
    break;
  case 4:
  case 260:
  case 516:
  case 772:
    for (unsigned i = 0; i < 16; i++) {
      unsigned n = B.byte[i] & 7;
      R.byte[i] = x == 4     ? (A.byte[i] << n) | (A.byte[i] >> ((8 - n) & 7))
                  : x == 260 ? A.byte[i] << n
                  : x == 516 ? A.byte[i] >> n
                             : (uint8_t)((int8_t)A.byte[i] >> n);
    }
    break;
  case 68:
  case 324:
  case 580:
  case 836:
    for (unsigned i = 0; i < 8; i++) {
      unsigned n = g16(&B, i) & 15;
      uint16_t q = g16(&A, i), r = x == 68 ? (q << n) | (q >> ((16 - n) & 15))
                                   : x == 324 ? q << n
                                   : x == 580 ? q >> n
                                              : (uint16_t)((int16_t)q >> n);
      p16(&R, i, r);
    }
    break;
  case 132:
  case 388:
  case 644:
  case 900:
    for (unsigned i = 0; i < 4; i++) {
      unsigned n = g32(&B, i) & 31;
      uint32_t q = g32(&A, i), r = x == 132 ? (q << n) | (q >> ((32 - n) & 31))
                                   : x == 388 ? q << n
                                   : x == 644 ? q >> n
                                              : (uint32_t)((int32_t)q >> n);
      p32(&R, i, r);
    }
    break;
  case 12:
  case 268:
    for (unsigned i = 0; i < 8; i++) {
      R.byte[i * 2] = A.byte[i + (x == 268 ? 8 : 0)];
      R.byte[i * 2 + 1] = B.byte[i + (x == 268 ? 8 : 0)];
    }
    break;
  case 76:
  case 332:
    for (unsigned i = 0; i < 4; i++) {
      p16(&R, i * 2, g16(&A, i + (x == 332 ? 4 : 0)));
      p16(&R, i * 2 + 1, g16(&B, i + (x == 332 ? 4 : 0)));
    }
    break;
  case 140:
  case 396:
    for (unsigned i = 0; i < 2; i++) {
      p32(&R, i * 2, g32(&A, i + (x == 396 ? 2 : 0)));
      p32(&R, i * 2 + 1, g32(&B, i + (x == 396 ? 2 : 0)));
    }
    break;
  case 14:
    for (unsigned i = 0; i < 8; i++)
      R.byte[i] = (uint8_t)g16(&A, i);
    for (unsigned i = 0; i < 8; i++)
      R.byte[i + 8] = (uint8_t)g16(&B, i);
    break;
  case 78:
    for (unsigned i = 0; i < 4; i++)
      p16(&R, i, (uint16_t)g32(&A, i));
    for (unsigned i = 0; i < 4; i++)
      p16(&R, i + 4, (uint16_t)g32(&B, i));
    break;
  case 142:
  case 270:
  case 398:
    for (unsigned i = 0; i < 16; i++) {
      int64_t q = (int16_t)g16(i < 8 ? &A : &B, i & 7);
      R.byte[i] = (uint8_t)(x == 142   ? uclip((uint16_t)q, 8, &sat)
                            : x == 270 ? uclip(q, 8, &sat)
                                       : sclip(q, 8, &sat));
    }
    break;
  case 206:
  case 334:
  case 462:
    for (unsigned i = 0; i < 8; i++) {
      int64_t q = (int32_t)g32(i < 4 ? &A : &B, i & 3);
      p16(&R, i,
          (uint16_t)(x == 206   ? uclip((uint32_t)q, 16, &sat)
                     : x == 334 ? uclip(q, 16, &sat)
                                : sclip(q, 16, &sat)));
    }
    break;
  case 526:
  case 654:
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i, (uint16_t)(int16_t)(int8_t)B.byte[i + (x == 654 ? 8 : 0)]);
    break;
  case 590:
  case 718:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, (uint32_t)(int32_t)(int16_t)g16(&B, i + (x == 718 ? 4 : 0)));
    break;
  case 782:
    for (unsigned i = 0; i < 4; i++) {
      uint32_t q = g32(&A, i);
      p16(&R, i,
          (uint16_t)(((q >> 9) & 0xfc00) | ((q >> 6) & 0x03e0) |
                     ((q >> 3) & 0x1f)));
      q = g32(&B, i);
      p16(&R, i + 4,
          (uint16_t)(((q >> 9) & 0xfc00) | ((q >> 6) & 0x03e0) |
                     ((q >> 3) & 0x1f)));
    }
    break;
  case 846:
  case 974:
    for (unsigned i = 0; i < 4; i++) {
      uint16_t q = g16(&B, i + (x == 974 ? 4 : 0));
      p32(&R, i,
          ((q & 0x8000) ? 0xff000000u : 0) |
              ((uint32_t)((q >> 10) & 31) << 16) |
              ((uint32_t)((q >> 5) & 31) << 8) | (q & 31));
    }
    break;
  case 522:
  case 586:
  case 650:
  case 714:
    for (unsigned i = 0; i < 4; i++) {
      float q = gf(&B, i);
      pf(&R, i,
         x == 522   ? nearbyintf(q)
         : x == 586 ? truncf(q)
         : x == 650 ? ceilf(q)
                    : floorf(q));
    }
    break;
  case 524: {
    unsigned n = a & 15;
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] = B.byte[n];
    break;
  }
  case 588: {
    unsigned n = a & 7;
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i, g16(&B, n));
    break;
  }
  case 652: {
    unsigned n = a & 3;
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, g32(&B, n));
    break;
  }
  case 780: {
    uint8_t q = (uint8_t)((int8_t)(a << 3) >> 3);
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] = q;
    break;
  }
  case 844: {
    int16_t q = (int16_t)(a << 11) >> 11;
    for (unsigned i = 0; i < 8; i++)
      p16(&R, i, q);
    break;
  }
  case 908: {
    int32_t q = (int32_t)(a << 27) >> 27;
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, q);
    break;
  }
  case 1540:
    memset(&R, 0, sizeof R);
    p32(&R, 3, s->vscr);
    break;
  case 1604:
    s->vscr = g32(&B, 3) & 0x00010001u;
    s->pc += 4;
    return BRPPCStopNone;
  case 778:
  case 842:
    for (unsigned i = 0; i < 4; i++)
      pf(&R, i,
         (x == 778 ? (float)g32(&B, i) : (float)(int32_t)g32(&B, i)) /
             ldexpf(1.0f, a));
    break;
  case 906:
  case 970:
    for (unsigned i = 0; i < 4; i++)
      p32(&R, i, fpToWord(gf(&B, i), a, x == 970, &sat));
    break;
  case 452:
  case 708: {
    unsigned n = B.byte[15] & 7;
    for (unsigned i = 0; i < 16; i++) {
      if (!n) {
        R.byte[i] = A.byte[i];
        continue;
      }
      if (x == 452) {
        unsigned j = i;
        R.byte[i] = (uint8_t)((A.byte[j] << n) |
                              (j + 1 < 16 ? A.byte[j + 1] >> (8 - n) : 0));
      } else {
        unsigned j = i;
        R.byte[i] =
            (uint8_t)((A.byte[j] >> n) | (j ? A.byte[j - 1] << (8 - n) : 0));
      }
    }
    break;
  }
  case 1036:
  case 1100: {
    unsigned n = (B.byte[15] >> 3) & 15;
    for (unsigned i = 0; i < 16; i++)
      R.byte[i] = x == 1036 ? (i + n < 16 ? A.byte[i + n] : 0)
                            : (i >= n ? A.byte[i - n] : 0);
    break;
  }
  case 1544:
  case 1800:
    for (unsigned i = 0; i < 4; i++) {
      int64_t q =
          x == 1544 ? (int64_t)(uint64_t)g32(&B, i) : (int32_t)g32(&B, i);
      for (unsigned j = 0; j < 4; j++)
        q += x == 1544 ? A.byte[i * 4 + j] : (int8_t)A.byte[i * 4 + j];
      p32(&R, i,
          (uint32_t)(x == 1544 ? uclip(q, 32, &sat) : sclip(q, 32, &sat)));
    }
    break;
  case 1608:
    for (unsigned i = 0; i < 4; i++) {
      int64_t q = (int32_t)g32(&B, i) + (int16_t)g16(&A, i * 2) +
                  (int16_t)g16(&A, i * 2 + 1);
      p32(&R, i, (uint32_t)sclip(q, 32, &sat));
    }
    break;
  case 1672:
    for (unsigned i = 0; i < 2; i++) {
      int64_t q = (int64_t)(int32_t)g32(&B, i * 2 + 1) +
                  (int32_t)g32(&A, i * 2) +
                  (int32_t)g32(&A, i * 2 + 1);
      p32(&R, i * 2, 0);
      p32(&R, i * 2 + 1, (uint32_t)sclip(q, 32, &sat));
    }
    break;
  case 1928: {
    int64_t q = (int32_t)g32(&B, 3);
    for (unsigned i = 0; i < 4; i++)
      q += (int32_t)g32(&A, i);
    p32(&R, 3, (uint32_t)sclip(q, 32, &sat));
    break;
  }
  default: {
    unsigned xa = w & 63;
    if (xa == 32 || xa == 33) {
      for (unsigned i = 0; i < 8; i++) {
        int64_t q =
            (int16_t)g16(&A, i) * (int16_t)g16(&B, i) + (xa == 33 ? 0x4000 : 0);
        q = (q >> 15) + (int16_t)g16(&C, i);
        p16(&R, i, (uint16_t)sclip(q, 16, &sat));
      }
      break;
    }
    if (xa == 34) {
      for (unsigned i = 0; i < 8; i++)
        p16(&R, i,
            (uint16_t)((uint32_t)g16(&A, i) * g16(&B, i) + g16(&C, i)));
      break;
    }
    if (xa >= 36 && xa <= 41) {
      for (unsigned i = 0; i < 4; i++) {
        int64_t q =
            xa == 39 ? (int64_t)(uint64_t)g32(&C, i) : (int32_t)g32(&C, i);
        if (xa == 36 || xa == 37) {
          for (unsigned j = 0; j < 4; j++)
            q += (xa == 36 ? A.byte[i * 4 + j] : (int8_t)A.byte[i * 4 + j]) *
                 B.byte[i * 4 + j];
        } else {
          for (unsigned j = 0; j < 2; j++) {
            if (xa == 38 || xa == 39)
              q += (int64_t)(uint32_t)g16(&A, i * 2 + j) *
                   g16(&B, i * 2 + j);
            else
              q += (int64_t)(int16_t)g16(&A, i * 2 + j) *
                   (int16_t)g16(&B, i * 2 + j);
          }
        }
        p32(&R, i,
            (uint32_t)((xa == 39)   ? uclip(q, 32, &sat)
                       : (xa == 41) ? sclip(q, 32, &sat)
                                    : q));
      }
      break;
    }
    if (xa == 42) {
      for (unsigned i = 0; i < 16; i++)
        R.byte[i] = (A.byte[i] & ~C.byte[i]) | (B.byte[i] & C.byte[i]);
      break;
    }
    if (xa == 43) {
      for (unsigned i = 0; i < 16; i++) {
        unsigned n = C.byte[i] & 31;
        R.byte[i] = n < 16 ? A.byte[n] : B.byte[n - 16];
      }
      break;
    }
    if (xa == 44) {
      unsigned n = (w >> 6) & 15;
      for (unsigned i = 0; i < 16; i++) {
        unsigned j = i + n;
        R.byte[i] = j < 16 ? A.byte[j] : B.byte[j - 16];
      }
      break;
    }
    if (xa == 46 || xa == 47) {
      for (unsigned i = 0; i < 4; i++)
        pf(&R, i,
           xa == 46 ? fmaf(gf(&A, i), gf(&C, i), gf(&B, i))
                    : -fmaf(gf(&A, i), gf(&C, i), -gf(&B, i)));
      break;
    }
    return BRPPCStopIllegalInstruction;
  }
  }
  if (fp && (s->vscr & 0x10000))
    for (unsigned i = 0; i < 4; i++) {
      float q = gf(&R, i);
      if (fpclassify(q) == FP_SUBNORMAL)
        p32(&R, i, g32(&R, i) & 0x80000000u);
    }
  s->vr[d] = R;
  if (sat)
    s->vscr |= 1;
  if (record)
    summary(s, &R);
  s->pc += 4;
  return BRPPCStopNone;
}
