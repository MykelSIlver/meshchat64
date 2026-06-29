; ================================================================
; B: fixed-base SIGNED comb scalar-mult (h=6).  ACC = SCALAR * B
;   32-point table INTERNAL (comb_table.inc @ $A900, 32 x 64 B).  NO banking.
;   Per step k=42..0: ACC=2*ACC ; idx (5 bits) from teeth signs relative to
;   tooth0 ; load +/-TABLE[idx] ; ACC += point.  43 doublings.
;   6 teeth at bit offsets 0,43,86,129,172,215 (W=43).  6*43=258 > 257 so the
;   top tooth reaches bits 256/257 for k=41/42 -> CB_POS is 16-bit.
;   Recode forces bit257 (= NB-1).  Validated byte-exact vs n*B.
; ================================================================
COMB_SCALAR_MUL
        jsr CB_RECODE                 ; MPRIME = u = (m>>1)|bit257
        ldx #31
CB_ID   lda #0
        sta ACC_X,x
        sta ACC_Y,x
        sta ACC_Z,x
        sta ACC_T,x
        dex
        bpl CB_ID
        lda #1
        sta ACC_Y
        sta ACC_Z
        lda #42                       ; 43 steps (k=42..0)
        sta CB_K
CB_LOOP
        +fcopy AX, ACC_X
        +fcopy AY, ACC_Y
        +fcopy AZ, ACC_Z
        +fcopy AT, ACC_T
        jsr PD_WRAP                   ; keepalive + POINT_DBL
        +fcopy ACC_X, RX
        +fcopy ACC_Y, RY
        +fcopy ACC_Z, RZ
        +fcopy ACC_T, RT
        lda CB_K : sta CB_POS : lda #0 : sta CB_POS+1
        jsr CB_GETBIT
        sta CB_B0
        eor #1 : sta CB_NEG
        lda #0 : sta CB_IDX
        lda CB_K : clc : adc #43  : sta CB_POS : lda #0 : adc #0 : sta CB_POS+1
        jsr CB_GETBIT
        eor CB_B0 : beq CB_T2
        lda CB_IDX : ora #$01 : sta CB_IDX
CB_T2   lda CB_K : clc : adc #86  : sta CB_POS : lda #0 : adc #0 : sta CB_POS+1
        jsr CB_GETBIT
        eor CB_B0 : beq CB_T3
        lda CB_IDX : ora #$02 : sta CB_IDX
CB_T3   lda CB_K : clc : adc #129 : sta CB_POS : lda #0 : adc #0 : sta CB_POS+1
        jsr CB_GETBIT
        eor CB_B0 : beq CB_T4
        lda CB_IDX : ora #$04 : sta CB_IDX
CB_T4   lda CB_K : clc : adc #172 : sta CB_POS : lda #0 : adc #0 : sta CB_POS+1
        jsr CB_GETBIT
        eor CB_B0 : beq CB_T5
        lda CB_IDX : ora #$08 : sta CB_IDX
CB_T5   lda CB_K : clc : adc #215 : sta CB_POS : lda #0 : adc #0 : sta CB_POS+1
        jsr CB_GETBIT
        eor CB_B0 : beq CB_LOADP
        lda CB_IDX : ora #$10 : sta CB_IDX
CB_LOADP
        jsr COMB_LOADPT_S
        +fcopy AX, ACC_X
        +fcopy AY, ACC_Y
        +fcopy AZ, ACC_Z
        +fcopy AT, ACC_T
        +fcopy BX_, PIN_X
        +fcopy BY_, PIN_Y
        +fcopy BZ_, PIN_Z
        +fcopy BT_, PIN_T
        jsr POINT_ADD
        +fcopy ACC_X, RX
        +fcopy ACC_Y, RY
        +fcopy ACC_Z, RZ
        +fcopy ACC_T, RT
        dec CB_K
        bmi CB_DONE
        jmp CB_LOOP
CB_DONE
        rts

CB_K    !byte 0
CB_IDX  !byte 0
CB_HI   !byte 0
CB_LO   !byte 0

!source "comb_table.inc"
