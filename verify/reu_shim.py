#!/usr/bin/env python3
# reu_shim.py - py65 memory shim emulating a Commodore REU (REC 8726) at
#   $DF00-$DF0A, backed by a Python bytearray. py65 is flat-memory and cannot
#   see $DF00 DMA; this intercepts writes to the command register and performs
#   the stash/fetch/swap/verify transfer against the bytearray "REU".
#
#   REC register map ($DF00-$DF0A):
#     $DF00 STATUS (R): bit7 INT, bit6 END-OF-BLOCK, bit5 FAULT(verify-mismatch),
#                       bit4 chipsize(1=256k+), bits3-0 version. Read clears 7-5.
#     $DF01 COMMAND (W): bit7 EXECUTE, bit5 AUTOLOAD, bit4 FF00-decode
#                        (1=run now, 0=wait $FF00), bits1-0 type
#                        (00 stash C64->REU, 01 fetch REU->C64, 10 swap, 11 verify)
#     $DF02-03 C64 base (lo,hi)
#     $DF04-06 REU base (lo,hi,bank)
#     $DF07-08 length (lo,hi; 0 => 65536)
#     $DF09 IRQ mask (W)
#     $DF0A address control (W): bit7 fix C64 addr, bit6 fix REU addr
#
#   Use with py65 ObservableMemory: register read/write subscribers on $DF00-$DF0A.

REU_BASE = 0xDF00
REU_SIZE = 16 * 1024 * 1024   # 16 MB (Michael's U64 setting)

class REU:
    def __init__(self, cpu_memory, size=REU_SIZE, version=0x10, chipsize_bit=0x10):
        self.mem = cpu_memory            # py65 ObservableMemory (C64 RAM)
        self.reu = bytearray(size)
        self.size = size
        self.reg = bytearray(0x0B)       # $DF00..$DF0A shadow
        self.status = 0x00
        self.version = version & 0x0F
        self.chipsize_bit = chipsize_bit # 0x10 if >=256k
        self.transfers = 0               # for test instrumentation

    # ---- register accessors ----
    def _c64_addr(self):
        return self.reg[0x02] | (self.reg[0x03] << 8)

    def _reu_addr(self):
        return self.reg[0x04] | (self.reg[0x05] << 8) | (self.reg[0x06] << 16)

    def _length(self):
        l = self.reg[0x07] | (self.reg[0x08] << 8)
        return l if l != 0 else 0x10000

    def read(self, addr):
        off = addr - REU_BASE
        if off == 0x00:
            val = (self.status & 0xE0) | self.chipsize_bit | self.version
            self.status &= ~0xE0 & 0xFF   # reading clears bits 7-5
            return val
        return self.reg[off]

    def write(self, addr, value):
        off = addr - REU_BASE
        value &= 0xFF
        if off == 0x00:
            return                        # status is read-only
        self.reg[off] = value
        if off == 0x01 and (value & 0x80):       # EXECUTE
            if value & 0x10:                      # FF00-decode=1 -> run immediately
                self._do_transfer(value & 0x03)
            # (FF00-decode=0 path: would wait for a $FF00 write; not modeled here)

    def _do_transfer(self, ttype):
        c64 = self._c64_addr()
        reu = self._reu_addr()
        n = self._length()
        fix_c64 = bool(self.reg[0x0A] & 0x80)
        fix_reu = bool(self.reg[0x0A] & 0x40)
        fault = False
        ci, ri = c64, reu
        for _ in range(n):
            if ttype == 0x00:             # stash C64 -> REU
                self.reu[ri] = self.mem[ci] & 0xFF
            elif ttype == 0x01:           # fetch REU -> C64
                self.mem[ci] = self.reu[ri]
            elif ttype == 0x02:           # swap
                a = self.mem[ci] & 0xFF; b = self.reu[ri]
                self.mem[ci] = b; self.reu[ri] = a
            elif ttype == 0x03:           # verify (compare)
                if (self.mem[ci] & 0xFF) != self.reu[ri]:
                    fault = True
                    break
            if not fix_c64:
                ci = (ci + 1) & 0xFFFF
            if not fix_reu:
                ri = (ri + 1) % self.size
        self.status |= 0x40               # END-OF-BLOCK
        if fault:
            self.status |= 0x20           # FAULT
        # write-back the advanced addresses (real REC updates these)
        if not fix_c64:
            self.reg[0x02] = ci & 0xFF; self.reg[0x03] = (ci >> 8) & 0xFF
        if not fix_reu:
            self.reg[0x04] = ri & 0xFF
            self.reg[0x05] = (ri >> 8) & 0xFF
            self.reg[0x06] = (ri >> 16) & 0xFF
        self.transfers += 1

def install(memory):
    """Attach a REU to a py65 ObservableMemory. Returns the REU instance."""
    reu = REU(memory)
    for a in range(REU_BASE, REU_BASE + 0x0B):
        memory.subscribe_to_write([a], lambda addr, val, r=reu: r.write(addr, val))
        memory.subscribe_to_read([a], lambda addr, r=reu: r.read(addr))
    return reu
