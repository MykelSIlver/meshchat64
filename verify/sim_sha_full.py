# -*- coding: utf-8 -*-
import re, hashlib, random
from py65.devices.mpu6502 import MPU
L={}
for ln in open("sha_labels.txt"):
    m=re.match(r"\s*([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)",ln)
    if m: L[m.group(1)]=int(m.group(2),16)
mem=bytearray(0x10000); img=open("sha512.prg","rb").read(); mem[0x0801:0x0801+len(img)]=img
mpu=MPU(memory=mem); MSGBUF=0x4000
def call(a,mx=80_000_000):
    mem[0x1FF]=0xFF;mem[0x1FE]=0xFF;mpu.sp=0xFD;mpu.pc=a;n=0
    while mpu.pc!=0:
        mpu.step();n+=1
        if n>mx: raise RuntimeError("hang")
def sha(msg):
    mem[MSGBUF:MSGBUF+len(msg)]=msg
    mem[L["SRC"]]=MSGBUF&0xff; mem[L["SRC"]+1]=MSGBUF>>8
    mem[L["SHA_MLEN"]]=len(msg)&0xff; mem[L["SHA_MLEN"]+1]=(len(msg)>>8)&0xff
    call(L["SHA512"])
    return bytes(mem[L["SHA_DIGEST"]:L["SHA_DIGEST"]+64])
random.seed(7)
lengths=[0,1,55,56,63,64,110,111,112,113,119,120,127,128,129,200,255,256,257,300,500]
fails=0
for n in lengths:
    msg=bytes(random.getrandbits(8) for _ in range(n))
    if sha(msg)!=hashlib.sha512(msg).digest():
        print(f"  FOUT len={n}"); fails+=1
print(f"{len(lengths)} lengtes getest (0..500, incl. blokgrenzen) -> {'ALLES OK' if not fails else str(fails)+' FOUT'}")
