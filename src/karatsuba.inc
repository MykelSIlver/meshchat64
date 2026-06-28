; ================================================================
; karatsuba.inc - one-level Karatsuba 256-bit multiply (test placement $A900)
;   FP_MUL_KARA : (FRP) = (FAP)*(FBP) mod p
;   a = a1:a0, b = b1:b0 (16-byte halves).
;   z0 = a0*b0 -> PROD[0:32] ; z2 = a1*b1 -> PROD[32:64]
;   sa=a0+a1 (ca), sb=b0+b1 (cb) ; zm = sa*sb (+carry terms) ; z1 = zm-z0-z2
;   P = z0 + z1<<128 + z2<<256 ; then FP_REDUCE.
;   3x (16x16) = 768 mul8 vs 1024 schoolbook.
; ================================================================

FP_MUL_KARA
        ; copy operands to MA, MB (then FAP/FBP are free scratch)
        ldy #0
FK_CA   lda (FAP),y : sta MA,y : iny : cpy #32 : bne FK_CA
        ldy #0
FK_CB   lda (FBP),y : sta MB,y : iny : cpy #32 : bne FK_CB
        ; z0 = a0*b0 -> PROD[0:32]
        ldx #15
FK_S0   lda MA,x : sta M16A,x : lda MB,x : sta M16B,x : dex : bpl FK_S0
        lda #<PROD : sta DST16 : lda #>PROD : sta DST16+1
        jsr MUL16
        ; z2 = a1*b1 -> PROD[32:64]
        ldx #15
FK_S2   lda MA+16,x : sta M16A,x : lda MB+16,x : sta M16B,x : dex : bpl FK_S2
        lda #<(PROD+32) : sta DST16 : lda #>(PROD+32) : sta DST16+1
        jsr MUL16
        ; sa = a0+a1 -> MA[0:16] ; ca
        clc
        ldx #0 : ldy #16
FK_SA   lda MA,x : adc MA+16,x : sta MA,x : inx : dey : bne FK_SA
        lda #0 : rol : sta KARA_CA
        ; sb = b0+b1 -> MB[0:16] ; cb
        clc
        ldx #0 : ldy #16
FK_SB   lda MB,x : adc MB+16,x : sta MB,x : inx : dey : bne FK_SB
        lda #0 : rol : sta KARA_CB
        ; zm = sa*sb -> ZM[0:32] ; ZM[32]=0
        ldx #15
FK_SM   lda MA,x : sta M16A,x : lda MB,x : sta M16B,x : dex : bpl FK_SM
        lda #<ZM : sta DST16 : lda #>ZM : sta DST16+1
        jsr MUL16
        lda #0 : sta ZM+32
        ; carry terms: if ca: ZM[16:32]+=sb(MB) ; if cb: ZM[16:32]+=sa(MA) ; if ca&cb: ZM[32]+=1
        lda KARA_CA : beq FK_NCA
        clc
        ldx #0 : ldy #16
FK_ACA  lda ZM+16,x : adc MB,x : sta ZM+16,x : inx : dey : bne FK_ACA
        lda ZM+32 : adc #0 : sta ZM+32
FK_NCA  lda KARA_CB : beq FK_NCB
        clc
        ldx #0 : ldy #16
FK_ACB  lda ZM+16,x : adc MA,x : sta ZM+16,x : inx : dey : bne FK_ACB
        lda ZM+32 : adc #0 : sta ZM+32
FK_NCB  lda KARA_CA : and KARA_CB : beq FK_NCC
        inc ZM+32
FK_NCC
        ; z1 = ZM - z0(PROD[0:32]) - z2(PROD[32:64])  (in place in ZM, 33 bytes)
        sec
        ldx #0 : ldy #32
FK_S1A  lda ZM,x : sbc PROD,x : sta ZM,x : inx : dey : bne FK_S1A
        lda ZM+32 : sbc #0 : sta ZM+32
        sec
        ldx #0 : ldy #32
FK_S1B  lda ZM,x : sbc PROD+32,x : sta ZM,x : inx : dey : bne FK_S1B
        lda ZM+32 : sbc #0 : sta ZM+32
        ; PROD[16:49] += ZM[0:33]
        clc
        ldx #0 : ldy #33
FK_AS   lda PROD+16,x : adc ZM,x : sta PROD+16,x : inx : dey : bne FK_AS
        ; propagate carry into PROD[49..63]
        ldy #15
FK_PROP bcc FK_RED
        lda PROD+16,x : adc #0 : sta PROD+16,x : inx : dey : bne FK_PROP
FK_RED
        jsr FP_REDUCE             ; PROD -> RES (reduced mod p)
        ldy #0
FK_OUT  lda RES,y : sta (FRP),y : iny : cpy #32 : bne FK_OUT
        rts

; --- MUL16: 32 bytes at (DST16) = M16A[0:16] * M16B[0:16] ---
MUL16
        lda DST16 : sta FAP : lda DST16+1 : sta FAP+1
        lda #0 : ldy #31
MK_CL   sta (FAP),y : dey : bpl MK_CL
        lda #0 : sta K16
MK_ROW
        lda DST16 : clc : adc K16 : sta FAP
        lda DST16+1 : adc #0 : sta FAP+1
        ldx K16
        lda M16A,x : sta MUL_A
        lda #0 : sta CARRY8
        ldy #0
MK_COL
        lda M16B,y : sta MUL_B
        ; --- inline quarter-square 8x8: MUL_RES = MUL_A*MUL_B ---
        lda MUL_A : clc : adc MUL_B : tax
        bcc .mlo
        lda QSL1+256,x : sta MUL_RES
        lda QSH1+256,x : sta MUL_RES+1
        jmp .msub
.mlo    lda QSL1,x : sta MUL_RES
        lda QSH1,x : sta MUL_RES+1
.msub   lda MUL_A : sec : sbc MUL_B
        bcs .mdpos
        eor #$FF : clc : adc #1
.mdpos  tax
        sec
        lda MUL_RES   : sbc QSL1,x : sta MUL_RES
        lda MUL_RES+1 : sbc QSH1,x : sta MUL_RES+1
        ; --- end mul8 ---
        lda MUL_RES   : clc : adc (FAP),y : sta TLO
        lda MUL_RES+1 : adc #0          : sta THI
        lda TLO       : clc : adc CARRY8 : sta (FAP),y
        lda THI       : adc #0          : sta CARRY8
        iny : cpy #16 : bne MK_COL
        ldy #16
        lda (FAP),y : clc : adc CARRY8 : sta (FAP),y
        inc K16
        lda K16 : cmp #16 : beq MK_RDONE
        jmp MK_ROW
MK_RDONE rts

M16A    !fill 16,0
M16B    !fill 16,0
ZM      !fill 33,0
DST16   !byte 0,0
K16     !byte 0
KARA_CA !byte 0
KARA_CB !byte 0
