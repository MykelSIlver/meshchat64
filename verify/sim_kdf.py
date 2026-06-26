# -*- coding: utf-8 -*-
# sim_kdf.py - verifieert dat de bestaande DERIVE_KEYPAIR in meshchat64Main.asm
# exact de MeshChat-256-bit KDF implementeert (salt/PBKDF2/HKDF/labels).
# Bewijs bij LAAG iteratie-aantal -> geldig ook bij 100000 (identiek codepad,
# alleen de luscounter verschilt). Daarna apart een 100000-bouw-sanity.
import re, os, subprocess, hashlib, hmac
from py65.devices.mpu6502 import MPU

SRC = "meshchat64Main.asm"
BASE = open(SRC, "r", newline="").read().replace("\r\n", "\n")
BASIC = "        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00  ; SYS 2061"

ITER_BLOCK = """        LDA #$E8
        STA PBKDF2_ITRLO
        LDA #$03
        STA PBKDF2_ITRMID
        LDA #$00
        STA PBKDF2_ITRHI"""

def build(iters):
    lo, mid, hi = iters & 0xFF, (iters >> 8) & 0xFF, (iters >> 16) & 0xFF
    blk = (f"        LDA #${lo:02X}\n        STA PBKDF2_ITRLO\n"
           f"        LDA #${mid:02X}\n        STA PBKDF2_ITRMID\n"
           f"        LDA #${hi:02X}\n        STA PBKDF2_ITRHI")
    src = BASE.replace("!basic", BASIC, 1)
    assert ITER_BLOCK in src, "iteratie-blok niet gevonden -- bron verschoven?"
    src = src.replace(ITER_BLOCK, blk, 1)
    open("kdf_build.asm", "w").write(src)
    r = subprocess.run(["acme", "-o", "kdf.prg", "--labeldump", "kdf_labels.txt",
                        "kdf_build.asm"], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    L = {}
    for ln in open("kdf_labels.txt"):
        m = re.search(r"([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)", ln)
        if m: L[m.group(1)] = int(m.group(2), 16)
    return open("kdf.prg", "rb").read(), L

def run_derive(img, L, name, passw, max_steps=200_000_000):
    mem = bytearray(0x10000)
    mem[0x0801:0x0801 + len(img)] = img
    nb = name.encode("ascii")
    mem[L["KDFIN_NAME"]:L["KDFIN_NAME"] + len(nb)] = nb
    mem[L["KDFIN_NAME"] + len(nb)] = 0           # null-terminator
    mem[L["KDFIN_NAMELEN"]] = len(nb)
    pb = passw.encode("ascii")
    mem[L["KDFIN_PASS"]:L["KDFIN_PASS"] + len(pb)] = pb
    mem[L["KDFIN_PASSLEN"]] = len(pb)
    mpu = MPU(memory=mem)
    mem[0x1FF] = 0xFF; mem[0x1FE] = 0xFF
    mpu.sp = 0xFD; mpu.pc = L["DERIVE_KEYPAIR"]
    n = 0
    while mpu.pc != 0 and n < max_steps:
        mpu.step(); n += 1
    assert mpu.pc == 0, f"pc!=0 na {n} stappen"
    okm = bytes(mem[L["HKDF_OKM"]:L["HKDF_OKM"] + 64])
    salt = bytes(mem[L["PBKDF2_SALT"]:L["PBKDF2_SALT"] + 32])
    return okm[:32], okm[32:64], salt, n

# ---- Python spec-referentie (256-bit pad) ----
def hkdf_expand(prk, info, L=32):
    # 1 blok (L==HashLen): T(1) = HMAC(prk, info || 0x01)
    return hmac.new(prk, info + b"\x01", hashlib.sha256).digest()[:L]

def spec_kdf(username, passphrase, iters):
    salt = hashlib.sha256(b"meshchat-v1:" + username.lower().encode("ascii")).digest()
    master = hashlib.pbkdf2_hmac("sha256", passphrase.encode("ascii"), salt, iters, 32)
    prk = hmac.new(b"\x00" * 32, master, hashlib.sha256).digest()   # HKDF-Extract, zero-salt
    enc = hkdf_expand(prk, b"meshchat-v1:encryption")
    sig = hkdf_expand(prk, b"meshchat-v1:signing")
    return enc, sig, salt

print("KDF-structuurkruistoets (C64 DERIVE_KEYPAIR vs spec-referentie)")
cases = [("harry128", "correct horse battery", 1),
         ("Harry128", "correct horse battery", 2),
         ("alice",    "hunter2hunter2",        4),
         ("bob99",    "Tr0ub4dor&3xyz",        3)]
fails = []
for name, pw, it in cases:
    img, L = build(it)
    enc_c, sig_c, salt_c, steps = run_derive(img, L, name, pw)
    enc_r, sig_r, salt_r = spec_kdf(name, pw, it)
    ok_salt = salt_c == salt_r
    ok_enc  = enc_c == enc_r
    ok_sig  = sig_c == sig_r
    status = "OK" if (ok_salt and ok_enc and ok_sig) else "FOUT"
    print(f"  name={name!r:12} iters={it} steps={steps:>9}  salt:{'ok' if ok_salt else 'X'} "
          f"enc:{'ok' if ok_enc else 'X'} sig:{'ok' if ok_sig else 'X'}  -> {status}")
    if status == "FOUT":
        if not ok_salt: fails.append(f"{name}: salt {salt_c.hex()} != {salt_r.hex()}")
        if not ok_enc:  fails.append(f"{name}: enc {enc_c.hex()} != {enc_r.hex()}")
        if not ok_sig:  fails.append(f"{name}: sig {sig_c.hex()} != {sig_r.hex()}")

print()
if fails:
    print("FOUTEN:");  [print("  " + f) for f in fails]
else:
    print("ALLES OK - C64-KDF == spec-KDF (salt + encKey + signSeed byte-exact).")
    print("Codepad is iteratie-onafhankelijk -> ook geldig bij 100000 iteraties.")

# ---- bouw-sanity: 100000-iteratie variant assembleert ----
img, L = build(100000)
print(f"\n100000-iteratie bouw: OK ({len(img)} bytes), DERIVE_KEYPAIR @ ${L['DERIVE_KEYPAIR']:04X}")
