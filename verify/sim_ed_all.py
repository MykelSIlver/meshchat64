# -*- coding: utf-8 -*-
# ================================================================
# sim_ed_all.py  -  Verificatie-suite Edwards25519-module (stap 3).
# ----------------------------------------------------------------
# Toetst de C64-routines byte-exact tegen ref_ed.py (Python-oracle).
#
# SNELLE tests (draaien hier, < ~4 min totaal):
#   - POINT_DBL : 8 willekeurige punten
#   - POINT_ADD : 8 willekeurige paren
#   - SCALAR_MUL_N (korte ladder): 8- en 16-bit scalars, double-and-add
#     met meerdere ADDs incl. bytegrens-overgang (0xFFFF/0xAAAA/0x5555).
#
# TRAGE tests (apart draaien; ~3-5 min elk, bewezen geslaagd):
#   python3 sim_smul_full2.py 1                                  # k=1 -> B
#   python3 sim_smul_full2.py 800...08f                          # k=2^255+0x8F
#   python3 sim_pubkey2.py                                       # geclampt -> pubkey
#
# KRITISCH (testharnas): een SCALAR is GEEN veldelement -> NOOIT mod p
# reduceren bij het poken. Coordinaten WEL mod p. Zie fe_le/sc_le.
# ================================================================
import re, random, time
from py65.devices.mpu6502 import MPU
from ref_ed import p, B, point_add, point_dbl, scalar_mul, to_affine

L = {}
for ln in open("ed_labels.txt"):
    m = re.match(r"\s*([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)", ln)
    if m: L[m.group(1)] = int(m.group(2), 16)

mem = bytearray(0x10000)
img = open("ed.prg", "rb").read()
mem[0x0801:0x0801 + len(img)] = img
mpu = MPU(memory=mem)

def call(addr, mx=400_000_000):
    mem[0x1FF] = 0xFF; mem[0x1FE] = 0xFF; mpu.sp = 0xFD; mpu.pc = addr; n = 0
    while mpu.pc != 0:
        mpu.step(); n += 1
        if n > mx: raise RuntimeError("hang")
    return n

def fe_le(x): return (x % p).to_bytes(32, "little")          # veldelement: mod p
def sc_le(x): return (x & (2**256 - 1)).to_bytes(32, "little")  # scalar: GEEN mod p
def from_le(b): return int.from_bytes(b, "little")
def poke(a, d): mem[a:a + len(d)] = bytes(d)
def peekN(a, n): return bytes(mem[a:a + n])

def poke_point(prefix, P):
    X, Y, Z, T = P
    poke(L[prefix + "_X"], fe_le(X)); poke(L[prefix + "_Y"], fe_le(Y))
    poke(L[prefix + "_Z"], fe_le(Z)); poke(L[prefix + "_T"], fe_le(T))
def read_point(prefix):
    return tuple(from_le(peekN(L[prefix + "_" + c], 32)) for c in "XYZT")
def read_acc():
    return tuple(from_le(peekN(L["ACC_" + c], 32)) for c in "XYZT")

def rand_point():
    return scalar_mul(random.randrange(1, p), B)

def test_pdbl(n=8):
    bad = 0; mx = 0
    for _ in range(n):
        P = rand_point(); poke_point("INP", P)
        mx = max(mx, call(L["T_PDBL"]))
        if to_affine(read_point("OUT")) != to_affine(point_dbl(P)): bad += 1
    print(f"POINT_DBL : {n} punten -> {'OK' if not bad else str(bad)+' FOUT'} (max {mx} stappen)")
    return bad

def test_padd(n=8):
    bad = 0; mx = 0
    for _ in range(n):
        P = rand_point(); Q = rand_point()
        poke_point("INP", P); poke_point("INQ", Q)
        mx = max(mx, call(L["T_PADD"]))
        if to_affine(read_point("OUT")) != to_affine(point_add(P, Q)): bad += 1
    print(f"POINT_ADD : {n} paren  -> {'OK' if not bad else str(bad)+' FOUT'} (max {mx} stappen)")
    return bad

def smul_n(k, nbits):
    poke_point("PIN", B); poke(L["SCALAR"], sc_le(k)); mem[L["SM_NBITS"]] = nbits
    call(L["T_SMUL_N"]); return read_acc()

def test_smul_n(nbits, scalars):
    bad = 0
    for k in scalars:
        if to_affine(smul_n(k, nbits)) != to_affine(scalar_mul(k, B)): bad += 1
    print(f"SCALAR_MUL_N nbits={nbits}: {len(scalars)} scalars -> {'OK' if not bad else str(bad)+' FOUT'}")
    return bad

if __name__ == "__main__":
    random.seed(13); t0 = time.time(); fails = 0
    print("--- snelle punttests ---")
    fails += test_pdbl(8)
    fails += test_padd(8)
    print("--- korte-ladder double-and-add ---")
    fails += test_smul_n(8,  [0, 1, 2, 5, 0xAA, 0xFF])
    fails += test_smul_n(16, [0xFFFF, 0xAAAA, 0x5555, 0x1234])
    print("=" * 50)
    print(("ALLE SNELLE TESTS OK" if not fails else f"{fails} FOUTEN"),
          f"({time.time()-t0:.0f}s)")
    print("Trage volle-ladder tests: zie kop van dit bestand (bewezen OK).")
