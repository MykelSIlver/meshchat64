# Verification scripts

Every cryptographic primitive in MeshChat64 was built standalone and checked
**byte-exact** against a Python reference before integration, following the
project's rule: *Python reference → py65 simulation → hardware*. These scripts
are those references and harnesses.

## Requirements

```bash
pip install py65 pynacl cryptography      # hashlib is stdlib
```

`ref_ed.py` (the Ed25519 oracle: field arithmetic, base point `B`,
`point_add`/`point_dbl`/`scalar_mul`, `to_affine`) is imported by several
scripts and must sit alongside them (it already does).

## Core primitives

| Script | Proves |
|--------|--------|
| `ref_ed.py` | Ed25519 reference (imported by the others, not run directly). |
| `sim_sha_full.py` | SHA-512 compression matches `hashlib`. |
| `sim_kdf.py` | PBKDF2-HMAC-SHA256 + HKDF identity derivation. |
| `sim_aes256.py` | AES-256-GCM encryption/auth. |
| `sim_ed_all.py` | Full Ed25519 keygen + sign path. |
| `sim_sign.py` | End-to-end message signing. |
| `verify_pong.py` | The woven-in keepalive pong does **not** change the signature. |

## REU signed-comb scalar multiplication

These cover the optional [REU build](../docs/REU.md).

| Script | Proves |
|--------|--------|
| `gen_comb_table.py` | Generates the signed-comb table for any `t`. Reproduces the production h6 `comb_table.inc` **byte-for-byte**, so it is trusted for h12/h18. |
| `sim_comb_signed.py` | The signed comb equals `n·B` (0 fails for t=6 and t=12). |
| `sim_reu_comb.py` | An **assembly-faithful** model (multi-byte recode/idx, `idx·64` REU addressing, 64-byte DMA fetch); 0 fails for t=12 and t=18. |
| `reu_shim.py` | py65 memory shim emulating the REC (`$DF00–$DF0A`) against a 16 MB bytearray — stash/fetch/swap/verify + status bits. |
| `verify_reu_asm.py` | Runs the **assembled** `meshchat64_reu.prg` in py65 with the shim (table pre-loaded, keepalive stubbed) and compares `ACC` to `scalar_mul(s,B)`. |

### Running the REU checks

```bash
# 1) algorithm proofs (fast)
python3 sim_comb_signed.py
python3 sim_reu_comb.py            # h18 generates an 8 MB table -> slower

# 2) generate a table + build the REU program, then verify the assembled comb
python3 gen_comb_table.py -t 12 --bin combtable_h12.bin
( cd ../src && acme -f cbm -DREU=1 -DREU_T=12 --symbollist reu12.sym -o reu12.prg meshchat64.asm )
python3 verify_reu_asm.py ../src/reu12.prg ../src/reu12.sym combtable_h12.bin 12 8
#   -> h12: 0 fails / 8   (each full scalar-mult ~14.4 M cycles)
```

`verify_reu_asm.py` takes `<prg> <sym> <table.bin> <t> <ntrials>`. It strips the
2-byte PRG load address, installs the REU shim, pre-loads the raw table into the
shim's REU, stubs `PD_WRAP → POINT_DBL` (to skip ACIA I/O), pokes `SCALAR`,
calls `COMB_SCALAR_MUL`, and compares the accumulator to the Python reference.
