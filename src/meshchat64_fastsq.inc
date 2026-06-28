; ============================================================================
; meshchat64_fastsq.inc  -  Ed25519 signing speedup (opt 1+2)
;   FP_SQ        : dedicated squaring (~528 vs ~1024 mul8) + inlined mul8
;   FP_MUL_FAST  : FP_MUL with inlined mul8 (no per-byte JSR/RTS)
;   Placed in free RAM $BC00 (below SHA tables $C000); contiguous code untouched.
;   Verified byte-exact vs FP_MUL / a*b mod p / a^2 mod p in py65.
; ============================================================================
* = $BC00

; --- inlined 8x8 quarter-square mul (= MUL8 body, no JSR/RTS) ---
!macro mul8_inline {
        LDA MUL_A : CLC : ADC MUL_B : TAX
        BCC .lo
        LDA QSL1+256,X : STA MUL_RES
        LDA QSH1+256,X : STA MUL_RES+1
        JMP .sub
.lo     LDA QSL1,X : STA MUL_RES
        LDA QSH1,X : STA MUL_RES+1
.sub    LDA MUL_A : SEC : SBC MUL_B
        BCS .dpos
        EOR #$FF : CLC : ADC #1
.dpos   TAX
        SEC
        LDA MUL_RES   : SBC QSL1,X : STA MUL_RES
        LDA MUL_RES+1 : SBC QSH1,X : STA MUL_RES+1
}

; ================================================================
; FP_SQ : (FRP) = (FAP)^2 mod p   (dedicated squaring, inlined mul8)
;   Same 64-byte PROD as FP_MUL(a,a) -> FP_REDUCE. ~528 mul vs ~1024.
;   In-place safe (copies A->MA before writing (FRP)).
; ================================================================
FP_SQ
        LDY #0
FQ_CA   LDA (FAP),Y : STA MA,Y : INY : CPY #32 : BNE FQ_CA
        LDA #0
        LDX #63
FQ_CP   STA PROD,X : DEX : BPL FQ_CP
        LDA #0 : STA II
FQ_ROW
        LDA #<PROD : CLC : ADC II : STA FAP
        LDA #>PROD : ADC #0 : STA FAP+1
        LDX II
        LDA MA,X : STA MUL_A
        LDA #0 : STA CARRY8
        LDX II : INX
        TXA : TAY
        CPY #32
        BCS FQ_ROWE
FQ_COL
        LDA MA,Y : STA MUL_B
        +mul8_inline
        LDA MUL_RES   : CLC : ADC (FAP),Y : STA TLO
        LDA MUL_RES+1 : ADC #0          : STA THI
        LDA TLO       : CLC : ADC CARRY8 : STA (FAP),Y
        LDA THI       : ADC #0          : STA CARRY8
        INY
        CPY #32
        BNE FQ_COL
        LDY #32
        LDA (FAP),Y : CLC : ADC CARRY8 : STA (FAP),Y
FQ_ROWE
        INC II
        LDA II : CMP #31
        BEQ FQ_ROWZ
        JMP FQ_ROW
FQ_ROWZ
        LDX #0
        LDY #64
        CLC
FQ_DBL  LDA PROD,X : ROL : STA PROD,X
        INX
        DEY
        BNE FQ_DBL
        LDA #0 : STA II
FQ_DIAG
        LDX II
        LDA MA,X : STA MUL_A : STA MUL_B
        +mul8_inline
        LDA II : ASL : TAX
        CLC
        LDA PROD,X   : ADC MUL_RES   : STA PROD,X
        INX
        LDA PROD,X   : ADC MUL_RES+1 : STA PROD,X
        BCC FQ_DIAGN
FQ_RIP  INX
        CPX #64
        BCS FQ_DIAGN
        INC PROD,X
        BEQ FQ_RIP
FQ_DIAGN
        INC II
        LDA II : CMP #32
        BEQ FQ_DIAGZ
        JMP FQ_DIAG
FQ_DIAGZ
        JSR FP_REDUCE
        LDY #0
FQ_OUT  LDA RES,Y : STA (FRP),Y : INY : CPY #32 : BNE FQ_OUT
        RTS

; ================================================================
; FP_MUL_FAST : (FRP) = (FAP)*(FBP) mod p   (FP_MUL + inlined mul8)
;   Identical result to FP_MUL; removes 1024 JSR/RTS in the column loop.
; ================================================================
FP_MUL_FAST
        LDY #0
FF_CA   LDA (FAP),Y : STA MA,Y : INY : CPY #32 : BNE FF_CA
        LDY #0
FF_CB   LDA (FBP),Y : STA MB,Y : INY : CPY #32 : BNE FF_CB
        LDA #0
        LDX #63
FF_CP   STA PROD,X
        DEX
        BPL FF_CP
        LDA #0
        STA II
FF_ROW
        LDA #<PROD
        CLC
        ADC II
        STA FAP
        LDA #>PROD
        ADC #0
        STA FAP+1
        LDX II
        LDA MA,X
        STA MUL_A
        LDA #0
        STA CARRY8
        LDY #0
FF_COL
        LDA MB,Y
        STA MUL_B
        +mul8_inline
        LDA MUL_RES
        CLC
        ADC (FAP),Y
        STA TLO
        LDA MUL_RES+1
        ADC #0
        STA THI
        LDA TLO
        CLC
        ADC CARRY8
        STA (FAP),Y
        LDA THI
        ADC #0
        STA CARRY8
        INY
        CPY #32
        BNE FF_COL
        LDY #32
        LDA (FAP),Y
        CLC
        ADC CARRY8
        STA (FAP),Y
        INC II
        LDA II
        CMP #32
        BEQ FF_ROWZ
        JMP FF_ROW
FF_ROWZ
        JSR FP_REDUCE
        LDY #0
FF_OUT  LDA RES,Y : STA (FRP),Y : INY : CPY #32 : BNE FF_OUT
        RTS
