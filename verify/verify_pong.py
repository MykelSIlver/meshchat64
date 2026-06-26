from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ACC=[0x8bdd,0x8bfd,0x8c1d,0x8c3d]; SCALAR=0x8cdd; WD_ON=0xb502
COMB=0xa6d4

def run(prg, set_wd_on, cbk=None):
    b=open(prg,'rb').read(); la=b[0]|(b[1]<<8); code=b[2:]
    mem=ObservableMemory()
    for i,by in enumerate(code): mem[la+i]=by
    # stub ACIA: $DE01 lees -> TDRE=1 ($10); $DE00 schrijf -> sink
    mem.subscribe_to_read([0xDE01], lambda a: 0x10)
    mem.subscribe_to_read([0xDE00], lambda a: 0x00)
    sink={}
    mem.subscribe_to_write([0xDE00,0xDE02,0xDD0D], lambda a,v: None)
    mpu=MPU(memory=mem)
    # test-SCALAR (32 bytes, willekeurig-deterministisch)
    for i in range(32): mem[SCALAR+i]=(i*7+3)&0xff
    mem[WD_ON]=set_wd_on
    if cbk is not None:
        # verklein iteraties voor snelheid: patch 'lda #63' immediate -> #cbk
        # COMB_SCALAR_MUL: ... lda #63 : sta CB_K  (zoek #63 vlak na entry)
        for a in range(COMB, COMB+40):
            if mem[a]==0xA9 and mem[a+1]==63:
                mem[a+1]=cbk; break
    # nep-returnadres: RTS -> $0001 (sentinel)
    mem[0x01ff]=0x00; mem[0x01fe]=0x00; mpu.sp=0xfd
    mpu.pc=COMB
    steps=0
    while mpu.pc!=0x0001 and steps<80_000_000:
        mpu.step(); steps+=1
    acc=b''.join(bytes(mem[a+i] for i in range(32)) for a in ACC)
    return steps, acc

import time
for cbk in (None,):       # eerst snelle 4-iteratie sanity, dan volledige 64
    lab = f"CB_K={cbk if cbk is not None else 63} (volledig)" if cbk is None else f"CB_K={cbk}"
    t=time.time()
    s0,a0=run('merged28_A3BMX.prg',  0, cbk)          # baseline, geen PD_WRAP
    s1,a1=run('merged28_A3BMXP.prg', 1, cbk)          # pong actief (WD_ON=1)
    s2,a2=run('merged28_A3BMXP.prg', 0, cbk)          # pong overgeslagen (WD_ON=0)
    ok = (a0==a1==a2)
    print(f"[{lab}] stappen ~{s1}  ACC identiek(base==pong-aan==pong-uit): {ok}  ({time.time()-t:.1f}s)")
    if not ok:
        print("  base :", a0.hex())
        print("  pong1:", a1.hex())
        print("  pong0:", a2.hex())
