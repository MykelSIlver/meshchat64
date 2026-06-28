# MeshChat64 — Memory Map (C64, 64 KB)

This document describes how MeshChat64 uses the Commodore 64's 64 KB address
space. It was compiled by hand from the ACME symbol list and serves as a
reference when further optimizing the Ed25519/AES-256-GCM crypto: free gaps are
scarce, and any expansion has to fit *without* ROM banking (see
[Banking rule](#banking-rule)).

The binary (`meshchat64.prg`) loads at `$0801` and runs up to `$BF57`. Everything
above `$C000` is **runtime working memory** that is filled at startup — it is not
part of the PRG and cannot hold permanent tables.

## Full map

| Range | Size | Contents | Type |
|---|---:|---|---|
| `$0801–$096A` | 361 B | code (init, vectors) | PRG |
| `$096A–$0B86` | — | *(pin alignment)* | |
| `$0B86–$3099` | 9,491 B | code — `B64D_ERR` pinned at original address | PRG |
| `$3332–$9B65` | 26,675 B | code — `GCM_INIT` pinned at original address | PRG |
| `$9B65–$9C00` | **155 B** | free | — |
| `$9C00–$A484` | 2,180 B | crypto data (`X64`/`SEED`/`SK`/`WS_AUTH256`) | PRG |
| `$A484–$A4B4` | **48 B** | free | — |
| `$A4B4–$B091` | 3,037 B | code + `COMB_TABLE` (signed-comb, 2 KB @ `$A891`) | PRG |
| `$B091–$B100` | **111 B** | free | — |
| `$B100–$B500` | 1,024 B | qsq tables (`QSL1`/`QSH1`, page-aligned) | PRG |
| `$B500–$B6F3` | 499 B | watchdog + `PD_WRAP` + sendfix | PRG |
| `$B6F3–$BBF3` | 1,280 B | `SAVE_BUF` (frame storage for resend) | runtime |
| `$BBF3–$BC00` | **13 B** | free | — |
| `$BC00–$BE56` | 598 B | `FP_SQ` + `FP_MUL_FAST` (dedicated squaring) | PRG |
| `$BE56–$BF57` | 257 B | signed-comb helpers + recoding | PRG |
| `$BF57–$C000` | **169 B** | free | — |
| `$C000–$CC00` | 3,072 B | SHA-512 tables | runtime |
| `$CC00–$CF81` | 897 B | PBKDF2 working buffers | runtime |
| `$CF81–$D000` | **127 B** | free | — |
| `$D000–$DFFF` | 4 KB | I/O (VIC/SID/CIA + ACIA @ `$DE00`) | hardware |
| `$E000–$FFFF` | 8 KB | KERNAL ROM (RAM underneath, not used freely) | ROM |

Total scattered free below `$D000`: about **740 B** static, in separate gaps of
at most ~170 B. There is **no** contiguous block of several KB free anywhere.

## Pins (fixed `* =` addresses)

Three code segments live at fixed addresses because external references or
self-modified jumps point at them: `$0801`, `$0B86` (`B64D_ERR`),
`$3332` (`GCM_INIT`). In addition: `$9C00` (`X64` on a page boundary), `$A4B4`
(`RCV_DECRYPT_DISPATCH`), `$B100`/`$B300` (qsq, page-aligned for the `+256`
trick), and the free-RAM overlays `$B500`/`$BC00`/`$BE56`.

## Runtime overlays (not in the PRG)

Three regions are only filled during operation and share no lifetime with the
permanent data below them:

- **`SAVE_BUF` (`$B6F3`, 1280 B)** — copy of the outgoing frame for auto-resend
  after reconnect. Lifetime: send → reconnect → re-auth.
- **SHA-512 tables (`$C000`, 3 KB)** — built at init; active during both signing
  and re-auth.
- **PBKDF2 buffers (`$CC00`, 897 B)** — active only during login (key
  derivation), free afterwards.

> `SAVE_BUF` is the big fragmenter of `$A000–$BFFF`. Because it is needed at the
> same time as the SHA tables (during re-auth after reconnect), it cannot overlap
> `$C000+`, and it is also unusable as permanent comb-table space. It therefore
> blocks any contiguous block larger than ~2.2 KB in the `$A000` region.

## Banking rule

**Never** place working buffers under BASIC ROM (`$A000–$BFFF`) and bank them in
and out with `STA $01`: on the Ultimate-64 this causes reproducible crashes. Data
that sits permanently under banked-out ROM (such as `COMB_TABLE`, qsq, sendfix) is
fine — it is accessed with BASIC continuously banked out, without toggling per
access. The toggling is the problem, not the location.

Consequence: expansions that need 4–8 KB contiguous (e.g. an *unsigned* h=6/h=8
comb table) would have to bank `$E000–$FFFF` under the KERNAL — and thus fall
under this rule. They are avoided.

## Case study: widening the comb table without banking (h=4 → h=6)

The fixed-base comb for `r·B` and `a·B` used an **h=4** window: 64 doublings, a
table of 16 points (2 KB). A wider window saves both doublings and additions, but
a plain **h=6** table (63 points) needs 4–8 KB — which does not fit, and banking
is forbidden.

Solution: a **signed comb**. With the negation trick in Edwards
(`−P = (−X, Y)`, cheap) only half the points need to be stored: **32 instead of
63**. In XY format (`Z=1` implicit, `T = X·Y` recomputed on the C64 at load time)
that is exactly **2 KB** — precisely the existing slot. No banking, no runtime-RAM
reshuffle.

Briefly how it works (fully validated in Python against `n·B`, 5500+ scalars):

- **Recoding** — the scalar `m` is made odd (`m+L` with `L` = group order if `m`
  is even; `(m+L)·B = m·B`). Then `u = (m >> 1)` with bit 257 forced set. This
  yields an all-`±1` representation over 258 bits (`H·W = 6·43`).
- **Per column** `k = 42…0`: `ACC = 2·ACC`; read the signs of the 6 teeth at bit
  positions `i·43 + k`; build a 5-bit index from the signs *relative* to tooth 0;
  load `±TABLE[idx]`; `ACC += point`. Every step adds (no skip).

Result: **43 doublings instead of 64**. Measured on the C64 (py65):
`44,371,224 → 33,573,599` cycles for one scalar-mult = **1.322× = 24.3%
faster**.

### Files

| File | Location | Role |
|---|---|---|
| `comb_table.inc` | `$A891` | 32 × 64 B signed table (by `gen_comb_table.py`) |
| `comb_keepalive.inc` | `$A4B4` segment | `COMB_SCALAR_MUL` = 43-step signed loop |
| `meshchat64_combsigned.inc` | `$BE56` | `CB_RECODE`, `CB_GETBIT`, `COMB_LOADPT_S` |

The group order `L` was not stored again — the existing `LT` constant in the
binary is exactly the Ed25519 order and is reused.

## 6502 gotchas (recorded from hardware experience)

- `CPX #N` clobbers the carry in a multi-byte ADC loop → use a `DEY` counter.
- Long backward branches exceed the `±128` range → `BMI/BNE skip` + `JMP`
  trampoline.
- `LDA ($FB),X` does not exist; only `abs,X`, `abs,Y` or `LDA ($FB),Y`.
- Working buffers under ROM with `STA $01` banking → crash (see Banking rule).
- All screen output via `JSR PRINT_CHR`, not `JSR $FFD2` (mixed-case mode).
