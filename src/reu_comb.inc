; ================================================================
; reu_comb.inc  -  REU-backed SIGNED comb scalar-mult (build -DREU=1)
; ----------------------------------------------------------------
;   ACC = SCALAR * B.  Replaces the in-RAM h6 comb (comb_keepalive.inc).
;   The wide comb table lives in the REU (2^(t-1) x 64 B), fetched one
;   point per step by DMA at $DF00 -> PIN.  This FREES C64 RAM $A900-$B0FF
;   (the former in-RAM table).  NO banking, NO $FFFA/NMI hazard: the REC
;   pauses the CPU during DMA and never exposes an interrupt vector.
;
;   Teeth t = REU_T (default 18; valid 12/16/18; 19 fills a 16 MB REU).
;     W   = ceil(258/t)  doublings
;     L   = t*W          ; recode forces bit L-1
;   Table convention (gen_comb_table.py):
;     TABLE[idx] = sum_i sigma_i*2^(iW)*B ; sigma_0=+1 ; idx in 0..2^(t-1)-1
;   Per step the loop adds sum_i (2*b_i-1)*2^(iW)*B = +/-TABLE[idx].
;
;   Algorithm proven byte-exact vs n*B in sim_comb_signed.py and the
;   asm-faithful sim_reu_comb.py (0 fails, t=12 and t=18).
;   The table must be loaded into the REU at boot (see reu_loader.inc).
; ================================================================

!ifndef REU_T { REU_T = 18 }

REU_W       = (258 + REU_T - 1) / REU_T          ; ceil(258/t) = doublings
REU_L       = REU_T * REU_W                       ; bits covered
REU_TOPBIT  = REU_L - 1                            ; forced bit
REU_TOPBYTE = REU_TOPBIT / 8
REU_TOPMASK = 1 << (REU_TOPBIT & 7)
REU_NB      = (REU_TOPBIT / 8) + 1                ; MPRIME_R byte count (33 or 34)
REU_IDXBYTES = (REU_T + 6) / 8                     ; ceil((t-1)/8): 2 (t<=9? ) ; 11b->2, 17b->3

; ---------------------------------------------------------------
COMB_SCALAR_MUL
        jsr CB_RECODE_REU                ; MPRIME_R = u = (m>>1)|2^(L-1)
        ; ACC = identity (0,1,1,0)
        ldx #31
RID     lda #0
        sta ACC_X,x
        sta ACC_Y,x
        sta ACC_Z,x
        sta ACC_T,x
        dex
        bpl RID
        lda #1
        sta ACC_Y
        sta ACC_Z
        lda #(REU_W-1)
        sta CB_K
RLOOP
        ; ACC = 2*ACC  (keepalive woven in, then POINT_DBL)
        +fcopy AX, ACC_X
        +fcopy AY, ACC_Y
        +fcopy AZ, ACC_Z
        +fcopy AT, ACC_T
        jsr PD_WRAP
        +fcopy ACC_X, RX
        +fcopy ACC_Y, RY
        +fcopy ACC_Z, RZ
        +fcopy ACC_T, RT
        ; --- tooth 0 (pos = CB_K): b0 -> CB_B0, CB_NEG = !b0 ---
        lda CB_K : sta CB_POS : lda #0 : sta CB_POS+1
        jsr CB_GETBIT_R
        sta CB_B0
        eor #1 : sta CB_NEG
        ; clear idx (REU_IDXBYTES bytes)
        lda #0
        ldx #(REU_IDXBYTES-1)
RIC     sta REU_IDX,x
        dex
        bpl RIC
        ; --- teeth 1..t-1: CB_POS += W each ; set idx bit (i-1) if b_i != b0 ---
        lda CB_K : sta CB_POS : lda #0 : sta CB_POS+1
        lda #1 : sta REU_TI
RTEETH
        clc
        lda CB_POS   : adc #<REU_W : sta CB_POS
        lda CB_POS+1 : adc #>REU_W : sta CB_POS+1
        jsr CB_GETBIT_R
        eor CB_B0
        beq RT_NEXT                      ; b_i == b0 -> idx bit stays 0
        ; set idx bit number (REU_TI-1)
        ldx REU_TI
        dex                              ; X = bitnum
        txa
        lsr : lsr : lsr                  ; A = bitnum>>3 = byte index
        sta REU_TMP
        txa
        and #7 : tax                     ; X = bitnum & 7
        lda #1
RMSK    cpx #0
        beq RMSKD
        asl
        dex
        jmp RMSK
RMSKD   ldx REU_TMP
        ora REU_IDX,x
        sta REU_IDX,x
