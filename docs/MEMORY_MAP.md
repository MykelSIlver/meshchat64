# MeshChat64 — Memory Map (h=6 comb + Karatsuba, no banking)

Single-file build: `LOAD"MESHCHAT64.PRG",8,1` then `RUN`. No `combtable.prg`, no ROM banking.

## Performance (scalar multiplication, py65 cycle counts)

| version | cycles | speedup |
|---|---|---|
| baseline (h=4 comb) | 44,371,224 | 1.00x |
| h=6 signed comb | 33,626,256 | 1.32x |
| **h=6 + Karatsuba FP_MUL** | **28,159,670** | **1.58x** |

Karatsuba `FP_MUL`: 45,727 -> 36,997 cycles (19.1% faster, byte-exact 0/5081 vs `a*b mod p`). The scalar multiplication is ~16% faster because field multiplies are ~82% of it; the inversion benefits too. Real hardware: ~2 min 24 s per signed message at 1 MHz, ~2 s on an Ultimate 64 in 64 MHz Turbo.

## Key regions

| region | contents |
|---|---|
| `$0801` | BASIC stub + entry |
| `$7088` | **FP_MUL_KARA + MUL16** (placed in the reclaimed dead SCALAR_MUL / SCALAR_MUL_N) |
| `$9C00`–`$A4B4` | crypto data (X64/SEED, SK_*, WS_AUTH256, send buffers) |
| `$A6D4` | COMB_SCALAR_MUL (h=6 signed comb, 43 doublings, 6 teeth, no banking) |
| `$A900`–`$B100` | COMB_TABLE (32 points x 64 B, X/Y affine, internal) |
| `$B100`–`$B500` | QSL1 / QSH1 quarter-square multiply tables |
| `$B500`–`$B6F3` | watchdog / keepalive (PD_WRAP) + send-fix |
| `$BC00`–`$BE56` | FP_SQ + FP_MUL_FAST (schoolbook; now unused — `+fmul` redirects to FP_MUL_KARA) |
| `$BE56` | comb helpers: CB_RECODE (force bit257), CB_GETBIT (16-bit), COMB_LOADPT_S |
| `$C000`–`$CC00` | SHA tables (runtime) |
| `$CC00`–`$CF81` | PBKDF2 working buffers (runtime) |

Field-arithmetic pointers: `FAP = $FB`, `FBP = $FD`, `FRP = $F7`.

## Karatsuba field multiply (FP_MUL_KARA @ $7088)

One-level Karatsuba on the 256-bit (32-byte) operands. Split `a = a1:a0`, `b = b1:b0` into 16-byte halves:

- `z0 = a0*b0` -> written directly to `PROD[0:32]`
- `z2 = a1*b1` -> written directly to `PROD[32:64]`
- `sa = a0+a1` (carry `ca`), `sb = b0+b1` (carry `cb`) — overwrite `MA`/`MB` low halves
- `zm = sa*sb` plus carry terms: `if ca: zm[16:32]+=sb`, `if cb: zm[16:32]+=sa`, `if ca&cb: zm[32]+=1`
- `z1 = zm - z0 - z2` (33-byte, non-negative)
- `PROD[16:49] += z1`, then `FP_REDUCE` (fold `PROD[32:64]*38 + PROD[0:32]`, since `2^256 = 38 mod p`)

This is `3 x (16x16) = 768` 8x8 multiplies instead of the `1024` of a 32x32 schoolbook. `MUL16` is a self-contained 16x16 building block with an inlined quarter-square `mul8` (no external macro dependency). Validated byte-exact in py65 (0/5081 vs `a*b mod p`, 0/5000 vs the schoolbook).

## h=6 signed comb (COMB_SCALAR_MUL @ $A6D4)

Recode: `m = SCALAR` (add the group order `L` if even, so `m` is odd); `u = (m>>1) | bit257`. Mathematically `m_repr = m`, so the comb computes `m*B = SCALAR*B`.

- 6 teeth at bit offsets `0, 43, 86, 129, 172, 215` (window `W = 43`)
- 43 doublings (`k = 42..0`)
- `6 * 43 = 258 > 257`, so the top tooth reaches bits 256/257 for `k = 41/42` — `CB_POS` is therefore 16-bit and `CB_GETBIT` handles positions 0..257
- per step: `ACC = 2*ACC`; build a 5-bit `idx` from the signs of teeth 1..5 relative to tooth 0; load `+/-TABLE[idx]` (negate X if tooth 0 is 0); `ACC += point`

Table convention (`comb_table.inc`): `TABLE[idx] = sum_i sigma_i * 2^(i*W) * B`, `sigma_0 = +1`, `sigma_i (i>=1) = -1` if bit `(i-1)` of `idx` is set. Point negation uses `-P = (-X, Y)` so only 32 points are stored. Validated byte-exact vs `n*B` in Python (0/2007) and in py65 (0/9).

## Verification methodology

Every cryptographic component is built as a standalone module and verified byte-exact against a Python reference (pynacl, pyca-cryptography, hashlib) in py65 before integration and before any hardware test. `FP_MUL` and the full scalar multiplication are both checked against the Edwards25519 reference (`ref_ed.py`).
