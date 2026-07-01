#!/usr/bin/env python3
# sim_reu_comb.py - ASM-FAITHFUL model of the REU-backed signed comb.
#   Mirrors exactly what reu_comb.inc will do at the byte level, so the asm
#   is a 1:1 transcription:
#     - MPRIME as NB_BYTES bytes; recode adds ORDER if scalar even, >>1, forces
#       bit (L-1), L = t*W.
#     - per step: looped teeth GETBIT -> multi-byte idx (t-1 bits).
#     - REU offset = idx * 64 (idx<<6); DMA-fetch 64 bytes = X[32]||Y[32] LE.
#     - negate X if tooth0 sign (CB_NEG); Z=1; T = X*Y mod p.
#   Proven vs scalar_mul(s,B) for t=12 and t=18.

import sys, random, math
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_ed import p, B, scalar_mul, point_add, point_dbl, to_affine
from gen_comb_table import gen_table, comb_W

ORDER = 2**252 + 27742317777372353535851937790883648493
IDENT = (0, 1, 1, 0)

def recode_bytes(scalar, t, W):
    """Return MPRIME as a list of NB_BYTES bytes, mirroring CB_RECODE_REU."""
    L = t * W
    nbits_top = L - 1
    NB_BYTES = (nbits_top // 8) + 1
    m = scalar
    if m % 2 == 0:
        m = m + ORDER                       # +ell flips parity, same point
    # >>1 then force top bit: equivalent to ((m>>1) | 2^(L-1))
    u = (m >> 1) | (1 << nbits_top)
    return [(u >> (8 * i)) & 0xFF for i in range(NB_BYTES)], NB_BYTES, L

def getbit(mprime_bytes, pos):
    return (mprime_bytes[pos >> 3] >> (pos & 7)) & 1

def reu_comb(scalar, t, W, reu_image):
    mp, NB, L = recode_bytes(scalar, t, W)
    ACC = IDENT
    for k in range(W - 1, -1, -1):
        ACC = point_dbl(ACC)
        b0 = getbit(mp, k)
        neg = (b0 == 0)
        idx = 0
        for i in range(1, t):
            bi = getbit(mp, k + i * W)
            if bi != b0:
                idx |= (1 << (i - 1))
        off = idx << 6                        # idx * 64  (REU offset)
        blob = reu_image[off:off + 64]
        x = int.from_bytes(blob[0:32], "little")
        y = int.from_bytes(blob[32:64], "little")
        if neg:
            x = (p - x) % p
        T = x * y % p
        ACC = point_add(ACC, (x, y, 1, T))
    return ACC

def test(t, trials=200, seed=7):
    W = comb_W(t)
    table, _, npts = gen_table(t)            # flat REU image (npts*64 bytes)
    L = t * W
    NB = ((L - 1) // 8) + 1
    rng = random.Random(seed)
    print(f"--- t={t} W={W} L={L} NB_BYTES={NB} idxbits={t-1} "
          f"reu_size={len(table)}B ({len(table)//1024}KB) ---")
    fails = 0
    for _ in range(trials):
        s = rng.randrange(1, ORDER)
        if to_affine(reu_comb(s, t, W, table)) != to_affine(scalar_mul(s, B)):
            fails += 1
    for s in (1, 2, ORDER - 1, ORDER - 2):
        if to_affine(reu_comb(s, t, W, table)) != to_affine(scalar_mul(s, B)):
            fails += 1
    print(f"  {fails} fails / {trials}+4")
    return fails

if __name__ == "__main__":
    total = 0
    total += test(12, trials=300)
    total += test(18, trials=60)             # 8MB table gen is slower; fewer trials
    print("\nTOTAL:", total, "->", "OK" if total == 0 else "BROKEN")
