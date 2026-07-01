# REU-accelerated scalar multiplication

MeshChat64 signs every outgoing message with Ed25519, and the slowest part of
signing is the fixed-base scalar multiplication `R = r·B`. The default build
does this with a **6-tooth signed comb** and a 2 KB lookup table in C64 RAM.

This is an **optional build variant** that moves a much larger comb table into a
**RAM Expansion Unit (REU)** and fetches one point per step by DMA. More teeth
means fewer point doublings, so the scalar multiplication is markedly faster —
and the 2 KB in-RAM table (`$A900–$B0FF`) is freed.

The default (non-REU) build is **byte-for-byte unchanged**: all REU code is
behind `!ifdef REU`, so building without `-DREU=1` produces exactly the same
binary as before.

## Results (measured on an Ultimate-64)

| Build | teeth | table | REU | doublings | scalar-mult | send 1 msg @ 1 MHz |
|-------|-------|-------|-----|-----------|-------------|--------------------|
| default | 6 | 2 KB (RAM) | – | 43 | 28.1 M cyc | ~2:26 |
| REU h12 | 12 | 128 KB | yes | 22 | 14.4 M cyc (1.95×) | **~1:34** |
| REU h18 | 18 | 8 MB | yes | 15 | 9.82 M cyc (2.86×) | – |

h12 (128 KB) is the sweet spot: it fits in a single `.d81`, loads in seconds
with JiffyDOS, and already halves the doublings. h18 (8 MB) shaves a little more
off the scalar-mult but needs an 8 MB companion file. h19 (16 MB) would fill the
whole REU for just one fewer doubling than h18 — not worth it.

> Note: the ~52 s saved per message on a 1 MHz machine is larger than the
> scalar-mult delta alone; the comb's per-step savings compound across the
> signing path.

## How it works

- **Signed comb.** For `t` teeth of width `W = ceil(258/t)`, the recoded scalar
  is split into `t` bit-columns per step. Each step adds `±TABLE[idx]·B` where
  `idx` selects the column and the tooth-0 bit chooses the sign (point negation
  is free: `−P = (−X, Y)`). The recode forces bit `L−1` (`L = t·W`) so the
  signed representation equals the odd scalar exactly.
- **Table.** `TABLE[idx] = Σ σᵢ·2^(iW)·B` for `idx ∈ 0 … 2^(t-1)−1`, each point
  stored affine little-endian `X[32]‖Y[32]` = 64 bytes. Size = `2^(t-1)·64`.
- **Per step:** compute the multi-byte `idx`, DMA-fetch 64 bytes from
  `REU[idx·64]` into the point buffer, negate X if needed, set `Z=1`,
  `T = X·Y`, then `POINT_ADD`. The REC pauses the CPU during DMA, so there is
  **no `$FFFA`/NMI hazard**.

Source: [`src/reu_comb.inc`](../src/reu_comb.inc) (the comb + recode + fetch),
[`src/reu_loader.inc`](../src/reu_loader.inc) (presence check + table loader).

## Building

```bash
cd src
# default build (unchanged, no REU):
acme -f cbm -o meshchat64.prg meshchat64.asm

# REU build, 12 teeth (128 KB table):
acme -f cbm -DREU=1 -DREU_T=12 -o meshchat64_reu.prg meshchat64.asm
# or 18 teeth (8 MB table):
acme -f cbm -DREU=1 -DREU_T=18 -o meshchat64_reu.prg meshchat64.asm
```

`REU_T` defaults to 18 if omitted. Valid values 12 / 16 / 18 (19 fills 16 MB).

## Generating the table file

The table is a companion file loaded into the REU at boot. Generate it with
[`verify/gen_comb_table.py`](../verify/gen_comb_table.py) (needs `ref_ed.py`
alongside it, already in `verify/`):

```bash
cd verify
python3 gen_comb_table.py -t 12 --bin combtable_h12.bin      # 128 KB raw table
```

The loader reads a **PRG** file and skips the 2-byte load address (`REU_SKIP=2`,
the default). Prepend a dummy 2-byte header:

```bash
python3 -c "open('combtable.prg','wb').write(b'\x00\x20'+open('combtable_h12.bin','rb').read())"
```

(For a raw SEQ file instead, build with `-DREU_SKIP=0` and use the raw `.bin`.)

## Putting it on a disk (Ultimate-64)

The loader opens `"COMBTABLE"` on device 8, so the table must be on a disk image
mounted as **Drive A**. A `.d81` (800 KB) holds the 128 KB table and the 46 KB
program with room to spare.

**Filename case matters.** The loader searches for the PETSCII bytes
`43 4F 4D 42 54 41 42 4C 45` (unshifted — shows as `COMBTABLE` in the C64's
default uppercase mode). VICE's `c1541` flips case on write: give it the name in
**lowercase** so it stores the unshifted bytes the loader expects:

```bash
c1541 -format "meshchat64,01" d81 MeshChat64.d81 \
      -write combtable.prg combtable \
      -write meshchat64_reu.prg meshchatreu
```

Mount `MeshChat64.d81` on Drive A (device 8) and run the program. **JiffyDOS**
speeds the one-time table load considerably (≈25 s for the 128 KB h12 table vs a
plain 1581).

## Verification

Same methodology as the rest of the project — Python reference → byte-exact in
[py65](https://github.com/mnaberez/py65) → hardware:

- [`sim_comb_signed.py`](../verify/sim_comb_signed.py) — signed comb equals `n·B`
  (0 fails for t=6 and t=12).
- [`sim_reu_comb.py`](../verify/sim_reu_comb.py) — an **assembly-faithful** model
  (multi-byte recode/idx, `idx·64` REU addressing, 64-byte fetch); 0 fails for
  t=12 and t=18.
- [`reu_shim.py`](../verify/reu_shim.py) — a py65 memory shim emulating the REC
  at `$DF00–$DF0A` against a 16 MB bytearray.
- [`verify_reu_asm.py`](../verify/verify_reu_asm.py) — runs the **assembled**
  `meshchat64_reu.prg` in py65 with the shim (table pre-loaded, keepalive
  stubbed) and compares `ACC` to `scalar_mul(s,B)`: **h12 8/8, h18 4/4
  byte-exact**.
- [`gen_comb_table.py`](../verify/gen_comb_table.py) reproduces the production
  h6 `comb_table.inc` byte-for-byte, so it is trusted for all `t`.

On real hardware (Ultimate-64, 16 MB REU) the h12 build signs and the relay
reports the signature as **verified**.

## Table persistence across resets — work in progress

REU contents survive a warm reset (only a power-off clears them), so in
principle the table need only be loaded once. The loader stashes a small
`"MC64COMB" + REU_T` marker just past the table (`REU[table_size]`) and, on boot,
checks it first (`REU_CHECK_MARK`) to skip the disk load when the table is
already present.

This is **verified in the py65 shim** (empty REU → load + stash marker; warm
"reboot" → marker matches → skip). It is **not yet confirmed on hardware**:

- `RUN/STOP`+`RESTORE` does *not* restart the program, so the boot check never
  re-runs — that is not a valid persistence test.
- On a real reset it depends on whether the Ultimate-64 preserves REU contents
  across reset (firmware/configuration dependent), and on the loader reliably
  reaching its marker-stash path with real drive I/O.

For now, the one-time JiffyDOS load is fast and pleasant (disk sounds and all),
so persistence is parked as a future improvement.
