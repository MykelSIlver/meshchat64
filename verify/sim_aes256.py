# -*- coding: utf-8 -*-
# sim_aes256.py - byte-exacte toetsing van aes256test.asm tegen pyca/cryptography.
#   encrypt: AGE256 -> (CT, TAG) == AESGCM(key).encrypt(nonce, pt, None)
#   decrypt: AGD256 -> hersteld PT == origineel, VERIFY_FAIL == 0
#   tamper : 1 CT-byte flippen -> VERIFY_FAIL == 1
import re, os
from py65.devices.mpu6502 import MPU
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

L = {}
for ln in open("aes256_labels.txt"):
    m = re.search(r"([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)", ln)
    if m:
        L[m.group(1)] = int(m.group(2), 16)

IMG = open("aes256.prg", "rb").read()

def fresh():
    mem = bytearray(0x10000)
    mem[0x0801:0x0801 + len(IMG)] = IMG
    return mem

def run(mem, entry, max_steps=80_000_000):
    mpu = MPU(memory=mem)
    mem[0x1FF] = 0xFF; mem[0x1FE] = 0xFF
    mpu.sp = 0xFD; mpu.pc = L[entry]
    n = 0
    while mpu.pc != 0 and n < max_steps:
        mpu.step(); n += 1
    assert mpu.pc == 0, f"{entry}: pc!=0 na {n} stappen (pc=${mpu.pc:04X})"
    return n

def poke(mem, addr, data): mem[addr:addr + len(data)] = bytes(data)
def peek(mem, addr, n):    return bytes(mem[addr:addr + n])

def set_len(mem, n):
    mem[L["PTLEN"] + 0] = n & 0xFF
    mem[L["PTLEN"] + 1] = (n >> 8) & 0xFF

def enc_ref(key, nonce, pt):
    ctt = AESGCM(key).encrypt(nonce, pt, None)
    return ctt[:-16], ctt[-16:]   # ct, tag

def test_len(n, seed):
    key   = bytes((seed + i) & 0xFF for i in range(32))
    nonce = bytes((seed * 3 + i) & 0xFF for i in range(12))
    pt    = bytes((seed * 7 + i * 13) & 0xFF for i in range(n))
    ct_ref, tag_ref = enc_ref(key, nonce, pt)

    # --- encrypt ---
    mem = fresh()
    poke(mem, L["AES_KEY"], key)
    poke(mem, L["AES_NONCE"], nonce)
    poke(mem, L["PTBUF"], pt)
    set_len(mem, n)
    run(mem, "AGE256")
    ct  = peek(mem, L["CTBUF"], n)
    tag = peek(mem, L["GCM_TAG"], 16)
    if ct != ct_ref:
        return f"len {n}: CT mismatch\n  got {ct.hex()}\n  ref {ct_ref.hex()}"
    if tag != tag_ref:
        return f"len {n}: TAG mismatch\n  got {tag.hex()}\n  ref {tag_ref.hex()}"

    # --- decrypt (goede tag) ---
    mem = fresh()
    poke(mem, L["AES_KEY"], key)
    poke(mem, L["AES_NONCE"], nonce)
    poke(mem, L["CTBUF"], ct_ref)
    poke(mem, L["GCM_RECV_TAG"], tag_ref)
    set_len(mem, n)
    run(mem, "AGD256")
    rec  = peek(mem, L["PTBUF"], n)
    vfail = mem[L["VERIFY_FAIL"]]
    if rec != pt:
        return f"len {n}: decrypt PT mismatch\n  got {rec.hex()}\n  ref {pt.hex()}"
    if vfail != 0:
        return f"len {n}: VERIFY_FAIL={vfail} bij geldige tag (verwacht 0)"

    # --- tamper (alleen voor n>=1) ---
    if n >= 1:
        bad = bytearray(ct_ref); bad[0] ^= 0x01
        mem = fresh()
        poke(mem, L["AES_KEY"], key)
        poke(mem, L["AES_NONCE"], nonce)
        poke(mem, L["CTBUF"], bytes(bad))
        poke(mem, L["GCM_RECV_TAG"], tag_ref)
        set_len(mem, n)
        run(mem, "AGD256")
        if mem[L["VERIFY_FAIL"]] != 1:
            return f"len {n}: tamper niet gedetecteerd (VERIFY_FAIL=0)"
    return None

# NIST AES-256-GCM bekende-antwoord (gcmEncryptExtIV256, 96-bit IV, lege AAD):
#   Key  = b52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4
#   IV   = 516c33929df5a3284ff463d7
#   PT   = (leeg)  Tag = bdc1ac884d332457a1d2664f168c76f0
def test_kat_empty():
    key   = bytes.fromhex("b52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4")
    nonce = bytes.fromhex("516c33929df5a3284ff463d7")
    tag_exp = bytes.fromhex("bdc1ac884d332457a1d2664f168c76f0")
    mem = fresh()
    poke(mem, L["AES_KEY"], key)
    poke(mem, L["AES_NONCE"], nonce)
    set_len(mem, 0)
    run(mem, "AGE256")
    tag = peek(mem, L["GCM_TAG"], 16)
    if tag != tag_exp:
        return f"NIST KAT (leeg): TAG mismatch\n  got {tag.hex()}\n  exp {tag_exp.hex()}"
    return None

print("AES-256-GCM verificatie tegen pyca/cryptography + NIST KAT")
print("labels:", {k: hex(L[k]) for k in ("AGE256","AGD256","AES_KEY","PTBUF","CTBUF","GCM_TAG")})

fails = []
e = test_kat_empty()
print("  NIST KAT (lege PT):", "OK" if e is None else "FOUT")
if e: fails.append(e)

lengths = [0, 1, 2, 15, 16, 17, 31, 32, 33, 47, 48, 49, 63, 64, 65,
           100, 200, 239, 240, 255, 256, 257, 500, 1000, 1100, 1200]
for i, n in enumerate(lengths):
    r = test_len(n, seed=(i * 17 + 3) & 0xFF)
    print(f"  len {n:>5}: {'OK' if r is None else 'FOUT'}")
    if r: fails.append(r)

print()
if fails:
    print(f"{len(fails)} FOUT(en):")
    for f in fails: print("---\n" + f)
else:
    print(f"ALLES OK  ({len(lengths)} lengtes + NIST KAT, encrypt+decrypt+tamper byte-exact)")
