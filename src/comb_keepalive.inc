; ================================================================
; B: vaste-basis comb scalar-mult (h=4).  ACC = SCALAR * B
;   Replaces LOAD_B + SCALAR_MUL for R=r*B (and A=a*B).
;   Per step k=63..0: ACC=2*ACC ; idx from 4 bits (k,k+64,k+128,k+192)
;   via SM_TESTBIT ; if idx: ACC += COMB_TABLE[idx].
; ================================================================
COMB_SCALAR_MUL
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
        lda #63
        sta CB_K
CB_LOOP
        ; ACC = 2*ACC
        +fcopy AX, ACC_X
        +fcopy AY, ACC_Y
        +fcopy AZ, ACC_Z
        +fcopy AT, ACC_T
        jsr PD_WRAP              ; keepalive: weave in pong, then continue to POINT_DBL
        +fcopy ACC_X, RX
        +fcopy ACC_Y, RY
        +fcopy ACC_Z, RZ
        +fcopy ACC_T, RT
        ; --- idx uit 4 bits ---
        lda #0
        sta CB_IDX
        lda CB_K
        sta SM_BIT
        jsr SM_TESTBIT
        bcc CB_B1
        lda CB_IDX : ora #$01 : sta CB_IDX
CB_B1   lda CB_K : clc : adc #64  : sta SM_BIT
        jsr SM_TESTBIT
        bcc CB_B2
        lda CB_IDX : ora #$02 : sta CB_IDX
CB_B2   lda CB_K : clc : adc #128 : sta SM_BIT
        jsr SM_TESTBIT
        bcc CB_B3
        lda CB_IDX : ora #$04 : sta CB_IDX
CB_B3   lda CB_K : clc : adc #192 : sta SM_BIT
        jsr SM_TESTBIT
        bcc CB_ADDQ
        lda CB_IDX : ora #$08 : sta CB_IDX
CB_ADDQ
        lda CB_IDX
        bne CB_DOADD
        jmp CB_NEXT
CB_DOADD
        jsr COMB_LOADPT          ; PIN = COMB_TABLE[idx]
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
CB_NEXT
        dec CB_K
        bmi CB_DONE
        jmp CB_LOOP
CB_DONE
        rts

; COMB_LOADPT : PIN = COMB_TABLE[CB_IDX]  (idx*128, self-modifying absolute read)
COMB_LOADPT
        lda CB_IDX
        lsr                      ; A=idx>>1 ; C=idx&1
        sta CB_HI
        lda #0
        bcc CB_LP0
        lda #$80
CB_LP0  sta CB_LO
        clc
        lda #<COMB_TABLE : adc CB_LO : sta CB_RD+1
        lda #>COMB_TABLE : adc CB_HI : sta CB_RD+2
        ldy #0
CB_RD   lda COMB_TABLE,y         ; operand zelf-gemodificeerd -> src
        sta PIN_X,y
        iny
        cpy #128
        bne CB_RD
        rts

CB_K    !byte 0
CB_IDX  !byte 0
CB_HI   !byte 0
CB_LO   !byte 0
!source "comb_table.inc"
