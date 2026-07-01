#!/usr/bin/env python3
# verify_reu_asm.py - run the ASSEMBLED REU comb (reu12.prg / reu18.prg) in py65
#   with the REU shim, table pre-loaded, PD_WRAP stubbed to POINT_DBL.
#   Compares ACC to scalar_mul(s, B) byte-exact.
#
#   usage: python3 verify_reu_asm.py <prg> <sym> <table.bin> <t> <ntrials>

import sys, re, time, random
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory
from ref_ed import p, B, scalar_mul, to_affine
import reu_shim

prg, sym, tablebin, t, ntri = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])

L = {}
for ln in open(sym):
    m = re.search(r"([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)", ln)
    if m:
        L[m.group(1)] = int(m.group(2), 16)

mem = ObservableMemory()
reu = reu_shim.install(mem)

# load PRG (strip 2-byte load addr) at $0801
img = open(prg, "rb").read()
base = img[0] | (img[1] << 8)
for i, b in enumerate(img[2:]):
    mem[base + i] = b

# pre-load REU table image
table = open(tablebin, "rb").read()
reu.reu[0:len(table)] = table

# stub PD_WRAP -> JMP POINT_DBL (skip keepalive/ACIA I/O)
pd, pdbl = L["PD_WRAP"], L["POINT_DBL"]
mem[pd] = 0x4C; mem[pd+1] = pdbl & 0xFF; mem[pd+2] = (pdbl >> 8) & 0xFF

cpu = MPU(memory=mem)

def call(addr, mx=80_000_000):
    mem[0x1FF] = 0xFF; mem[0x1FE] = 0xFF; cpu.sp = 0xFD; cpu.pc = addr
    n = 0
    while cpu.pc != 0x0000:        # RTS pops $FFFF -> PC = $0000
        cpu.step(); n += 1
        if n > mx: raise RuntimeError("hang")
    return n

def sc_le(x): return (x & (2**256-1)).to_bytes(32, "little")
def fe_le(x): return (x % p).to_bytes(32, "little")
def poke(a, d):
    for i, b in enumerate(d): mem[a+i] = b
def peek(a, n): return bytes(mem[a+i] for i in range(n))
def racc():
    return tuple(int.from_bytes(peek(L["ACC_"+c], 32), "little") for c in "XYZT")

rng = random.Random(123)
fails = 0
t0 = time.time()
for j in range(ntri):
    s = rng.randrange(1, 2**252)
    poke(L["SCALAR"], sc_le(s))
    steps = call(L["COMB_SCALAR_MUL"])
    got = to_affine(racc())
    exp = to_affine(scalar_mul(s, B))
    ok = got == exp
    if not ok:
        fails += 1
        print(f"  FAIL s={hex(s)[:18]} steps={steps}")
        if fails == 1:
            print("   got", hex(got[0])[:18], hex(got[1])[:18])
            print("   exp", hex(exp[0])[:18], hex(exp[1])[:18])
    else:
        print(f"  ok   s={hex(s)[:18]} steps={steps} ({time.time()-t0:.0f}s)")
print(f"t={t}: {fails} fails / {ntri}   total {time.time()-t0:.0f}s")