RT_NEXT
        inc REU_TI
        lda REU_TI
        cmp #REU_T
        bcc RTEETH
        ; --- reu_off = idx << 6  (24-bit) ---
        lda #0
        sta REU_ADDR+0 : sta REU_ADDR+1 : sta REU_ADDR+2
        ldx #(REU_IDXBYTES-1)
RCPY    lda REU_IDX,x
        sta REU_ADDR,x
        dex
        bpl RCPY
        ldx #6
RSHL    asl REU_ADDR+0
        rol REU_ADDR+1
        rol REU_ADDR+2
        dex
        bne RSHL
        ; --- DMA fetch 64 B: REU[off] -> PIN_X (PIN_X..PIN_Y contiguous) ---
        lda #<PIN_X : sta $DF02
        lda #>PIN_X : sta $DF03
        lda REU_ADDR+0 : sta $DF04
        lda REU_ADDR+1 : sta $DF05
        lda REU_ADDR+2 : sta $DF06
        lda #64 : sta $DF07
        lda #0  : sta $DF08
        lda #0  : sta $DF0A              ; both addresses increment
        lda #$91 : sta $DF01             ; EXECUTE | FF00-now | fetch(01)
        ; --- finish point: negate X if CB_NEG ; Z=1 ; T = X*Y ---
        lda CB_NEG
        beq RNN
        +fsub PIN_X, P_CONST, PIN_X      ; X = p - X
RNN
        lda #0
        ldx #31
RZC     sta PIN_Z,x
        dex
        bpl RZC
        lda #1 : sta PIN_Z
        +fmul PIN_T, PIN_X, PIN_Y        ; T = X * Y
        ; --- ACC = ACC + PIN ---
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
        bmi RDONE
        jmp RLOOP
RDONE
        rts

; ---------------------------------------------------------------
; CB_RECODE_REU : MPRIME_R = ((SCALAR [+ORDER if even]) >> 1) | 2^(L-1)
;   m must be odd; +ORDER (=LT, group order) flips parity, same point.
; ---------------------------------------------------------------
CB_RECODE_REU
        ldx #31
RRC     lda SCALAR,x : sta MPRIME_R,x : dex : bpl RRC
        lda #0                                  ; zero high bytes 32..NB-1
        ldx #32
RRZ     sta MPRIME_R,x : inx : cpx #REU_NB : bne RRZ
        lda SCALAR : and #1 : bne RR_ODD        ; odd -> skip +ORDER
        clc                                      ; MPRIME_R += LT (32 bytes)
        ldx #0
        ldy #32
RR_AD     lda MPRIME_R,x : adc LT,x : sta MPRIME_R,x
        inx : dey : bne RR_AD
        lda MPRIME_R+32 : adc #0 : sta MPRIME_R+32   ; carry into high byte(s)
!if REU_NB > 33 {
        lda MPRIME_R+33 : adc #0 : sta MPRIME_R+33
}
RR_ODD
        clc                                      ; MPRIME_R >>= 1 (NB bytes)
        ldx #(REU_NB-1)
RRSH    ror MPRIME_R,x : dex : bpl RRSH
        lda MPRIME_R+REU_TOPBYTE : ora #REU_TOPMASK : sta MPRIME_R+REU_TOPBYTE
        rts

; ---------------------------------------------------------------
; CB_GETBIT_R : bit CB_POS (16-bit, 0..L-1) of MPRIME_R -> A = 0/1
; ---------------------------------------------------------------
CB_GETBIT_R
        lda CB_POS : sta CB_TMP
        lsr CB_TMP : lsr CB_TMP : lsr CB_TMP     ; (low>>3) 0..31
        lda CB_POS+1                              ; high byte (0 or 1)
        asl : asl : asl : asl : asl               ; high<<5 (0 or 32)
        clc : adc CB_TMP : tax                     ; byte index 0..33
        lda MPRIME_R,x : sta CB_TMP
        lda CB_POS : and #7 : tax
RGS     cpx #0
        beq RGD
        lsr CB_TMP
        dex
        jmp RGS
RGD     lda CB_TMP : and #1
        rts

; ---------------------------------------------------------------
; work vars (in freed in-RAM-table region, < $B100)
; ---------------------------------------------------------------
CB_K      !byte 0
CB_B0     !byte 0
CB_NEG    !byte 0
CB_POS    !byte 0,0
CB_TMP    !byte 0
REU_TI    !byte 0
REU_TMP   !byte 0
REU_IDX   !fill 3,0
REU_ADDR  !fill 3,0
MPRIME_R  !fill 34,0           ; max NB (h18/h19); h12 uses 33
