; ================================================================
; meshchat64_sendfix.inc  -  1 MHz send-timeout fix (briefing section 9)
; ----------------------------------------------------------------
; Combined, all net-zero (only existing JSR operands are redirected;
; no inline bytes inserted in the main segment):
;
;   PART A  - weave unsolicited pongs through SIGN's SHA-512 / MODL gaps
;             so the relay keepalive never expires during a 1 MHz sign.
;   PART B  - pre-send liveness GATE: ping-probe the link right before
;             the frame goes out; optional self-calibrating DCD fast
;             path; if dead, SAVE the already-signed frame, reconnect,
;             and AUTO-RESEND it (no re-sign, no silent loss).
;
; Redirects applied by patch_sendfix.py:
;   JSR SHA_BLOCK            (SHA512 block loop)        -> PW_SHA   (A)
;   ldx IOFF : jsr LDCELL    (MODL LOOP1)               -> PW_LDC   (A)
;   JSR WS_SEND_EXT          (WS_SEND_MSG256 send site) -> MSG_SEND_GATE (B)
;
; Why safe mid-signature (briefing section 7): ACIA_SEND only polls TDRE
; and writes $DE00 (no IRQ/NMI - SIGN disables those), preserves A/X/Y,
; touches no signing zeropage. The pong/ping senders change only A, so X
; (=IOFF for LDCELL) and Y survive -> no PHA/PLA, crypto bit-identical.
; The liveness probe consumes NOTHING from the RX ring (it snapshots
; RING_HEAD and watches it advance), so WS_RECV_FRAME stays in sync.
;
; Depends on existing labels: ACIA_SEND, WD_ON, SHA_BLOCK, LDCELL,
;   WS_SEND_EXT, MC_CHAT_LOOP, PRINT_CHR, PRINT_STR_FB, RING_HEAD,
;   JOUT_BUF, JOUT_LEN, ACIA_INIT, FPGA_SETTLE, MODEM_DIAL,
;   WS_HANDSHAKE, INSTALL_RX_NMI, WS_AUTH_DISPATCH.
;
; ----------------------------------------------------------------
; PLACEMENT  (confirmed against the current build, baseline md5
;   f61567509681c4ba7d3a6eba419f8e35):
;   watchdog $B500-$B53F, PD_WRAP $B540-$B565. This block sits at $B580
;   (code ~$B580..$B6F0), then a 1280-byte frame-save buffer follows it
;   (ends well below the $C000 SHA tables). All under the banked-out
;   BASIC ROM where the watchdog/PD_WRAP already live. The patch appends
;   the !source at END of meshchat64.asm so this absolute segment comes
;   after the $B540 block and disturbs nothing.
; ================================================================

; ---- build switches -------------------------------------------------
USE_DCD     = 1            ; 1 = self-calibrating DCD fast path in LINK_ALIVE
                          ;     (records $DE01 bit5 when known-alive; a later
                          ;      change => fast "dead". If the FPGA holds bit5
                          ;      constant it never triggers -> identical to the
                          ;      probe-only path. Set 0 if you see false drops.)
DCD_BIT     = $20         ; $DE01 bit to watch (real 6551: bit5 = /DCD carrier)
LA_TICKS    = 15          ; probe timeout = LA_TICKS x 20 ms (15 = ~300 ms)

KSG_BASE    = $B580
        * = KSG_BASE

; ====================================================================
; PART A  -  keepalive pongs through the signing gaps
; ====================================================================

; ---- shared control-frame sender: A = opcode ($89 ping / $8A pong) --
; emits opcode + $80 (mask-bit, len 0) + WS_MASK. clobbers A; keeps X,Y.
CTRL_TX
        JSR ACIA_SEND               ; opcode (caller preloaded A)
        LDA #$80 : JSR ACIA_SEND    ; mask-bit set, payload length 0
        LDA #$37 : JSR ACIA_SEND    ; WS_MASK 0
        LDA #$FA : JSR ACIA_SEND    ; WS_MASK 1
        LDA #$21 : JSR ACIA_SEND    ; WS_MASK 2
        LDA #$3D : JSR ACIA_SEND    ; WS_MASK 3
        RTS

