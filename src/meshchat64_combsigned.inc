; ================================================================
; meshchat64_combsigned.inc  -  signed-comb h=6 helpers (free RAM $BE56)
;   CB_RECODE     : SCALAR -> MPRIME = u = (m>>1)|bit257 ; m = SCALAR|+L (odd)
;   CB_GETBIT     : bit CB_POS (16-bit, 0..257) of MPRIME -> A (0/1)
;   COMB_LOADPT_S : PIN = signed COMB_TABLE[CB_IDX] (XY, Z=1, T=X*Y, negX if CB_NEG)
;                   table @ COMB_TABLE (internal, 32 points x 64 B).
; Algorithm validated byte-exact in Python vs n*B and in py65 (0 fails).
; ================================================================
* = $BE56

CB_RECODE
        ldx #31
CRC_C   lda SCALAR,x : sta MPRIME,x : dex : bpl CRC_C
        lda #0 : sta MPRIME+32
        lda SCALAR : and #1 : bne CRC_ODD     ; odd -> no +L
        clc
        ldx #0
        ldy #32                                ; DEY counter (CPX clobbers carry!)
CRC_AD  lda MPRIME,x : adc LT,x : sta MPRIME,x
        inx : dey : bne CRC_AD
        lda MPRIME+32 : adc #0 : sta MPRIME+32
CRC_ODD
        clc                                    ; MPRIME >>= 1 (33 bytes)
        ldx #32
CRC_SH  ror MPRIME,x : dex : bpl CRC_SH
        lda MPRIME+32 : ora #$02 : sta MPRIME+32   ; force bit257 (= NB-1)
        rts

; --- bit CB_POS (16-bit, 0..257) of MPRIME -> A=0/1 ---
CB_GETBIT
        lda CB_POS : sta CB_TMP
        lsr CB_TMP : lsr CB_TMP : lsr CB_TMP      ; (low>>3) 0..31
        lda CB_POS+1                              ; high byte (0 or 1)
        asl : asl : asl : asl : asl               ; high<<5 (0 or 32)
        clc : adc CB_TMP : tax                     ; byte index 0..32
        lda MPRIME,x : sta CB_TMP
        lda CB_POS : and #7 : tax
CBG_S   cpx #0
        beq CBG_D
        lsr CB_TMP
        dex
        jmp CBG_S
CBG_D   lda CB_TMP : and #1
        rts

; --- PIN = signed COMB_TABLE[CB_IDX]  (32 x 64 B internal, src = +idx*64) ---
COMB_LOADPT_S
        lda CB_IDX : and #3
        asl : asl : asl : asl : asl : asl          ; (idx&3)*64
        sta CB_LO
        lda CB_IDX : lsr : lsr : sta CB_HI          ; idx>>2
        clc
        lda #<COMB_TABLE : adc CB_LO : sta CBS_RD+1
        lda #>COMB_TABLE : adc CB_HI : sta CBS_RD+2
        ldy #0
CBS_RD  lda COMB_TABLE,y                            ; self-modified operand
        sta PIN_X,y                                ; PIN_X (0..31) + PIN_Y (32..63)
        iny
        cpy #64
        bne CBS_RD
        lda CB_NEG : beq CBS_NN                     ; negate X if tooth0 sign -
        +fsub PIN_X, P_CONST, PIN_X
CBS_NN
        lda #0                                      ; Z = 1
        ldx #31
CBS_ZC  sta PIN_Z,x : dex : bpl CBS_ZC
        lda #1 : sta PIN_Z
        +fmul PIN_T, PIN_X, PIN_Y                   ; T = X * Y
        rts

MPRIME  !fill 33,0
CB_POS  !byte 0,0
CB_B0   !byte 0
CB_NEG  !byte 0
CB_TMP  !byte 0
