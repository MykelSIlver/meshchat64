# -*- coding: utf-8 -*-
# ================================================================
# sim_sign.py  -  end-to-end Ed25519 sign-vector vs pynacl.
#   mode "setup": poke SEED -> SIGN_SETUP -> SK_PUB == verify_key
#   mode "sign" : poke gecachte a/prefix/A + bericht -> SIGN
#                 -> SIG_OUT == nacl sign().signature   (1 scalar-mult)
#   mode "full" : poke SEED -> SIGN_SETUP (A) -> SIGN  (2 scalar-mults)
# Gebruik:  python3 sim_sign.py {setup|sign|full} [bericht]
# DUUR: elke scalar-mult ~350s in deze py65 (~0,89M stappen/s).
# ================================================================
import re, sys, time, hashlib, nacl.signing
from py65.devices.mpu6502 import MPU

mode = sys.argv[1] if len(sys.argv) > 1 else "sign"
MSG  = (sys.argv[2] if len(sys.argv) > 2 else "hallo Harry128 vanaf de C64!").encode("ascii")

L = {}
for ln in open("sign_labels.txt"):
    m = re.search(r"([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)", ln)
    if m: L[m.group(1)] = int(m.group(2), 16)

mem = bytearray(0x10000)
img = open("sign.prg", "rb").read()
mem[0x0801:0x0801 + len(img)] = img
mpu = MPU(memory=mem)

def call(addr, mx=1_500_000_000):
    mem[0x1FF] = 0xFF; mem[0x1FE] = 0xFF; mpu.sp = 0xFD; mpu.pc = addr; n = 0
    while mpu.pc != 0:
        mpu.step(); n += 1
        if n > mx: raise RuntimeError("hang")
    return n

def poke(a, d): mem[a:a + len(d)] = bytes(d)
def peekN(a, n): return bytes(mem[a:a + n])

# --- referentie ---
seed = bytes(range(32))
sk   = nacl.signing.SigningKey(seed)
pub  = bytes(sk.verify_key)
h    = hashlib.sha512(seed).digest()
a    = bytearray(h[:32]); a[0] &= 248; a[31] &= 127; a[31] |= 64
prefix = h[32:64]
sig_ref = sk.sign(MSG).signature        # 64-byte R||S

def poke_msg():
    assert len(MSG) <= 255
    poke(L["MSG_BUF"], MSG); mem[L["MSG_LEN"]] = len(MSG)

t0 = time.time()

if mode in ("setup", "full"):
    poke(L["SEED"], seed)
    steps = call(L["SIGN_SETUP"])
    got_pub = peekN(L["SK_PUB"], 32)
    ok = got_pub == pub
    print(f"SIGN_SETUP: SK_PUB == pynacl verify_key : {'OK' if ok else 'FOUT'}  ({steps} stappen, {time.time()-t0:.0f}s)")
    if not ok:
        print("  got", got_pub.hex()); print("  ref", pub.hex())

if mode == "sign":
    # gecachte identiteit poken (elk afzonderlijk al geverifieerd)
    poke(L["SK_A"], a); poke(L["SK_PREFIX"], prefix); poke(L["SK_PUB"], pub)

if mode in ("sign", "full"):
    poke_msg()
    t1 = time.time()
    steps = call(L["SIGN"])
    sig_got = peekN(L["SIG_OUT"], 64)
    ok = sig_got == sig_ref
    print(f"SIGN: SIG_OUT == nacl sign().signature  : {'OK' if ok else 'FOUT'}  ({steps} stappen, {time.time()-t1:.0f}s)")
    print(f"  bericht ({len(MSG)} tekens): {MSG.decode('ascii')}")
    if not ok:
        print("  got R", sig_got[:32].hex()); print("  ref R", sig_ref[:32].hex())
        print("  got S", sig_got[32:].hex()); print("  ref S", sig_ref[32:].hex())
    # extra: pynacl-verificatie van de C64-sig (onafhankelijke check)
    if ok:
        try:
            nacl.signing.VerifyKey(pub).verify(MSG, sig_got)
            print("  pynacl VerifyKey.verify(C64-sig) : OK")
        except Exception as e:
            print("  pynacl verify FOUT:", e)

print(f"--- totaal {time.time()-t0:.0f}s ---")