PONG_TX LDA #$8A : JMP CTRL_TX      ; unsolicited pong (FIN+pong 0x0A)
PING_TX LDA #$89 : JMP CTRL_TX      ; ping (FIN+ping 0x09) -> relay pongs back

; ---- redirect of: JSR SHA_BLOCK (covers both SHA-512 phases) --------
PW_SHA
        LDA WD_ON
        BEQ PWS_GO
        JSR PONG_TX                 ; X/Y preserved; SHA_BLOCK needs neither
PWS_GO
        JMP SHA_BLOCK               ; tail-call: its RTS returns to caller

; ---- redirect of: ldx IOFF : jsr LDCELL (MODL LOOP1, the bulk) ------
PW_LDC
        LDA WD_ON
        BEQ PWL_GO
        JSR PONG_TX                 ; X (=IOFF) survives PONG_TX
PWL_GO
        JMP LDCELL

; ====================================================================
; PART B  -  pre-send liveness gate + auto-resend
; ====================================================================

; ---- redirect of: JSR WS_SEND_EXT (WS_SEND_MSG256 send site) --------
MSG_SEND_GATE
        LDA WD_ON
        BEQ MSG_SEND_NOW           ; pre-connect/not armed -> just send
        JSR LINK_ALIVE             ; C=0 alive, C=1 dead
        BCC MSG_SEND_NOW           ; alive -> send the frame
        ; --- dead: keep the signed frame, warn, reconnect, resend ---
        JSR SAVE_FRAME             ; JOUT_BUF/LEN -> SAVE_BUF/LEN
        JSR PRINT_LINKLOST
        JMP RECON_RESEND
MSG_SEND_NOW
        JMP WS_SEND_EXT            ; reads JOUT_BUF / JOUT_LEN

; ---- LINK_ALIVE : is the ws link still up? -------------------------
; Optional DCD fast path, then a ping + ~300 ms ring-watch (consumes
; nothing). Clock-independent (CIA2), same timer discipline as
; RING_GET_TO. C=0 alive / C=1 dead.
LINK_ALIVE
!if USE_DCD = 1 {
        LDA DCD_VALID
        BEQ LA_PROBE               ; not calibrated yet -> probe & calibrate
        LDA $DE01
        AND #DCD_BIT
        CMP DCD_REF
        BEQ LA_PROBE               ; carrier unchanged -> confirm via probe
        SEC                        ; carrier changed vs known-alive -> dead
        RTS
LA_PROBE
}
        LDA RING_HEAD : STA LA_SNAP ; snapshot producer index
        LDA #$89 : JSR CTRL_TX     ; send ping (relay should pong)
        LDA #LA_TICKS : STA LA_RETRY
LA_ARM  LDA #$20 : STA $DD04       ; 20 ms = $4E20 cycles @1MHz (mirror ring)
        LDA #$4E : STA $DD05
        LDA #$19 : STA $DD0E       ; load latch + one-shot + start
LA_W    LDA RING_HEAD
        CMP LA_SNAP
        BNE LA_ALIVE               ; head moved -> RX arrived -> alive
        LDA $DD0D                  ; CIA2 ICR (clears flags; ISR never reads it)
        AND #$01                   ; Timer A underflow?
        BEQ LA_W                   ; no -> keep waiting this 20 ms slot
        DEC LA_RETRY
        BNE LA_ARM                 ; more slots -> re-arm
        SEC                        ; out of slots, no RX -> dead
        RTS
LA_ALIVE
!if USE_DCD = 1 {
        LDA $DE01                  ; calibrate: record alive carrier value
        AND #DCD_BIT
        STA DCD_REF
        LDA #1 : STA DCD_VALID
}
        CLC
        RTS

