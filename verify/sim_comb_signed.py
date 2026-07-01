#!/usr/bin/env python3
# sim_comb_signed.py - models the meshchat64 SIGNED fixed-base comb scalar-mult
#   for arbitrary teeth t, and proves ACC == scalar*B for random scalars.
#   Mirrors the asm: CB_RECODE -> W doublings -> per-step teeth/idx/CB_NEG ->
#   load +/-TABLE[idx] -> POINT_ADD.
#
#   This is the algorithm proof required before writing reu_comb.inc (h=12).

import sys, math, random
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_ed import p, B, scalar_mul, point_add, point_dbl, to_affine
from gen_comb_table import gen_table, comb_W, table_point_index

ORDER = 2**252 + 27742317777372353535851937790883648493
IDENT = (0, 1, 1, 0)

def negate(P):
    X, Y, Z, T = P
    return ((p - X) % p, Y, Z, (p - T) % p)

def build_table_points(t):
    """list of extended-coord points TABLE[idx] for idx in 0..2^(t-1)-1."""
    W = comb_W(t)
    npts = 1 << (t - 1)
    pts = []
    for idx in range(npts):
        n = table_point_index(idx, t, W)
        pts.append(scalar_mul(n % ORDER, B))
    return pts, W

def recode(scalar, t, W):
    """MPRIME = ((scalar [+ORDER if even]) >> 1) | 2^(L-1), L=t*W."""
    L = t * W
    m = scalar
    if m % 2 == 0:
        m = m + ORDER          # +ell flips parity, same point
    u = (m >> 1) | (1 << (L - 1))
    return u, L

def comb_scalar_mul(scalar, t, table_pts, W):
    mprime, L = recode(scalar, t, W)
    def bit(n, i):
        return (n >> i) & 1
    ACC = IDENT
    for k in range(W - 1, -1, -1):
        ACC = point_dbl(ACC)
        b0 = bit(mprime, k)
        neg = (b0 == 0)
        idx = 0
        for i in range(1, t):
            bi = bit(mprime, k + i * W)
            if bi != b0:
                idx |= (1 << (i - 1))
        P = table_pts[idx]
        if neg:
            P = negate(P)
        ACC = point_add(ACC, P)
    return ACC

def test(t, trials=200, seed=1):
    rng = random.Random(seed)
    table_pts, W = build_table_points(t)
    L = t * W
    print(f"--- t={t}  W={W}(doublings)  L={L}  forcebit={L-1}  points={len(table_pts)} ---")
    fails = 0
    for _ in range(trials):
        s = rng.randrange(1, ORDER)
        got = to_affine(comb_scalar_mul(s, t, table_pts, W))
        exp = to_affine(scalar_mul(s, B))
        if got != exp:
            fails += 1
            if fails <= 3:
                print("  FAIL s=", hex(s))
    # edge cases
    for s in (1, 2, ORDER - 1, ORDER - 2, (1 << (L - 2))):
        got = to_affine(comb_scalar_mul(s % ORDER or 1, t, table_pts, W))
        exp = to_affine(scalar_mul(s % ORDER or 1, B))
        if got != exp:
            fails += 1
            print("  EDGE FAIL s=", hex(s))
    print(f"  result: {fails} fails / {trials}+5")
    return fails

if __name__ == "__main__":
    total = 0
    total += test(6, trials=300)    # must match production
    total += test(12, trials=300)   # the REU target
    print("\nTOTAL FAILS:", total, "->", "OK" if total == 0 else "BROKEN")