; ---- SAVE / RESTORE the already-built+signed outgoing frame --------
; The frame survives reconnect in SAVE_BUF; WS_AUTH rebuilds JOUT_BUF
; during re-auth, so we copy it out first and back in afterwards.
SAVE_FRAME
        LDA #<JOUT_BUF : STA $FB
        LDA #>JOUT_BUF : STA $FC
        LDA #<SAVE_BUF : STA $FD
        LDA #>SAVE_BUF : STA $FE
        JSR CP1280
        LDA JOUT_LEN+0 : STA SAVE_LEN+0
        LDA JOUT_LEN+1 : STA SAVE_LEN+1
        RTS
RESTORE_FRAME
        LDA #<SAVE_BUF : STA $FB
        LDA #>SAVE_BUF : STA $FC
        LDA #<JOUT_BUF : STA $FD
        LDA #>JOUT_BUF : STA $FE
        JSR CP1280
        LDA SAVE_LEN+0 : STA JOUT_LEN+0
        LDA SAVE_LEN+1 : STA JOUT_LEN+1
        RTS
; copy 1280 bytes ($FB/$FC) -> ($FD/$FE) ; clobbers A,X,Y + the pointers
CP1280
        LDX #5                     ; 5 x 256 = 1280 (= JOUT_BUF size, exact)
CP_PG   LDY #0
CP_BY   LDA ($FB),Y
        STA ($FD),Y
        INY
        BNE CP_BY
        INC $FC
        INC $FE
        DEX
        BNE CP_PG
        RTS

; ---- redial + re-auth, then restore the saved frame and resend -----
; Mirrors MC_RECONNECT (no clear-screen) but resends the signed frame.
RECON_RESEND
        LDX #$FF : TXS             ; reset stack (jump out of deep call stack)
        LDA #0 : STA DCD_VALID     ; recalibrate carrier after the new connect
        LDA #2 : STA $D020         ; red border during reconnect
        JSR ACIA_INIT
        JSR FPGA_SETTLE
        JSR MODEM_DIAL
        JSR WS_HANDSHAKE
        JSR INSTALL_RX_NMI
        JSR WS_AUTH_DISPATCH       ; (auth receives frames -> WD_ON back to 1)
        JSR RESTORE_FRAME          ; SAVE_BUF -> JOUT_BUF + JOUT_LEN
        JSR WS_SEND_EXT            ; resend the original signed frame
        LDA #5 : STA $D020
        JMP MC_CHAT_LOOP

; ---- clear, unmistakable "link lost" notice ------------------------
PRINT_LINKLOST
        LDA #$0D : JSR PRINT_CHR
        LDA #$1C : JSR PRINT_CHR    ; red
        LDA #<STR_LINKLOST : STA $FB
        LDA #>STR_LINKLOST : STA $FC
        JSR PRINT_STR_FB
        LDA #$0D : JSR PRINT_CHR
        LDA #$05 : JSR PRINT_CHR    ; back to white
        RTS

STR_LINKLOST
        !text "LINK LOST - RECONNECTING + RESENDING"
        !byte 0

; ---- free-RAM scratch + frame-save buffer --------------------------
LA_SNAP   !byte 0
LA_RETRY  !byte 0
DCD_REF   !byte 0
DCD_VALID !byte 0
SAVE_LEN  !byte 0,0
SAVE_BUF  = *               ; 1280-byte hold buffer (not emitted; runtime RAM)
                            ; lives just above this code, below $C000.

; ====================================================================
; OPTIONAL: hard-disable the DCD fast path by setting USE_DCD = 0 above.
; It is self-calibrating, so it cannot cause a false "dead" UNLESS the
; FPGA actually toggles $DE01 bit5 while the link is still up. If you
; observe spurious reconnects right after a send, set USE_DCD = 0 and
; the probe-only path remains as the safety net.
; ====================================================================
