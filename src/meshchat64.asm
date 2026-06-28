; ================================================================
; MeshChat64 - key derivation library
; PBKDF2-HMAC-SHA256 + HKDF on the Commodore 64
; ACME 0.97 assembler format
; ================================================================

* = $0801

        !byte $0C,$08,$0A,$00,$9E,$32,$30,$36,$31,$00,$00,$00  ; SYS 2061 stub (instead of !basic)

; ================================================================
; MAIN PROGRAM
; ================================================================

        ; disable CIA2 NMI - CIA2 Timer A is used for timing
        ; writing $DD0D with bit 7=0 clears all CIA2 interrupt masks
        ; --- bank out BASIC ROM: KERNAL+I/O stay, RAM up to $BFFF ---
        ; (app uses no BASIC; $00/$01 not touched anywhere else)
        LDA #$36
        STA $01

        LDA #$7F
        STA $DD0D               ; Bug 6 fix: no unwanted NMI from CIA2

        ; --- U64 turbo ON: full CPU speed (48/64 MHz) -------
        ; $D031 = speed index, $0F = max. Only effective if
        ; the U64 menu is in register-controlled turbo mode;
        ; otherwise a harmless no-op. Once set, the speed
        ; stays latched, even if I/O is banked out later.
        LDA #$0F
        STA $D031
        ; --- lock lower/upper-case charset (mode 2) ---
        LDA $D018
        ORA #$02
        STA $D018               ; select lowercase char ROM
        LDA #$80
        STA $0291               ; block C= +SHIFT charset toggle


        ; init ACIA FIRST (FPGA modem emulation requires this)
        LDA #3
        STA $D020
        JSR ACIA_INIT
        JSR FPGA_SETTLE         ; Bug 3 fix: 50ms real-time via CIA2

        ; 128-bit path removed: boot straight to 256-bit login.
        JSR MC_LOGIN

        ; initialise message counter for GCM nonce uniqueness
        LDA #0
        STA GCM_MSG_CTR+0
        STA GCM_MSG_CTR+1

        ; connect AFTER key derivation
        ; extra ACIA_INIT to refresh FPGA state after long computation
        LDA #5
        STA $D020
        JSR ACIA_INIT           ; <- extra reset (Bug 4 fix)
        JSR FPGA_SETTLE         ; Bug 3 fix: ~51ms settle after ACIA_INIT
        JSR MODEM_DIAL          ; Bug 5 fix: AT wake-up is now inside MODEM_DIAL
        LDA #7
        STA $D020
        JSR WS_HANDSHAKE
        LDA #1
        STA $D020

        ; draw the chat screen BEFORE connecting, so polling
        ; starts right after connect (like recvtest64). Otherwise
        ; the seen frames arrive during the slow screen draw
        ; and the ACIA (1-byte buffer) overflows -> RX breaks.
        JSR MC_CHAT_SCREEN

        ; install NMI-RX FIRST: the auth handshake must receive frames
        JSR INSTALL_RX_NMI

        ; new relay protocol (server.py HEAD): challenge-response auth
        ; instead of {"type":"connect"}. See WS_AUTH.
        JSR WS_AUTH_DISPATCH

        LDA #5
        STA $D020

        ; polling starts right after connect (screen already drawn)
        JSR MC_CHAT_LOOP
        JMP *

; ================================================================
; MC_HEADER - show title bar (40 chars, inverse)
; ================================================================
MC_HEADER
        LDA #$93        ; clear screen
        JSR PRINT_CHR
        LDA #$9F        ; cyan
        JSR PRINT_CHR
        LDA #$12        ; inverse on
        JSR PRINT_CHR
        LDA #<STR_TITLE
        STA $FB
        LDA #>STR_TITLE
        STA $FC
        JSR PRINT_STR_FB
        LDA #$92        ; inverse off
        JSR PRINT_CHR
        LDA #$0D
        JSR PRINT_CHR
        RTS

; ================================================================
; MC_LOGIN - input screen: name + passphrase + key derivation
; ================================================================
MC_LOGIN
        JSR MC_HEADER
        LDA #$0D
        JSR PRINT_CHR
        LDA #$0D
        JSR PRINT_CHR

        ; name input
        LDA #$9E        ; yellow
        JSR PRINT_CHR
        LDA #<STR_NAAM_P
        STA $FB
        LDA #>STR_NAAM_P
        STA $FC
        JSR PRINT_STR_FB
        LDA #$05        ; white
        JSR PRINT_CHR
        JSR INPUT_LINE

        ; copy to KDFIN_NAME
        LDX #0
ML_CN   LDA INP_BUF,X
        STA KDFIN_NAME,X
        BEQ ML_CNE
        INX
        CPX #32
        BNE ML_CN
ML_CNE  STX KDFIN_NAMELEN
        LDA #$0D
        JSR PRINT_CHR

        ; passphrase input
        LDA #$9E        ; yellow
        JSR PRINT_CHR
        LDA #<STR_PASS_P
        STA $FB
        LDA #>STR_PASS_P
        STA $FC
        JSR PRINT_STR_FB
        LDA #$05        ; wit
        JSR PRINT_CHR
        JSR INPUT_PASS

        ; copy to KDFIN_PASS
        LDX #0
ML_CP   LDA INP_BUF,X
        STA KDFIN_PASS,X
        BEQ ML_CPE
        INX
        CPX #64
        BNE ML_CP
ML_CPE  STX KDFIN_PASSLEN
        LDA #$0D
        JSR PRINT_CHR
        LDA #$0D
        JSR PRINT_CHR

        ; progress message
        LDA #$1C        ; red
        JSR PRINT_CHR
        LDA #<STR_BEZIG
        STA $FB
        LDA #>STR_BEZIG
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #<STR_WACHT
        STA $FB
        LDA #>STR_WACHT
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR

        ; border red = busy
        LDA #2
        STA $D020

        ; key derivation
        JSR DERIVE_KEYPAIR
        ; -- 256-bit identity: mode flag + cache signing seed --
        LDA #1
        STA USE_256
        JSR SETUP_SIGN_ID256

        ; border green = done
        LDA #5
        STA $D020

        ; compute user ID
        JSR COMPUTE_USER_ID
        JSR COMPUTE_C64_ID256  ; 256-bit publicId: SHA-256(encKey32)[0:12]
        JSR MC_PEER_SETUP256   ; contact shareable -> KEY_PEER256 + PEER_IDSTR (empty=self)


        ; done message
        LDA #$0D
        JSR PRINT_CHR
        LDA #$1E        ; green
        JSR PRINT_CHR
        LDA #<STR_KLAAR
        STA $FB
        LDA #>STR_KLAAR
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR

        ; wait for space
ML_SPC  JSR $FFE4
        BEQ ML_SPC
        CMP #$20
        BNE ML_SPC
        RTS

; ================================================================
; MC_SETUP - paste-encKey setup screen (login model level 2)
; asks for two base64url encKeys (22 chars; '_' = left-arrow key):
;   1) own encKey -> KEY_SELF (decrypt incoming + identity)
;   2) peer encKey  -> KEY_PEER (encrypt outgoing + 'to')
; derives: C64_IDSTR (own publicId), PEER_IDSTR ('to' field),
; KDFIN_NAME (prompt label = first 8 chars of own publicId).
; ================================================================
; ================================================================
; 128-bit MC_SETUP (paste path) + B64URL_DECODE22 22-char decode loop
; REMOVED (AES128 cleanup). Only reachable via the removed
; MC_BOOT_MENU -> dead. NOTE: the shared helpers B64D_ERR/B64D_CHAR
; (below) STAY - the live 256-bit shareable decoder uses them.
; Stub + pin keeps B64D_ERR (and MC_CHAT_SCREEN + watchdog hook after it)
; byte-identical.
; ================================================================
MC_SETUP
        RTS
* = $0B86                       ; pin: B64D_ERR at original address
B64D_ERR
        SEC
        RTS

; B64D_CHAR - look up ASCII char A in B64_TABLE -> 6-bit value
; C=0 + A=value; C=1 = invalid char. Clobbers Y.
B64D_CHAR
        LDY #0
B64C_LP CMP B64_TABLE,Y
        BEQ B64C_HIT
        INY
        CPY #64
        BNE B64C_LP
        SEC
        RTS
B64C_HIT
        TYA
        CLC
        RTS

; ================================================================
; MC_CHAT_SCREEN - show chat screen after login
; ================================================================
MC_CHAT_SCREEN
        JSR MC_HEADER

        ; show ID
        LDA #$9E        ; yellow
        JSR PRINT_CHR
        LDA #<STR_ID_LBL
        STA $FB
        LDA #>STR_ID_LBL
        STA $FC
        JSR PRINT_STR_FB
        LDA #$05        ; wit
        JSR PRINT_CHR

        ; own publicId (16 base64url chars)
        LDA #<C64_IDSTR
        STA $FB
        LDA #>C64_IDSTR
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR

        JSR SHOW_SHAREABLE  ; show own shareable (256-bit only)

        ; divider
        LDA #<STR_DIV
        STA $FB
        LDA #>STR_DIV
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #$0D
        JSR PRINT_CHR
        RTS

; ================================================================
; MC_CHAT_LOOP - main chat loop
; ================================================================
MC_CHAT_LOOP
MCL_TOP
        ; show "NAME> " prompt
        LDA #$1E        ; green
        JSR PRINT_CHR
        LDX #0
MCL_NM  LDA KDFIN_NAME,X
        BEQ MCL_NME
        JSR PRINT_CHR
        INX
        BNE MCL_NM
MCL_NME
        LDA #<STR_PFX
        STA $FB
        LDA #>STR_PFX
        STA $FC
        JSR PRINT_STR_FB
        LDA #$05        ; wit
        JSR PRINT_CHR

        ; read message (INPUT_LINE converts PETSCII->ASCII: item 10A)
        JSR INPUT_LINE

        ; skip empty line
        LDA INP_LEN
        BEQ MCL_TOP

        ; new line after message
        LDA #$0D
        JSR PRINT_CHR

        ; encrypt and send via WebSocket (AES-128-GCM)
        JSR WS_SEND_DISPATCH
        LDA #1
        STA $D020           ; white = send done

        JMP MCL_TOP

INPUT_LINE
        LDX #0
IL_LOOP TXA
        PHA             ; save X on stack
        JSR $FFE4       ; A = toets, X/Y geclobberd
        TAY             ; save char in Y
        PLA             ; restore X from stack
        TAX
        TYA             ; A = char back
        BNE IL_GOTKEY
        JSR MRP_WD          ; net-zero wrapper: poll + watchdog
        JMP IL_LOOP
IL_GOTKEY
        CMP #$0D
        BEQ IL_DONE
        CMP #$14
        BEQ IL_DEL
        JSR KEY_TO_ASCII    ; PETSCII -> ASCII (lower/upper): mixed-case name/message
        CPX #200             ; send limit 200 chars (was 40)
        BEQ IL_LOOP
        STA INP_BUF,X
        INX
        JSR PRINT_CHR
        JMP IL_LOOP
IL_DEL  CPX #0
        BEQ IL_LOOP
        DEX
        LDA #$14
        JSR PRINT_CHR
        JMP IL_LOOP
IL_DONE LDA #0
        STA INP_BUF,X
        STX INP_LEN
        RTS

INPUT_PASS
        LDX #0
IP_LOOP TXA
        PHA
        JSR $FFE4
        TAY
        PLA
        TAX
        TYA
        BEQ IP_LOOP
        CMP #$0D
        BEQ IP_DONE
        CMP #$14
        BEQ IP_DEL
        JSR KEY_TO_ASCII    ; PETSCII -> ASCII: mixed-case passphrase (case-sensitive)
        CPX #64
        BEQ IP_LOOP
        STA INP_BUF,X
        INX
        LDA #$2A
        JSR PRINT_CHR
        JMP IP_LOOP
IP_DEL  CPX #0
        BEQ IP_LOOP
        DEX
        LDA #$14
        JSR PRINT_CHR
        JMP IP_LOOP
IP_DONE LDA #0
        STA INP_BUF,X
        STX INP_LEN
        RTS

; ================================================================
; KEY_TO_ASCII - C64 keyboard PETSCII -> ASCII (letters only)
; Item 10A: allow typing/sending lowercase letters.
; In : A = char from $FFE4 (GETIN)
; Out: A = ASCII; X and Y are preserved
;   $41-$5A (unshifted) -> $61-$7A  lowercase
;   $C1-$DA (with SHIFT)  -> $41-$5A  uppercase
; Everything else (digits, punctuation, $0D, $14, colour/control codes)
; passes through unchanged, so control/colour codes stay intact.
; ================================================================
KEY_TO_ASCII
        CMP #$85            ; F1 -> '{'  (C64 mist {}-toetsen)
        BNE KTA_NF3
        LDA #$7B
        RTS
KTA_NF3 CMP #$86            ; F3 -> '}'
        BNE KTA_NCURLY
        LDA #$7D
        RTS
KTA_NCURLY
        CMP #$41
        BCC KTA_DONE        ; < $41: leave untouched
        CMP #$5B
        BCC KTA_LOWER       ; $41-$5A: unshifted -> lowercase
        CMP #$C1
        BCC KTA_DONE        ; $5B-$C0: leave untouched
        CMP #$DB
        BCS KTA_DONE        ; >= $DB: leave untouched
        SEC                 ; $C1-$DA: SHIFT -> uppercase
        SBC #$80
        RTS
KTA_LOWER
        CLC
        ADC #$20
KTA_DONE
        RTS

; ================================================================
; PRINT_STR_FB - print null-terminated string via $FB/$FC
; ================================================================
; ================================================================
; PRINT_CHR - CHROUT with ASCII->PETSCII case correction (mode 2)
; Letters A-Z/a-z: flip bit $20 so they show with the correct case
; in the lower/upper-case charset; control codes stay intact.
; ================================================================
PRINT_CHR
        CMP #$41
        BCC PC_OUT          ; < 'A'
        CMP #$5B
        BCC PC_FLIP         ; 'A'-'Z'
        CMP #$61
        BCC PC_OUT          ; between 'Z' and 'a'
        CMP #$7B
        BCS PC_OUT          ; > 'z'
PC_FLIP EOR #$20
PC_OUT  JMP $FFD2


PRINT_STR_FB
        LDY #0
PSF_LP  LDA ($FB),Y
        BEQ PSF_DN
        JSR PRINT_CHR
        INY
        BNE PSF_LP
PSF_DN  RTS

; 16-bit variant (>255 chars): increments $FB/$FC
PRINT_STR16
PS16_LP LDY #0
        LDA ($FB),Y
        BEQ PS16_DN
        JSR PRINT_CHR
        INC $FB
        BNE PS16_LP
        INC $FC
        JMP PS16_LP
PS16_DN RTS

; ================================================================
; NIBBLE_PET - nibble to PETSCII hex char
; ================================================================
NIBBLE_PET
        CMP #10
        BCC NPT_DIG
        CLC
        ADC #$37        ; A=$41 t/m F=$46
        RTS
NPT_DIG ORA #$30        ; 0=$30 t/m 9=$39
        RTS

; ================================================================
; PRINT_HEX_PET - byte as 2 PETSCII hex chars via CHROUT
; ================================================================
PRINT_HEX_PET
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR NIBBLE_PET
        JSR PRINT_CHR
        PLA
        AND #$0F
        JSR NIBBLE_PET
        JSR PRINT_CHR
        RTS

DBG_SHOW
        JSR PRINT_CHR           ; print label char (A = char from caller, e.g. 'N')
        LDA $FB             ; store only now - still intact after $FFD2
        STA DBG_LO
        LDA $FC
        STA DBG_HI
        LDA #$3A
        JSR PRINT_CHR           ; ':'
        LDA #$20
        JSR PRINT_CHR           ; ' '
        LDA #$00
        STA DBG_IDX
DBG_LP  LDA DBG_LO
        STA $FB
        LDA DBG_HI
        STA $FC
        LDY DBG_IDX
        LDA ($FB),Y
        JSR PRINT_HEX_PET
        LDA #$20
        JSR PRINT_CHR
        INC DBG_IDX
        LDA DBG_IDX
        CMP #8
        BNE DBG_LP
        LDA #$0D
        JSR PRINT_CHR
        RTS

; ================================================================
; TEST_DERIVE_TIMING - estimate time for a full run
; ================================================================
TEST_DERIVE_TIMING
        LDX #0
TDT_WL  LDA #$00
        STA PBKDF2_PWD,X
        INX
        CPX #64
        BNE TDT_WL
        LDA #$74
        STA PBKDF2_PWD+0
        LDA #$65
        STA PBKDF2_PWD+1
        LDA #$73
        STA PBKDF2_PWD+2
        LDA #$74
        STA PBKDF2_PWD+3
        LDA #4
        STA PBKDF2_PWDLEN
        LDA #$73
        STA PBKDF2_SALT+0
        LDA #$61
        STA PBKDF2_SALT+1
        LDA #$6c
        STA PBKDF2_SALT+2
        LDA #$74
        STA PBKDF2_SALT+3
        LDA #4
        STA PBKDF2_SALTLEN
        LDA #100
        STA PBKDF2_ITRLO
        LDA #0
        STA PBKDF2_ITRMID
        STA PBKDF2_ITRHI
        LDA #0
        STA $A0
        STA $A1
        STA $A2
        LDA #2
        STA $D020
        JSR PBKDF2
        LDA $A0
        STA ELAPSED+0
        LDA $A1
        STA ELAPSED+1
        LDA $A2
        STA ELAPSED+2
        LDA #1
        STA $D020
        RTS

; ================================================================
; TEST_DERIVE - full key derivation
; ================================================================
TEST_DERIVE
        LDX #0
TD_WL   LDA #$00
        STA KDFIN_NAME,X
        STA KDFIN_PASS,X
        INX
        CPX #64
        BNE TD_WL
        LDA #$41
        STA KDFIN_NAME+0
        LDA #$6c
        STA KDFIN_NAME+1
        LDA #$69
        STA KDFIN_NAME+2
        LDA #$63
        STA KDFIN_NAME+3
        LDA #$65
        STA KDFIN_NAME+4
        LDA #5
        STA KDFIN_NAMELEN
        LDA #$67
        STA KDFIN_PASS+0
        LDA #$65
        STA KDFIN_PASS+1
        LDA #$68
        STA KDFIN_PASS+2
        LDA #$65
        STA KDFIN_PASS+3
        LDA #$69
        STA KDFIN_PASS+4
        LDA #$6d
        STA KDFIN_PASS+5
        LDA #6
        STA KDFIN_PASSLEN
        LDA #0
        STA $A0
        STA $A1
        STA $A2
        LDA #2
        STA $D020
        JSR DERIVE_KEYPAIR
        LDA $A0
        STA ELAPSED+0
        LDA $A1
        STA ELAPSED+1
        LDA $A2
        STA ELAPSED+2
        LDA #5
        STA $D020
        JSR SHOW_USER_ID
        RTS

; ================================================================
; 64-BIT MATH LIBRARY
; ================================================================

ADD64
        CLC
        LDA OPER_A+0
        ADC OPER_B+0
        STA OPER_A+0
        LDA OPER_A+1
        ADC OPER_B+1
        STA OPER_A+1
        LDA OPER_A+2
        ADC OPER_B+2
        STA OPER_A+2
        LDA OPER_A+3
        ADC OPER_B+3
        STA OPER_A+3
        LDA OPER_A+4
        ADC OPER_B+4
        STA OPER_A+4
        LDA OPER_A+5
        ADC OPER_B+5
        STA OPER_A+5
        LDA OPER_A+6
        ADC OPER_B+6
        STA OPER_A+6
        LDA OPER_A+7
        ADC OPER_B+7
        STA OPER_A+7
        RTS

SUB64
        SEC
        LDA OPER_A+0
        SBC OPER_B+0
        STA OPER_A+0
        LDA OPER_A+1
        SBC OPER_B+1
        STA OPER_A+1
        LDA OPER_A+2
        SBC OPER_B+2
        STA OPER_A+2
        LDA OPER_A+3
        SBC OPER_B+3
        STA OPER_A+3
        LDA OPER_A+4
        SBC OPER_B+4
        STA OPER_A+4
        LDA OPER_A+5
        SBC OPER_B+5
        STA OPER_A+5
        LDA OPER_A+6
        SBC OPER_B+6
        STA OPER_A+6
        LDA OPER_A+7
        SBC OPER_B+7
        STA OPER_A+7
        RTS

SHL64
        ASL OPER_A+0
        ROL OPER_A+1
        ROL OPER_A+2
        ROL OPER_A+3
        ROL OPER_A+4
        ROL OPER_A+5
        ROL OPER_A+6
        ROL OPER_A+7
        RTS

SHR64
        LSR OPER_A+7
        ROR OPER_A+6
        ROR OPER_A+5
        ROR OPER_A+4
        ROR OPER_A+3
        ROR OPER_A+2
        ROR OPER_A+1
        ROR OPER_A+0
        RTS

CMP64
        LDA OPER_A+7
        CMP OPER_B+7
        BNE CMP64DONE
        LDA OPER_A+6
        CMP OPER_B+6
        BNE CMP64DONE
        LDA OPER_A+5
        CMP OPER_B+5
        BNE CMP64DONE
        LDA OPER_A+4
        CMP OPER_B+4
        BNE CMP64DONE
        LDA OPER_A+3
        CMP OPER_B+3
        BNE CMP64DONE
        LDA OPER_A+2
        CMP OPER_B+2
        BNE CMP64DONE
        LDA OPER_A+1
        CMP OPER_B+1
        BNE CMP64DONE
        LDA OPER_A+0
        CMP OPER_B+0
CMP64DONE
        RTS

CPY64
        LDA OPER_A+0
        STA OPER_B+0
        LDA OPER_A+1
        STA OPER_B+1
        LDA OPER_A+2
        STA OPER_B+2
        LDA OPER_A+3
        STA OPER_B+3
        LDA OPER_A+4
        STA OPER_B+4
        LDA OPER_A+5
        STA OPER_B+5
        LDA OPER_A+6
        STA OPER_B+6
        LDA OPER_A+7
        STA OPER_B+7
        RTS

ADD_A_TO_C
        CLC
        LDA OPER_A+0
        ADC OPER_C+0
        STA OPER_C+0
        LDA OPER_A+1
        ADC OPER_C+1
        STA OPER_C+1
        LDA OPER_A+2
        ADC OPER_C+2
        STA OPER_C+2
        LDA OPER_A+3
        ADC OPER_C+3
        STA OPER_C+3
        LDA OPER_A+4
        ADC OPER_C+4
        STA OPER_C+4
        LDA OPER_A+5
        ADC OPER_C+5
        STA OPER_C+5
        LDA OPER_A+6
        ADC OPER_C+6
        STA OPER_C+6
        LDA OPER_A+7
        ADC OPER_C+7
        STA OPER_C+7
        RTS

SHL_OPERA
        ASL OPER_A+0
        ROL OPER_A+1
        ROL OPER_A+2
        ROL OPER_A+3
        ROL OPER_A+4
        ROL OPER_A+5
        ROL OPER_A+6
        ROL OPER_A+7
        RTS

MUL64
        LDA #0
        STA OPER_C+0
        STA OPER_C+1
        STA OPER_C+2
        STA OPER_C+3
        STA OPER_C+4
        STA OPER_C+5
        STA OPER_C+6
        STA OPER_C+7
        LSR OPER_B+0
        BCC MB00
        JSR ADD_A_TO_C
MB00    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB01
        JSR ADD_A_TO_C
MB01    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB02
        JSR ADD_A_TO_C
MB02    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB03
        JSR ADD_A_TO_C
MB03    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB04
        JSR ADD_A_TO_C
MB04    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB05
        JSR ADD_A_TO_C
MB05    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB06
        JSR ADD_A_TO_C
MB06    JSR SHL_OPERA
        LSR OPER_B+0
        BCC MB07
        JSR ADD_A_TO_C
MB07    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB08
        JSR ADD_A_TO_C
MB08    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB09
        JSR ADD_A_TO_C
MB09    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB10
        JSR ADD_A_TO_C
MB10    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB11
        JSR ADD_A_TO_C
MB11    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB12
        JSR ADD_A_TO_C
MB12    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB13
        JSR ADD_A_TO_C
MB13    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB14
        JSR ADD_A_TO_C
MB14    JSR SHL_OPERA
        LSR OPER_B+1
        BCC MB15
        JSR ADD_A_TO_C
MB15    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB16
        JSR ADD_A_TO_C
MB16    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB17
        JSR ADD_A_TO_C
MB17    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB18
        JSR ADD_A_TO_C
MB18    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB19
        JSR ADD_A_TO_C
MB19    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB20
        JSR ADD_A_TO_C
MB20    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB21
        JSR ADD_A_TO_C
MB21    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB22
        JSR ADD_A_TO_C
MB22    JSR SHL_OPERA
        LSR OPER_B+2
        BCC MB23
        JSR ADD_A_TO_C
MB23    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB24
        JSR ADD_A_TO_C
MB24    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB25
        JSR ADD_A_TO_C
MB25    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB26
        JSR ADD_A_TO_C
MB26    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB27
        JSR ADD_A_TO_C
MB27    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB28
        JSR ADD_A_TO_C
MB28    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB29
        JSR ADD_A_TO_C
MB29    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB30
        JSR ADD_A_TO_C
MB30    JSR SHL_OPERA
        LSR OPER_B+3
        BCC MB31
        JSR ADD_A_TO_C
MB31    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB32
        JSR ADD_A_TO_C
MB32    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB33
        JSR ADD_A_TO_C
MB33    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB34
        JSR ADD_A_TO_C
MB34    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB35
        JSR ADD_A_TO_C
MB35    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB36
        JSR ADD_A_TO_C
MB36    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB37
        JSR ADD_A_TO_C
MB37    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB38
        JSR ADD_A_TO_C
MB38    JSR SHL_OPERA
        LSR OPER_B+4
        BCC MB39
        JSR ADD_A_TO_C
MB39    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB40
        JSR ADD_A_TO_C
MB40    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB41
        JSR ADD_A_TO_C
MB41    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB42
        JSR ADD_A_TO_C
MB42    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB43
        JSR ADD_A_TO_C
MB43    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB44
        JSR ADD_A_TO_C
MB44    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB45
        JSR ADD_A_TO_C
MB45    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB46
        JSR ADD_A_TO_C
MB46    JSR SHL_OPERA
        LSR OPER_B+5
        BCC MB47
        JSR ADD_A_TO_C
MB47    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB48
        JSR ADD_A_TO_C
MB48    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB49
        JSR ADD_A_TO_C
MB49    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB50
        JSR ADD_A_TO_C
MB50    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB51
        JSR ADD_A_TO_C
MB51    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB52
        JSR ADD_A_TO_C
MB52    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB53
        JSR ADD_A_TO_C
MB53    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB54
        JSR ADD_A_TO_C
MB54    JSR SHL_OPERA
        LSR OPER_B+6
        BCC MB55
        JSR ADD_A_TO_C
MB55    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB56
        JSR ADD_A_TO_C
MB56    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB57
        JSR ADD_A_TO_C
MB57    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB58
        JSR ADD_A_TO_C
MB58    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB59
        JSR ADD_A_TO_C
MB59    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB60
        JSR ADD_A_TO_C
MB60    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB61
        JSR ADD_A_TO_C
MB61    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB62
        JSR ADD_A_TO_C
MB62    JSR SHL_OPERA
        LSR OPER_B+7
        BCC MB63
        JSR ADD_A_TO_C
MB63    RTS

; ================================================================
; 32-BIT OPERATIES
; ================================================================

XOR32
        LDA WORD_A+0
        EOR WORD_B+0
        STA WORD_A+0
        LDA WORD_A+1
        EOR WORD_B+1
        STA WORD_A+1
        LDA WORD_A+2
        EOR WORD_B+2
        STA WORD_A+2
        LDA WORD_A+3
        EOR WORD_B+3
        STA WORD_A+3
        RTS

AND32
        LDA WORD_A+0
        AND WORD_B+0
        STA WORD_A+0
        LDA WORD_A+1
        AND WORD_B+1
        STA WORD_A+1
        LDA WORD_A+2
        AND WORD_B+2
        STA WORD_A+2
        LDA WORD_A+3
        AND WORD_B+3
        STA WORD_A+3
        RTS

NOT32
        LDA WORD_A+0
        EOR #$FF
        STA WORD_A+0
        LDA WORD_A+1
        EOR #$FF
        STA WORD_A+1
        LDA WORD_A+2
        EOR #$FF
        STA WORD_A+2
        LDA WORD_A+3
        EOR #$FF
        STA WORD_A+3
        RTS

ADD32
        CLC
        LDA WORD_A+0
        ADC WORD_B+0
        STA WORD_A+0
        LDA WORD_A+1
        ADC WORD_B+1
        STA WORD_A+1
        LDA WORD_A+2
        ADC WORD_B+2
        STA WORD_A+2
        LDA WORD_A+3
        ADC WORD_B+3
        STA WORD_A+3
        RTS

; ================================================================
; ROTATIES
; ================================================================

ROTR1
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        BCC ROTR1DONE
        LDA WORD_A+3
        ORA #$80
        STA WORD_A+3
ROTR1DONE
        RTS

ROTL1
        ASL WORD_A+0
        ROL WORD_A+1
        ROL WORD_A+2
        ROL WORD_A+3
        BCC ROTL1DONE
        LDA WORD_A+0
        ORA #$01
        STA WORD_A+0
ROTL1DONE
        RTS

ROTR8
        LDA WORD_A+0
        LDX WORD_A+1
        STX WORD_A+0
        LDX WORD_A+2
        STX WORD_A+1
        LDX WORD_A+3
        STX WORD_A+2
        STA WORD_A+3
        RTS

ROTR16
        LDA WORD_A+0
        LDX WORD_A+2
        STX WORD_A+0
        STA WORD_A+2
        LDA WORD_A+1
        LDX WORD_A+3
        STX WORD_A+1
        STA WORD_A+3
        RTS

ROTR2
        JSR ROTR1
        JSR ROTR1
        RTS

ROTR6
        JSR ROTR8
        JSR ROTL1
        JSR ROTL1
        RTS

ROTR7
        JSR ROTR8
        JSR ROTL1
        RTS

ROTR11
        JSR ROTR8
        JSR ROTR1
        JSR ROTR1
        JSR ROTR1
        RTS

ROTR13
        JSR ROTR8
        JSR ROTR1
        JSR ROTR1
        JSR ROTR1
        JSR ROTR1
        JSR ROTR1
        RTS

ROTR17
        JSR ROTR16
        JSR ROTR1
        RTS

ROTR18
        JSR ROTR16
        JSR ROTR1
        JSR ROTR1
        RTS

ROTR19
        JSR ROTR16
        JSR ROTR1
        JSR ROTR1
        JSR ROTR1
        RTS

ROTR22
        JSR ROTR16
        JSR ROTR6
        RTS

ROTR25
        JSR ROTR16
        JSR ROTR8
        JSR ROTR1
        RTS

; ================================================================
; SHA-256 HULPROUTINES
; ================================================================

SAVEWA
        LDA WORD_A+0
        STA SIGMA_T+0
        LDA WORD_A+1
        STA SIGMA_T+1
        LDA WORD_A+2
        STA SIGMA_T+2
        LDA WORD_A+3
        STA SIGMA_T+3
        RTS

SAVEWB
        LDA WORD_A+0
        STA SIGMA_U+0
        LDA WORD_A+1
        STA SIGMA_U+1
        LDA WORD_A+2
        STA SIGMA_U+2
        LDA WORD_A+3
        STA SIGMA_U+3
        RTS

RESTORET
        LDA SIGMA_T+0
        STA WORD_A+0
        LDA SIGMA_T+1
        STA WORD_A+1
        LDA SIGMA_T+2
        STA WORD_A+2
        LDA SIGMA_T+3
        STA WORD_A+3
        RTS

XORWBU
        LDA WORD_A+0
        EOR SIGMA_U+0
        STA WORD_A+0
        LDA WORD_A+1
        EOR SIGMA_U+1
        STA WORD_A+1
        LDA WORD_A+2
        EOR SIGMA_U+2
        STA WORD_A+2
        LDA WORD_A+3
        EOR SIGMA_U+3
        STA WORD_A+3
        RTS

S0
        JSR SAVEWA
        JSR ROTR7
        JSR SAVEWB
        JSR RESTORET
        JSR ROTR18
        JSR XORWBU
        JSR SAVEWB
        JSR RESTORET
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        JSR XORWBU
        RTS

S1
        JSR SAVEWA
        JSR ROTR17
        JSR SAVEWB
        JSR RESTORET
        JSR ROTR19
        JSR XORWBU
        JSR SAVEWB
        JSR RESTORET
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        LSR WORD_A+3
        ROR WORD_A+2
        ROR WORD_A+1
        ROR WORD_A+0
        JSR XORWBU
        RTS

BIGS0
        JSR SAVEWA
        JSR ROTR2
        JSR SAVEWB
        JSR RESTORET
        JSR ROTR13
        JSR XORWBU
        JSR SAVEWB
        JSR RESTORET
        JSR ROTR22
        JSR XORWBU
        RTS

BIGS1
        JSR SAVEWA
        JSR ROTR6
        JSR SAVEWB
        JSR RESTORET
        JSR ROTR11
        JSR XORWBU
        JSR SAVEWB
        JSR RESTORET
        JSR ROTR25
        JSR XORWBU
        RTS

CH
        LDA SHA_E+0
        AND SHA_F+0
        STA WORD_A+0
        LDA SHA_E+1
        AND SHA_F+1
        STA WORD_A+1
        LDA SHA_E+2
        AND SHA_F+2
        STA WORD_A+2
        LDA SHA_E+3
        AND SHA_F+3
        STA WORD_A+3
        JSR SAVEWB
        LDA SHA_E+0
        EOR #$FF
        AND SHA_G+0
        STA WORD_A+0
        LDA SHA_E+1
        EOR #$FF
        AND SHA_G+1
        STA WORD_A+1
        LDA SHA_E+2
        EOR #$FF
        AND SHA_G+2
        STA WORD_A+2
        LDA SHA_E+3
        EOR #$FF
        AND SHA_G+3
        STA WORD_A+3
        JSR XORWBU
        RTS

MAJ
        LDA SHA_A+0
        AND SHA_B+0
        STA WORD_A+0
        LDA SHA_A+1
        AND SHA_B+1
        STA WORD_A+1
        LDA SHA_A+2
        AND SHA_B+2
        STA WORD_A+2
        LDA SHA_A+3
        AND SHA_B+3
        STA WORD_A+3
        JSR SAVEWB
        LDA SHA_A+0
        AND SHA_C+0
        STA WORD_A+0
        LDA SHA_A+1
        AND SHA_C+1
        STA WORD_A+1
        LDA SHA_A+2
        AND SHA_C+2
        STA WORD_A+2
        LDA SHA_A+3
        AND SHA_C+3
        STA WORD_A+3
        JSR XORWBU
        JSR SAVEWB
        LDA SHA_B+0
        AND SHA_C+0
        STA WORD_A+0
        LDA SHA_B+1
        AND SHA_C+1
        STA WORD_A+1
        LDA SHA_B+2
        AND SHA_C+2
        STA WORD_A+2
        LDA SHA_B+3
        AND SHA_C+3
        STA WORD_A+3
        JSR XORWBU
        RTS

; ================================================================
; SHA-256 KERN
; ================================================================

LOADK
        TYA
        ASL
        ASL
        TAY
        LDA SHA_K+0,Y
        STA WORD_B+3
        LDA SHA_K+1,Y
        STA WORD_B+2
        LDA SHA_K+2,Y
        STA WORD_B+1
        LDA SHA_K+3,Y
        STA WORD_B+0
        RTS

LOADW
        TYA
        ASL
        ASL
        TAY
        LDA SHA_W+0,Y
        STA WORD_A+3
        LDA SHA_W+1,Y
        STA WORD_A+2
        LDA SHA_W+2,Y
        STA WORD_A+1
        LDA SHA_W+3,Y
        STA WORD_A+0
        RTS

STOREW
        TYA
        ASL
        ASL
        TAY
        LDA WORD_A+3
        STA SHA_W+0,Y
        LDA WORD_A+2
        STA SHA_W+1,Y
        LDA WORD_A+1
        STA SHA_W+2,Y
        LDA WORD_A+0
        STA SHA_W+3,Y
        RTS

SHA_EXPAND
        LDX #$00
EXPLOOP1
        LDA SHA_BLK,X
        STA SHA_W,X
        INX
        CPX #$40
        BNE EXPLOOP1
        LDY #16
        STY SHA_YNDX
EXPLOOP2
        LDY SHA_YNDX
        DEY
        DEY
        JSR LOADW
        LDY SHA_YNDX
        JSR S1
        LDA WORD_A+0
        STA EXPAND_T+0
        LDA WORD_A+1
        STA EXPAND_T+1
        LDA WORD_A+2
        STA EXPAND_T+2
        LDA WORD_A+3
        STA EXPAND_T+3
        LDY SHA_YNDX
        TYA
        SEC
        SBC #7
        TAY
        JSR LOADW
        CLC
        LDA WORD_A+0
        ADC EXPAND_T+0
        STA EXPAND_T+0
        LDA WORD_A+1
        ADC EXPAND_T+1
        STA EXPAND_T+1
        LDA WORD_A+2
        ADC EXPAND_T+2
        STA EXPAND_T+2
        LDA WORD_A+3
        ADC EXPAND_T+3
        STA EXPAND_T+3
        LDY SHA_YNDX
        TYA
        SEC
        SBC #15
        TAY
        JSR LOADW
        LDY SHA_YNDX
        JSR S0
        CLC
        LDA WORD_A+0
        ADC EXPAND_T+0
        STA EXPAND_T+0
        LDA WORD_A+1
        ADC EXPAND_T+1
        STA EXPAND_T+1
        LDA WORD_A+2
        ADC EXPAND_T+2
        STA EXPAND_T+2
        LDA WORD_A+3
        ADC EXPAND_T+3
        STA EXPAND_T+3
        LDY SHA_YNDX
        TYA
        SEC
        SBC #16
        TAY
        JSR LOADW
        CLC
        LDA WORD_A+0
        ADC EXPAND_T+0
        STA WORD_A+0
        LDA WORD_A+1
        ADC EXPAND_T+1
        STA WORD_A+1
        LDA WORD_A+2
        ADC EXPAND_T+2
        STA WORD_A+2
        LDA WORD_A+3
        ADC EXPAND_T+3
        STA WORD_A+3
        LDY SHA_YNDX
        JSR STOREW
        LDY SHA_YNDX
        INY
        CPY #64
        BEQ EXPDONE
        STY SHA_YNDX
        JMP EXPLOOP2
EXPDONE
        RTS

SHA_INIT
        LDA #$67
        STA SHA_H0+0
        LDA #$e6
        STA SHA_H0+1
        LDA #$09
        STA SHA_H0+2
        LDA #$6a
        STA SHA_H0+3
        LDA #$85
        STA SHA_H1+0
        LDA #$ae
        STA SHA_H1+1
        LDA #$67
        STA SHA_H1+2
        LDA #$bb
        STA SHA_H1+3
        LDA #$72
        STA SHA_H2+0
        LDA #$f3
        STA SHA_H2+1
        LDA #$6e
        STA SHA_H2+2
        LDA #$3c
        STA SHA_H2+3
        LDA #$3a
        STA SHA_H3+0
        LDA #$f5
        STA SHA_H3+1
        LDA #$4f
        STA SHA_H3+2
        LDA #$a5
        STA SHA_H3+3
        LDA #$7f
        STA SHA_H4+0
        LDA #$52
        STA SHA_H4+1
        LDA #$0e
        STA SHA_H4+2
        LDA #$51
        STA SHA_H4+3
        LDA #$8c
        STA SHA_H5+0
        LDA #$68
        STA SHA_H5+1
        LDA #$05
        STA SHA_H5+2
        LDA #$9b
        STA SHA_H5+3
        LDA #$ab
        STA SHA_H6+0
        LDA #$d9
        STA SHA_H6+1
        LDA #$83
        STA SHA_H6+2
        LDA #$1f
        STA SHA_H6+3
        LDA #$19
        STA SHA_H7+0
        LDA #$cd
        STA SHA_H7+1
        LDA #$e0
        STA SHA_H7+2
        LDA #$5b
        STA SHA_H7+3
        RTS

SHA_COMPRESS
        LDA SHA_H0+0
        STA SHA_A+0
        LDA SHA_H0+1
        STA SHA_A+1
        LDA SHA_H0+2
        STA SHA_A+2
        LDA SHA_H0+3
        STA SHA_A+3
        LDA SHA_H1+0
        STA SHA_B+0
        LDA SHA_H1+1
        STA SHA_B+1
        LDA SHA_H1+2
        STA SHA_B+2
        LDA SHA_H1+3
        STA SHA_B+3
        LDA SHA_H2+0
        STA SHA_C+0
        LDA SHA_H2+1
        STA SHA_C+1
        LDA SHA_H2+2
        STA SHA_C+2
        LDA SHA_H2+3
        STA SHA_C+3
        LDA SHA_H3+0
        STA SHA_D+0
        LDA SHA_H3+1
        STA SHA_D+1
        LDA SHA_H3+2
        STA SHA_D+2
        LDA SHA_H3+3
        STA SHA_D+3
        LDA SHA_H4+0
        STA SHA_E+0
        LDA SHA_H4+1
        STA SHA_E+1
        LDA SHA_H4+2
        STA SHA_E+2
        LDA SHA_H4+3
        STA SHA_E+3
        LDA SHA_H5+0
        STA SHA_F+0
        LDA SHA_H5+1
        STA SHA_F+1
        LDA SHA_H5+2
        STA SHA_F+2
        LDA SHA_H5+3
        STA SHA_F+3
        LDA SHA_H6+0
        STA SHA_G+0
        LDA SHA_H6+1
        STA SHA_G+1
        LDA SHA_H6+2
        STA SHA_G+2
        LDA SHA_H6+3
        STA SHA_G+3
        LDA SHA_H7+0
        STA SHA_HH+0
        LDA SHA_H7+1
        STA SHA_HH+1
        LDA SHA_H7+2
        STA SHA_HH+2
        LDA SHA_H7+3
        STA SHA_HH+3
        LDY #0
        STY SHA_YNDX
CMPLOOP
        LDA SHA_HH+0
        STA T1+0
        LDA SHA_HH+1
        STA T1+1
        LDA SHA_HH+2
        STA T1+2
        LDA SHA_HH+3
        STA T1+3
        LDA SHA_E+0
        STA WORD_A+0
        LDA SHA_E+1
        STA WORD_A+1
        LDA SHA_E+2
        STA WORD_A+2
        LDA SHA_E+3
        STA WORD_A+3
        JSR BIGS1
        CLC
        LDA T1+0
        ADC WORD_A+0
        STA T1+0
        LDA T1+1
        ADC WORD_A+1
        STA T1+1
        LDA T1+2
        ADC WORD_A+2
        STA T1+2
        LDA T1+3
        ADC WORD_A+3
        STA T1+3
        JSR CH
        CLC
        LDA T1+0
        ADC WORD_A+0
        STA T1+0
        LDA T1+1
        ADC WORD_A+1
        STA T1+1
        LDA T1+2
        ADC WORD_A+2
        STA T1+2
        LDA T1+3
        ADC WORD_A+3
        STA T1+3
        LDY SHA_YNDX
        JSR LOADK
        CLC
        LDA T1+0
        ADC WORD_B+0
        STA T1+0
        LDA T1+1
        ADC WORD_B+1
        STA T1+1
        LDA T1+2
        ADC WORD_B+2
        STA T1+2
        LDA T1+3
        ADC WORD_B+3
        STA T1+3
        LDY SHA_YNDX
        JSR LOADW
        CLC
        LDA T1+0
        ADC WORD_A+0
        STA T1+0
        LDA T1+1
        ADC WORD_A+1
        STA T1+1
        LDA T1+2
        ADC WORD_A+2
        STA T1+2
        LDA T1+3
        ADC WORD_A+3
        STA T1+3
        LDA SHA_A+0
        STA WORD_A+0
        LDA SHA_A+1
        STA WORD_A+1
        LDA SHA_A+2
        STA WORD_A+2
        LDA SHA_A+3
        STA WORD_A+3
        JSR BIGS0
        LDA WORD_A+0
        STA T2+0
        LDA WORD_A+1
        STA T2+1
        LDA WORD_A+2
        STA T2+2
        LDA WORD_A+3
        STA T2+3
        JSR MAJ
        CLC
        LDA T2+0
        ADC WORD_A+0
        STA T2+0
        LDA T2+1
        ADC WORD_A+1
        STA T2+1
        LDA T2+2
        ADC WORD_A+2
        STA T2+2
        LDA T2+3
        ADC WORD_A+3
        STA T2+3
        LDA SHA_G+0
        STA SHA_HH+0
        LDA SHA_G+1
        STA SHA_HH+1
        LDA SHA_G+2
        STA SHA_HH+2
        LDA SHA_G+3
        STA SHA_HH+3
        LDA SHA_F+0
        STA SHA_G+0
        LDA SHA_F+1
        STA SHA_G+1
        LDA SHA_F+2
        STA SHA_G+2
        LDA SHA_F+3
        STA SHA_G+3
        LDA SHA_E+0
        STA SHA_F+0
        LDA SHA_E+1
        STA SHA_F+1
        LDA SHA_E+2
        STA SHA_F+2
        LDA SHA_E+3
        STA SHA_F+3
        CLC
        LDA SHA_D+0
        ADC T1+0
        STA SHA_E+0
        LDA SHA_D+1
        ADC T1+1
        STA SHA_E+1
        LDA SHA_D+2
        ADC T1+2
        STA SHA_E+2
        LDA SHA_D+3
        ADC T1+3
        STA SHA_E+3
        LDA SHA_C+0
        STA SHA_D+0
        LDA SHA_C+1
        STA SHA_D+1
        LDA SHA_C+2
        STA SHA_D+2
        LDA SHA_C+3
        STA SHA_D+3
        LDA SHA_B+0
        STA SHA_C+0
        LDA SHA_B+1
        STA SHA_C+1
        LDA SHA_B+2
        STA SHA_C+2
        LDA SHA_B+3
        STA SHA_C+3
        LDA SHA_A+0
        STA SHA_B+0
        LDA SHA_A+1
        STA SHA_B+1
        LDA SHA_A+2
        STA SHA_B+2
        LDA SHA_A+3
        STA SHA_B+3
        CLC
        LDA T1+0
        ADC T2+0
        STA SHA_A+0
        LDA T1+1
        ADC T2+1
        STA SHA_A+1
        LDA T1+2
        ADC T2+2
        STA SHA_A+2
        LDA T1+3
        ADC T2+3
        STA SHA_A+3
        LDY SHA_YNDX
        INY
        CPY #64
        BEQ CMPDONE
        STY SHA_YNDX
        JMP CMPLOOP
CMPDONE
        CLC
        LDA SHA_H0+0
        ADC SHA_A+0
        STA SHA_H0+0
        LDA SHA_H0+1
        ADC SHA_A+1
        STA SHA_H0+1
        LDA SHA_H0+2
        ADC SHA_A+2
        STA SHA_H0+2
        LDA SHA_H0+3
        ADC SHA_A+3
        STA SHA_H0+3
        CLC
        LDA SHA_H1+0
        ADC SHA_B+0
        STA SHA_H1+0
        LDA SHA_H1+1
        ADC SHA_B+1
        STA SHA_H1+1
        LDA SHA_H1+2
        ADC SHA_B+2
        STA SHA_H1+2
        LDA SHA_H1+3
        ADC SHA_B+3
        STA SHA_H1+3
        CLC
        LDA SHA_H2+0
        ADC SHA_C+0
        STA SHA_H2+0
        LDA SHA_H2+1
        ADC SHA_C+1
        STA SHA_H2+1
        LDA SHA_H2+2
        ADC SHA_C+2
        STA SHA_H2+2
        LDA SHA_H2+3
        ADC SHA_C+3
        STA SHA_H2+3
        CLC
        LDA SHA_H3+0
        ADC SHA_D+0
        STA SHA_H3+0
        LDA SHA_H3+1
        ADC SHA_D+1
        STA SHA_H3+1
        LDA SHA_H3+2
        ADC SHA_D+2
        STA SHA_H3+2
        LDA SHA_H3+3
        ADC SHA_D+3
        STA SHA_H3+3
        CLC
        LDA SHA_H4+0
        ADC SHA_E+0
        STA SHA_H4+0
        LDA SHA_H4+1
        ADC SHA_E+1
        STA SHA_H4+1
        LDA SHA_H4+2
        ADC SHA_E+2
        STA SHA_H4+2
        LDA SHA_H4+3
        ADC SHA_E+3
        STA SHA_H4+3
        CLC
        LDA SHA_H5+0
        ADC SHA_F+0
        STA SHA_H5+0
        LDA SHA_H5+1
        ADC SHA_F+1
        STA SHA_H5+1
        LDA SHA_H5+2
        ADC SHA_F+2
        STA SHA_H5+2
        LDA SHA_H5+3
        ADC SHA_F+3
        STA SHA_H5+3
        CLC
        LDA SHA_H6+0
        ADC SHA_G+0
        STA SHA_H6+0
        LDA SHA_H6+1
        ADC SHA_G+1
        STA SHA_H6+1
        LDA SHA_H6+2
        ADC SHA_G+2
        STA SHA_H6+2
        LDA SHA_H6+3
        ADC SHA_G+3
        STA SHA_H6+3
        CLC
        LDA SHA_H7+0
        ADC SHA_HH+0
        STA SHA_H7+0
        LDA SHA_H7+1
        ADC SHA_HH+1
        STA SHA_H7+1
        LDA SHA_H7+2
        ADC SHA_HH+2
        STA SHA_H7+2
        LDA SHA_H7+3
        ADC SHA_HH+3
        STA SHA_H7+3
        RTS

SHA256
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS
        RTS

; ================================================================
; HMAC-SHA256
; ================================================================

HMAC_SHA256
        ; Inner hash block 1: key XOR ipad
        LDX #0
HMAC_IP LDA HMAC_KEY,X
        EOR #$36
        STA SHA_BLK,X
        INX
        CPX #64
        BNE HMAC_IP
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS

        ; Inner hash block 2: message + padding
        LDX #0
HMAC_CL LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE HMAC_CL
        LDX #0
HMAC_MB LDA HMAC_MSG,X
        STA SHA_BLK,X
        INX
        CPX HMAC_MLEN
        BNE HMAC_MB
        LDX HMAC_MLEN
        LDA #$80
        STA SHA_BLK,X
        LDA HMAC_MLEN
        ASL
        ASL
        ASL
        STA SHA_BLK+63
        LDA #$00
        ROL
        ADC #$02
        STA SHA_BLK+62
        LDA #$00
        STA SHA_BLK+61
        STA SHA_BLK+60
        STA SHA_BLK+59
        STA SHA_BLK+58
        STA SHA_BLK+57
        STA SHA_BLK+56
        JSR SHA_EXPAND
        JSR SHA_COMPRESS

        ; store inner hash
        LDA SHA_H0+0
        STA HMAC_INNER+0
        LDA SHA_H0+1
        STA HMAC_INNER+1
        LDA SHA_H0+2
        STA HMAC_INNER+2
        LDA SHA_H0+3
        STA HMAC_INNER+3
        LDA SHA_H1+0
        STA HMAC_INNER+4
        LDA SHA_H1+1
        STA HMAC_INNER+5
        LDA SHA_H1+2
        STA HMAC_INNER+6
        LDA SHA_H1+3
        STA HMAC_INNER+7
        LDA SHA_H2+0
        STA HMAC_INNER+8
        LDA SHA_H2+1
        STA HMAC_INNER+9
        LDA SHA_H2+2
        STA HMAC_INNER+10
        LDA SHA_H2+3
        STA HMAC_INNER+11
        LDA SHA_H3+0
        STA HMAC_INNER+12
        LDA SHA_H3+1
        STA HMAC_INNER+13
        LDA SHA_H3+2
        STA HMAC_INNER+14
        LDA SHA_H3+3
        STA HMAC_INNER+15
        LDA SHA_H4+0
        STA HMAC_INNER+16
        LDA SHA_H4+1
        STA HMAC_INNER+17
        LDA SHA_H4+2
        STA HMAC_INNER+18
        LDA SHA_H4+3
        STA HMAC_INNER+19
        LDA SHA_H5+0
        STA HMAC_INNER+20
        LDA SHA_H5+1
        STA HMAC_INNER+21
        LDA SHA_H5+2
        STA HMAC_INNER+22
        LDA SHA_H5+3
        STA HMAC_INNER+23
        LDA SHA_H6+0
        STA HMAC_INNER+24
        LDA SHA_H6+1
        STA HMAC_INNER+25
        LDA SHA_H6+2
        STA HMAC_INNER+26
        LDA SHA_H6+3
        STA HMAC_INNER+27
        LDA SHA_H7+0
        STA HMAC_INNER+28
        LDA SHA_H7+1
        STA HMAC_INNER+29
        LDA SHA_H7+2
        STA HMAC_INNER+30
        LDA SHA_H7+3
        STA HMAC_INNER+31

        ; Outer hash block 1: key XOR opad
        LDX #0
HMAC_OP LDA HMAC_KEY,X
        EOR #$5c
        STA SHA_BLK,X
        INX
        CPX #64
        BNE HMAC_OP
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS

        ; Outer hash block 2: inner hash + padding
        LDX #0
HMAC_C2 LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE HMAC_C2
        LDA HMAC_INNER+3
        STA SHA_BLK+0
        LDA HMAC_INNER+2
        STA SHA_BLK+1
        LDA HMAC_INNER+1
        STA SHA_BLK+2
        LDA HMAC_INNER+0
        STA SHA_BLK+3
        LDA HMAC_INNER+7
        STA SHA_BLK+4
        LDA HMAC_INNER+6
        STA SHA_BLK+5
        LDA HMAC_INNER+5
        STA SHA_BLK+6
        LDA HMAC_INNER+4
        STA SHA_BLK+7
        LDA HMAC_INNER+11
        STA SHA_BLK+8
        LDA HMAC_INNER+10
        STA SHA_BLK+9
        LDA HMAC_INNER+9
        STA SHA_BLK+10
        LDA HMAC_INNER+8
        STA SHA_BLK+11
        LDA HMAC_INNER+15
        STA SHA_BLK+12
        LDA HMAC_INNER+14
        STA SHA_BLK+13
        LDA HMAC_INNER+13
        STA SHA_BLK+14
        LDA HMAC_INNER+12
        STA SHA_BLK+15
        LDA HMAC_INNER+19
        STA SHA_BLK+16
        LDA HMAC_INNER+18
        STA SHA_BLK+17
        LDA HMAC_INNER+17
        STA SHA_BLK+18
        LDA HMAC_INNER+16
        STA SHA_BLK+19
        LDA HMAC_INNER+23
        STA SHA_BLK+20
        LDA HMAC_INNER+22
        STA SHA_BLK+21
        LDA HMAC_INNER+21
        STA SHA_BLK+22
        LDA HMAC_INNER+20
        STA SHA_BLK+23
        LDA HMAC_INNER+27
        STA SHA_BLK+24
        LDA HMAC_INNER+26
        STA SHA_BLK+25
        LDA HMAC_INNER+25
        STA SHA_BLK+26
        LDA HMAC_INNER+24
        STA SHA_BLK+27
        LDA HMAC_INNER+31
        STA SHA_BLK+28
        LDA HMAC_INNER+30
        STA SHA_BLK+29
        LDA HMAC_INNER+29
        STA SHA_BLK+30
        LDA HMAC_INNER+28
        STA SHA_BLK+31
        LDA #$80
        STA SHA_BLK+32
        LDA #$03
        STA SHA_BLK+62
        LDA #$00
        STA SHA_BLK+63
        STA SHA_BLK+61
        STA SHA_BLK+60
        STA SHA_BLK+59
        STA SHA_BLK+58
        STA SHA_BLK+57
        STA SHA_BLK+56
        JSR SHA_EXPAND
        JSR SHA_COMPRESS

; copy output to HMAC_OUT (big-endian per word)
        LDA SHA_H0+3
        STA HMAC_OUT+0
        LDA SHA_H0+2
        STA HMAC_OUT+1
        LDA SHA_H0+1
        STA HMAC_OUT+2
        LDA SHA_H0+0
        STA HMAC_OUT+3
        LDA SHA_H1+3
        STA HMAC_OUT+4
        LDA SHA_H1+2
        STA HMAC_OUT+5
        LDA SHA_H1+1
        STA HMAC_OUT+6
        LDA SHA_H1+0
        STA HMAC_OUT+7
        LDA SHA_H2+3
        STA HMAC_OUT+8
        LDA SHA_H2+2 
        STA HMAC_OUT+9
        LDA SHA_H2+1 
        STA HMAC_OUT+10
        LDA SHA_H2+0 
        STA HMAC_OUT+11
        LDA SHA_H3+3 
        STA HMAC_OUT+12
        LDA SHA_H3+2 
        STA HMAC_OUT+13
        LDA SHA_H3+1 
        STA HMAC_OUT+14
        LDA SHA_H3+0 
        STA HMAC_OUT+15
        LDA SHA_H4+3 
        STA HMAC_OUT+16
        LDA SHA_H4+2 
        STA HMAC_OUT+17
        LDA SHA_H4+1 
        STA HMAC_OUT+18
        LDA SHA_H4+0  
        STA HMAC_OUT+19
        LDA SHA_H5+3 
        STA HMAC_OUT+20
        LDA SHA_H5+2 
        STA HMAC_OUT+21
        LDA SHA_H5+1 
        STA HMAC_OUT+22
        LDA SHA_H5+0 
        STA HMAC_OUT+23
        LDA SHA_H6+3 
        STA HMAC_OUT+24
        LDA SHA_H6+2 
        STA HMAC_OUT+25
        LDA SHA_H6+1 
        STA HMAC_OUT+26
        LDA SHA_H6+0 
        STA HMAC_OUT+27
        LDA SHA_H7+3 
        STA HMAC_OUT+28
        LDA SHA_H7+2 
        STA HMAC_OUT+29
        LDA SHA_H7+1 
        STA HMAC_OUT+30
        LDA SHA_H7+0 
        STA HMAC_OUT+31
        RTS


; ================================================================
; PBKDF2-HMAC-SHA256
; ================================================================

PBKDF2
        PHP
        SEI
        LDA #$30
        STA $0427
        LDA #$0B
        STA $DE02
        LDA #$7F
        STA $DD0D
        LDA $DD0D
        LDA $DE01
        LDA $DE00
        JSR PBKDF2_FAST
        LDA #$09
        STA $DE02
        PLP
        RTS
        LDX #0
PK_CKL  LDA #$00
        STA HMAC_KEY,X
        INX
        CPX #64
        BNE PK_CKL
        LDX #0
PK_CPW  LDA PBKDF2_PWD,X
        STA HMAC_KEY,X
        INX
        CPX PBKDF2_PWDLEN
        BNE PK_CPW
        LDX #0
PK_CSL  LDA PBKDF2_SALT,X
        STA HMAC_MSG,X
        INX
        CPX PBKDF2_SALTLEN
        BNE PK_CSL
        LDX PBKDF2_SALTLEN
        LDA #$00
        STA HMAC_MSG,X
        INX
        LDA #$00
        STA HMAC_MSG,X
        INX
        LDA #$00
        STA HMAC_MSG,X
        INX
        LDA #$01
        STA HMAC_MSG,X
        INX
        STX HMAC_MLEN
        JSR HMAC_SHA256
        LDX #0
PK_CDK  LDA HMAC_OUT,X
        STA PBKDF2_DK,X
        INX
        CPX #32
        BNE PK_CDK
        LDA PBKDF2_ITRLO
        STA PBKDF2_CTRLO
        LDA PBKDF2_ITRMID
        STA PBKDF2_CTRMID
        LDA PBKDF2_ITRHI
        STA PBKDF2_CTRHI
        DEC PBKDF2_CTRLO
        LDA PBKDF2_CTRLO
        CMP #$FF
        BNE PK_CHK0
        DEC PBKDF2_CTRMID
        LDA PBKDF2_CTRMID
        CMP #$FF
        BNE PK_CHK0
        DEC PBKDF2_CTRHI
PK_CHK0 LDA PBKDF2_CTRLO
        ORA PBKDF2_CTRMID
        ORA PBKDF2_CTRHI
        BEQ PK_DONE
        LDA #32
        STA HMAC_MLEN
PK_LOOP
        INC $D020
        LDX #0
PK_CUI  LDA HMAC_OUT,X
        STA HMAC_MSG,X
        INX
        CPX #32
        BNE PK_CUI
        JSR HMAC_SHA256
        LDX #0
PK_XOR  LDA PBKDF2_DK,X
        EOR HMAC_OUT,X
        STA PBKDF2_DK,X
        INX
        CPX #32
        BNE PK_XOR
        DEC PBKDF2_CTRLO
        LDA PBKDF2_CTRLO
        CMP #$FF
        BNE PK_CHK
        DEC PBKDF2_CTRMID
        LDA PBKDF2_CTRMID
        CMP #$FF
        BNE PK_CHK
        DEC PBKDF2_CTRHI
PK_CHK  LDA PBKDF2_CTRLO
        ORA PBKDF2_CTRMID
        ORA PBKDF2_CTRHI
        BNE PK_LOOP
PK_DONE RTS

; ================================================================
; HKDF-Extract
; ================================================================

HKDF_EXTRACT
        LDX #0
HE_CKL  LDA #$00
        STA HMAC_KEY,X
        INX
        CPX #64
        BNE HE_CKL
        LDX #0
HE_CSL  LDA HKDF_SALT,X
        STA HMAC_KEY,X
        INX
        CPX HKDF_SALTLEN
        BNE HE_CSL
        LDX #0
HE_CIM  LDA HKDF_IKM,X
        STA HMAC_MSG,X
        INX
        CPX HKDF_IKMLEN
        BNE HE_CIM
        LDA HKDF_IKMLEN
        STA HMAC_MLEN
        JSR HMAC_SHA256
        LDX #0
HE_CPR  LDA HMAC_OUT,X
        STA HKDF_PRK,X
        INX
        CPX #32
        BNE HE_CPR
        RTS

; ================================================================
; HKDF-Expand (64 bytes output)
; ================================================================

HKDF_EXPAND
        LDX #0
HX_CKL  LDA #$00
        STA HMAC_KEY,X
        INX
        CPX #64
        BNE HX_CKL
        LDX #0
HX_CPR  LDA HKDF_PRK,X
        STA HMAC_KEY,X
        INX
        CPX #32
        BNE HX_CPR
        LDX #0
HX_CI1  LDA HKDF_INFO,X
        STA HMAC_MSG,X
        INX
        CPX HKDF_INFOLEN
        BNE HX_CI1
        LDX HKDF_INFOLEN
        LDA #$01
        STA HMAC_MSG,X
        INX
        STX HMAC_MLEN
        JSR HMAC_SHA256
        LDX #0
HX_CT1  LDA HMAC_OUT,X
        STA HKDF_OKM,X
        INX
        CPX #32
        BNE HX_CT1
        LDX #0
HX_CT2  LDA HKDF_OKM,X
        STA HMAC_MSG,X
        INX
        CPX #32
        BNE HX_CT2
        LDX #0
HX_CI2  LDA HKDF_INFO,X
        STA HMAC_MSG+32,X
        INX
        CPX HKDF_INFOLEN
        BNE HX_CI2
        LDX HKDF_INFOLEN
        LDA #$02
        STA HMAC_MSG+32,X
        INX
        TXA
        CLC
        ADC #32
        STA HMAC_MLEN
        JSR HMAC_SHA256
        LDX #0
HX_CT3  LDA HMAC_OUT,X
        STA HKDF_OKM+32,X
        INX
        CPX #32
        BNE HX_CT3
        RTS

; ================================================================
; HKDF_T1 - compute T(1) = HMAC(PRK, info || $01)
; ================================================================
HKDF_T1
        LDX #0
HT_CKL  LDA #$00
        STA HMAC_KEY,X
        INX
        CPX #64
        BNE HT_CKL
        LDX #0
HT_CPR  LDA HKDF_PRK,X
        STA HMAC_KEY,X
        INX
        CPX #32
        BNE HT_CPR
        LDX #0
HT_CI   LDA HKDF_INFO,X
        STA HMAC_MSG,X
        INX
        CPX HKDF_INFOLEN
        BNE HT_CI
        LDX HKDF_INFOLEN
        LDA #$01
        STA HMAC_MSG,X
        INX
        STX HMAC_MLEN
        JSR HMAC_SHA256
        RTS

; ================================================================
; DERIVE_KEYPAIR - compatible with the MeshChat web client
; ================================================================
DERIVE_KEYPAIR
        ; Step 1: salt = SHA-256("meshchat-v1:" + lowercase(name))
        ; prefix "meshchat-v1:" in SHA_BLK
        LDA #$6D
        STA SHA_BLK+0
        LDA #$65
        STA SHA_BLK+1
        LDA #$73
        STA SHA_BLK+2
        LDA #$68
        STA SHA_BLK+3
        LDA #$63
        STA SHA_BLK+4
        LDA #$68
        STA SHA_BLK+5
        LDA #$61
        STA SHA_BLK+6
        LDA #$74
        STA SHA_BLK+7
        LDA #$2D
        STA SHA_BLK+8
        LDA #$76
        STA SHA_BLK+9
        LDA #$31
        STA SHA_BLK+10
        LDA #$3A
        STA SHA_BLK+11

        ; append lowercase name (PETSCII $01-$1A + ASCII $41-$5A)
        LDX #0
DV_SN   LDA KDFIN_NAME,X
        BEQ DV_SNE
        ; PETSCII lowercase $01-$1A -> ASCII lowercase $61-$7A
        CMP #$01
        BCC DV_SNS          ; < $01: ongewijzigd
        CMP #$1B
        BCS DV_CHK_N        ; >= $1B: check op uppercase
        CLC
        ADC #$60            ; PETSCII $01-$1A -> ASCII $61-$7A
        BNE DV_SNS          ; always branch (result != 0)
DV_CHK_N
        CMP #$41
        BCC DV_SNS
        CMP #$5B
        BCS DV_SNS
        ORA #$20
DV_SNS  STA SHA_BLK+12,X
        INX
        CPX #32
        BNE DV_SN
DV_SNE
        TXA
        CLC
        ADC #12
        STA DV_TMPLEN

        ; clear rest of SHA_BLK
        LDX DV_TMPLEN 
DV_SCL  LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE DV_SCL

        ; padding byte
        LDX DV_TMPLEN
        LDA #$80
        STA SHA_BLK,X

        ; Bitlengte
        LDA DV_TMPLEN
        ASL
        ASL
        ASL
        STA SHA_BLK+63
        LDA #$00
        ROL
        STA SHA_BLK+62

        ; compute SHA-256
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS

        ; copy SHA result (big-endian) to PBKDF2_SALT
        LDA SHA_H0+3
        STA PBKDF2_SALT+0
        LDA SHA_H0+2
        STA PBKDF2_SALT+1
        LDA SHA_H0+1
        STA PBKDF2_SALT+2
        LDA SHA_H0+0
        STA PBKDF2_SALT+3
        LDA SHA_H1+3
        STA PBKDF2_SALT+4
        LDA SHA_H1+2
        STA PBKDF2_SALT+5
        LDA SHA_H1+1
        STA PBKDF2_SALT+6
        LDA SHA_H1+0
        STA PBKDF2_SALT+7
        LDA SHA_H2+3
        STA PBKDF2_SALT+8
        LDA SHA_H2+2
        STA PBKDF2_SALT+9
        LDA SHA_H2+1
        STA PBKDF2_SALT+10
        LDA SHA_H2+0
        STA PBKDF2_SALT+11
        LDA SHA_H3+3
        STA PBKDF2_SALT+12
        LDA SHA_H3+2
        STA PBKDF2_SALT+13
        LDA SHA_H3+1
        STA PBKDF2_SALT+14
        LDA SHA_H3+0
        STA PBKDF2_SALT+15
        LDA SHA_H4+3
        STA PBKDF2_SALT+16
        LDA SHA_H4+2
        STA PBKDF2_SALT+17
        LDA SHA_H4+1
        STA PBKDF2_SALT+18
        LDA SHA_H4+0
        STA PBKDF2_SALT+19
        LDA SHA_H5+3
        STA PBKDF2_SALT+20
        LDA SHA_H5+2
        STA PBKDF2_SALT+21
        LDA SHA_H5+1
        STA PBKDF2_SALT+22
        LDA SHA_H5+0
        STA PBKDF2_SALT+23
        LDA SHA_H6+3
        STA PBKDF2_SALT+24
        LDA SHA_H6+2
        STA PBKDF2_SALT+25
        LDA SHA_H6+1
        STA PBKDF2_SALT+26
        LDA SHA_H6+0
        STA PBKDF2_SALT+27
        LDA SHA_H7+3
        STA PBKDF2_SALT+28
        LDA SHA_H7+2
        STA PBKDF2_SALT+29
        LDA SHA_H7+1
        STA PBKDF2_SALT+30
        LDA SHA_H7+0
        STA PBKDF2_SALT+31
        LDA #32
        STA PBKDF2_SALTLEN

        ; Step 2: PBKDF2 passphrase
        LDX #0
DV_CWL  LDA #$00
        STA PBKDF2_PWD,X
        INX
        CPX #64
        BNE DV_CWL
        LDX #0
DV_CPW  LDA KDFIN_PASS,X
        STA PBKDF2_PWD,X
        INX
        CPX KDFIN_PASSLEN
        BNE DV_CPW
        LDA KDFIN_PASSLEN
        STA PBKDF2_PWDLEN

        ; Item 10A login: do NOT lowercase the passphrase. The web client uses
        ; the passphrase case-sensitively (TextEncoder().encode(passphrase) as-is),
        ; so a mixed-case passphrase must be preserved byte-for-byte to
        ; match. INPUT_PASS already yields real ASCII (lower/upper case).
        ; (an existing lowercase passphrase stays identical -> same key.)

        ; 100,000 iterations = $0186A0  (Option B: 256-bit path, ON)
        LDA #$A0
        STA PBKDF2_ITRLO
        LDA #$86
        STA PBKDF2_ITRMID
        LDA #$01
        STA PBKDF2_ITRHI


        ; 1000 iterations = $E80300  (128-bit dev path, OFF)
        ;LDA #$E8
        ;STA PBKDF2_ITRLO
        ;LDA #$03
        ;STA PBKDF2_ITRMID
        ;LDA #$00
        ;STA PBKDF2_ITRHI




        ; (removed) lowercase conversion of KDFIN_PASS: was dead code
        ; (KDFIN_PASS is not read after derivation) and would
        ; break a mixed-case passphrase.

        JSR PBKDF2
        ; Step 3: HKDF-Extract
        LDX #0
DV_CSZ  LDA #$00
        STA HKDF_SALT,X
        INX
        CPX #32
        BNE DV_CSZ
        LDA #32
        STA HKDF_SALTLEN
        LDX #0
DV_CIM  LDA PBKDF2_DK,X
        STA HKDF_IKM,X
        INX
        CPX #32
        BNE DV_CIM
        LDA #32
        STA HKDF_IKMLEN
        JSR HKDF_EXTRACT

        ; Step 4: T(1) info="meshchat-v1:encryption"
        LDA #$6d
        STA HKDF_INFO+0
        LDA #$65
        STA HKDF_INFO+1
        LDA #$73
        STA HKDF_INFO+2
        LDA #$68
        STA HKDF_INFO+3
        LDA #$63
        STA HKDF_INFO+4
        LDA #$68
        STA HKDF_INFO+5
        LDA #$61
        STA HKDF_INFO+6
        LDA #$74
        STA HKDF_INFO+7
        LDA #$2d
        STA HKDF_INFO+8
        LDA #$76
        STA HKDF_INFO+9
        LDA #$31
        STA HKDF_INFO+10
        LDA #$3a
        STA HKDF_INFO+11
        LDA #$65
        STA HKDF_INFO+12
        LDA #$6e
        STA HKDF_INFO+13
        LDA #$63
        STA HKDF_INFO+14
        LDA #$72
        STA HKDF_INFO+15
        LDA #$79
        STA HKDF_INFO+16
        LDA #$70
        STA HKDF_INFO+17
        LDA #$74
        STA HKDF_INFO+18
        LDA #$69
        STA HKDF_INFO+19
        LDA #$6f
        STA HKDF_INFO+20
        LDA #$6e
        STA HKDF_INFO+21
        LDA #22
        STA HKDF_INFOLEN

        JSR HKDF_T1

        LDX #0
DV_CE   LDA HMAC_OUT,X
        STA HKDF_OKM,X
        INX
        CPX #32
        BNE DV_CE

        ; Step 5: T(1) info="meshchat-v1:signing"
        LDA #$73
        STA HKDF_INFO+12
        LDA #$69
        STA HKDF_INFO+13
        LDA #$67
        STA HKDF_INFO+14
        LDA #$6e
        STA HKDF_INFO+15
        LDA #$69
        STA HKDF_INFO+16
        LDA #$6e
        STA HKDF_INFO+17
        LDA #$67
        STA HKDF_INFO+18
        LDA #19
        STA HKDF_INFOLEN

        JSR HKDF_T1

        LDX #0
DV_CS   LDA HMAC_OUT,X
        STA HKDF_OKM+32,X
        INX
        CPX #32
        BNE DV_CS

        RTS

; ================================================================
; NIBBLE_TO_SCR
; ================================================================
NIBBLE_TO_SCR
        CMP #10
        BCC NTS_DIG
        SBC #9
        RTS
NTS_DIG ORA #$30
        RTS

; ================================================================
; PRINT_HEX
; ================================================================
PRINT_HEX
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR NIBBLE_TO_SCR
        LDY #0
        STA ($FB),Y
        INC $FB
        BNE PH1
        INC $FC
PH1     PLA
        AND #$0F
        JSR NIBBLE_TO_SCR
        LDY #0
        STA ($FB),Y
        INC $FB
        BNE PH2
        INC $FC
PH2     RTS

; ================================================================
; COMPUTE_USER_ID
; SHA-256(HKDF_OKM[0..31]) -> USER_ID
; ================================================================
COMPUTE_USER_ID
        LDX #0
CUI_CP  LDA KEY_SELF,X        ; interop: hash own key (BX7U)
        STA SHA_BLK,X
        INX
        CPX #16
        BNE CUI_CP
        LDX #16
CUI_CL  LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE CUI_CL
        LDA #$80
        STA SHA_BLK+16
        LDA #$00            ; 128 bits high byte
        STA SHA_BLK+62
        LDA #$80            ; 128 bits low byte
        STA SHA_BLK+63
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS
        LDX #0
CUI_CR  LDA SHA_H0,X
        STA USER_ID,X
        INX
        CPX #32
        BNE CUI_CR
        RTS

; ================================================================
; DISPLAY_USER_ID
; ================================================================
DISPLAY_USER_ID
        LDA #$20
        LDX #0
DUI_C1  STA $0400,X
        INX
        BNE DUI_C1
        LDX #0
DUI_C2  STA $0500,X
        INX
        BNE DUI_C2
        LDX #0
DUI_C3  STA $0600,X
        INX
        BNE DUI_C3
        LDX #0
DUI_C4  STA $0700,X
        INX
        CPX #$E8
        BNE DUI_C4
        LDA #$09
        STA $0400
        LDA #$04
        STA $0401
        LDA #$3A
        STA $0402
        LDX #0
        LDA #$28
        STA $FB
        LDA #$04
        STA $FC
        JSR DUI_ROW
        LDA #$50
        STA $FB
        LDA #$04
        STA $FC
        JSR DUI_ROW
        LDA #$78
        STA $FB
        LDA #$04
        STA $FC
        JSR DUI_ROW
        LDA #$A0
        STA $FB
        LDA #$04
        STA $FC
        JSR DUI_ROW
        RTS

DUI_ROW
        LDA USER_ID,X
        JSR PRINT_HEX
        LDA #$20
        LDY #0
        STA ($FB),Y
        INC $FB
        BNE DUR1
        INC $FC
DUR1    INX
        TXA
        AND #$07
        BNE DUI_ROW
        RTS

; ================================================================
; SHOW_USER_ID
; ================================================================
SHOW_USER_ID
        JSR COMPUTE_USER_ID
        JSR DISPLAY_USER_ID
        RTS


; ================================================================
; ACIA / 6551 ROUTINES (SwiftLink / U64 modem emulatie)
; Registers: $DE00=data  $DE01=status/reset  $DE02=command  $DE03=control
; ================================================================

ACIA_INIT
        LDA #$00
        STA $DE01       ; reset
        LDA #$1F        ; was $1E - 38400 baud for C64U
        STA $DE03
        LDA #$09
        STA $DE02
        RTS

; ----------------------------------------------------------------
; CIA2_WAIT_10MS - wait A x 10ms via CIA2 Timer A
;
; CIA2 Timer A always runs at PHI2 = 1MHz, regardless of CPU speed.
; Works correctly in both 1MHz and 64MHz turbo mode.
; 10ms = 10000 cycles @ 1MHz = $2710
; Input: A = count × 10ms (1..255), max = 2.55s
; Bug 6 fix: replaces all cpu-count loops with clock-free timing
; ----------------------------------------------------------------
CIA2_WAIT_10MS
        STA CIA_MSCTR
CWM_LP  LDA #$10                ; $2710 lo byte (10000 & $FF)
        STA $DD04               ; CIA2 Timer A lo latch
        LDA #$27                ; $2710 hi byte (10000 >> 8)
        STA $DD05               ; CIA2 Timer A hi latch
        LDA #$19                ; load latch + one-shot + start
        STA $DD0E               ; CIA2 Control A
CWM_WT  LDA $DD0D               ; read CIA2 ICR (reading clears flags)
        AND #$01                ; bit 0 = Timer A underflow?
        BNE CWM_NXT
        JMP CWM_WT
CWM_NXT DEC CIA_MSCTR
        BNE CWM_LP
        RTS

; ----------------------------------------------------------------
; FPGA_SETTLE - 50ms real via CIA2 Timer A (Bug 3 fix)
; Clock-speed independent: works at 1MHz and 64MHz
; ----------------------------------------------------------------
FPGA_SETTLE
        LDA #5
        JSR CIA2_WAIT_10MS      ; 5 × 10ms = 50ms real
        RTS

; ----------------------------------------------------------------
; LONG_DELAY - 100ms real via CIA2 Timer A (Bug 5 fix)
; Clock-speed independent: works at 1MHz and 64MHz
; ----------------------------------------------------------------
LONG_DELAY
        LDA #10
        JSR CIA2_WAIT_10MS      ; 10 × 10ms = 100ms real
        RTS

; ----------------------------------------------------------------
; ACIA_SEND - send byte in A
; ----------------------------------------------------------------
ACIA_SEND
        PHA             ; save A (byte to send)
        TXA
        PHA             ; save X
        TYA
        PHA             ; save Y

        LDX #$40        ; Bug 6 fix: raised from $10->$40 for 64MHz margin
ACS_OT  LDY #0
ACS_IN  LDA $DE01
        AND #$10
        BNE ACS_RDY     ; TDRE=1 -> send
        DEY
        BNE ACS_IN
        DEX
        BNE ACS_OT

        ; timeout - recover and drop byte
        PLA
        TAY
        PLA
        TAX
        PLA
        RTS

ACS_RDY
        ; TDRE=1 - recover and send byte
        PLA
        TAY
        PLA
        TAX
        PLA
        STA $DE00
        RTS

; ----------------------------------------------------------------
; ACIA_RECV - wait for byte, return in A (blocking)
; ----------------------------------------------------------------
ACIA_RECV
        LDA $DE01
        AND #$08        ; bit3 = RDRF (byte available)
        BEQ ACIA_RECV
        LDA $DE00
        RTS

; ----------------------------------------------------------------
; ACIA_SEND_STR - send null-terminated string via $FB/$FC
; ----------------------------------------------------------------
ACIA_SEND_STR
        LDY #0
ASS_LP  LDA ($FB),Y
        BEQ ASS_DN
        JSR ACIA_SEND
        INY
        BNE ASS_LP
ASS_DN  RTS

; ----------------------------------------------------------------
; ACIA_RECV_TO - receive byte with CIA2-based timeout
; Bug 6 fix: replaces cpu-count loop that was too short at 64MHz.
;   cpu-count loop: ~0.64ms @ 64MHz but ~41ms @ 1MHz
;   TCP RTT on LAN: 1-5ms -> at 64MHz timed out before CONNECT
;   CIA2 Timer A: always 10ms real, regardless of CPU clock
; C=0 + A=byte received / C=1 = timeout
; ----------------------------------------------------------------
ACIA_RECV_TO
        ; CIA2 Timer A: 10ms = 10000 cycles @ 1MHz = $2710
        LDA #$10                ; $2710 lo byte
        STA $DD04               ; CIA2 Timer A lo latch
        LDA #$27                ; $2710 hi byte
        STA $DD05               ; CIA2 Timer A hi latch
        LDA #$19                ; load latch + one-shot + start
        STA $DD0E               ; CIA2 Control A
ACRT_W  LDA $DE01
        AND #$08                ; RDRF bit
        BNE ACRT_OK             ; byte available
        LDA $DD0D               ; read CIA2 ICR (clears flags)
        AND #$01                ; Timer A underflow?
        BNE ACRT_TO             ; timeout
        JMP ACRT_W
ACRT_OK LDA $DE00
        CLC
        RTS
ACRT_TO SEC
        RTS

; ----------------------------------------------------------------
; NMI-DRIVEN RECEIVER (SwiftLink/ACIA on /NMI)
; ----------------------------------------------------------------
; The U64 FPGA modem delivers RX bytes in bursts (TCP bridge), not
; clocked at the configured baud. At 1MHz a polling read loop
; can't keep up -> overrun of the 1-byte ACIA buffer -> frame lost.
; Solution: the ACIA already asserts /NMI on every RX byte ($DE02=$09,
; bit1=0). We hook the NMI vector ($0318/$0319) and drain the ACIA
; in the ISR into a 256-byte ring buffer. The main code reads from
; the ring via RING_GET_TO (drop-in for ACIA_RECV_TO).
;
; Single-producer (ISR -> RING_HEAD) / single-consumer
; (main code -> RING_TAIL), lock-free. CIA2 Timer A is NOT
; touched by the ISR; the timeout in RING_GET_TO keeps working.
; $DD0D is NOT read by the ISR (no race with underflow).
;
; Important: the ISR FULLY drains the ACIA per NMI (drain loop),
; so the NMI overhead is spread across a whole burst.
; ----------------------------------------------------------------

; RX_NMI - NMI handler, hooked on $0318. KERNAL $FE43 only does
; SEI + JMP ($0318): A/X/Y are NOT saved yet. We save A and
; X ourselves and return with RTI.
RX_NMI
        PHA
        TXA
        PHA
        LDA $DE01
        AND #$08            ; RDRF? (our byte?)
        BEQ RXN_EXIT        ; no (e.g. RESTORE key): do nothing
RXN_LP
        LDA $DE00           ; read byte (clears RDRF, de-asserts /NMI)
        LDX RING_HEAD
        STA RING_BUF,X
        INX
        CPX RING_TAIL       ; would HEAD catch up to TAIL? -> full
        BEQ RXN_FULL
        STX RING_HEAD       ; commit byte
RXN_NX
        LDA $DE01
        AND #$08
        BNE RXN_LP          ; another byte ready -> keep draining
RXN_EXIT
        PLA
        TAX
        PLA
        RTI
RXN_FULL
        LDA #$01
        STA RING_OVF        ; mark overflow (diagnostic); byte is dropped
        JMP RXN_NX          ; ACIA already drained (byte read) -> continue

; INSTALL_RX_NMI - hook RX_NMI on $0318/$0319. ACIA RX-IRQ briefly off
; during the vector swap so no NMI grabs a half-written vector;
; then RX-IRQ back on ($DE02=$09).
INSTALL_RX_NMI
        SEI
        LDA #$00
        STA RING_HEAD
        STA RING_TAIL
        STA RING_OVF
        LDA #$0B            ; %0000_1011: DTR on, RX-IRQ OFF, RTS low
        STA $DE02
        LDA #<RX_NMI
        STA $0318
        LDA #>RX_NMI
        STA $0319
        LDA #$09            ; %0000_1001: DTR on, RX-IRQ ON
        STA $DE02
        CLI
        RTS

; RING_GET_TO - drop-in for ACIA_RECV_TO in the RECEIVE loop.
; C=0 + A=byte, or C=1 = timeout (10ms via CIA2 Timer A). Reads
; first from the ring; if the ring is empty, as a fallback also the live
; ACIA (race with IRQ-clear during simultaneous send). CLOBBERS X
; (MC_RECV_POLL already preserves the input index, so that's fine here).
RING_GET_TO
        LDA #50             ; ~50 x 20ms = ~1s total timeout (large frame
        STA RGT_RETRY       ;  of 300+ bytes may stream in slowly)
RGT_ARM
        LDA #$20            ; $4E20 = 20000 cycli = 20ms @1MHz
        STA $DD04
        LDA #$4E
        STA $DD05
        LDA #$19            ; load latch + one-shot + start
        STA $DD0E
RGT_W
        LDX RING_TAIL
        CPX RING_HEAD
        BNE RGT_GET         ; ring not empty -> byte available
        LDA $DD0D
        AND #$01
        BEQ RGT_W           ; no underflow yet -> keep waiting
        DEC RGT_RETRY
        BNE RGT_ARM         ; more retries -> restart 20ms timer
        BEQ RGT_TO          ; retries exhausted -> real timeout
RGT_GET
        LDA RING_BUF,X
        INC RING_TAIL       ; wrap bij 256 (byte)
        CLC
        RTS
RGT_TO
        SEC
        RTS



; ----------------------------------------------------------------
; MODEM_DIAL - send ATDT, wait for CONNECT
; Bug 5 fix: AT wake-up primer added.
;   After ACIA_INIT the U64 FPGA modem refuses to process ATDT
;   without a preceding AT\r. Symptom: CRs echoed but no
;   CONNECT and no TCP connection. Proven on hardware v3.
; C=0 = connected / C=1 = failed or timeout
; ----------------------------------------------------------------
MODEM_DIAL
        ; Step 1: AT wake-up primer (Bug 5 fix)
        LDA #<STR_AT
        STA $FB
        LDA #>STR_AT
        STA $FC
        JSR ACIA_SEND_STR       ; send AT\r

        ; Flush AT respons (max 20 bytes, weggooien)
        LDX #20
MDW_FL  JSR ACIA_RECV_TO
        BCS MDW_DN              ; timeout = done
        DEX
        BNE MDW_FL
MDW_DN

        ; ~100ms wait: modem fully processes wake-up
        JSR LONG_DELAY

        ; Step 2: ATDT dial
        LDA #<STR_ATDT
        STA $FB
        LDA #>STR_ATDT
        STA $FC
        JSR ACIA_SEND_STR

        LDX #64
MD_RD   JSR ACIA_RECV_TO
        BCS MD_OK
        DEX
        BNE MD_RD
MD_OK   CLC
        RTS

ATDT_TEST
        LDA #<STR_ATDT
        STA $FB
        LDA #>STR_ATDT
        STA $FC
        JSR ACIA_SEND_STR   ; send "ATDT192.168.1.100:8889\r"

        ; read buffer first, only then print
        LDX #0
ADT_RD  JSR ACIA_RECV_TO
        BCS ADT_PR
        STA AT_BUF,X
        INX
        CPX #24
        BNE ADT_RD
ADT_PR  STX AT_CNT
        LDX #0
ADT_PL  CPX AT_CNT
        BEQ ADT_DN
        LDA AT_BUF,X
        JSR PRINT_HEX_PET
        LDA #$20
        JSR PRINT_CHR
        INX
        JMP ADT_PL
ADT_DN  LDA #$0D
        JSR PRINT_CHR
        RTS          
          

MD_TRIES !byte 0


; ================================================================
; WS_HANDSHAKE - send HTTP upgrade + wait fixed time + BOUNDED 101 drain
; On the U64 RDRF can "stick"; so we drain the 101 response
; bounded (max 16 read attempts OR until timeout). C=0 always.
; ================================================================
WS_HANDSHAKE
        LDA #<STR_WS_HDR
        STA $FB
        LDA #>STR_WS_HDR
        STA $FC
        JSR ACIA_SEND_STR   ; send HTTP upgrade

        ; 1000ms real via CIA2 — clock-speed-independent (Bug 6 fix)
        ; Previously cpu-count loops: ~1s @ 64MHz but ~64s @ 1MHz!
        LDA #100
        JSR CIA2_WAIT_10MS  ; 100 × 10ms = 1000ms real

        ; Item 11B: read and discard the HTTP 101 response - BOUNDED,
        ; like recvtest64. Otherwise the HTTP headers stay in the
        ; ACIA buffer and WS_RECV_FRAME reads them later as an (invalid)
        ; frame. Unbounded could hang forever if RDRF sticks on the U64;
        ; so: drain until timeout (buffer truly empty). nginx' 101 response
        ; is ~188 bytes; the old limit of 16 left ~172 bytes of HTTP header
        ; which WS_AUTH then read as a junk frame. Limit 255 = safety brake.
        LDX #255
WSH_DRN JSR ACIA_RECV_TO
        BCS WSH_DN          ; timeout = buffer empty, response consumed
        DEX
        BNE WSH_DRN         ; max 255 bytes
WSH_DN  CLC
        RTS


; ================================================================
; WS_SEND - send null-terminated string as a WebSocket text frame
; $FB/$FC = pointer to string
; ================================================================
WS_SEND
        LDY #0
WSLEN   LDA ($FB),Y
        BEQ WSLEN_DN
        INY
        CPY #125
        BNE WSLEN
WSLEN_DN STY WS_MLEN

        LDA #$81        ; FIN + text opcode
        JSR ACIA_SEND
        LDA WS_MLEN
        ORA #$80        ; mask bit aan
        JSR ACIA_SEND
        LDA #$37        ; masking key byte 0
        JSR ACIA_SEND
        LDA #$FA        ; masking key byte 1
        JSR ACIA_SEND
        LDA #$21        ; masking key byte 2
        JSR ACIA_SEND
        LDA #$3D        ; masking key byte 3
        JSR ACIA_SEND

        LDY #0
WSPL    CPY WS_MLEN
        BEQ WSPL_DN
        STY WS_YT
        TYA
        AND #$03
        TAX
        LDA WS_MASK,X
        LDY WS_YT
        EOR ($FB),Y     ; mask XOR payload byte
        JSR ACIA_SEND
        INY
        JMP WSPL
WSPL_DN RTS

WS_HS_ST !byte 0
WS_MLEN  !byte 0
WS_YT    !byte 0
WS_MASK  !byte $37,$FA,$21,$3D

; ----------------------------------------------------------------
; AT_TEST - send AT\r, buffer response, only then print
; ----------------------------------------------------------------
AT_TEST
        JSR ACIA_INIT

        ; small pause after init
        LDX #0
ATT_DL  DEX
        BNE ATT_DL

        LDA #<STR_AT
        STA $FB
        LDA #>STR_AT
        STA $FC
        JSR ACIA_SEND_STR

        ; read up to 16 bytes into buffer (NO print while reading)
        LDX #0
ATT_RD  JSR ACIA_RECV_TO
        BCS ATT_PR      ; timeout = done
        STA AT_BUF,X
        INX
        CPX #16
        BNE ATT_RD

ATT_PR  STX AT_CNT
        LDX #0
ATT_PL  CPX AT_CNT
        BEQ ATT_DN
        LDA AT_BUF,X
        JSR PRINT_HEX_PET
        LDA #$20
        JSR PRINT_CHR
        INX
        JMP ATT_PL
ATT_DN  LDA #$0D
        JSR PRINT_CHR
        RTS


; ================================================================
; GCM COMBINATIE: NONCE-GENERATOR + AES_GCM_ENCRYPT + JSON-BUILDER
; + WS_SEND_EXT (uitgebreide WebSocket-frame) + WS_SEND_MSG
; ================================================================

; ================================================================
; JOUT_INIT  -  reset JSON-uitvoerbuffer
; ================================================================
JOUT_INIT
        LDA #<JOUT_BUF
        STA JOUT_LO
        LDA #>JOUT_BUF
        STA JOUT_HI
        LDA #0
        STA JOUT_LEN+0
        STA JOUT_LEN+1
        RTS

; ================================================================
; JOUT_EMIT  -  write byte A to JOUT_BUF, advance write pointer
; ================================================================
JOUT_EMIT
        ; STA (addr),Y requires a zero-page address for addr.
        ; JOUT_LO/HI are outside zero-page, so copy to $FD/$FE first.
        PHA                 ; save byte to write
        LDA JOUT_LO
        STA $FD             ; zero-page write pointer lo
        LDA JOUT_HI
        STA $FE             ; zero-page write pointer hi
        PLA                 ; restore byte
        LDY #0
        STA ($FD),Y         ; indirect write via zero-page pointer
        INC JOUT_LO
        BNE JOE_D
        INC JOUT_HI
JOE_D   INC JOUT_LEN+0
        BNE JOE_N
        INC JOUT_LEN+1
JOE_N   RTS

; ================================================================
; JOUT_EMIT_STR  -  write null-terminated string via $FB/$FC
; Fix: increment $FB/$FC pointer instead of Y-index; JOUT_EMIT may Y
; clobber (LDY #0 internally) without breaking the loop.
; ================================================================
JOUT_EMIT_STR
JES_LP  LDY #0
        LDA ($FB),Y         ; read current char (Y always 0)
        BEQ JES_DN
        JSR JOUT_EMIT       ; may clobber Y - no problem
        INC $FB             ; advance $FB/$FC one char
        BNE JES_LP
        INC $FC
        JMP JES_LP
JES_DN  RTS

; ================================================================
; BYTE_TO_DEC  -  emit byte A as 1-3 decimal chars to JOUT
; ================================================================
BYTE_TO_DEC
        STA BTD_VAL
        LDA #0
        STA BTD_NZ          ; 0 = no non-zero char seen yet

        ; ---- honderdtallen ----
        LDX #0
BTD_H1  LDA BTD_VAL
        CMP #100
        BCC BTD_H2
        SBC #100            ; carry already set by CMP (A>=100)
        STA BTD_VAL
        INX
        JMP BTD_H1
BTD_H2  TXA
        BEQ BTD_T1          ; 0 hundreds -> skip
        ORA #$30
        JSR JOUT_EMIT
        LDA #1
        STA BTD_NZ

        ; ---- tens ----
BTD_T1  LDX #0
BTD_T2  LDA BTD_VAL
        CMP #10
        BCC BTD_T3
        SBC #10
        STA BTD_VAL
        INX
        JMP BTD_T2
BTD_T3  TXA
        BEQ BTD_TZ          ; 0 tens - check flag
        ORA #$30
        JSR JOUT_EMIT
        LDA #1
        STA BTD_NZ
        JMP BTD_U1
BTD_TZ  LDA BTD_NZ          ; write '0' only if hundreds digit was written
        BEQ BTD_U1
        LDA #$30
        JSR JOUT_EMIT

        ; ---- units (always write) ----
BTD_U1  LDA BTD_VAL
        ORA #$30
        JSR JOUT_EMIT
        RTS

; ================================================================
; GCM_NONCE_GEN  -  generate 12-byte nonce via CIA timers + counter
; ================================================================
; CIA1: $DC04/$DC05 = Timer-A lo/hi,  $DC06/$DC07 = Timer-B lo/hi
; CIA2: $DD04/$DD05 = Timer-A lo/hi,  $DD06/$DD07 = Timer-B lo/hi
; Bytes 8-9   : message counter GCM_MSG_CTR (ensures uniqueness)
; Bytes 10-11 : CIA1-A re-read XOR counter (extra entropy)
; Output     : AES_NONCE[0..11] filled
; ================================================================
GCM_NONCE_GEN
        LDA $DC04           ; CIA1 Timer-A low
        STA AES_NONCE+0
        LDA $DC05           ; CIA1 Timer-A high
        STA AES_NONCE+1
        LDA $DC06           ; CIA1 Timer-B low
        STA AES_NONCE+2
        LDA $DC07           ; CIA1 Timer-B high
        STA AES_NONCE+3
        LDA $DD04           ; CIA2 Timer-A low
        STA AES_NONCE+4
        LDA $DD05           ; CIA2 Timer-A high
        STA AES_NONCE+5
        LDA $DD06           ; CIA2 Timer-B low
        STA AES_NONCE+6
        LDA $DD07           ; CIA2 Timer-B high
        STA AES_NONCE+7
        ; message counter gives guaranteed uniqueness per message
        LDA GCM_MSG_CTR+0
        STA AES_NONCE+8
        LDA GCM_MSG_CTR+1
        STA AES_NONCE+9
        ; re-read after some delay XOR counter
        LDA $DC04
        EOR GCM_MSG_CTR+0
        STA AES_NONCE+10
        LDA $DC05
        EOR GCM_MSG_CTR+1
        STA AES_NONCE+11
        ; increment 16-bit counter
        INC GCM_MSG_CTR+0
        BNE GNG_DN
        INC GCM_MSG_CTR+1
GNG_DN  RTS

; ================================================================
; AES_GCM_ENCRYPT  -  full AES-128-GCM: CTR mode + GHASH tag
; ================================================================
; Input:
;   GCM_IN_KEY[0..15]  16-byte AES-128 key
;   GCM_PT_PTR[0..1]   lo/hi address of plaintext buffer
;   GCM_PT_LEN         plaintext length in bytes (1..239)
; Output:
;   AES_NONCE[0..11]   fresh nonce (generated by GCM_NONCE_GEN)
;   GCM_CTBUF[0..n-1]  ciphertext (n = GCM_PT_LEN bytes)
;   GCM_TAG[0..15]     16-byte GHASH authentication tag
; Clobbers : AES_KEY, AES_RK, AES_BLOCK, AES_STATE, GCM_H, GCM_EK0
;            GCM_Y, GCM_BLK, GCM_GX/GY/GZ/VBUF, AES_CTR_*
; ================================================================
AES_GCM_ENCRYPT
        ; -- load key and compute round keys --
        LDX #15
AGE_K   LDA GCM_IN_KEY,X
        STA AES_KEY,X
        DEX
        BPL AGE_K
        JSR AES_SETKEY

        ; -- generate fresh 12-byte nonce --
        JSR GCM_NONCE_GEN

        ; -- compute GCM hash subkey H and tag block EK0 --
        ;    GCM_INIT expects AES_RK filled and AES_NONCE[0..11] set
        JSR GCM_INIT

        ; -- CTR-modus encryptie: plaintext -> GCM_CTBUF --
        ;    counter starts at $00000002 (per GCM spec; J0 reserved)
        LDA GCM_PT_PTR+0
        STA AES_CTR_IN+0
        LDA GCM_PT_PTR+1
        STA AES_CTR_IN+1
        LDA #<GCM_CTBUF
        STA AES_CTR_OUT+0
        LDA #>GCM_CTBUF
        STA AES_CTR_OUT+1
        LDA GCM_PT_LEN+0
        STA AES_CTR_LEN+0
        LDA GCM_PT_LEN+1
        STA AES_CTR_LEN+1
        JSR AES_CTR_CRYPT

        ; -- GHASH authentication tag over ciphertext --
        ;    GCM_AUTH: empty AAD; GHASH over CT blocks + length block; XOR EK0
        LDA #<GCM_CTBUF
        STA GCM_CT_PTR+0
        LDA #>GCM_CTBUF
        STA GCM_CT_PTR+1
        LDA GCM_PT_LEN+0
        STA GCM_CT_LEN+0
        LDA GCM_PT_LEN+1
        STA GCM_CT_LEN+1
        JSR GCM_AUTH        ; -> GCM_TAG[0..15]
        RTS

; ================================================================
; GCM_TAG_MAC  -  AES-128-GCM auth tag as MAC (web client signBlob128)
; ================================================================
; Reproduceert: AES-128-GCM(key, IV=12x00, plaintext).slice(-16)
; Input:
;   KEY_SIGN_SELF[0..15]  16-byte MAC key (own signKey128)
;   BLOB_PTR[0..1]        lo/hi address of the blob bytes (in JOUT_BUF)
;   MAC_LEN[0..1]         16-bit length of the blob bytes
; Output:
;   GCM_TAG[0..15]        16-byte tag (= sig)
; Difference from AES_GCM_ENCRYPT: NO GCM_NONCE_GEN; fixed zero IV.
; Writes ciphertext to MAC_CTBUF (not GCM_CTBUF -> message intact).
; ================================================================
GCM_TAG_MAC
        ; key = KEY_SIGN_SELF -> AES_KEY, round keys --
        LDX #15
GTM_K   LDA KEY_SIGN_SELF,X
        STA AES_KEY,X
        DEX
        BPL GTM_K
        JSR AES_SETKEY

        ; -- fixed zero-IV: AES_NONCE[0..11] = 0 --
        LDA #$00
        LDX #11
GTM_N   STA AES_NONCE,X
        DEX
        BPL GTM_N

        ; H and EK0 (J0 = zero-IV || $00000001) --
        JSR GCM_INIT

        ; -- CTR-encrypt blob-bytes -> MAC_CTBUF --
        LDA BLOB_PTR+0
        STA AES_CTR_IN+0
        LDA BLOB_PTR+1
        STA AES_CTR_IN+1
        LDA #<MAC_CTBUF
        STA AES_CTR_OUT+0
        LDA #>MAC_CTBUF
        STA AES_CTR_OUT+1
        LDA MAC_LEN+0
        STA AES_CTR_LEN+0
        LDA MAC_LEN+1
        STA AES_CTR_LEN+1
        JSR AES_CTR_CRYPT

        ; -- GHASH over ciphertext -> GCM_TAG --
        LDA #<MAC_CTBUF
        STA GCM_CT_PTR+0
        LDA #>MAC_CTBUF
        STA GCM_CT_PTR+1
        LDA MAC_LEN+0
        STA GCM_CT_LEN+0
        LDA MAC_LEN+1
        STA GCM_CT_LEN+1
        JSR GCM_AUTH        ; -> GCM_TAG[0..15]
        RTS

; ================================================================
; B64URL_12BYTES  -  base64url-codering: C64_IDBYTES[0..11] -> C64_IDSTR[0..15]
; ================================================================
; 4 groups of 3 bytes -> 4 chars each  (no padding: 12 bytes = 16 chars)
; URL-veilig alfabet: index 62 = '-', index 63 = '_'
; ================================================================
B64URL_12BYTES
        LDA #0
        STA B64_GRPIDX          ; groepsindex 0..3
B64_GLP LDA B64_GRPIDX
        CMP #4
        ; BEQ B64_GDN would jump 147 bytes - outside +-127 range.
        ; Solution: invert to BNE-skip + absolute JMP.
        BNE B64_GC
        JMP B64_GDN         ; 3-byte absolute jump, no distance limit
B64_GC

        ; byte-offset = GRPIDX * 3 = (GRPIDX<<1) + GRPIDX
        LDA B64_GRPIDX
        ASL
        STA B64_BOFF
        CLC
        ADC B64_GRPIDX
        STA B64_BOFF            ; B64_BOFF = GRPIDX * 3

        ; load 3 input bytes
        TAX
        LDA C64_IDBYTES+0,X
        STA B64_B0
        LDA C64_IDBYTES+1,X
        STA B64_B1
        LDA C64_IDBYTES+2,X
        STA B64_B2

        ; output offset = GRPIDX * 4
        LDA B64_GRPIDX
        ASL
        ASL
        STA B64_OIDX            ; B64_OIDX = GRPIDX * 4

        ; char 0: B0[7..2] = B0 >> 2
        LDA B64_B0
        LSR
        LSR
        TAX
        LDA B64_TABLE,X
        LDY B64_OIDX
        STA C64_IDSTR,Y

        ; char 1: (B0[1..0] << 4) | (B1[7..4])
        LDA B64_B0
        AND #$03
        ASL
        ASL
        ASL
        ASL
        STA B64_T
        LDA B64_B1
        LSR
        LSR
        LSR
        LSR
        ORA B64_T
        TAX
        LDA B64_TABLE,X
        LDY B64_OIDX
        INY
        STA C64_IDSTR,Y

        ; char 2: (B1[3..0] << 2) | (B2[7..6])
        LDA B64_B1
        AND #$0F
        ASL
        ASL
        STA B64_T
        LDA B64_B2
        LSR
        LSR
        LSR
        LSR
        LSR
        LSR
        ORA B64_T
        TAX
        LDA B64_TABLE,X
        LDY B64_OIDX
        INY
        INY
        STA C64_IDSTR,Y

        ; char 3: B2[5..0]
        LDA B64_B2
        AND #$3F
        TAX
        LDA B64_TABLE,X
        LDY B64_OIDX
        INY
        INY
        INY
        STA C64_IDSTR,Y

        INC B64_GRPIDX
        JMP B64_GLP
B64_GDN RTS

; ================================================================
; COMPUTE_C64_ID  -  compute C64 publicId: base64url(SHA256(encKey)[0..11])
; ================================================================
; publicId = base64url( SHA-256(HKDF_OKM[0..15])[0..11] )
; Identiek aan JS: derivePublicId(keys.encryptionKey)
; Output: C64_IDSTR[0..15] = 16 ASCII chars + null terminator
; ================================================================
COMPUTE_C64_ID
        ; OPTION A: SHA-256 of the 16-byte AES key
        ; Identiek aan JS: derivePublicId(keys.encryptionKey.slice(0,16))
        LDX #15
CC4_SK  LDA KEY_SELF,X         ; own key -> staging
        STA ID_KEY_IN,X
        DEX
        BPL CC4_SK
COMPUTE_ID_CORE
        LDX #15
CC4_CP  LDA ID_KEY_IN,X        ; staging buffer (self or peer)
        STA SHA_BLK,X
        DEX
        BPL CC4_CP

        ; clear the rest of the SHA block
        LDX #16
CC4_CL  LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE CC4_CL

        ; SHA-256 padding: $80 op positie 16; bitlengte = 128 bits = $0080
        LDA #$80
        STA SHA_BLK+16
        LDA #$00            ; 128 bits high byte
        STA SHA_BLK+62
        LDA #$80            ; 128 bits low byte
        STA SHA_BLK+63

        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS

        ; copy first 12 bytes of SHA output (big-endian per word)
        ; -> C64_IDBYTES[0..11]
CC4_DIGEST_TAIL
        LDA SHA_H0+3
        STA C64_IDBYTES+0
        LDA SHA_H0+2
        STA C64_IDBYTES+1
        LDA SHA_H0+1
        STA C64_IDBYTES+2
        LDA SHA_H0+0
        STA C64_IDBYTES+3
        LDA SHA_H1+3
        STA C64_IDBYTES+4
        LDA SHA_H1+2
        STA C64_IDBYTES+5
        LDA SHA_H1+1
        STA C64_IDBYTES+6
        LDA SHA_H1+0
        STA C64_IDBYTES+7
        LDA SHA_H2+3
        STA C64_IDBYTES+8
        LDA SHA_H2+2
        STA C64_IDBYTES+9
        LDA SHA_H2+1
        STA C64_IDBYTES+10
        LDA SHA_H2+0
        STA C64_IDBYTES+11

        ; base64url encoding of 12 bytes -> 16 chars
        JSR B64URL_12BYTES

        ; null-terminator
        LDA #0
        STA C64_IDSTR+16
        RTS

; ================================================================
; COMPUTE_PEER_ID - publicId of KEY_PEER -> PEER_IDSTR ('to' field)
; Uses COMPUTE_ID_CORE; clobbers C64_IDSTR (afterwards
; call COMPUTE_C64_ID for the own id).
; ================================================================
COMPUTE_PEER_ID
        LDX #15
CPI_CK  LDA KEY_PEER,X
        STA ID_KEY_IN,X
        DEX
        BPL CPI_CK
        JSR COMPUTE_ID_CORE
        LDX #0
CPI_CP  LDA C64_IDSTR,X
        STA PEER_IDSTR,X
        INX
        CPX #17
        BNE CPI_CP
        RTS

; ================================================================
; INNER_EMIT  -  write byte A to MSG_INNER_BUF
; Uses MIJ_LO/HI as write pointer (via $FD/$FE).
; Increments MSG_INNER_LEN. Preserves A; clobbers Y.
; ================================================================
; MC_RECV_POLL  -  poll ACIA, process incoming WS message
; Called from INPUT_LINE when no key.
; Preserves X (input buffer index). Clobbers A, Y.
; ================================================================
MC_RECV_POLL
        TXA
        PHA                     ; save X (= typed chars)
        LDA #0
        STA MSG_SHOWN
        LDA RING_TAIL
        CMP RING_HEAD
        BEQ MRP_DONE            ; ring empty -> nothing to do
        JSR WS_RECV_FRAME
        BCS MRP_DONE            ; error/non-text frame -> show nothing
        JSR PROC_RECV_MSG       ; shows only real message frames
        LDA MSG_SHOWN
        BEQ MRP_DONE            ; nothing shown -> do not redraw
        PLA
        TAX                     ; X = saved number of typed chars
        JSR REDRAW_INPUT        ; redraw prompt + typed text
        TXA
        PHA                     ; store again for restore
MRP_DONE
        PLA
        TAX                     ; restore X
        RTS

; ================================================================
; WS_RECV_FRAME  -  read 1 WebSocket text frame into RCV_BUF
; Server does not mask; we read unmasked payload.
; Carry clear = success, carry set = error or non-text frame.
; ================================================================
WS_RECV_FRAME
        LDA RING_OVF            ; A2: overflow = backup-flood/desync
        BEQ WRF_NOOVF
WRF_RESYNC
        JSR RING_GET_TO         ; drain the ring until timeout (flush flood)
        BCC WRF_RESYNC
        LDA #$00
        STA RING_OVF
        SEC                     ; no frame this time; next is aligned
        RTS
WRF_NOOVF
        LDA #$00
        STA RING_OVF            ; clear per-frame overflow flag
        STA RCV_TOOBIG          ; clear per-frame too-big flag
        JSR RING_GET_TO
        BCS WRFE_TR
        AND #$0F                ; mask FIN/RSV: opcode
        CMP #$09                ; ping frame (keepalive)?
        BNE WRF_NOTPING
        JMP WRF_PING            ; -> pong back, reset keepalive
WRFE_TR JMP WRF_ERR             ; trampoline (branches within +-127)
WRFS_TR JMP WRF_SKIP            ; trampoline
WRFO_TR JMP WRF_OVERSIZE        ; trampoline (too-big -> reconnect)
WRF_NOTPING
        CMP #$08                ; A: close frame? relay closes -> reconnect
        BNE WRF_NOTCLOSE
        JMP MC_RECONNECT
WRF_NOTCLOSE
        CMP #$01                ; text frame?
        BNE WRFS_TR
        ; read length byte
        JSR RING_GET_TO
        BCS WRFE_TR
        CMP #126
        BCS WRF_EXT             ; >= 126 = extended length
        STA RCV_LEN_LO
        LDA #0
        STA RCV_LEN_HI
        JMP WRF_DO_READ
WRF_EXT
        BNE WRFS_TR             ; 127 = 64-bit length: skip (drain until timeout)
        JSR RING_GET_TO        ; high byte
        BCS WRFE_TR
        STA RCV_LEN_HI
        JSR RING_GET_TO        ; low byte
        BCS WRFE_TR
        STA RCV_LEN_LO
WRF_DO_READ
        ; (no more reconnect on large frames) The read loop below
        ; drains EVERY 16-bit-length frame: store up to RCV_BUF_END,
        ; discard the rest and set RCV_TOOBIG. PROC_RECV_MSG then shows
        ; the non-reconnecting warning and the connection stays.
        ; (web client periodically sends large backup_push frames; they
        ;  are swallowed cleanly instead of an endless reconnect loop.)
        LDA #<RCV_BUF
        STA $FB
        LDA #>RCV_BUF
        STA $FC
        LDA RCV_LEN_HI
        STA WRF_CTR_HI
        LDA RCV_LEN_LO
        STA WRF_CTR_LO
        ORA WRF_CTR_HI
        BEQ WRF_RDONE           ; length zero
WRF_RLOP
        JSR RING_GET_TO
        BCS WRF_ERR
        LDX $FC                 ; grens-check: pointer < RCV_BUF_END?
        CPX #>RCV_BUF_END
        BCC WRF_STORE
        BNE WRF_NOSTORE
        LDX $FB
        CPX #<RCV_BUF_END
        BCC WRF_STORE
WRF_NOSTORE
        LDX #1
        STX RCV_TOOBIG
        JMP WRF_DEC
WRF_STORE
        LDY #0
        STA ($FB),Y
        INC $FB
        BNE WRF_DEC
        INC $FC
WRF_DEC
        LDA WRF_CTR_LO
        BNE WRF_DHI
        DEC WRF_CTR_HI
WRF_DHI DEC WRF_CTR_LO
        LDA WRF_CTR_LO
        ORA WRF_CTR_HI
        BNE WRF_RLOP
WRF_RDONE
        LDY #0
        LDA #0
        STA ($FB),Y             ; null-terminate
        CLC
        RTS
WRF_SKIP                        ; non-text frame: drain until timeout
WRF_DRN JSR RING_GET_TO
        BCC WRF_DRN
        SEC
        RTS
WRF_ERR SEC
        RTS

; ----------------------------------------------------------------
; WRF_PING - answer WebSocket ping (opcode 0x9) with pong (0xA)
;   The websockets lib sends a keepalive ping every ~20s with 4
;   random payload bytes; without a pong with the SAME payload
;   the relay drops after ping_timeout (keepalive ping timeout).
;   We read the payload from the ring and send it back masked
;   as a pong. Client always masks (RFC 6455) -> WS_MASK.
;   Return: carry set -> caller treats this as a non-text frame.
; ----------------------------------------------------------------
WRF_PING
        JSR RING_GET_TO         ; length byte (control frame <=125)
        BCS WRF_PERR
        AND #$7F                ; mask-bit defensief weg
        STA PING_LEN
        ; -- pong-header --
        LDA #$8A                ; FIN + pong opcode (0x0A)
        JSR ACIA_SEND
        LDA PING_LEN
        ORA #$80                ; mask bit (client always masks)
        JSR ACIA_SEND
        LDA #$37                ; masking key byte 0
        JSR ACIA_SEND
        LDA #$FA                ; masking key byte 1
        JSR ACIA_SEND
        LDA #$21                ; masking key byte 2
        JSR ACIA_SEND
        LDA #$3D                ; masking key byte 3
        JSR ACIA_SEND
        ; -- payload: read from ring, mask with WS_MASK[Y&3], send --
        LDY #0
WRP_LP  CPY PING_LEN
        BEQ WRP_DN
        JSR RING_GET_TO         ; payload byte (leaves Y intact)
        BCS WRF_PERR
        STA PING_TMP
        TYA
        AND #$03
        TAX
        LDA WS_MASK,X           ; mask byte for this position
        EOR PING_TMP
        JSR ACIA_SEND           ; preserves A/X/Y
        INY
        JMP WRP_LP
WRP_DN  SEC                     ; no text frame -> caller shows nothing
        RTS
WRF_PERR SEC
        RTS
WRF_OVERSIZE
        ; frame too big to drain safely -> reset connection
        LDA #$0D
        JSR PRINT_CHR
        LDA #$1C            ; red
        JSR PRINT_CHR
        LDA #<STR_TOOBIGRC
        STA $FB
        LDA #>STR_TOOBIGRC
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        ; fall through to MC_RECONNECT
MC_RECONNECT
        LDX #$FF                ; reset stack (jump out of deep call stack)
        TXS
        LDA #2
        STA $D020               ; red border during reconnect
        JSR ACIA_INIT
        JSR FPGA_SETTLE
        JSR MODEM_DIAL
        JSR WS_HANDSHAKE
        ; A3: do NOT clear screen on reconnect -> chat history stays
        JSR INSTALL_RX_NMI
        JSR WS_AUTH_DISPATCH
        LDA #5
        STA $D020
        JMP MC_CHAT_LOOP


; ================================================================
; PROC_RECV_MSG  -  process received JSON: parse, decrypt, show
; Works on RCV_BUF (filled by WS_RECV_FRAME).
; ================================================================
PROC_RECV_MSG
        LDA RCV_TOOBIG
        BEQ PRM_NOTBIG
        JMP PRM_TOOBIG
PRM_NOTBIG
        LDA #<RCV_BUF
        STA $FB
        LDA #>RCV_BUF
        STA $FC
        ; 1) check type=message
        LDA #<JSC_TYPE_MSG
        STA JSC_PAT_LO
        LDA #>JSC_TYPE_MSG
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP PRM_DONE
        ; 2) read from-ID (16 chars)
        LDA #<JSC_FROM
        STA JSC_PAT_LO
        LDA #>JSC_FROM
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP PRM_DONE
        LDX #0
PRM_FLP LDY #0
        LDA ($FB),Y
        BEQ PRM_FEND
        CMP #$22            ; sluitende '"'
        BEQ PRM_FEND
        STA RCV_FROM,X
        INX
        INC $FB
        BNE PRM_FNX
        INC $FC
PRM_FNX CPX #16
        BNE PRM_FLP
PRM_FEND
        LDA #0
        STA RCV_FROM,X
        ; 3) Parse IV-array (12 bytes)
        LDA #<JSC_IV
        STA JSC_PAT_LO
        LDA #>JSC_IV
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP PRM_DONE
        LDA #<RCV_IV
        STA $FD
        LDA #>RCV_IV
        STA $FE
        LDA #12
        STA PRM_CNT
        LDA #0
        STA RCV_CT_LEN
        STA RCV_CT_LEN+1
        JSR JSON_PARSE_ARR
        BCC *+5
        JMP PRM_DONE
        ; 4) parse data array (CT + tag, variable length)
        LDA #<JSC_DATA
        STA JSC_PAT_LO
        LDA #>JSC_DATA
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP PRM_DONE
        LDA #<RCV_CT
        STA $FD
        LDA #>RCV_CT
        STA $FE
        LDA #0
        STA PRM_CNT         ; 0 = variable length
        STA RCV_CT_LEN
        STA RCV_CT_LEN+1
        STA RCV_TOOLONG
        JSR JSON_PARSE_ARR
        BCC *+5
        JMP PRM_DONE
        LDA RCV_TOOLONG
        BEQ PRM_NTL
        JMP PRM_TOOLONG
PRM_NTL
        LDA RCV_CT_LEN+1        ; CT_LEN >= 17 ? (16-bit)
        BNE PRM_LOK
        LDA RCV_CT_LEN+0
        CMP #17
        BCS PRM_LOK
        JMP PRM_DONE        ; too short
PRM_LOK
        LDA RCV_CT_LEN+0        ; PT_LEN(16) = CT_LEN(16) - 16
        SEC
        SBC #16
        STA RCV_PT_LEN+0
        LDA RCV_CT_LEN+1
        SBC #0
        STA RCV_PT_LEN+1
        ; 5) load IV and key, decrypt
        LDX #11
PRM_IVL LDA RCV_IV,X
        STA AES_NONCE,X
        DEX
        BPL PRM_IVL
        JSR RCV_DECRYPT_DISPATCH  ; 128:AES-128/KEY_SELF  256:AGD256/HKDF_OKM -> GCM_CTBUF
        BCC *+5                 ; tag valid -> continue
        JMP PRM_BADTAG          ; tag invalid -> reject
        ; 6) find 'text' in decrypted inner JSON (GCM_CTBUF)
        LDA #<GCM_CTBUF
        STA $FB
        LDA #>GCM_CTBUF
        STA $FC
        LDA #<JSC_TEXT
        STA JSC_PAT_LO
        LDA #>JSC_TEXT
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP PRM_DONE
        LDA #<RCV_TEXT
        STA $FD
        LDA #>RCV_TEXT
        STA $FE
        LDA #0
        STA PRM_TCNT+0
        STA PRM_TCNT+1
PRM_TLP LDY #0
        LDA ($FB),Y
        BEQ PRM_TEND
        CMP #$22
        BEQ PRM_TEND
        STA ($FD),Y
        INC $FB
        BNE PRM_TS1
        INC $FC
PRM_TS1 INC $FD
        BNE PRM_TS2
        INC $FE
PRM_TS2 INC PRM_TCNT+0
        BNE PRM_TCK
        INC PRM_TCNT+1
PRM_TCK LDA PRM_TCNT+1
        CMP #>560
        BCC PRM_TLP
        BNE PRM_TEND
        LDA PRM_TCNT+0
        CMP #<560
        BCC PRM_TLP
PRM_TEND
        LDY #0
        LDA #0
        STA ($FD),Y
        ; 7) show on screen
        LDA #1
        STA MSG_SHOWN
        JSR SHOW_RECV_MSG
        JMP PRM_DONE
PRM_TOOBIG
        ; B-fix: backup/oversize frame already drained -> silently ignore
        JMP PRM_DONE
PRM_TOOLONG
        ; data array > RCV_CT: message too long for the C64
        LDA #$0D
        JSR PRINT_CHR
        LDA #$1C            ; red
        JSR PRINT_CHR
        LDA #<STR_TOOLONG
        STA $FB
        LDA #>STR_TOOLONG
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; wit
        JSR PRINT_CHR
        LDA #1
        STA MSG_SHOWN
        JMP PRM_DONE
PRM_BADTAG
        ; tag verification failed: red warning, message rejected
        LDA #$0D
        JSR PRINT_CHR
        LDA #$1C            ; red
        JSR PRINT_CHR
        LDA #<STR_BADTAG
        STA $FB
        LDA #>STR_BADTAG
        STA $FC
        JSR PRINT_STR_FB
        LDA RING_OVF        ; ring overflow during this frame?
        BEQ PRM_BT_NOVF
        LDA #$0D
        JSR PRINT_CHR
        LDA #<STR_RXOVF
        STA $FB
        LDA #>STR_RXOVF
        STA $FC
        JSR PRINT_STR_FB
PRM_BT_NOVF
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; wit
        JSR PRINT_CHR
        LDA #1
        STA MSG_SHOWN       ; redraw trigger (warning is on screen)
PRM_DONE
        RTS

; ================================================================
; REDRAW_INPUT - redraw "NAME> " prompt + already-typed chars.
; In : X = number of typed chars (INP_BUF[0..X-1]). Preserves X.
; Called after showing an incoming message, so the
; in-progress input line reappears neatly below the message.
; ================================================================
REDRAW_INPUT
        STX RDI_CNT
        LDA #$1E            ; green
        JSR PRINT_CHR
        LDX #0
RDI_NM  LDA KDFIN_NAME,X
        BEQ RDI_NME
        JSR PRINT_CHR
        INX
        BNE RDI_NM
RDI_NME
        LDA #<STR_PFX
        STA $FB
        LDA #>STR_PFX
        STA $FC
        JSR PRINT_STR_FB
        LDA #$05            ; wit
        JSR PRINT_CHR
        LDX #0
RDI_TL  CPX RDI_CNT
        BEQ RDI_DN
        LDA INP_BUF,X
        JSR PRINT_CHR
        INX
        BNE RDI_TL
RDI_DN  LDX RDI_CNT         ; restore X = count
        RTS


; ================================================================
; JSON_SCAN  -  find null-terminated pattern in buffer
; In:  $FB/$FC = current scan position in buffer
;      JSC_PAT_LO/HI = pattern address
; Out: $FB/$FC = position AFTER matched pattern, carry clear
;      carry set = not found (buffer end reached)
; Clobbers: A, Y. Preserves X.
; ================================================================
JSON_SCAN
JSC_OUT LDY #0
        LDA ($FB),Y
        BEQ JSC_FAIL        ; end of buffer
        ; save current position for the comparison attempt
        LDA $FB
        STA JSC_MPOS_LO
        LDA $FC
        STA JSC_MPOS_HI
        LDA JSC_PAT_LO
        STA JSC_CPOS_LO
        LDA JSC_PAT_HI
        STA JSC_CPOS_HI
JSC_INN ; read pattern byte via ($FD/$FE = JSC_CPOS)
        LDA JSC_CPOS_LO
        STA $FD
        LDA JSC_CPOS_HI
        STA $FE
        LDY #0
        LDA ($FD),Y
        BEQ JSC_HIT         ; pattern fully matched
        STA JSC_PB          ; save pattern byte
        ; read buffer byte via ($FD/$FE = JSC_MPOS)
        LDA JSC_MPOS_LO
        STA $FD
        LDA JSC_MPOS_HI
        STA $FE
        LDA ($FD),Y         ; Y=0
        CMP JSC_PB
        BNE JSC_NEXT        ; no match, try next position
        ; match: both pointers advance one step
        INC JSC_MPOS_LO
        BNE JSC_IPA
        INC JSC_MPOS_HI
JSC_IPA INC JSC_CPOS_LO
        BNE JSC_INN
        INC JSC_CPOS_HI
        JMP JSC_INN
JSC_HIT LDA JSC_MPOS_LO
        STA $FB
        LDA JSC_MPOS_HI
        STA $FC
        CLC
        RTS
JSC_NEXT
        INC $FB
        BNE JSC_OUT
        INC $FC
        JMP JSC_OUT
JSC_FAIL
        SEC
        RTS

; ================================================================
; JSON_PARSE_INT  -  parse decimaal getal op ($FB/$FC)
; Out: A = value 0..255, $FB/$FC past the digits
;      carry set = no digit found
; ================================================================
JSON_PARSE_INT
        LDY #0
        LDA ($FB),Y
        CMP #$30            ; < '0'?
        BCC JPI_ERR
        CMP #$3A            ; >= ':'?
        BCS JPI_ERR
        LDA #0
        STA JPI_VAL
JPI_LP  LDY #0
        LDA ($FB),Y
        CMP #$30
        BCC JPI_DONE
        CMP #$3A
        BCS JPI_DONE
        SEC
        SBC #$30
        STA JPI_DIG
        LDA JPI_VAL
        ASL                 ; val*2
        STA JPI_TMP
        ASL                 ; val*4
        ASL                 ; val*8
        CLC
        ADC JPI_TMP         ; val*10
        CLC
        ADC JPI_DIG
        STA JPI_VAL
        INC $FB
        BNE JPI_LP
        INC $FC
        JMP JPI_LP
JPI_DONE
        LDA JPI_VAL
        CLC
        RTS
JPI_ERR SEC
        RTS

; ================================================================
; JSON_PARSE_ARR  -  parse komma-gescheiden decimale byte-array
; $FB/$FC: scanpositie NA '['
; $FD/$FE: write target (set by caller)
; PRM_CNT: expected count (0 = variable, counts via RCV_CT_LEN)
; RCV_CT_LEN: MUST be 0 on entry; is incremented per byte.
; ================================================================
JSON_PARSE_ARR
        LDA PRM_CNT
        STA JPA_REM
JPA_LP  LDY #0
        LDA ($FB),Y
        BEQ JPA_ERR
        CMP #$5D            ; ']' = end
        BEQ JPA_ENDB
        CMP #$2C            ; skip ','
        BNE JPA_NUM
        INC $FB
        BNE JPA_LP
        INC $FC
        JMP JPA_LP
JPA_NUM JSR JSON_PARSE_INT
        BCS JPA_ERR
        LDY #0
        STA ($FD),Y
        INC $FD
        BNE JPA_INC
        INC $FE
JPA_INC INC RCV_CT_LEN+0
        BNE JPA_RC
        INC RCV_CT_LEN+1
JPA_RC  LDA JPA_REM
        BEQ JPA_UNL         ; 0 = onbeperkt -> grens-check
        DEC JPA_REM
        BNE JPA_LP
        CLC
        RTS
JPA_UNL LDA RCV_CT_LEN+1     ; RCV_CT_LEN >= 640 ? (RCV_CT capaciteit)
        CMP #>640
        BCC JPA_LP
        BNE JPA_TL
        LDA RCV_CT_LEN+0
        CMP #<640
        BCC JPA_LP
JPA_TL  LDA #1
        STA RCV_TOOLONG
        CLC
        RTS
JPA_ENDB
        INC $FB
        BNE JPA_OK
        INC $FC
JPA_OK  CLC
        RTS
JPA_ERR SEC
        RTS

; ================================================================
; AES_GCM_DECRYPT  -  decrypt received message (CTR mode)
; Requires: AES_NONCE = received IV (12 bytes)
;          GCM_IN_KEY, GCM_PT_PTR/LEN set
; Output: GCM_CTBUF = plaintext
; Tag verification skipped (v1).
; ================================================================
AES_GCM_DECRYPT
        LDX #15
AGD_K   LDA GCM_IN_KEY,X
        STA AES_KEY,X
        DEX
        BPL AGD_K
        JSR AES_SETKEY
        ; AES_NONCE already set to received IV
        JSR GCM_INIT
        LDA GCM_PT_PTR+0
        STA AES_CTR_IN+0
        LDA GCM_PT_PTR+1
        STA AES_CTR_IN+1
        LDA #<GCM_CTBUF
        STA AES_CTR_OUT+0
        LDA #>GCM_CTBUF
        STA AES_CTR_OUT+1
        LDA GCM_PT_LEN+0
        STA AES_CTR_LEN+0
        LDA GCM_PT_LEN+1
        STA AES_CTR_LEN+1
        JSR AES_CTR_CRYPT
        ; -- optional GCM tag verification (one-shot via GCM_DO_VERIFY) --
        LDA GCM_DO_VERIFY
        BNE AGD_VRF
        CLC                     ; verify off -> always 'valid'
        RTS
AGD_VRF
        LDA #0
        STA GCM_DO_VERIFY       ; one-shot: off again immediately
        LDA GCM_PT_PTR+0
        STA GCM_CT_PTR+0
        LDA GCM_PT_PTR+1
        STA GCM_CT_PTR+1
        LDA GCM_PT_LEN+0
        STA GCM_CT_LEN+0
        LDA GCM_PT_LEN+1
        STA GCM_CT_LEN+1
        JSR GCM_AUTH            ; expected tag -> GCM_TAG (H/EK0 from GCM_INIT)
        ; received tag = 16 bytes at (GCM_PT_PTR + GCM_PT_LEN)
        CLC
        LDA GCM_PT_PTR+0
        ADC GCM_PT_LEN+0
        STA $FD
        LDA GCM_PT_PTR+1
        ADC GCM_PT_LEN+1
        STA $FE
        LDY #15
AGD_CT  LDA ($FD),Y
        STA GCM_RECV_TAG,Y
        DEY
        BPL AGD_CT
        JMP GCM_VERIFY          ; C=0 valid / C=1 invalid -> to caller

; ================================================================
; SHOW_RECV_MSG  -  show received message in cyan on screen
; RCV_FROM: sender ID, RCV_TEXT: decrypted text
; ================================================================
SHOW_RECV_MSG
        LDA #$0D
        JSR PRINT_CHR
        LDA #$9F            ; cyan
        JSR PRINT_CHR
        LDX #0
SRM_LP  LDA RCV_FROM,X
        BEQ SRM_E
        JSR PRINT_CHR
        INX
        CPX #8
        BNE SRM_LP
SRM_E   LDA #$3E            ; '>'
        JSR PRINT_CHR
        LDA #$20
        JSR PRINT_CHR
        LDA #<RCV_TEXT
        STA $FB
        LDA #>RCV_TEXT
        STA $FC
        JSR PRINT_STR16
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; back to white
        JSR PRINT_CHR
        RTS

; ================================================================
INNER_EMIT
        PHA
        LDA MIJ_LO
        STA $FD
        LDA MIJ_HI
        STA $FE
        PLA
        LDY #0
        STA ($FD),Y
        INC MIJ_LO
        BNE INEM_D
        INC MIJ_HI
INEM_D  INC MSG_INNER_LEN
        RTS

; ================================================================
; INNER_EMIT_STR  -  write null-terminated string via $FB/$FC
; Increments $FB/$FC per char (safe if INNER_EMIT clobbers Y).
; ================================================================
INNER_EMIT_STR
INES_LP LDY #0
        LDA ($FB),Y
        BEQ INES_DN
        JSR INNER_EMIT
        INC $FB
        BNE INES_LP
        INC $FC
        JMP INES_LP
INES_DN RTS

; ================================================================
; INNER_HEX  -  emit byte A as 2 hex-ASCII chars to INNER_BUF
; Uses existing NIBBLE_TO_SCR. Preserves A. Clobbers no X.
; ================================================================
INNER_HEX
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR NIBBLE_TO_SCR
        JSR INNER_EMIT
        PLA
        AND #$0F
        JSR NIBBLE_TO_SCR
        JSR INNER_EMIT
        RTS

; ================================================================
; BUILD_INNER_JSON
; Builds the plaintext for AES-GCM encryption:
;   {"id":"<C64_IDSTR>-<GCM_MSG_CTR as 4 hex>","text":"<INP_BUF>","ts":0}
; Voorbeeld: {"id":"oMiBr6h3K7BsgnwJ-0000","text":"test","ts":0}
;
; Na afloop: GCM_PT_PTR -> MSG_INNER_BUF, GCM_PT_LEN = MSG_INNER_LEN
; Clobbers: A, Y, $FB/$FC, $FD/$FE, MIJ_LO/HI, MSG_INNER_LEN
; ================================================================
BUILD_INNER_JSON
        ; reset write pointer and byte counter
        LDA #<MSG_INNER_BUF
        STA MIJ_LO
        LDA #>MSG_INNER_BUF
        STA MIJ_HI
        LDA #0
        STA MSG_INNER_LEN

        ; {"id":"
        LDA #<STR_INNER_IDHDR
        STA $FB
        LDA #>STR_INNER_IDHDR
        STA $FC
        JSR INNER_EMIT_STR

        ; publicId: C64_IDSTR (16 ASCII chars, null-terminated)
        LDA #<C64_IDSTR
        STA $FB
        LDA #>C64_IDSTR
        STA $FC
        JSR INNER_EMIT_STR

        ; hyphen '-'
        LDA #$2D
        JSR INNER_EMIT

        ; message-unique: GCM_MSG_CTR hi+lo as 4 hex chars
        ; Gives unique IDs per message: 0000 .. FFFF
        LDA GCM_MSG_CTR+1
        JSR INNER_HEX
        LDA GCM_MSG_CTR+0
        JSR INNER_HEX

        ; ","text":"
        LDA #<STR_INNER_TXTHDR
        STA $FB
        LDA #>STR_INNER_TXTHDR
        STA $FC
        JSR INNER_EMIT_STR

        ; message text from INP_BUF (null-terminated)
        LDA #<INP_BUF
        STA $FB
        LDA #>INP_BUF
        STA $FC
        JSR INNER_EMIT_STR

        ; ","ts":0}
        LDA #<STR_INNER_TS
        STA $FB
        LDA #>STR_INNER_TS
        STA $FC
        JSR INNER_EMIT_STR

        ; set AES_GCM_ENCRYPT input to the built inner JSON
        LDA #<MSG_INNER_BUF
        STA GCM_PT_PTR+0
        LDA #>MSG_INNER_BUF
        STA GCM_PT_PTR+1
        LDA MSG_INNER_LEN
        STA GCM_PT_LEN+0
        LDA #0
        STA GCM_PT_LEN+1
        RTS

; ================================================================
; BUILD_GCM_BLOB  -  emitteer {"iv":[...],"data":[...CT...TAG...]}
; ================================================================
; Requires: AES_GCM_ENCRYPT called earlier
;          GCM_PT_LEN = ciphertext length (= plaintext length)
; Writes directly to current JOUT position (no JOUT_INIT call).
; ================================================================
BUILD_GCM_BLOB
        ; {"iv":[
        LDA #<STR_IVHDR
        STA $FB
        LDA #>STR_IVHDR
        STA $FC
        JSR JOUT_EMIT_STR

        ; 12 nonce bytes as comma-separated decimal numbers
        ; Fix: BYTE_TO_DEC clobbers X (internal LDX #0 tens loop).
        ; X after return = tens digit (0..9) -- never >= 12 or 16.
        ; Solution: STX/LDX BGB_XTMP around each BYTE_TO_DEC call.
        LDX #0
BGB_IV  LDA AES_NONCE,X
        STX BGB_XTMP        ; save loop counter before BYTE_TO_DEC
        JSR BYTE_TO_DEC
        LDX BGB_XTMP        ; restore loop counter after BYTE_TO_DEC
        INX
        CPX #12
        BEQ BGB_IVD
        LDA #$2C            ; ','
        JSR JOUT_EMIT
        JMP BGB_IV
BGB_IVD

        ; ],"data":[
        LDA #<STR_DATAHDR
        STA $FB
        LDA #>STR_DATAHDR
        STA $FC
        JSR JOUT_EMIT_STR

        ; ciphertext-bytes (GCM_PT_LEN bytes)
        LDX #0
BGB_CT  LDA GCM_CTBUF,X
        STX BGB_XTMP        ; save loop counter
        JSR BYTE_TO_DEC
        LDX BGB_XTMP        ; restore loop counter
        INX
        CPX GCM_PT_LEN
        BEQ BGB_CTD
        LDA #$2C
        JSR JOUT_EMIT
        JMP BGB_CT
BGB_CTD

        ; comma before tag block
        LDA #$2C
        JSR JOUT_EMIT

        ; 16 GHASH authentication tag bytes
        LDX #0
BGB_TG  LDA GCM_TAG,X
        STX BGB_XTMP        ; save loop counter
        JSR BYTE_TO_DEC
        LDX BGB_XTMP        ; restore loop counter
        INX
        CPX #16
        BEQ BGB_TGD
        LDA #$2C
        JSR JOUT_EMIT
        JMP BGB_TG
BGB_TGD

        ; ]}
        LDA #$5D            ; ']'
        JSR JOUT_EMIT
        LDA #$7D            ; '}'
        JSR JOUT_EMIT
        RTS

; ================================================================
; WS_SEND_EXT  -  send WebSocket text frame (supports >125 bytes)
; ================================================================
; Input  : JOUT_BUF = payload, JOUT_LEN[0..1] = payload length
; Protocol: FIN=1, opcode=text(1); masking always on
;   <= 125 bytes : 1-byte length
;  126..65535 bytes : length byte $7E + 2-byte big-endian length
; Masking key: WS_MASK ($37,$FA,$21,$3D) - fixed for simplicity
; Pointer $FD/$FE used as read zero-page pointer
; ================================================================
WS_SEND_EXT
        ; FIN + text opcode
        LDA #$81
        JSR ACIA_SEND

        ; determine length encoding
        LDA JOUT_LEN+1
        BNE WSX_EXT             ; hi-byte != 0 -> zeker >= 256 > 125
        LDA JOUT_LEN+0
        CMP #126
        BCS WSX_EXT             ; >= 126 -> extended 2-byte length
        ; direct 7-bit length + mask bit ($80)
        ORA #$80
        JSR ACIA_SEND
        JMP WSX_MASK

WSX_EXT ; length byte $7E (126) with mask bit = $FE
        LDA #$FE
        JSR ACIA_SEND
        LDA JOUT_LEN+1          ; big-endian high byte
        JSR ACIA_SEND
        LDA JOUT_LEN+0          ; big-endian low byte
        JSR ACIA_SEND

WSX_MASK
        ; send fixed 4-byte masking key
        LDA #$37
        JSR ACIA_SEND
        LDA #$FA
        JSR ACIA_SEND
        LDA #$21
        JSR ACIA_SEND
        LDA #$3D
        JSR ACIA_SEND

        ; set read pointer via zero-page $FD/$FE
        LDA #<JOUT_BUF
        STA $FD
        LDA #>JOUT_BUF
        STA $FE

        ; resterende bytes = JOUT_LEN
        LDA JOUT_LEN+0
        STA WSX_REM+0
        LDA JOUT_LEN+1
        STA WSX_REM+1

        ; mask-byte-index: 0..3 (cyclisch)
        LDA #0
        STA WSX_MIDX

WSX_LP  LDA WSX_REM+0
        ORA WSX_REM+1
        BEQ WSX_DN              ; done when REM = 0

        ; read payload byte via zeropage pointer
        LDY #0
        LDA ($FD),Y

        ; XOR with masking byte (WSX_MIDX mod 4)
        LDX WSX_MIDX
        EOR WS_MASK,X
        JSR ACIA_SEND

        ; advance read pointer
        INC $FD
        BNE WSX_NP
        INC $FE
WSX_NP

        ; cyclisch masking-index (0->1->2->3->0)
        INC WSX_MIDX
        LDA WSX_MIDX
        AND #$03
        STA WSX_MIDX

        ; decrement 16-bit counter
        LDA WSX_REM+0
        BNE WSX_DCL
        DEC WSX_REM+1
WSX_DCL DEC WSX_REM+0
        JMP WSX_LP

WSX_DN  RTS

; ================================================================
; WS_AUTH - challenge-response authentication with server.py (HEAD)
;  1) send {"type":"sig:auth_init","bits":128,"enc_key":[..16..]}
;  2) wait for sig:auth_challenge {"iv":[12],"data":[48]}
;  3) GCM-decrypt with KEY_SELF -> 32-byte nonce in GCM_CTBUF
;  4) send {"type":"sig:auth_proof","nonce":[..32..]}
;  5) wait for sig:auth_ok -> C=0; auth_fail/timeout -> C=1
; Requires: INSTALL_RX_NMI already active (steps 2/5 receive frames).
; ================================================================
; ================================================================
; 128-bit WS_AUTH + WS_SEND_MSG REMOVED (AES128 cleanup).
; USE_256 is always 1, so these paths were unreachable. Safe
; stubs keep the dispatcher JMPs (WAD_128/WSD_128) valid and route
; to the 256-bit routines. The SHARED GCM/GHASH core after this
; (GCM_INIT etc.) stays fully intact and is pinned at its original
; address, so all live code stays byte-identical.
; ================================================================
WS_AUTH
        JMP WS_AUTH256
WS_SEND_MSG
        JMP WS_SEND_MSG256
* = $3332                       ; pin: GCM_INIT at original address
; ================================================================
; GCM_INIT -- compute hash subkey H and tag encryption block EK0
; ================================================================
; Input  : AES_RK filled, AES_NONCE[0..11] set
; Output: GCM_H[0..15], GCM_EK0[0..15]
; Clobbers: AES_BLOCK, AES_STATE (via AES_ENCRYPT_BLOCK)
; ================================================================
GCM_INIT

        ; H = AES_ENCRYPT(key, 0^16)
        LDX #15
        LDA #$00
GCI_ZB  STA AES_BLOCK,X         ; clear input block
        DEX
        BPL GCI_ZB
        JSR AES_ENCRYPT_BLOCK
        LDX #15
GCI_CH  LDA AES_BLOCK,X
        STA GCM_H,X
        DEX
        BPL GCI_CH

        ; EK0 = AES_ENCRYPT(key, nonce || $00000001)
        ; This is GCM J0: counter = 1, reserved for tag masking
        ; AES_CTR_CRYPT starts at $00000002 (counter 2+) -> spec-compliant ?
        LDX #11
GCI_CN  LDA AES_NONCE,X
        STA AES_BLOCK,X
        DEX
        BPL GCI_CN
        LDA #$00
        STA AES_BLOCK+12
        STA AES_BLOCK+13
        STA AES_BLOCK+14
        LDA #$01
        STA AES_BLOCK+15
        JSR AES_ENCRYPT_BLOCK
        LDX #15
GCI_CE  LDA AES_BLOCK,X
        STA GCM_EK0,X
        DEX
        BPL GCI_CE
        RTS

; ================================================================
; GCM_AUTH -- compute authentication tag
; ================================================================
; Input  : GCM_CT_PTR[0/1] lo/hi address of ciphertext
;          GCM_CT_LEN       length of ciphertext 1..255 bytes
;          GCM_H, GCM_EK0 already computed via GCM_INIT
; Output: GCM_TAG[0..15]
;
; GHASH algorithm (empty AAD):
;   Y = 0
;   for each 16-byte CT block C_i (zero-pad the last):
;       Y = GF_MUL(Y XOR C_i, H)
;   length block = 0^8 || big-endian64(CT_LEN*8)
;   Y = GF_MUL(Y XOR length block, H)
;   TAG = Y XOR EK0
;
; Self-modifying: GCAS_SRC+1/+2 patched with GCM_CT_PTR
; ================================================================
GCM_AUTH

        LDX #15
        LDA #$00
GCA_ZY  STA GCM_Y,X
        DEX
        BPL GCA_ZY
        LDA GCM_CT_PTR+0
        STA GCAS_SRC+1
        LDA GCM_CT_PTR+1
        STA GCAS_SRC+2
        LDA GCM_CT_LEN+0
        STA GCM_BREM+0
        LDA GCM_CT_LEN+1
        STA GCM_BREM+1
GCA_BLK
        LDA GCM_BREM+0
        ORA GCM_BREM+1
        BNE GCA_BC
        JMP GCA_LEND
GCA_BC
        LDA GCM_BREM+1
        BNE GCA_F16
        LDA GCM_BREM+0
        CMP #16
        BCS GCA_F16
        STA GCM_GBSIZ
        JMP GCA_ZBUF
GCA_F16 LDA #16
        STA GCM_GBSIZ
GCA_ZBUF
        LDX #15
        LDA #$00
GCA_ZB  STA GCM_BLK,X
        DEX
        BPL GCA_ZB
        LDX #0
GCA_CPL CPX GCM_GBSIZ
        BNE GCA_CPC
        JMP GCA_CPD
GCA_CPC
        TXA
        TAY
GCAS_SRC LDA $1234,Y
        STA GCM_BLK,X
        INX
        JMP GCA_CPL
GCA_CPD
        LDX #15
GCA_XY  LDA GCM_Y,X
        EOR GCM_BLK,X
        STA GCM_Y,X
        DEX
        BPL GCA_XY
        JSR GCA_MUL
        LDA GCAS_SRC+1
        CLC
        ADC GCM_GBSIZ
        STA GCAS_SRC+1
        BCC GCA_NB
        INC GCAS_SRC+2
GCA_NB
        LDA GCM_BREM+0
        SEC
        SBC GCM_GBSIZ
        STA GCM_BREM+0
        LDA GCM_BREM+1
        SBC #0
        STA GCM_BREM+1
        JMP GCA_BLK
GCA_LEND
        LDX #15
        LDA #$00
GCA_ZL  STA GCM_BLK,X
        DEX
        BPL GCA_ZL
        LDA GCM_CT_LEN+0
        STA GCA_LB0
        LDA GCM_CT_LEN+1
        STA GCA_LB1
        ASL GCA_LB0
        ROL GCA_LB1
        ASL GCA_LB0
        ROL GCA_LB1
        ASL GCA_LB0
        ROL GCA_LB1
        LDA GCA_LB1
        STA GCM_BLK+14
        LDA GCA_LB0
        STA GCM_BLK+15
        LDX #15
GCA_XL  LDA GCM_Y,X
        EOR GCM_BLK,X
        STA GCM_Y,X
        DEX
        BPL GCA_XL
        JSR GCA_MUL
        LDX #15
GCA_TG  LDA GCM_Y,X
        EOR GCM_EK0,X
        STA GCM_TAG,X
        DEX
        BPL GCA_TG
        RTS

; ---- hulp: Y -> GCM_GX, H -> GCM_GY, GF_MUL, GCM_GZ -> Y -------
GCA_MUL
        LDX #15
GCA_MX  LDA GCM_Y,X
        STA GCM_GX,X
        DEX
        BPL GCA_MX
        LDX #15
GCA_MY  LDA GCM_H,X
        STA GCM_GY,X
        DEX
        BPL GCA_MY
        JSR GCM_GFMUL
        LDX #15
GCA_MR  LDA GCM_GZ,X
        STA GCM_Y,X
        DEX
        BPL GCA_MR
        RTS

; ================================================================
; GCM_VERIFY -- compare GCM_TAG with GCM_RECV_TAG
; ================================================================
; Output: C=0 tag valid / C=1 tag invalid
; ================================================================
GCM_VERIFY
        LDX #15
GCV_LP  LDA GCM_TAG,X
        CMP GCM_RECV_TAG,X
        BNE GCV_FAIL
        DEX
        BPL GCV_LP
        CLC
        RTS
GCV_FAIL
        SEC
        RTS

; ================================================================
; GCM_GFMUL -- vermenigvuldiging in GF(2^128)
; ================================================================
; Input  : GCM_GX[0..15], GCM_GY[0..15]  (16 bytes, big-endian)
; Output: GCM_GZ[0..15] = GCM_GX * GCM_GY mod p
;
; Methode: MSB-first shift-and-XOR (128 iteraties)
;   Z = 0 ; V = X
;   for bit i of Y (MSB -> LSB, from byte 0 to byte 15):
;     if bit i = 1: Z ^= V
;     old_lsb = bit 0 of V[15]
;     V >>= 1  (shift right, big-endian, bit 127 becomes 0)
;     if old_lsb = 1: V[0] ^= $E1   (reduction mod p)
;
; Reductiepolynoom: x^128 + x^7 + x^2 + x + 1
; Reductieconstante: R = $E1 00 00 ... 00  (MSB-first, byte 0)
;   because x^128 = x^7 + x^2 + x + 1 -> lowest bits = 1110 0001 = $E1
;
; Backward branch GFM_BLOOP: ~82 bytes -- within 127-byte limit ?
; ================================================================
GCM_GFMUL

        ; Z = 0
        LDX #15
        LDA #$00
GFM_CZ  STA GCM_GZ,X
        DEX
        BPL GFM_CZ

        ; V = X
        LDX #15
GFM_CV  LDA GCM_GX,X
        STA GCM_VBUF,X
        DEX
        BPL GFM_CV

        LDA #0
        STA GCM_GYCNT           ; Y byte index: 0..15

; ---- outer loop: per byte of Y (MSB first) ----------------
GFM_YLOOP
        LDA GCM_GYCNT
        CMP #16
        BNE GFM_YC
        JMP GFM_DONE
GFM_YC  TAX
        LDA GCM_GY,X            ; load current Y-byte
        STA GCM_GYBYTE
        LDA #8
        STA GCM_GBIT            ; counts down 8->1

; ---- inner loop: per bit of Y-byte (MSB first via ASL) ----
; Bewezen backward-branch afstand ? 82 bytes (< 127 limiet):
;   GFM_BLOOP t/m DEC GCM_GBIT = 80 bytes; BNE offset = -82
GFM_BLOOP
        ASL GCM_GYBYTE          ; MSB to carry; byte shifts left
        BCC GFM_NOZ
        JSR GFM_ZXV             ; Z ^= V  (carry=1 -> bit was 1)
GFM_NOZ
        ; save LSB of V (bit 0 of byte 15) for shift
        LDA GCM_VBUF+15
        AND #$01
        STA GCM_GLSB

        ; V >>= 1  (shift right: LSR byte[0], then ROR through)
        LSR GCM_VBUF+0
        ROR GCM_VBUF+1
        ROR GCM_VBUF+2
        ROR GCM_VBUF+3
        ROR GCM_VBUF+4
        ROR GCM_VBUF+5
        ROR GCM_VBUF+6
        ROR GCM_VBUF+7
        ROR GCM_VBUF+8
        ROR GCM_VBUF+9
        ROR GCM_VBUF+10
        ROR GCM_VBUF+11
        ROR GCM_VBUF+12
        ROR GCM_VBUF+13
        ROR GCM_VBUF+14
        ROR GCM_VBUF+15

        ; if old LSB was 1: V[0] ^= $E1  (GF reduction)
        LDA GCM_GLSB
        BEQ GFM_NOR
        LDA GCM_VBUF+0
        EOR #$E1
        STA GCM_VBUF+0
GFM_NOR
        DEC GCM_GBIT
        BNE GFM_BLOOP           ; 8 bits per Y-byte (backward: -82 bytes)

        INC GCM_GYCNT
        JMP GFM_YLOOP

GFM_DONE
        RTS

; ---- Z ^= V  (subroutine; called from the inner bit loop) -
GFM_ZXV
        LDX #15
GFZ_LP  LDA GCM_GZ,X
        EOR GCM_VBUF,X
        STA GCM_GZ,X
        DEX
        BPL GFZ_LP
        RTS

; ================================================================
; DATA
; ================================================================

OPER_A   !byte 0,0,0,0,0,0,0,0
OPER_B   !byte 0,0,0,0,0,0,0,0
OPER_C   !byte 0,0,0,0,0,0,0,0

WORD_A   !byte 0,0,0,0
WORD_B   !byte 0,0,0,0
WORD_C   !byte 0,0,0,0

SIGMA_T  !byte 0,0,0,0
SIGMA_U  !byte 0,0,0,0

SHA_A    !byte 0,0,0,0
SHA_B    !byte 0,0,0,0
SHA_C    !byte 0,0,0,0
SHA_D    !byte 0,0,0,0
SHA_E    !byte 0,0,0,0
SHA_F    !byte 0,0,0,0
SHA_G    !byte 0,0,0,0
SHA_HH   !byte 0,0,0,0

SHA_H0   !byte 0,0,0,0
SHA_H1   !byte 0,0,0,0
SHA_H2   !byte 0,0,0,0
SHA_H3   !byte 0,0,0,0
SHA_H4   !byte 0,0,0,0
SHA_H5   !byte 0,0,0,0
SHA_H6   !byte 0,0,0,0
SHA_H7   !byte 0,0,0,0

T1       !byte 0,0,0,0
T2       !byte 0,0,0,0

SHA_MLEN !byte 0
SHA_YNDX !byte 0
EXPAND_T !byte 0,0,0,0

SHA_BLK  !fill 64,0
SHA_W    !fill 256,0

HMAC_KEY   !fill 64,0
HMAC_MSG   !fill 64,0
HMAC_INNER !fill 32,0
HMAC_OUT   !fill 32,0
HMAC_MLEN  !byte 0

PBKDF2_PWD    !fill 64,0
PBKDF2_PWDLEN !byte 0
PBKDF2_SALT   !fill 51,0
PBKDF2_SALTLEN !byte 0
PBKDF2_DK     !fill 32,0
PBKDF2_ITRLO  !byte 0
PBKDF2_ITRMID !byte 0
PBKDF2_ITRHI  !byte 0
PBKDF2_CTRLO  !byte 0
PBKDF2_CTRMID !byte 0
PBKDF2_CTRHI  !byte 0

HKDF_SALT    !fill 64,0
HKDF_SALTLEN !byte 0
HKDF_IKM     !fill 32,0
HKDF_IKMLEN  !byte 0
HKDF_PRK     !fill 32,0
HKDF_INFO    !fill 24,0
HKDF_INFOLEN !byte 0
HKDF_OKM     !fill 64,0
KEY_SELF     !byte $05,$7E,$D4,$62,$49,$EF,$60,$E5,$FD,$9C,$59,$AE,$DC,$E5,$6A,$0C   ; BX7U: own key (decrypt + identity)
KEY_PEER     !byte $82,$3D,$C6,$1F,$8B,$F4,$FC,$4F,$5D,$61,$39,$D9,$BC,$0C,$EF,$9A   ; Harry128: peer key (encrypt outgoing)
KEY_PEER256  !fill 32,$00     ; 256-bit peer encKey (from contact shareable)
USE_256      !byte 0          ; mode flag: 0=128-bit path, 1=256-bit path
B64E_IN      !fill 32,0       ; encoder input (32 bytes)
B64E_OUT     !fill 44,0       ; encoder output (43 chars + space)
B64E_GRP     !byte 0
B64E_B0      !byte 0
B64E_B1      !byte 0
B64E_B2      !byte 0
B64E_T       !byte 0
SHARE_STR    !fill 160,0      ; own shareable: 3 segments + null
STR_RELAY_B64
        !text "d3NzOi8veW91ci1tZXNoY2hhdC1yZWxheS5uZXQvd3Mv"   ; RELAY CONFIG: base64 of your wss URL, embedded in the shareable (btoa(wss://your-meshchat-relay.net/ws/))
STR_SHARE_LBL
        !text "SHAREABLE:"
        !byte 0
STR_BOOT_MENU
        !text "SELECT IDENTITY:"
        !byte $0D, $0D
        !text " 1 = 128-BIT (PASTE KEYS)  "
        !byte $0D
        !text " 2 = 256-BIT (PHRASE)  "
        !byte $0D, $0D
        !text " CHOICE (1/2):"
        !byte 0
PEER_IDBYTES !fill 12,0       ; SHA-256(KEY_PEER256)[0:12]
STR_PEER_P
        !text "PEER SHAREABLE (NONE=SELF):"
        !byte 0
STR_PEER_ERR
        !text "INVALID KEY  "
        !byte $0D,0
KEY_SIGN_SELF !fill 16,0   ; own 16-byte sign key (part after '.' of own shareableKey); HMAC key for outgoing sig
BLOB_PTR     !byte $00,$00 ; sig-MAC: JOUT address of blob start
BLOB_LEN0    !byte $00,$00 ; sig-MAC: JOUT_LEN before the blob
MAC_LEN      !byte $00,$00 ; sig-MAC: blob length (16-bit)
MAC_CTBUF    !fill 1280,$00 ; sig-MAC: scratch ciphertext (blob string length)

; -- paste-encKey setup (MC_SETUP) --
ID_KEY_IN    !fill 16,0     ; staging for COMPUTE_ID_CORE
PEER_IDSTR   !fill 17,0     ; peer-publicId ('to'-veld) + null
B64D_OUT     !fill 16,0     ; B64URL_DECODE22 output
B64D_V0      !byte 0
B64D_V1      !byte 0
B64D_V2      !byte 0
B64D_V3      !byte 0
B64D_T       !byte 0
B64D_GRP     !byte 0
B64D_IIX     !byte 0
WA_TRY       !byte 0        ; WS_AUTH frame/timeout counter

STR_KEY1_P
        !text "YOUR ENCKEY (22): "
        !byte 0
STR_KEY2_P
        !text "PEER ENCKEY (22): "
        !byte 0
STR_KEY3_P
        !text "YOUR SIGNKEY (22): "
        !byte 0
STR_KEYBAD
        !text "INVALID: NEED 22 BASE64URL CHARS   "
        !byte 0
STR_PEER_LBL
        !text "PEER: "
        !byte 0
STR_AUTH_BUSY
        !text "CONNECTING TO RELAY..."
        !byte 0
STR_AUTH_OK
        !text "CONNECTED!"
        !byte 0
STR_AUTH_ERR
        !text "AUTH FAILED "
        !byte 0
STR_BADTAG
        !text "!! BAD TAG - MESSAGE IGNORED       "
        !byte 0
STR_RXOVF
        !text "  (RX OVERFLOW - RING FULL)"
        !byte 0
STR_TOOBIG
        !text "!! FRAME TOO BIG -  $"
        !byte 0
STR_TOOLONG
        !text "!! MESSAGE TOO LONG (MAX ~550 CHARS)"
        !byte 0
STR_TOOBIGRC
        !text "!! FRAME TOO BIG - RECONNECTING "
        !byte 0

KDFIN_NAME    !fill 32,0
KDFIN_NAMELEN !byte 0
KDFIN_PASS    !fill 64,0
KDFIN_PASSLEN !byte 0

ELAPSED  !byte 0,0,0

USER_ID  !fill 32,0

DV_TMPLEN !byte 0
DBG_LO   !byte 0
DBG_HI   !byte 0
DBG_IDX  !byte 0

; ── UI strings ──────────────────────────────────────────────────
STR_TITLE
        !text " ** MESHCHAT 64 ** "
        !byte 0

STR_NAAM_P
        !text "NAME     : "
        !byte 0

STR_PASS_P
        !text "PHRASE   : "
        !byte 0

STR_BEZIG
        !text "KEY DERIVATION RUNNING..."
        !byte 0

STR_WACHT
        !text "PROGRESS (CA. 7 MIN) "
        !byte 0

STR_KLAAR
        !text "READY! PRESS SPACE TO CHAT.      "
        !byte 0

STR_ID_LBL
        !text "ID: "
        !byte 0

STR_DIV
        !text "----------------------------------------"
        !byte 0

STR_PFX
        !text "> "
        !byte 0

; ── Invoerbuffer ────────────────────────────────────────────────
INP_BUF  !fill 256,0
INP_LEN  !byte 0

STR_AT  !text "AT"
        !byte $0D, $00


AT_BUF   !fill 16,0
AT_CNT   !byte 0
CIA_MSCTR !byte 0       ; Bug 6: CIA2_WAIT_10MS counter


STR_ATDT !text "ATDT192.168.1.100:8889"   ; RELAY CONFIG: your nginx LAN door -> backend 127.0.0.1:8888 (must match nginx listen)
; via TLS-proxy: ;STR_ATDT !text "ATDTyour-meshchat-relay.net:8888"
         !byte $0D,$0D,$0D,$00    ; three CRs instead of one


STR_WS_HDR
        !text "GET / HTTP/1.1"
        !byte $0D,$0A
        !text "Host: 192.168.1.100:8889"
        !byte $0D,$0A
        !text "Upgrade: websocket"
        !byte $0D,$0A
        !text "Connection: Upgrade"
        !byte $0D,$0A
        !text "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="
        !byte $0D,$0A
        !text "Sec-WebSocket-Version: 13"
        !byte $0D,$0A
        !byte $0D,$0A,$00

STR_WS_CONN
        ; {"type":"connect","id":"C64TEST"}
        !byte $7B,$22,$74,$79,$70,$65,$22,$3A,$22
        !byte $63,$6F,$6E,$6E,$65,$63,$74,$22,$2C
        !byte $22,$69,$64,$22,$3A,$22
        !byte $43,$36,$34,$54,$45,$53,$54
        !byte $22,$7D,$00


STR_AT_WAKE
        !byte $0D       ; leading CR
        !text "AT"
        !byte $0D,$00


; ================================================================
; SHA-256 K CONSTANTS
; ================================================================
SHA_K
!byte $42,$8a,$2f,$98
!byte $71,$37,$44,$91
!byte $b5,$c0,$fb,$cf
!byte $e9,$b5,$db,$a5
!byte $39,$56,$c2,$5b
!byte $59,$f1,$11,$f1
!byte $92,$3f,$82,$a4
!byte $ab,$1c,$5e,$d5
!byte $d8,$07,$aa,$98
!byte $12,$83,$5b,$01
!byte $24,$31,$85,$be
!byte $55,$0c,$7d,$c3
!byte $72,$be,$5d,$74
!byte $80,$de,$b1,$fe
!byte $9b,$dc,$06,$a7
!byte $c1,$9b,$f1,$74
!byte $e4,$9b,$69,$c1
!byte $ef,$be,$47,$86
!byte $0f,$c1,$9d,$c6
!byte $24,$0c,$a1,$cc
!byte $2d,$e9,$2c,$6f
!byte $4a,$74,$84,$aa
!byte $5c,$b0,$a9,$dc
!byte $76,$f9,$88,$da
!byte $98,$3e,$51,$52
!byte $a8,$31,$c6,$6d
!byte $b0,$03,$27,$c8
!byte $bf,$59,$7f,$c7
!byte $c6,$e0,$0b,$f3
!byte $d5,$a7,$91,$47
!byte $06,$ca,$63,$51
!byte $14,$29,$29,$67
!byte $27,$b7,$0a,$85
!byte $2e,$1b,$21,$38
!byte $4d,$2c,$6d,$fc
!byte $53,$38,$0d,$13
!byte $65,$0a,$73,$54
!byte $76,$6a,$0a,$bb
!byte $81,$c2,$c9,$2e
!byte $92,$72,$2c,$85
!byte $a2,$bf,$e8,$a1
!byte $a8,$1a,$66,$4b
!byte $c2,$4b,$8b,$70
!byte $c7,$6c,$51,$a3
!byte $d1,$92,$e8,$19
!byte $d6,$99,$06,$24
!byte $f4,$0e,$35,$85
!byte $10,$6a,$a0,$70
!byte $19,$a4,$c1,$16
!byte $1e,$37,$6c,$08
!byte $27,$48,$77,$4c
!byte $34,$b0,$bc,$b5
!byte $39,$1c,$0c,$b3
!byte $4e,$d8,$aa,$4a
!byte $5b,$9c,$ca,$4f
!byte $68,$2e,$6f,$f3
!byte $74,$8f,$82,$ee
!byte $78,$a5,$63,$6f
!byte $84,$c8,$78,$14
!byte $8c,$c7,$02,$08
!byte $90,$be,$ff,$fa
!byte $a4,$50,$6c,$eb
!byte $be,$f9,$a3,$f7
!byte $c6,$71,$78,$f2

; ================================================================
; Connect JSON header: {"type":"connect","id":"
; (used by main program via JOUT_EMIT_STR)
; ================================================================
STR_CONN_HDR
        !byte $7B,$22,$74,$79,$70,$65,$22,$3A,$22   ; {"type":"
        !byte $63,$6F,$6E,$6E,$65,$63,$74,$22,$2C   ; connect",
        !byte $22,$69,$64,$22,$3A,$22               ; "id":"
        !byte 0


CONN_BUF !fill 50,0


; ================================================================
; AES-128 SINGLE BLOCK ENCRYPTION
; (integrated from aes128.asm)
; API:
;   AES_SETKEY         - fill AES_KEY[0..15], call once
;   AES_ENCRYPT_BLOCK  - encrypt AES_BLOCK[0..15] in-place
; ================================================================

; ================================================================
XTIME
        ASL                     ; shift left; MSB goes into carry
        BCC XTIME_OK
        EOR #$1B                ; reduce: XOR 0x1B on overflow
XTIME_OK
        RTS

; ================================================================
; AES_SETKEY  -  key expansion
;
;   Input : AES_KEY[0..15]
;   Output: AES_RK[0..175]   (W[0]..W[43], each word = 4 bytes)
;
;   AES_WOFF = write offset in bytes (runs from 16 to 172 in steps of 4)
;
;   For i >= 4:
;     if i mod 4 = 0 : SubWord( RotWord( W[i-1] ) )  XOR  Rcon[i/4-1]
;     anders          : W[i-1]
;   result XOR W[i-4]  ->  W[i]
;
;   Trick for offset calculation:
;     LDA AES_RK-4,X  =  LDA  (address of AES_RK - 4) + X
;     Valid 6502 absolute,X - the assembler computes the base address.
; ================================================================
AES_SETKEY
        LDA #10            ; AES-128: 10 ronden
        STA AES_NR
        ; copy key bytes directly to RK[0..15]
        LDX #15
ASKS_CP LDA AES_KEY,X
        STA AES_RK,X
        DEX
        BPL ASKS_CP

        LDA #16
        STA AES_WOFF            ; start bij W[4] (byte-offset 16)

ASKS_LP LDA AES_WOFF
        CMP #176
        BNE ASKS_CONT
        JMP ASKS_DN
ASKS_CONT

        ; --- load W[i-1] = AES_RK[ WOFF-4 .. WOFF-1 ] into AES_T4 ---
        LDX AES_WOFF
        LDA AES_RK-4,X          ; W[i-1] byte 0
        STA AES_T4+0
        LDA AES_RK-3,X          ; W[i-1] byte 1
        STA AES_T4+1
        LDA AES_RK-2,X          ; W[i-1] byte 2
        STA AES_T4+2
        LDA AES_RK-1,X          ; W[i-1] byte 3
        STA AES_T4+3

        ; only transform if WOFF is a multiple of 16 (i mod 4 = 0)
        LDA AES_WOFF
        AND #$0F
        BNE ASKS_XOR            ; not a multiple -> skip RotSub

        ; ---- RotWord: [a0,a1,a2,a3] -> [a1,a2,a3,a0] -----------
        LDA AES_T4+0
        PHA                     ; save a0
        LDA AES_T4+1
        STA AES_T4+0
        LDA AES_T4+2
        STA AES_T4+1
        LDA AES_T4+3
        STA AES_T4+2
        PLA
        STA AES_T4+3

        ; ---- SubWord via S-box ----------------------------------
        LDA AES_T4+0
        TAX
        LDA AES_SBOX,X
        STA AES_T4+0
        LDA AES_T4+1
        TAX
        LDA AES_SBOX,X
        STA AES_T4+1
        LDA AES_T4+2
        TAX
        LDA AES_SBOX,X
        STA AES_T4+2
        LDA AES_T4+3
        TAX
        LDA AES_SBOX,X
        STA AES_T4+3

        ; ---- XOR T4[0] with Rcon[ WOFF/16 - 1 ] -----------------
        LDA AES_WOFF
        LSR
        LSR
        LSR
        LSR                     ; = WOFF / 16  (gives 1..10)
        TAX
        DEX                     ; 0-based index into AES_RCON
        LDA AES_RCON,X
        EOR AES_T4+0
        STA AES_T4+0

ASKS_XOR
        ; XOR T4 with W[i-4] = AES_RK[ WOFF-16 .. WOFF-13 ]
        LDX AES_WOFF
        LDA AES_T4+0
        EOR AES_RK-16,X
        STA AES_T4+0
        LDA AES_T4+1
        EOR AES_RK-15,X
        STA AES_T4+1
        LDA AES_T4+2
        EOR AES_RK-14,X
        STA AES_T4+2
        LDA AES_T4+3
        EOR AES_RK-13,X
        STA AES_T4+3

        ; store W[i] in AES_RK[ WOFF .. WOFF+3 ]
        ; X = AES_WOFF  (still valid after the read/store sequence above)
        LDA AES_T4+0
        STA AES_RK+0,X
        LDA AES_T4+1
        STA AES_RK+1,X
        LDA AES_T4+2
        STA AES_RK+2,X
        LDA AES_T4+3
        STA AES_RK+3,X

        LDA AES_WOFF
        CLC
        ADC #4
        STA AES_WOFF
        JMP ASKS_LP

ASKS_DN RTS

; ================================================================
; AES_ENCRYPT_BLOCK  -  encrypt AES_BLOCK in-place
;
;   Requires: AES_RK is filled by AES_SETKEY.
;
;   Ronden:
;     0       : only AddRoundKey
;     1..9    : SubBytes + ShiftRows + MixColumns + AddRoundKey
;    10 (fin) : SubBytes + ShiftRows + AddRoundKey  (no Mix)
; ================================================================
AES_ENCRYPT_BLOCK
        ; copy plaintext to work state
        LDX #15
AESB_CI LDA AES_BLOCK,X
        STA AES_STATE,X
        DEX
        BPL AESB_CI

        ; Ronde 0 - AddRoundKey
        LDA #0
        STA AES_RNDOFF
        JSR AES_ARK

        LDA #1
        STA AES_RNDCNT

AESB_RL LDA AES_RNDCNT
        CMP AES_NR              ; 10 (AES-128) / 14 (AES-256)
        BEQ AESB_FN

        JSR AES_SUBBYTES
        JSR AES_SHIFTROWS
        JSR AES_MIXCOLS

        LDA AES_RNDCNT
        ASL
        ASL
        ASL
        ASL                     ; ronde x 16 = byte-offset in AES_RK
        STA AES_RNDOFF
        JSR AES_ARK

        INC AES_RNDCNT
        JMP AESB_RL

AESB_FN ; round 10 - no MixColumns
        JSR AES_SUBBYTES
        JSR AES_SHIFTROWS
        LDA AES_NR              ; Nr*16 (160 / 224)
        ASL
        ASL
        ASL
        ASL
        STA AES_RNDOFF
        JSR AES_ARK

        ; write result back to AES_BLOCK
        LDX #15
AESB_CO LDA AES_STATE,X
        STA AES_BLOCK,X
        DEX
        BPL AESB_CO
        RTS

; ================================================================
; AES-256: key schedule + GCM entries (from aes256test.asm,
;   byte-exact getoetst). AES_SETKEY->AES256_SETKEY hernoemd.
; ================================================================
AES256_SETKEY
        LDA #14            ; AES-256: 14 ronden
        STA AES_NR
        LDX #31                 ; copy 32 key bytes to RK[0..31]
SK2_CP  LDA AES_KEY,X
        STA AES_RK,X
        DEX
        BPL SK2_CP

        LDA #32
        STA AES_WOFF            ; start W[8] (byte-offset 32)

SK2_LP  LDA AES_WOFF
        CMP #240
        BNE SK2_CONT
        JMP SK2_DN
SK2_CONT
        ; --- load W[i-1] = AES_RK[woff-4 .. woff-1] into AES_T4 ---
        LDX AES_WOFF
        LDA AES_RK-4,X
        STA AES_T4+0
        LDA AES_RK-3,X
        STA AES_T4+1
        LDA AES_RK-2,X
        STA AES_T4+2
        LDA AES_RK-1,X
        STA AES_T4+3

        ; --- transform choice based on woff mod 32 ---
        LDA AES_WOFF
        AND #$1F
        BEQ SK2_FULL            ; mod 32 == 0
        CMP #16
        BEQ SK2_SUBONLY         ; mod 32 == 16
        JMP SK2_XOR             ; anders: temp = W[i-1] ongewijzigd

SK2_FULL
        ; RotWord: [a0,a1,a2,a3] -> [a1,a2,a3,a0]
        LDA AES_T4+0
        PHA
        LDA AES_T4+1
        STA AES_T4+0
        LDA AES_T4+2
        STA AES_T4+1
        LDA AES_T4+3
        STA AES_T4+2
        PLA
        STA AES_T4+3
        JSR SK2_SUBWORD
        ; XOR Rcon[woff/32 - 1]
        LDA AES_WOFF
        LSR
        LSR
        LSR
        LSR
        LSR                     ; / 32  -> 1..7
        TAX
        DEX                     ; 0..6
        LDA AES_RCON,X
        EOR AES_T4+0
        STA AES_T4+0
        JMP SK2_XOR

SK2_SUBONLY
        JSR SK2_SUBWORD

SK2_XOR
        ; W[i] = W[i-8] XOR temp ; W[i-8] = AES_RK[woff-32 .. woff-29]
        LDX AES_WOFF
        LDA AES_T4+0
        EOR AES_RK-32,X
        STA AES_RK+0,X
        LDA AES_T4+1
        EOR AES_RK-31,X
        STA AES_RK+1,X
        LDA AES_T4+2
        EOR AES_RK-30,X
        STA AES_RK+2,X
        LDA AES_T4+3
        EOR AES_RK-29,X
        STA AES_RK+3,X

        LDA AES_WOFF
        CLC
        ADC #4
        STA AES_WOFF
        JMP SK2_LP

SK2_DN  RTS

; SubWord: replace each of 4 bytes via S-box
SK2_SUBWORD
        LDA AES_T4+0
        TAX
        LDA AES_SBOX,X
        STA AES_T4+0
        LDA AES_T4+1
        TAX
        LDA AES_SBOX,X
        STA AES_T4+1
        LDA AES_T4+2
        TAX
        LDA AES_SBOX,X
        STA AES_T4+2
        LDA AES_T4+3
        TAX
        LDA AES_SBOX,X
        STA AES_T4+3
        RTS

; ================================================================
; AGE256 - AES-256-GCM encrypt (fixed nonce set by the caller)
;   in : AES_KEY[32], AES_NONCE[12], PTBUF, PTLEN(16b)
;   out: CTBUF[0..PTLEN-1], GCM_TAG[0..15]
; ================================================================
AGE256
        JSR AES256_SETKEY
        JSR GCM_INIT                ; H + EK0 (uses AES_NONCE)
        LDA #<PTBUF
        STA AES_CTR_IN+0
        LDA #>PTBUF
        STA AES_CTR_IN+1
        LDA #<CTBUF
        STA AES_CTR_OUT+0
        LDA #>CTBUF
        STA AES_CTR_OUT+1
        LDA PTLEN+0
        STA AES_CTR_LEN+0
        LDA PTLEN+1
        STA AES_CTR_LEN+1
        JSR AES_CTR_CRYPT
        LDA #<CTBUF
        STA GCM_CT_PTR+0
        LDA #>CTBUF
        STA GCM_CT_PTR+1
        LDA PTLEN+0
        STA GCM_CT_LEN+0
        LDA PTLEN+1
        STA GCM_CT_LEN+1
        JSR GCM_AUTH                ; -> GCM_TAG
        RTS

; ================================================================
; AGD256 - AES-256-GCM decrypt + tagverificatie
;   in : AES_KEY[32], AES_NONCE[12], CTBUF (received CT), PTLEN(16b),
;        GCM_RECV_TAG[16]
;   out: PTBUF (restored), GCM_TAG[16] (recomputed), VERIFY_FAIL (0=ok,1=error)
; ================================================================
AGD256
        JSR AES256_SETKEY
        JSR GCM_INIT
        ; tag over RECEIVED ciphertext (beforehand, CT is in CTBUF)
        LDA #<CTBUF
        STA GCM_CT_PTR+0
        LDA #>CTBUF
        STA GCM_CT_PTR+1
        LDA PTLEN+0
        STA GCM_CT_LEN+0
        LDA PTLEN+1
        STA GCM_CT_LEN+1
        JSR GCM_AUTH                ; verwachte tag -> GCM_TAG
        JSR GCM_VERIFY              ; C=0 ok / C=1 error
        LDA #0
        BCC AGD_OK
        LDA #1
AGD_OK  STA VERIFY_FAIL
        ; CTR-decrypt CTBUF -> PTBUF (symmetrisch)
        LDA #<CTBUF
        STA AES_CTR_IN+0
        LDA #>CTBUF
        STA AES_CTR_IN+1
        LDA #<PTBUF
        STA AES_CTR_OUT+0
        LDA #>PTBUF
        STA AES_CTR_OUT+1
        LDA PTLEN+0
        STA AES_CTR_LEN+0
        LDA PTLEN+1
        STA AES_CTR_LEN+1
        JSR AES_CTR_CRYPT
        RTS


; ================================================================
; AES_ARK  -  AddRoundKey
;   state[i]  ^=  AES_RK[ AES_RNDOFF + i ]   for i = 0..15
;   Uses X as state index (0..15) and Y as key index.
; ================================================================
AES_ARK
        LDX #0
        LDY AES_RNDOFF
ARK_LP  LDA AES_STATE,X
        EOR AES_RK,Y            ; AES_RK,Y  = absolute,Y  (NO zero-page)
        STA AES_STATE,X
        INX
        INY
        CPX #16
        BNE ARK_LP
        RTS

; ================================================================
; AES_SUBBYTES  -  replace each state byte with its S-box value
;   Uses X as index (15..0) and Y as S-box index register.
; ================================================================
AES_SUBBYTES
        LDX #15
ASUB_LP LDA AES_STATE,X
        TAY
        LDA AES_SBOX,Y          ; AES_SBOX,Y  = absolute,Y
        STA AES_STATE,X
        DEX
        BPL ASUB_LP
        RTS

; ================================================================
; AES_SHIFTROWS  -  rotate rows of the 4x4 state in-place
;
;   Column-major storage:  AES_STATE[c*4 + r]  =  s[r][c]
;   So the rows are at the following indices:
;     row 0  (idx  0,  4,  8, 12)  : shift 0 - unchanged
;     row 1  (idx  1,  5,  9, 13)  : rotate left 1
;     row 2  (idx  2,  6, 10, 14)  : rotate left 2 (= swap pairs)
;     row 3  (idx  3,  7, 11, 15)  : rotate left 3 (= rotate right 1)
; ================================================================
AES_SHIFTROWS
        ; -- Row 1: [s10,s11,s12,s13] -> [s11,s12,s13,s10] ------
        LDA AES_STATE+1
        PHA                     ; save s10
        LDA AES_STATE+5
        STA AES_STATE+1
        LDA AES_STATE+9
        STA AES_STATE+5
        LDA AES_STATE+13
        STA AES_STATE+9
        PLA
        STA AES_STATE+13

        ; -- Row 2: [s20,s21,s22,s23] -> [s22,s23,s20,s21] ------
        ;           (swap diagonal pairs)
        LDA AES_STATE+2
        STA AES_TMP
        LDA AES_STATE+10
        STA AES_STATE+2
        LDA AES_TMP
        STA AES_STATE+10
        LDA AES_STATE+6
        STA AES_TMP
        LDA AES_STATE+14
        STA AES_STATE+6
        LDA AES_TMP
        STA AES_STATE+14

        ; -- Row 3: [s30,s31,s32,s33] -> [s33,s30,s31,s32] ------
        ;           (rotate right 1)
        LDA AES_STATE+15
        PHA                     ; save s33
        LDA AES_STATE+11
        STA AES_STATE+15
        LDA AES_STATE+7
        STA AES_STATE+11
        LDA AES_STATE+3
        STA AES_STATE+7
        PLA
        STA AES_STATE+3

        RTS

; ================================================================
; AES_MIXCOLS  -  GF(2^8) column mixing, all 4 columns
;
;   For each column [c0,c1,c2,c3]  (c0 = row 0):
;     r0 = 2*c0  ^  3*c1  ^   c2  ^   c3
;     r1 =   c0  ^  2*c1  ^  3*c2 ^   c3
;     r2 =   c0  ^   c1   ^  2*c2 ^ 3*c3
;     r3 = 3*c0  ^   c1   ^   c2  ^ 2*c3
;   waarbij  2*x = xtime(x),   3*x = xtime(x) ^ x
;
;   X register is set to AES_COLOFF (0/4/8/12) at TAX,
;   and stays unchanged through XTIME and the EOR sequences.
;   So the write can also use X - no reload needed.
; ================================================================
AES_MIXCOLS
        LDA #0
        STA AES_COLOFF

AMC_LP  LDA AES_COLOFF
        CMP #16
        BNE AMC_CONT
        JMP AMC_DN
AMC_CONT

        ; --- load column bytes into c0..c3  (X = column offset) ------
        TAX
        LDA AES_STATE+0,X
        STA AES_C0
        LDA AES_STATE+1,X
        STA AES_C1
        LDA AES_STATE+2,X
        STA AES_C2
        LDA AES_STATE+3,X
        STA AES_C3

        ; --- compute xtime of each byte  (does not touch X) ------
        LDA AES_C0
        JSR XTIME
        STA AES_XC0
        LDA AES_C1
        JSR XTIME
        STA AES_XC1
        LDA AES_C2
        JSR XTIME
        STA AES_XC2
        LDA AES_C3
        JSR XTIME
        STA AES_XC3

        ; --- r0 = 2*c0 ^ 3*c1 ^ c2 ^ c3 -------------------------
        LDA AES_XC0
        EOR AES_XC1
        EOR AES_C1
        EOR AES_C2
        EOR AES_C3
        STA AES_R0

        ; --- r1 = c0 ^ 2*c1 ^ 3*c2 ^ c3 -------------------------
        LDA AES_C0
        EOR AES_XC1
        EOR AES_XC2
        EOR AES_C2
        EOR AES_C3
        STA AES_R1

        ; --- r2 = c0 ^ c1 ^ 2*c2 ^ 3*c3 -------------------------
        LDA AES_C0
        EOR AES_C1
        EOR AES_XC2
        EOR AES_XC3
        EOR AES_C3
        STA AES_R2

        ; --- r3 = 3*c0 ^ c1 ^ c2 ^ 2*c3 -------------------------
        LDA AES_XC0
        EOR AES_C0
        EOR AES_C1
        EOR AES_C2
        EOR AES_XC3
        STA AES_R3

        ; --- write back  (X = AES_COLOFF, still valid) --
        LDA AES_R0
        STA AES_STATE+0,X
        LDA AES_R1
        STA AES_STATE+1,X
        LDA AES_R2
        STA AES_STATE+2,X
        LDA AES_R3
        STA AES_STATE+3,X

        ; --- next column --------------------------------------
        LDA AES_COLOFF
        CLC
        ADC #4
        STA AES_COLOFF
        JMP AMC_LP

AMC_DN  RTS

; ================================================================
; AES-128 CTR-MODUS
; ================================================================
; AES_CTR_CRYPT  -  AES-128 CTR-modus  (encrypt = decrypt)
;
; Input (set before JSR AES_CTR_CRYPT):
;   AES_NONCE+0..+11   12-byte nonce
;   AES_CTR_IN+0/+1    lo/hi address of source buffer (plaintext or ciphertext)
;   AES_CTR_OUT+0/+1   lo/hi address of destination buffer
;   AES_CTR_LEN        message length 1..255 bytes
;   AES_RK already filled via JSR AES_SETKEY
;
; Output: destination buffer filled with (de)crypted result
; CTR is symmetrisch: encrypt = decrypt
;
; Counter: big-endian 32-bit, starts $00000002 (GCM-compatible)
; Implementation: self-modifying LDA/STA abs,Y (no zero-page)
; AES_CTR_REM guards termination (no BOFF overflow at 241..255 bytes)
; ================================================================
AES_CTR_CRYPT
        ; -- patch source/dest base address in self-modifying abs,Y --
        LDA AES_CTR_IN+0
        STA ACTR_SRC+1
        LDA AES_CTR_IN+1
        STA ACTR_SRC+2
        LDA AES_CTR_OUT+0
        STA ACTR_DST+1
        LDA AES_CTR_OUT+1
        STA ACTR_DST+2
        LDA #$00
        STA AES_CTR_CNT+0
        STA AES_CTR_CNT+1
        STA AES_CTR_CNT+2
        LDA #$02
        STA AES_CTR_CNT+3
        LDA AES_CTR_LEN+0
        STA AES_CTR_REM+0
        LDA AES_CTR_LEN+1
        STA AES_CTR_REM+1
ACTR_BLK
        LDA AES_CTR_REM+0
        ORA AES_CTR_REM+1
        BNE ACTR_BC
        JMP ACTR_DN
ACTR_BC
        LDX #11
ACTR_NC LDA AES_NONCE,X
        STA AES_BLOCK,X
        DEX
        BPL ACTR_NC
        LDA AES_CTR_CNT+0
        STA AES_BLOCK+12
        LDA AES_CTR_CNT+1
        STA AES_BLOCK+13
        LDA AES_CTR_CNT+2
        STA AES_BLOCK+14
        LDA AES_CTR_CNT+3
        STA AES_BLOCK+15
        JSR AES_ENCRYPT_BLOCK
        LDA AES_CTR_REM+1
        BNE ACTR_F16
        LDA AES_CTR_REM+0
        CMP #16
        BCS ACTR_F16
        STA AES_CTR_BSIZ
        JMP ACTR_XOR
ACTR_F16
        LDA #16
        STA AES_CTR_BSIZ
ACTR_XOR
        LDX #0
ACTR_XL CPX AES_CTR_BSIZ
        BNE ACTR_XC
        JMP ACTR_XD
ACTR_XC
        TXA
        TAY
ACTR_SRC LDA $1234,Y
        EOR AES_BLOCK,X
ACTR_DST STA $5678,Y
        INX
        JMP ACTR_XL
ACTR_XD
        INC AES_CTR_CNT+3
        BNE ACTR_NX
        INC AES_CTR_CNT+2
        BNE ACTR_NX
        INC AES_CTR_CNT+1
        BNE ACTR_NX
        INC AES_CTR_CNT+0
ACTR_NX
        LDA ACTR_SRC+1
        CLC
        ADC AES_CTR_BSIZ
        STA ACTR_SRC+1
        BCC ACTR_NS
        INC ACTR_SRC+2
ACTR_NS
        LDA ACTR_DST+1
        CLC
        ADC AES_CTR_BSIZ
        STA ACTR_DST+1
        BCC ACTR_ND
        INC ACTR_DST+2
ACTR_ND
        LDA AES_CTR_REM+0
        SEC
        SBC AES_CTR_BSIZ
        STA AES_CTR_REM+0
        LDA AES_CTR_REM+1
        SBC #0
        STA AES_CTR_REM+1
        JMP ACTR_BLK
ACTR_DN RTS

; ================================================================
; DATA
; ================================================================

; ---- Publieke I/O-buffers --------------------------------------
AES_KEY    !fill 32,$00         ; key input: 16 (AES-128) / 32 (AES-256)
; --- AES-128/256 coexistence (item 5, sub-step 1) ---
AES_NR     !byte $0A           ; round count 10/14 (set by (AES256_)SETKEY)
VERIFY_FAIL !byte $00          ; AGD256: 0=tag ok, 1=error
PTLEN      !byte $00,$00       ; 16-bit length for AGE256/AGD256
PTBUF      !fill 640,$00       ; AES-256-GCM plaintext (inner payload)
CTBUF      !fill 640,$00       ; AES-256-GCM ciphertext
AES_BLOCK  !fill 16,$00         ; block in/out            (set before AES_ENCRYPT_BLOCK)

; ---- Interne rondetoestand ------------------------------------
AES_STATE  !fill 16,$00         ; work state column-major 4x4
AES_RK     !fill 240,$00        ; round keys: 176 (AES-128) / 240 (AES-256)

; ---- key schedule scratch ----------------------------------
AES_WOFF   !byte $00            ; current word byte offset during expansion
AES_T4     !fill 4,$00          ; eenwoord-buffer

; ---- encryption scratch ----------------------------------------
AES_RNDCNT !byte $00            ; current round (1..9 main loop)
AES_RNDOFF !byte $00            ; byte offset in AES_RK for AddRoundKey
AES_COLOFF !byte $00            ; column offset for MixColumns (0/4/8/12)
AES_TMP    !byte $00            ; ShiftRows row-2 swap temp

AES_C0     !byte $00            ; MixColumns: column input bytes
AES_C1     !byte $00
AES_C2     !byte $00
AES_C3     !byte $00
AES_XC0    !byte $00            ; MixColumns: xtime(ci)
AES_XC1    !byte $00
AES_XC2    !byte $00
AES_XC3    !byte $00
AES_R0     !byte $00            ; MixColumns: resultaatbytes
AES_R1     !byte $00
AES_R2     !byte $00
AES_R3     !byte $00

; ---- Expected output for visual check -------------------
AES_RCON
        !byte $01,$02,$04,$08,$10,$20,$40,$80,$1B,$36

; ---- S-box (256 bytes) -----------------------------------------
; Tip: add "!align $100,$00,$00" for page alignment
; (avoids page crossing at LDA AES_SBOX,X and saves cycles).
AES_SBOX
        !byte $63,$7C,$77,$7B,$F2,$6B,$6F,$C5,$30,$01,$67,$2B,$FE,$D7,$AB,$76 ; 00-0F
        !byte $CA,$82,$C9,$7D,$FA,$59,$47,$F0,$AD,$D4,$A2,$AF,$9C,$A4,$72,$C0 ; 10-1F
        !byte $B7,$FD,$93,$26,$36,$3F,$F7,$CC,$34,$A5,$E5,$F1,$71,$D8,$31,$15 ; 20-2F
        !byte $04,$C7,$23,$C3,$18,$96,$05,$9A,$07,$12,$80,$E2,$EB,$27,$B2,$75 ; 30-3F
        !byte $09,$83,$2C,$1A,$1B,$6E,$5A,$A0,$52,$3B,$D6,$B3,$29,$E3,$2F,$84 ; 40-4F
        !byte $53,$D1,$00,$ED,$20,$FC,$B1,$5B,$6A,$CB,$BE,$39,$4A,$4C,$58,$CF ; 50-5F
        !byte $D0,$EF,$AA,$FB,$43,$4D,$33,$85,$45,$F9,$02,$7F,$50,$3C,$9F,$A8 ; 60-6F
        !byte $51,$A3,$40,$8F,$92,$9D,$38,$F5,$BC,$B6,$DA,$21,$10,$FF,$F3,$D2 ; 70-7F
        !byte $CD,$0C,$13,$EC,$5F,$97,$44,$17,$C4,$A7,$7E,$3D,$64,$5D,$19,$73 ; 80-8F
        !byte $60,$81,$4F,$DC,$22,$2A,$90,$88,$46,$EE,$B8,$14,$DE,$5E,$0B,$DB ; 90-9F
        !byte $E0,$32,$3A,$0A,$49,$06,$24,$5C,$C2,$D3,$AC,$62,$91,$95,$E4,$79 ; A0-AF
        !byte $E7,$C8,$37,$6D,$8D,$D5,$4E,$A9,$6C,$56,$F4,$EA,$65,$7A,$AE,$08 ; B0-BF
        !byte $BA,$78,$25,$2E,$1C,$A6,$B4,$C6,$E8,$DD,$74,$1F,$4B,$BD,$8B,$8A ; C0-CF
        !byte $70,$3E,$B5,$66,$48,$03,$F6,$0E,$61,$35,$57,$B9,$86,$C1,$1D,$9E ; D0-DF
        !byte $E1,$F8,$98,$11,$69,$D9,$8E,$94,$9B,$1E,$87,$E9,$CE,$55,$28,$DF ; E0-EF
        !byte $8C,$A1,$89,$0D,$BF,$E6,$42,$68,$41,$99,$2D,$0F,$B0,$54,$BB,$16 ; F0-FF
; ================================================================
; DATA - AES-128 CTR-modus
; ================================================================

; ---- publieke invoerbuffers ------------------------------------
AES_NONCE    !fill 12,$00       ; 12-byte nonce (set per message)
AES_CTR_IN   !byte $00,$00      ; lo/hi address of source buffer (plaintext)
AES_CTR_OUT  !byte $00,$00      ; lo/hi address of destination buffer (ciphertext)
AES_CTR_LEN  !byte $00,$00      ; message length 16-bit (lo,hi)

; ---- internal CTR scratch ----------------------------------------
AES_CTR_CNT  !fill 4,$00        ; 32-bit big-endian counter (start $00000002)
AES_CTR_REM  !byte $00,$00      ; resterende bytes 16-bit (lo,hi)
AES_CTR_BOFF !byte $00          ; byte offset in source/destination buffer
AES_CTR_BSIZ !byte $00          ; bytes in current block (1..16)
AES_CTR_BIDX !byte $00          ; byte index within current block

; ================================================================
; DATA - AES-128-GCM authentication tag
; ================================================================

; ---- GCM publiek -----------------------------------------------
GCM_CT_PTR   !byte $00,$00      ; lo/hi address of ciphertext (set before GCM_AUTH)
GCM_CT_LEN   !byte $00,$00      ; length of ciphertext 16-bit (lo,hi)
GCM_H        !fill 16,$00       ; hash subkey H = AES(key, 0^16)
GCM_EK0      !fill 16,$00       ; tag-encryptieblok = AES(key, nonce||$01)
GCM_TAG      !fill 16,$00       ; computed 16-byte authentication tag
GCM_RECV_TAG !fill 16,$00       ; received tag (for GCM_VERIFY)
GCM_DO_VERIFY !byte $00         ; 1 = verifieer tag in AES_GCM_DECRYPT (one-shot)

; ---- GCM intern ------------------------------------------------
GCM_Y        !fill 16,$00       ; lopende GHASH-accumulator
GCM_BLK      !fill 16,$00       ; current CT block (zero-padded to 16)
GCM_BREM     !byte $00,$00      ; resterende bytes 16-bit (lo,hi)
GCA_LB0      !byte $00          ; scratch length block lo
GCA_LB1      !byte $00          ; scratch length block hi
GCM_BOFF     !byte $00          ; byte-offset in CT-buffer (0, 16, 32, ...)
GCM_GBSIZ    !byte $00          ; size of current block (1..16)
GCM_BIDX     !byte $00          ; byte index within block (0..GBSIZ-1)

; ---- GF_MUL intern ---------------------------------------------
GCM_GX       !fill 16,$00       ; GF_MUL operand X (copy of Y at call)
GCM_GY       !fill 16,$00       ; GF_MUL operand Y (copy of H at call)
GCM_GZ       !fill 16,$00       ; GF_MUL resultaat Z
GCM_VBUF     !fill 16,$00       ; running V (starts as X, shifted per bit)
GCM_GLSB     !byte $00          ; old LSB of V[15] for shift (for reduction)
GCM_GYCNT    !byte $00          ; Y byte index (0..15)
GCM_GBIT     !byte $00          ; bit counter per Y-byte (8 counting down to 0)
GCM_GYBYTE   !byte $00          ; current Y-byte (shifts left via ASL)

; ================================================================
; DATA  -  AES-128-GCM encryption
; ================================================================
GCM_IN_KEY   !fill 16,$00   ; 16-byte AES-128 key input for AES_GCM_ENCRYPT
GCM_PT_PTR   !byte $00,$00  ; lo/hi address of plaintext buffer
GCM_PT_LEN   !byte $00,$00  ; plaintext/ciphertext length 16-bit (lo,hi)
GCM_CTBUF    !fill 640,$00  ; ciphertext/plaintext output (max ~624)
GCM_MSG_CTR  !byte $00,$00  ; 16-bit message counter: guarantees nonce uniqueness

; ================================================================
; DATA  -  JSON serieel uitvoerbuffer
; ================================================================
JOUT_BUF     !fill 1280,$00  ; JSON output (typically 200-420 bytes for a 40-char message)
JOUT_LO      !byte $00      ; write pointer lo (zero-page via LDA(ptr),Y)
JOUT_HI      !byte $00      ; write pointer hi
JOUT_LEN     !byte $00,$00  ; 16-bit payload length: lo, hi

; ================================================================
; DATA  -  C64 publieke identiteit (base64url publicId)
; ================================================================
C64_IDBYTES  !fill 12,$00   ; first 12 bytes SHA-256(encryption key)
C64_IDSTR    !fill 17,$00   ; 16 ASCII chars base64url publicId + $00 terminator

; ================================================================
; DATA  -  helper variables for BYTE_TO_DEC and B64URL_12BYTES
; ================================================================
BTD_VAL      !byte $00      ; BYTE_TO_DEC: werkwaarde
BTD_NZ       !byte $00      ; BYTE_TO_DEC: flag "non-zero char seen"
BGB_XTMP     !byte $00      ; BUILD_GCM_BLOB: X save slot around BYTE_TO_DEC
; receive variables
WRF_CTR_LO   !byte $00      ; WS_RECV_FRAME: loop counter lo
WRF_CTR_HI   !byte $00      ; WS_RECV_FRAME: loop counter hi
PING_LEN     !byte $00      ; WRF_PING: ping/pong payload length
PING_TMP     !byte $00      ; WRF_PING: raw payload byte (scratch)
RCV_LEN_LO   !byte $00      ; received frame length lo
RCV_LEN_HI   !byte $00      ; received frame length hi
RCV_TOOBIG   !byte $00      ; 1 = laatste frame > RCV_BUF (afgekapt)
RCV_TOOLONG  !byte $00      ; 1 = data array > RCV_CT (message too long)
PRM_TCNT     !byte $00,$00  ; display-kopieerteller (16-bit)
JSC_PAT_LO   !byte $00      ; JSON_SCAN: pattern address lo
JSC_PAT_HI   !byte $00      ; JSON_SCAN: pattern address hi
JSC_MPOS_LO  !byte $00      ; JSON_SCAN: buffer-matchpositie lo
JSC_MPOS_HI  !byte $00      ; JSON_SCAN: buffer-matchpositie hi
JSC_CPOS_LO  !byte $00      ; JSON_SCAN: patroon-cursor lo
JSC_CPOS_HI  !byte $00      ; JSON_SCAN: patroon-cursor hi
JSC_PB       !byte $00      ; JSON_SCAN: saved pattern byte
PRM_CNT      !byte $00      ; JSON_PARSE_ARR: expected count (0=variable)
JPA_REM      !byte $00      ; JSON_PARSE_ARR: resterende bytes
JPI_VAL      !byte $00      ; JSON_PARSE_INT: accumulator
JPI_TMP      !byte $00      ; JSON_PARSE_INT: val*2
JPI_DIG      !byte $00      ; JSON_PARSE_INT: huidig cijfer
RCV_CT_LEN   !byte $00,$00  ; received ciphertext+tag length (16-bit)
RCV_PT_LEN   !byte $00,$00  ; plaintext length 16-bit (CT_LEN - 16)
RCV_FROM     !fill 17,$00   ; sender publicId + null
RCV_IV       !fill 12,$00   ; received IV
RCV_CT
!source "fastsha_main.inc"   ; fast PBKDF2 code in main RAM (overlay; chat reuses this space)
RCV_TEXT = RCV_CT + 640
RCV_BUF  = RCV_CT + 1216
* = RCV_CT + 3775
RCV_BUF_END                 ; store-limietadres (RCV_BUF + 2559)
             !byte $00      ; +1 null-term slot -> RCV_BUF totaal 2560
RING_BUF     !fill 256,$00  ; NMI RX ring buffer (256, byte index wrap)
RING_HEAD    !byte $00      ; ISR write index
RING_TAIL    !byte $00      ; main code read index
RING_OVF     !byte $00      ; overflow flag (diagnostic)
RGT_RETRY    !byte $00      ; RING_GET_TO retry counter
MSG_SHOWN    !byte $00      ; 1 = message shown (trigger redraw)
RDI_CNT      !byte $00      ; REDRAW_INPUT: number of typed chars
MIJ_LO       !byte $00      ; BUILD_INNER_JSON: write pointer lo
MIJ_HI       !byte $00      ; BUILD_INNER_JSON: write pointer hi
MSG_INNER_LEN !byte $00     ; BUILD_INNER_JSON: payload length in bytes
MSG_INNER_BUF !fill 256,$00 ; BUILD_INNER_JSON: buffer for inner JSON plaintext

B64_B0       !byte $00      ; B64URL: invoerbyte 0
B64_B1       !byte $00      ; B64URL: invoerbyte 1
B64_B2       !byte $00      ; B64URL: invoerbyte 2
B64_T        !byte $00      ; B64URL: temporary combination byte
B64_GRPIDX   !byte $00      ; B64URL: current group index (0..3)
B64_BOFF     !byte $00      ; B64URL: byte offset in input = GRPIDX*3
B64_OIDX     !byte $00      ; B64URL: byte offset in output = GRPIDX*4

; ================================================================
; DATA  -  WS_SEND_EXT werkregisters
; ================================================================
WSX_REM      !byte $00,$00  ; resterende bytes te versturen (16-bit)
WSX_MIDX     !byte $00      ; masking key cyclic index (0..3)

; ================================================================
; Statische JSON strings
; ================================================================
; {"iv":[
STR_IVHDR    !byte $7B,$22,$69,$76,$22,$3A,$5B,$00

; ],"data":[
STR_DATAHDR  !byte $5D,$2C,$22,$64,$61,$74,$61,$22,$3A,$5B,$00
STR_SIGHDR   !byte $2C,$22,$73,$69,$67,$22,$3A,$5B,$00   ; ,"sig":[

; JSON search patterns (null-terminated, explicit as bytes):
; "type":"app:message"   (server.py HEAD)
JSC_TYPE_MSG
        !byte $22,$74,$79,$70,$65,$22,$3A,$22
        !byte $61,$70,$70,$3A,$6D,$65,$73,$73,$61,$67,$65,$22
        !byte 0
; "from":"
JSC_FROM
        !byte $22,$66,$72,$6F,$6D,$22,$3A,$22,0
; "iv":[
JSC_IV
        !byte $22,$69,$76,$22,$3A,$5B,0
; "data":[
JSC_DATA
        !byte $22,$64,$61,$74,$61,$22,$3A,$5B,0
; "text":"
JSC_TEXT
        !byte $22,$74,$65,$78,$74,$22,$3A,$22,0

; auth_challenge (substring is enough; only in sig:auth_challenge)
JSC_CHAL
        !byte $61,$75,$74,$68,$5F,$63,$68,$61,$6C,$6C,$65,$6E,$67
        !byte $65,$00
; auth_ok
JSC_AOK
        !byte $61,$75,$74,$68,$5F,$6F,$6B,$00
; auth_fail
JSC_AFAIL
        !byte $61,$75,$74,$68,$5F,$66,$61,$69,$6C,$00

; {"type":"sig:auth_init","bits":128,"enc_key":[
STR_AUTH1
        !byte $7B,$22,$74,$79,$70,$65,$22,$3A,$22,$73,$69,$67,$3A
        !byte $61,$75,$74,$68,$5F,$69,$6E,$69,$74,$22,$2C,$22,$62
        !byte $69,$74,$73,$22,$3A,$31,$32,$38,$2C,$22,$65,$6E,$63
        !byte $5F,$6B,$65,$79,$22,$3A,$5B,$00
; {"type":"sig:auth_proof","nonce":[
STR_AUTH2
        !byte $7B,$22,$74,$79,$70,$65,$22,$3A,$22,$73,$69,$67,$3A
        !byte $61,$75,$74,$68,$5F,$70,$72,$6F,$6F,$66,$22,$2C,$22
        !byte $6E,$6F,$6E,$63,$65,$22,$3A,$5B,$00

STR_DBG_OKM  !text "OKM: "
             !byte 0

; DBGRX debug prefix: "RX[" followed by hex length + ']' + space + 56 chars payload
STR_DBGRX_LEN  !text "RX["
               !byte 0

; Inner JSON strings for BUILD_INNER_JSON:
; {"id":"
STR_INNER_IDHDR
        !byte $7B,$22,$69,$64,$22,$3A,$22,$00

; ","text":"
STR_INNER_TXTHDR
        !byte $22,$2C,$22,$74,$65,$78,$74,$22,$3A,$22,$00

; ","ts":0}
STR_INNER_TS
        !byte $22,$2C,$22,$74,$73,$22,$3A,$30,$7D,$00

; {"type":"app:message","from":"   (server.py HEAD)
STR_MSG_HDR1
        !byte $7B,$22,$74,$79,$70,$65,$22,$3A,$22
        !byte $61,$70,$70,$3A,$6D,$65,$73,$73,$61,$67,$65,$22,$2C
        !byte $22,$66,$72,$6F,$6D,$22,$3A,$22
        !byte $00

; ","to":"           (peer publicId is emitted at runtime from PEER_IDSTR)
STR_MSG_TO   !byte $22,$2C,$22,$74,$6F,$22,$3A,$22,$00
; ","blob":
STR_MSG_BLOB !byte $22,$2C,$22,$62,$6C,$6F,$62,$22,$3A,$00

; ================================================================
; Base64url alfabet (RFC 4648 §5: A-Z a-z 0-9 - _)
; ================================================================
B64_TABLE
        !text "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        !byte $2D,$5F       ; '-' (62) en '_' (63)

; ================================================================
; ED25519 SIGN CORE  (from signtest.asm; SHA_K/W/MLEN -> SHA5_*)
; ================================================================
; ================================================================
; ed25519test.asm  -  Edwards25519 point arithmetic (step 3 Ed25519 path)
; ----------------------------------------------------------------
; Builds on the verified Fp layer (mod p = 2^255-19) from step 2.
; Punt = extended twisted Edwards coords (X:Y:Z:T), a = -1.
;   x = X/Z , y = Y/Z , T = X*Y/Z .
; Elk coord = 32 bytes little-endian, canoniek in [0,p).
;
;   POINT_ADD  : (PR) = (PA) + (PB)        (HWCD add-2008-hwcd-3, a=-1)
;   POINT_DBL  : (PR) = 2*(PA)             (dbl-2008-hwcd, a=-1)
;   SCALAR_MUL : (PACC) = SCALAR * (PIN)   (double-and-add, MSB->LSB, 256 bits)
;
; A point lives in a 128-byte block: X(32) Y(32) Z(32) T(32).
; Pointers to such a block: PAP/PBP/PRP (24-bit not needed; coords lie
; contiguous, so block base + offset 0/32/64/96).
;
; Test wrappers (fixed blocks IN_P / IN_Q -> OUT_P, and SCALAR buffer):
;   T_PADD T_PDBL T_SMUL
; Getoetst byte-exact in py65 tegen ref_ed.py (Python).
; ================================================================

; --- zeropage pointers (Fp layer) ---
FAP = $FB       ; arg A pointer (reused in FP_MUL as PROD pointer)
FBP = $FD       ; arg B pointer
FRP = $F7       ; result pointer
; SHA-512 zeropage aliases (same addresses; SHA and Fp never run at once)
PA  = $FB
PB  = $FD
SRC = $F7
BP  = $F9
; --- COPY_M (16-bit message copy) zeropage; $02-$05 free in this module ---
; Runs fully to completion before each SHA512 call, so no aliasing with SRC/PA/PB.
CSRC = $02      ; copy source pointer
CDST = $04      ; copy destination pointer


; ================================================================
; MACROS - call the Fp layer with absolute buffer labels
; ================================================================
!macro fmul .r, .a, .b {
        lda #<.a : sta FAP : lda #>.a : sta FAP+1
        lda #<.b : sta FBP : lda #>.b : sta FBP+1
        lda #<.r : sta FRP : lda #>.r : sta FRP+1
        jsr FP_MUL_KARA
}
!macro fsq .r, .a {
        lda #<.a : sta FAP : lda #>.a : sta FAP+1
        lda #<.r : sta FRP : lda #>.r : sta FRP+1
        jsr FP_SQ
}
!macro fadd .r, .a, .b {
        lda #<.a : sta FAP : lda #>.a : sta FAP+1
        lda #<.b : sta FBP : lda #>.b : sta FBP+1
        lda #<.r : sta FRP : lda #>.r : sta FRP+1
        jsr FP_ADD
}
!macro fsub .r, .a, .b {
        lda #<.a : sta FAP : lda #>.a : sta FAP+1
        lda #<.b : sta FBP : lda #>.b : sta FBP+1
        lda #<.r : sta FRP : lda #>.r : sta FRP+1
        jsr FP_SUB
}
; copy 32-byte field .src -> .dst
!macro fcopy .dst, .src {
        ldx #31
.cl     lda .src,x
        sta .dst,x
        dex
        bpl .cl
}
; --- Fp macros for FP_INV (from fp25519test) ---
!macro mul .r, .a, .b {
        lda #<.a : sta FAP : lda #>.a : sta FAP+1
        lda #<.b : sta FBP : lda #>.b : sta FBP+1
        lda #<.r : sta FRP : lda #>.r : sta FRP+1
        jsr FP_MUL_KARA
}
!macro sq .r, .a {
        lda #<.a : sta FAP : lda #>.a : sta FAP+1
        lda #<.r : sta FRP : lda #>.r : sta FRP+1
        jsr FP_SQ
}
!macro sqn .buf, .n {
        lda #<.buf : sta SQ_PTR : lda #>.buf : sta SQ_PTR+1
        lda #.n    : sta SQN_CNT
        jsr SQN
}

; ================================================================
; POINT_ADD : (PR) = (PA) + (PB)
; PA = block at PA_X (X,Y,Z,T), same for PB, result PR.
; Fixed work blocks here: input in A-coords / B-coords; out in R-coords.
; We use named buffers (no indirect block pointers) to keep the
; formula readable; SCALAR_MUL copies in/out of these buffers.
;   A = (Y1-X1)*(Y2-X2)
;   B = (Y1+X1)*(Y2+X2)
;   C = T1 * (2d) * T2
;   D = Z1 * 2 * Z2
;   E = B-A ; F = D-C ; G = D+C ; H = B+A
;   X3=E*F ; Y3=G*H ; T3=E*H ; Z3=F*G
; ================================================================
PA_X = AX
PA_Y = AY
PA_Z = AZ
PA_T = AT
PB_X = BX_
PB_Y = BY_
PB_Z = BZ_
PB_T = BT_
PR_X = RX
PR_Y = RY
PR_Z = RZ
PR_T = RT

POINT_ADD
        ; tmpA = (Y1-X1)*(Y2-X2)
        +fsub PT1, PA_Y, PA_X      ; PT1 = Y1-X1
        +fsub PT2, PB_Y, PB_X      ; PT2 = Y2-X2
        +fmul PvA, PT1, PT2        ; A
        ; tmpB = (Y1+X1)*(Y2+X2)
        +fadd PT1, PA_Y, PA_X      ; PT1 = Y1+X1
        +fadd PT2, PB_Y, PB_X      ; PT2 = Y2+X2
        +fmul PvB, PT1, PT2        ; B
        ; C = T1 * 2d * T2  -> PT1 = T1*2d ; C = PT1*T2
        +fmul PT1, PA_T, D2_CONST  ; T1*2d
        +fmul PvC, PT1, PB_T       ; C
        ; D = Z1 * 2 * Z2 -> PT1 = Z1*Z2 ; D = PT1*2  (2 as field constant)
        +fmul PT1, PA_Z, PB_Z      ; Z1*Z2
        +fadd PvD, PT1, PT1        ; D = 2*Z1*Z2
        ; E=B-A ; H=B+A ; F=D-C ; G=D+C
        +fsub PvE, PvB, PvA
        +fadd PvH, PvB, PvA
        +fsub PvF, PvD, PvC
        +fadd PvG, PvD, PvC
        ; X3=E*F ; Y3=G*H ; T3=E*H ; Z3=F*G
        +fmul PR_X, PvE, PvF
        +fmul PR_Y, PvG, PvH
        +fmul PR_T, PvE, PvH
        +fmul PR_Z, PvF, PvG
        RTS

; ================================================================
; POINT_DBL : (PR) = 2*(PA)
;   A = X1^2 ; B = Y1^2 ; C = 2*Z1^2 ; D = -A
;   E = (X1+Y1)^2 - A - B
;   G = D+B ; F = G-C ; H = D-B
;   X3=E*F ; Y3=G*H ; T3=E*H ; Z3=F*G
; ================================================================
POINT_DBL
        +fsq  PvA, PA_X            ; A = X1^2
        +fsq  PvB, PA_Y            ; B = Y1^2
        ; C = 2*Z1^2 -> PT1=Z1^2 ; C=PT1+PT1
        +fsq  PT1, PA_Z
        +fadd PvC, PT1, PT1
        ; D = -A = 0 - A
        +fsub PvD, ZERO_CONST, PvA
        ; E = (X1+Y1)^2 - A - B
        +fadd PT1, PA_X, PA_Y      ; X1+Y1
        +fsq  PT2, PT1             ; (X1+Y1)^2
        +fsub PT1, PT2, PvA        ; -A
        +fsub PvE, PT1, PvB        ; -B  -> E
        ; G=D+B ; F=G-C ; H=D-B
        +fadd PvG, PvD, PvB
        +fsub PvF, PvG, PvC
        +fsub PvH, PvD, PvB
        ; X3=E*F ; Y3=G*H ; T3=E*H ; Z3=F*G
        +fmul PR_X, PvE, PvF
        +fmul PR_Y, PvG, PvH
        +fmul PR_T, PvE, PvH
        +fmul PR_Z, PvF, PvG
        RTS

; ================================================================
; SCALAR_MUL : ACC = SCALAR * PIN  (256-bit, MSB->LSB double-and-add)
; SCALAR = 32 bytes little-endian in SCALAR-buffer.
; PIN    = invoerpunt in PIN_X/Y/Z/T (extended coords).
; ACC    = accumulator in ACC_X/Y/Z/T.
; Method per bit (from bit 255 down to 0):
;   ACC = 2*ACC                 (POINT_DBL: A=ACC -> R=ACC)
;   if bit: ACC = ACC + PIN     (POINT_ADD: A=ACC, B=PIN -> R=ACC)
; ACC starts as the neutral element (0,1,1,0).
; ================================================================
!source "karatsuba.inc"

SM_TESTBIT
        lda SM_BIT
        lsr
        lsr
        lsr               ; A = byte index (0..31)
        tax
        lda SCALAR,x
        sta SM_TMP
        lda SM_BIT
        and #7
        tax               ; X = bit within byte
        lda SM_TMP
SM_TB_S cpx #0
        beq SM_TB_D
        lsr
        dex
        jmp SM_TB_S
SM_TB_D and #1
        cmp #1            ; C=1 if bit set
        rts

; ================================================================
; TEST-WRAPPERS
; ================================================================
; T_PADD : load IN_P -> A-coords, IN_Q -> B-coords, POINT_ADD, R->OUT_P

; ================================================================
; ====================  Fp LAYER (from step 2)  ====================
; ================================================================
MUL8
        ; M-fix: quarter-square table mul (preserves Y, clobbers A,X)
        LDA MUL_A
        CLC
        ADC MUL_B
        TAX
        BCC M8_S1LO
        LDA QSL1+256,X
        STA MUL_RES
        LDA QSH1+256,X
        STA MUL_RES+1
        JMP M8_SUB
M8_S1LO LDA QSL1,X
        STA MUL_RES
        LDA QSH1,X
        STA MUL_RES+1
M8_SUB  LDA MUL_A
        SEC
        SBC MUL_B
        BCS M8_DPOS
        EOR #$FF
        CLC
        ADC #1
M8_DPOS TAX
        SEC
        LDA MUL_RES
        SBC QSL1,X
        STA MUL_RES
        LDA MUL_RES+1
        SBC QSH1,X
        STA MUL_RES+1
        RTS

FP_ADD
        LDY #0
FA_CA   LDA (FAP),Y : STA MA,Y : INY : CPY #32 : BNE FA_CA
        LDY #0
FA_CB   LDA (FBP),Y : STA MB,Y : INY : CPY #32 : BNE FA_CB
        CLC
        LDX #32
        LDY #0
FA_L    LDA MA,Y
        ADC MB,Y
        STA RES,Y
        INY
        DEX
        BNE FA_L
        JSR CONDSUBP
        LDY #0
FA_O    LDA RES,Y : STA (FRP),Y : INY : CPY #32 : BNE FA_O
        RTS

FP_SUB
        LDY #0
FS_CA   LDA (FAP),Y : STA MA,Y : INY : CPY #32 : BNE FS_CA
        LDY #0
FS_CB   LDA (FBP),Y : STA MB,Y : INY : CPY #32 : BNE FS_CB
        SEC
        LDX #32
        LDY #0
FS_L    LDA MA,Y
        SBC MB,Y
        STA RES,Y
        INY
        DEX
        BNE FS_L
        BCS FS_NOP
        CLC
        LDX #32
        LDY #0
FS_AP   LDA RES,Y
        ADC P_CONST,Y
        STA RES,Y
        INY
        DEX
        BNE FS_AP
FS_NOP
        LDY #0
FS_O    LDA RES,Y : STA (FRP),Y : INY : CPY #32 : BNE FS_O
        RTS

FP_MUL
        LDY #0
FM_CA   LDA (FAP),Y : STA MA,Y : INY : CPY #32 : BNE FM_CA
        LDY #0
FM_CB   LDA (FBP),Y : STA MB,Y : INY : CPY #32 : BNE FM_CB
        LDA #0
        LDX #63
FM_CP   STA PROD,X
        DEX
        BPL FM_CP
        LDA #0
        STA II
FM_ROW
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
FM_COL
        LDA MB,Y
        STA MUL_B
        JSR MUL8
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
        BNE FM_COL
        LDY #32
        LDA (FAP),Y
        CLC
        ADC CARRY8
        STA (FAP),Y
        INC II
        LDA II
        CMP #32
        BNE FM_ROW
        JSR FP_REDUCE
        LDY #0
FM_OUT  LDA RES,Y : STA (FRP),Y : INY : CPY #32 : BNE FM_OUT
        RTS

FP_REDUCE
        LDA #0
        LDX #35
FR_HBC  STA HB,X
        DEX
        BPL FR_HBC
        STA CARRY16
        STA CARRY16+1
        LDY #0
FR_H38
        LDA PROD+32,Y
        STA MUL_A
        LDA #38
        STA MUL_B
        JSR MUL8
        LDA MUL_RES
        CLC
        ADC CARRY16
        STA HB,Y
        LDA MUL_RES+1
        ADC CARRY16+1
        STA CARRY16
        LDA #0
        ADC #0
        STA CARRY16+1
        INY
        CPY #32
        BNE FR_H38
        LDA CARRY16
        STA HB+32

        LDA #0
        LDX #35
FR_TBC  STA TB,X
        DEX
        BPL FR_TBC
        CLC
        LDX #32
        LDY #0
FR_TBL  LDA PROD,Y
        ADC HB,Y
        STA TB,Y
        INY
        DEX
        BNE FR_TBL
        LDA HB,Y
        ADC #0
        STA TB,Y

        LDX #32
        LDY #0
FR_RC   LDA TB,Y : STA RES,Y : INY : DEX : BNE FR_RC
        LDA TB+32
        STA MUL_A
        LDA #38
        STA MUL_B
        JSR MUL8
        CLC
        LDA RES+0 : ADC MUL_RES   : STA RES+0
        LDA RES+1 : ADC MUL_RES+1 : STA RES+1
        LDX #30
        LDY #2
FR_RP   LDA RES,Y
        ADC #0
        STA RES,Y
        INY
        DEX
        BNE FR_RP
        BCC FR_NOC
        JSR ADD38
FR_NOC
        JSR FREEZE
        RTS

ADD38
        CLC
        LDA RES+0
        ADC #38
        STA RES+0
        LDX #31
        LDY #1
A38_L   LDA RES,Y
        ADC #0
        STA RES,Y
        INY
        DEX
        BNE A38_L
        BCS ADD38
        RTS

FREEZE
        JSR CONDSUBP
        JSR CONDSUBP
        RTS

CONDSUBP
        SEC
        LDX #32
        LDY #0
CS_L    LDA RES,Y
        SBC P_CONST,Y
        STA TMP,Y
        INY
        DEX
        BNE CS_L
        BCC CS_DONE
        LDX #32
        LDY #0
CS_C    LDA TMP,Y
        STA RES,Y
        INY
        DEX
        BNE CS_C
CS_DONE
        RTS

; ================================================================
; FP_INV : OUT = ZIN^(p-2) mod p    (ref10 fe_invert additieketen)
;   254 kwadrateringen + 11 vermenigvuldigingen
; ================================================================
FP_INV
        +sq  z2, ZIN            ; z^2
        +sq  t1, z2             ; z^4
        +sq  t0, t1            ; z^8
        +mul z9, t0, ZIN       ; z^9
        +mul z11, z9, z2       ; z^11
        +sq  t0, z11           ; z^22
        +mul z5_0, t0, z9      ; z^(2^5-1)
        +sq  t0, z5_0
        +sqn t0, 4             ; 5 kwadr. -> z^(2^10-2^5)
        +mul z10_0, t0, z5_0   ; z^(2^10-1)
        +sq  t0, z10_0
        +sqn t0, 9             ; z^(2^20-2^10)
        +mul z20_0, t0, z10_0  ; z^(2^20-1)
        +sq  t0, z20_0
        +sqn t0, 19            ; z^(2^40-2^20)
        +mul t0, t0, z20_0     ; z^(2^40-1)
        +sq  t0, t0
        +sqn t0, 9             ; z^(2^50-2^10)
        +mul z50_0, t0, z10_0  ; z^(2^50-1)
        +sq  t0, z50_0
        +sqn t0, 49            ; z^(2^100-2^50)
        +mul z100_0, t0, z50_0 ; z^(2^100-1)
        +sq  t0, z100_0
        +sqn t0, 99            ; z^(2^200-2^100)
        +mul t0, t0, z100_0    ; z^(2^200-1)
        +sq  t0, t0
        +sqn t0, 49            ; z^(2^250-2^50)
        +mul t0, t0, z50_0     ; z^(2^250-1)
        +sq  t0, t0
        +sqn t0, 4             ; 5 kwadr. -> z^(2^255-2^5)
        +mul OUT, t0, z11      ; z^(2^255-21) = z^(p-2)
        RTS

; in-place squaring of (SQ_PTR), SQN_CNT times
SQN
        LDA SQN_CNT
        BEQ SQN_D
SQN_L
        JSR FP_SQ_IP
        DEC SQN_CNT
        BNE SQN_L
SQN_D
        RTS
FP_SQ_IP
        LDA SQ_PTR   : STA FAP : STA FBP : STA FRP
        LDA SQ_PTR+1 : STA FAP+1 : STA FBP+1 : STA FRP+1
        JMP FP_SQ               ; tail-call; FP_MUL's RTS returns to SQN_L


; ================================================================
; ENCODE  -  Ed25519 puntcompressie (X:Y:Z) -> 32-byte LE in ENC
;   zi=FP_INV(PZ) ; y=PY*zi ; x=PX*zi ; ENC=y_le ; ENC[31]|=(x&1)<<7
; ================================================================
ENCODE
        LDY #0
EN_CZ   LDA PZ,Y : STA ZIN,Y : INY : CPY #32 : BNE EN_CZ
        JSR FP_INV
        LDY #0
EN_CI   LDA OUT,Y : STA ZI,Y : INY : CPY #32 : BNE EN_CI
        +mul EY, PY, ZI
        +mul EX, PX, ZI
        LDY #0
EN_CO   LDA EY,Y : STA ENC,Y : INY : CPY #32 : BNE EN_CO
        LDA EX
        AND #1
        BEQ EN_DONE
        LDA ENC+31
        ORA #$80
        STA ENC+31
EN_DONE RTS
T_ENCODE JMP ENCODE


; ================================================================
; ==================  SHA-512 (from step 1)  ====================
; ================================================================


; ================================================================
; 64-bit primitives on (PA) and (PB) - 8 bytes, little-endian
; ================================================================
C64COPY LDY #0                  ; (PA) <- (PB)
CC_L    LDA (PB),Y
        STA (PA),Y
        INY
        CPY #8
        BNE CC_L
        RTS

C64ADD  CLC                     ; (PA) += (PB)
        LDY #0
        LDX #8                  ; counter via X: DEX/BNE keep carry intact (CPY would clear carry!)
CA_L    LDA (PA),Y
        ADC (PB),Y
        STA (PA),Y
        INY
        DEX
        BNE CA_L
        RTS

C64XOR  LDY #0                  ; (PA) ^= (PB)
CX_L    LDA (PA),Y
        EOR (PB),Y
        STA (PA),Y
        INY
        CPY #8
        BNE CX_L
        RTS

C64AND  LDY #0                  ; (PA) &= (PB)
CN_L    LDA (PA),Y
        AND (PB),Y
        STA (PA),Y
        INY
        CPY #8
        BNE CN_L
        RTS

; ================================================================
; Rotate/shift on fixed scratch word SHA_TA (8 bytes, LE)
;   SHA_N = number of bits.  ROTR_TA = rotate right; SHR_TA = shift right.
; ================================================================
; --- 1-bit right rotation of SHA_TA (LE) ---
ROR1_TA LDA SHA_TA+0
        LSR                     ; C = bit0 (wrap bit -> becomes MSB)
        LDX #7
R1_L    ROR SHA_TA,X
        DEX
        BPL R1_L
        RTS
; --- 1-bit logical right shift of SHA_TA ---
SHR1_TA CLC
        LDX #7
S1_L    ROR SHA_TA,X
        DEX
        BPL S1_L
        RTS

; --- byte right rotation of SHA_TA by SHA_BK bytes (LE: out[i]=in[(i+k)&7]) ---
BROT_TA LDX #0
BR_L    TXA
        CLC
        ADC SHA_BK
        AND #7
        TAY
        LDA SHA_TA,Y
        STA SHA_TB,X
        INX
        CPX #8
        BNE BR_L
        LDX #7                  ; SHA_TB -> SHA_TA
BR_C    LDA SHA_TB,X
        STA SHA_TA,X
        DEX
        BPL BR_C
        RTS

; --- ROTR_TA: rotate SHA_TA right by SHA_N bits ---
ROTR_TA LDA SHA_N
        LSR
        LSR
        LSR                     ; A = SHA_N>>3 = bytes
        STA SHA_BK
        JSR BROT_TA
        LDA SHA_N
        AND #7
        STA SHA_BC              ; remaining bits
RT_BL   LDA SHA_BC
        BEQ RT_DN
        JSR ROR1_TA
        DEC SHA_BC
        JMP RT_BL
RT_DN   RTS

; --- SHR_TA: shift SHA_TA right by SHA_N bits (fills high with 0) ---
SHR_TA  LDA SHA_N
        LSR
        LSR
        LSR
        STA SHA_BK              ; bytes
        BEQ SH_BIT
        ; byte shift right (LE: out[i]=in[i+k] or 0): do k times a 1-byte shift
SH_BYL  LDX #0
SH_BY1  CPX #7
        BEQ SH_BYT
        LDY SHA_TA+1,X          ; placeholder (see below) -- replaced
SH_BYT  NOP
        ; (simplified: byte shift via loop below)
        JMP SH_BYDONE
SH_BYDONE
        ; simple byte shift: move elements down k times
        LDA SHA_BK
        STA SHA_BC2
SH_KL   LDA SHA_BC2
        BEQ SH_BIT
        LDX #0
SH_SL   CPX #7
        BEQ SH_SLT
        LDA SHA_TA+1,X
        STA SHA_TA,X
        INX
        JMP SH_SL
SH_SLT  LDA #0
        STA SHA_TA+7
        DEC SHA_BC2
        JMP SH_KL
SH_BIT  LDA SHA_N
        AND #7
        STA SHA_BC
SH_BBL  LDA SHA_BC
        BEQ SH_DN
        JSR SHR1_TA
        DEC SHA_BC
        JMP SH_BBL
SH_DN   RTS

; ================================================================
; Sigma functions -> result in SHA_ACC.  PB points to source word.
; ================================================================
; helper: copy (PB) -> SHA_TA
CP_PB_TA LDY #0
PT_L    LDA (PB),Y
        STA SHA_TA,Y
        INY
        CPY #8
        BNE PT_L
        RTS
; helper: SHA_ACC ^= SHA_TA
ACC_X_TA LDX #7
AX_L    LDA SHA_ACC,X
        EOR SHA_TA,X
        STA SHA_ACC,X
        DEX
        BPL AX_L
        RTS
; helper: SHA_ACC <- SHA_TA
ACC_C_TA LDX #7
AC_L    LDA SHA_TA,X
        STA SHA_ACC,X
        DEX
        BPL AC_L
        RTS

; BIGSIG0(PB) = ROTR28 ^ ROTR34 ^ ROTR39
BIGSIG0 JSR CP_PB_TA
        LDA #28
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_C_TA
        JSR CP_PB_TA
        LDA #34
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_X_TA
        JSR CP_PB_TA
        LDA #39
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_X_TA
        RTS

; BIGSIG1(PB) = ROTR14 ^ ROTR18 ^ ROTR41
BIGSIG1 JSR CP_PB_TA
        LDA #14
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_C_TA
        JSR CP_PB_TA
        LDA #18
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_X_TA
        JSR CP_PB_TA
        LDA #41
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_X_TA
        RTS

; SMALLSIG0(PB) = ROTR1 ^ ROTR8 ^ SHR7
SSIG0   JSR CP_PB_TA
        LDA #1
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_C_TA
        JSR CP_PB_TA
        LDA #8
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_X_TA
        JSR CP_PB_TA
        LDA #7
        STA SHA_N
        JSR SHR_TA
        JSR ACC_X_TA
        RTS

; SMALLSIG1(PB) = ROTR19 ^ ROTR61 ^ SHR6
SSIG1   JSR CP_PB_TA
        LDA #19
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_C_TA
        JSR CP_PB_TA
        LDA #61
        STA SHA_N
        JSR ROTR_TA
        JSR ACC_X_TA
        JSR CP_PB_TA
        LDA #6
        STA SHA_N
        JSR SHR_TA
        JSR ACC_X_TA
        RTS

; ================================================================
; SHA_BLOCK  -  process 1 block of 128 bytes at (BP)
; ================================================================
SHA_BLOCK
        ; -- W[0..15] = big-endian words from block (reverse to LE) --
        LDA #0
        STA SHA_J               ; word index 0..15
SB_LDW  LDA SHA_J
        ASL
        ASL
        ASL                     ; J*8 = byte offset within block
        STA SHA_OFF
        ; dest = SHA5_W + J*8 ; we fill LE: W[J].byte(b) = block[off + (7-b)]
        LDX #0                  ; b = 0..7
SB_BR   TXA                     ; b
        EOR #7                  ; 7-b
        CLC
        ADC SHA_OFF
        TAY                     ; index in block
        LDA (BP),Y
        ; dest index = J*8 + b
        STX SHA_BTMP
        LDA SHA_J
        ASL
        ASL
        ASL
        CLC
        ADC SHA_BTMP            ; J*8 + b
        TAY
        LDA (BP),Y              ; (wrong: should be source byte) -- see fix
        ; --- correct approach below ---
        JMP SB_BR_FIX
SB_BR_FIX
        ; (block above is replaced; correct version:)
        LDX #0
SB_BR2  TXA
        EOR #7
        CLC
        ADC SHA_OFF
        TAY
        LDA (BP),Y              ; source byte = block[off + (7-b)]
        LDY SHA_J
        ; store in W via pointer
        STA SHA_WBYTE
        ; compute target address SHA5_W + J*8 + b in PA
        LDA SHA_J
        ASL
        ASL
        ASL
        CLC
        ADC #<SHA5_W
        STA PA
        LDA #>SHA5_W
        ADC #0
        STA PA+1
        TXA
        TAY                     ; Y = b
        LDA SHA_WBYTE
        STA (PA),Y
        INX
        CPX #8
        BNE SB_BR2
        INC SHA_J
        LDA SHA_J
        CMP #16
        BNE SB_LDW

        ; -- W[16..79] = SSIG1(W[i-2]) + W[i-7] + SSIG0(W[i-15]) + W[i-16] --
        LDA #16
        STA SHA_J
SB_EXT  ; PB -> W[i-2]
        LDA SHA_J
        SEC
        SBC #2
        JSR SET_PB_W
        JSR SSIG1               ; SHA_ACC = ssig1(W[i-2])
        ; T = SHA_ACC ; PA->SHA_T1 copy
        JSR ACC_TO_T1
        ; T1 += W[i-7]
        LDA #<SHA_T1
        STA PA
        LDA #>SHA_T1
        STA PA+1
        LDA SHA_J
        SEC
        SBC #7
        JSR SET_PB_W
        JSR C64ADD
        ; SHA_ACC = ssig0(W[i-15])
        LDA SHA_J
        SEC
        SBC #15
        JSR SET_PB_W
        JSR SSIG0
        ; T1 += SHA_ACC
        LDA #<SHA_ACC
        STA PB
        LDA #>SHA_ACC
        STA PB+1
        JSR C64ADD
        ; T1 += W[i-16]
        LDA SHA_J
        SEC
        SBC #16
        JSR SET_PB_W
        JSR C64ADD
        ; W[i] = T1
        LDA SHA_J
        JSR SET_PA_W
        LDA #<SHA_T1
        STA PB
        LDA #>SHA_T1
        STA PB+1
        JSR C64COPY
        INC SHA_J
        LDA SHA_J
        CMP #80
        BNE SB_EXT

        ; -- a..h = H[0..7] --
        LDA #<SHA_AH
        STA PA
        LDA #>SHA_AH
        STA PA+1
        LDA #<SHA_H
        STA PB
        LDA #>SHA_H
        STA PB+1
        LDX #0
SB_IH   STX SHA_BTMP
        JSR C64COPY
        ; advance both pointers by 8
        LDA PA
        CLC
        ADC #8
        STA PA
        BCC SB_IH1
        INC PA+1
SB_IH1  LDA PB
        CLC
        ADC #8
        STA PB
        BCC SB_IH2
        INC PB+1
SB_IH2  LDX SHA_BTMP
        INX
        CPX #8
        BNE SB_IH

        ; -- 80 rondes --
        LDA #0
        STA SHA_J
        LDA #<SHA5_K
        STA SHA_KP
        LDA #>SHA5_K
        STA SHA_KP+1
        LDA #<SHA5_W
        STA SHA_WP
        LDA #>SHA5_W
        STA SHA_WP+1
SB_RND
        ; T1 = h
        LDA #<SHA_T1
        STA PA
        LDA #>SHA_T1
        STA PA+1
        LDA #<(SHA_AH+56)         ; h = word 7
        STA PB
        LDA #>(SHA_AH+56)
        STA PB+1
        JSR C64COPY
        ; SHA_ACC = BIGSIG1(e)  (e = word 4)
        LDA #<(SHA_AH+32)
        STA PB
        LDA #>(SHA_AH+32)
        STA PB+1
        JSR BIGSIG1
        ; T1 += SHA_ACC
        LDA #<SHA_ACC
        STA PB
        LDA #>SHA_ACC
        STA PB+1
        JSR C64ADD
        ; SHA_ACC = Ch(e,f,g) = (e&f) ^ (~e & g)
        JSR CH_EFG
        ; T1 += SHA_ACC
        LDA #<SHA_ACC
        STA PB
        LDA #>SHA_ACC
        STA PB+1
        JSR C64ADD
        ; T1 += K[i]   (SHA_KP)
        LDA SHA_KP
        STA PB
        LDA SHA_KP+1
        STA PB+1
        JSR C64ADD
        ; T1 += W[i]   (SHA_WP)
        LDA SHA_WP
        STA PB
        LDA SHA_WP+1
        STA PB+1
        JSR C64ADD
        ; T2 = BIGSIG0(a) + Maj(a,b,c)
        LDA #<(SHA_AH+0)          ; a = word 0
        STA PB
        LDA #>(SHA_AH+0)
        STA PB+1
        JSR BIGSIG0
        ; T2 = SHA_ACC
        LDA #<SHA_T2
        STA PA
        LDA #>SHA_T2
        STA PA+1
        LDA #<SHA_ACC
        STA PB
        LDA #>SHA_ACC
        STA PB+1
        JSR C64COPY
        ; SHA_ACC = Maj(a,b,c)
        JSR MAJ_ABC
        ; T2 += SHA_ACC
        LDA #<SHA_T2
        STA PA
        LDA #>SHA_T2
        STA PA+1
        LDA #<SHA_ACC
        STA PB
        LDA #>SHA_ACC
        STA PB+1
        JSR C64ADD

        ; -- shift werkvars: h=g,g=f,f=e,e=d+T1,d=c,c=b,b=a,a=T1+T2 --
        ; do back to front: word7<-6,6<-5,5<-4 ; e(4)=d(3)+T1 ; 3<-2,2<-1,1<-0 ; a(0)=T1+T2
        ; h<-g
        JSR CP_W6_W7
        ; g<-f
        JSR CP_W5_W6
        ; f<-e
        JSR CP_W4_W5
        ; e = d + T1  -> copy d(3) to e(4), then += T1
        LDA #<(SHA_AH+32)
        STA PA
        LDA #>(SHA_AH+32)
        STA PA+1
        LDA #<(SHA_AH+24)
        STA PB
        LDA #>(SHA_AH+24)
        STA PB+1
        JSR C64COPY
        LDA #<(SHA_AH+32)
        STA PA
        LDA #>(SHA_AH+32)
        STA PA+1
        LDA #<SHA_T1
        STA PB
        LDA #>SHA_T1
        STA PB+1
        JSR C64ADD
        ; d<-c, c<-b, b<-a
        JSR CP_W2_W3
        JSR CP_W1_W2
        JSR CP_W0_W1
        ; a = T1 + T2
        LDA #<(SHA_AH+0)
        STA PA
        LDA #>(SHA_AH+0)
        STA PA+1
        LDA #<SHA_T1
        STA PB
        LDA #>SHA_T1
        STA PB+1
        JSR C64COPY
        LDA #<(SHA_AH+0)
        STA PA
        LDA #>(SHA_AH+0)
        STA PA+1
        LDA #<SHA_T2
        STA PB
        LDA #>SHA_T2
        STA PB+1
        JSR C64ADD

        ; advance KP, WP by 8
        LDA SHA_KP
        CLC
        ADC #8
        STA SHA_KP
        BCC SB_R1
        INC SHA_KP+1
SB_R1   LDA SHA_WP
        CLC
        ADC #8
        STA SHA_WP
        BCC SB_R2
        INC SHA_WP+1
SB_R2   INC SHA_J
        LDA SHA_J
        CMP #80
        BEQ SB_RDN
        JMP SB_RND
SB_RDN

        ; -- H[i] += werkvar[i] --
        LDA #<SHA_H
        STA PA
        LDA #>SHA_H
        STA PA+1
        LDA #<SHA_AH
        STA PB
        LDA #>SHA_AH
        STA PB+1
        LDX #0
SB_UH   STX SHA_BTMP
        JSR C64ADD
        LDA PA
        CLC
        ADC #8
        STA PA
        BCC SB_UH1
        INC PA+1
SB_UH1  LDA PB
        CLC
        ADC #8
        STA PB
        BCC SB_UH2
        INC PB+1
SB_UH2  LDX SHA_BTMP
        INX
        CPX #8
        BNE SB_UH
        RTS

; --- Ch(e,f,g) = (e & f) ^ (~e & g) -> SHA_ACC ---
CH_EFG  ; SHA_ACC = e & f
        LDX #7
CH_CE   LDA SHA_AH+32,X        ; e
        AND SHA_AH+40,X        ; f
        STA SHA_ACC,X
        DEX
        BPL CH_CE
        ; SHA_TC = (~e) & g
        LDX #7
CH_NE   LDA SHA_AH+32,X        ; e
        EOR #$FF               ; ~e
        AND SHA_AH+48,X        ; g
        STA SHA_TC,X
        DEX
        BPL CH_NE
        ; SHA_ACC ^= SHA_TC
        LDX #7
CH_XR   LDA SHA_ACC,X
        EOR SHA_TC,X
        STA SHA_ACC,X
        DEX
        BPL CH_XR
        RTS

; --- Maj(a,b,c) = (a&b)^(a&c)^(b&c) -> SHA_ACC ---
MAJ_ABC LDX #7
MJ_AB   LDA SHA_AH+0,X         ; a
        AND SHA_AH+8,X         ; b
        STA SHA_ACC,X
        DEX
        BPL MJ_AB
        LDX #7
MJ_AC   LDA SHA_AH+0,X         ; a
        AND SHA_AH+16,X        ; c
        STA SHA_TC,X
        DEX
        BPL MJ_AC
        LDX #7
MJ_X1   LDA SHA_ACC,X
        EOR SHA_TC,X
        STA SHA_ACC,X
        DEX
        BPL MJ_X1
        LDX #7
MJ_BC   LDA SHA_AH+8,X         ; b
        AND SHA_AH+16,X        ; c
        STA SHA_TC,X
        DEX
        BPL MJ_BC
        LDX #7
MJ_X2   LDA SHA_ACC,X
        EOR SHA_TC,X
        STA SHA_ACC,X
        DEX
        BPL MJ_X2
        RTS

; --- word-copy helpers within SHA_AH (from source to target) ---
CP_W6_W7 LDX #7
C67     LDA SHA_AH+48,X
        STA SHA_AH+56,X
        DEX
        BPL C67
        RTS
CP_W5_W6 LDX #7
C56     LDA SHA_AH+40,X
        STA SHA_AH+48,X
        DEX
        BPL C56
        RTS
CP_W4_W5 LDX #7
C45     LDA SHA_AH+32,X
        STA SHA_AH+40,X
        DEX
        BPL C45
        RTS
CP_W2_W3 LDX #7
C23     LDA SHA_AH+16,X
        STA SHA_AH+24,X
        DEX
        BPL C23
        RTS
CP_W1_W2 LDX #7
C12     LDA SHA_AH+8,X
        STA SHA_AH+16,X
        DEX
        BPL C12
        RTS
CP_W0_W1 LDX #7
C01     LDA SHA_AH+0,X
        STA SHA_AH+8,X
        DEX
        BPL C01
        RTS

; --- SHA_ACC -> SHA_T1 ---
ACC_TO_T1 LDX #7
AT_L    LDA SHA_ACC,X
        STA SHA_T1,X
        DEX
        BPL AT_L
        RTS

; --- set PB = SHA5_W + A*8 ; set PA = SHA5_W + A*8 ---
SET_PB_W STA SHA_TMPI           ; A = word index (0..79)
        LDA #0
        STA SHA_TMPH
        ASL SHA_TMPI            ; index*8 as 16-bit (else overflow at index>=32)
        ROL SHA_TMPH
        ASL SHA_TMPI
        ROL SHA_TMPH
        ASL SHA_TMPI
        ROL SHA_TMPH
        LDA #<SHA5_W
        CLC
        ADC SHA_TMPI
        STA PB
        LDA #>SHA5_W
        ADC SHA_TMPH
        STA PB+1
        RTS
SET_PA_W STA SHA_TMPI           ; A = word index (0..79)
        LDA #0
        STA SHA_TMPH
        ASL SHA_TMPI
        ROL SHA_TMPH
        ASL SHA_TMPI
        ROL SHA_TMPH
        ASL SHA_TMPI
        ROL SHA_TMPH
        LDA #<SHA5_W
        CLC
        ADC SHA_TMPI
        STA PA
        LDA #>SHA5_W
        ADC SHA_TMPH
        STA PA+1
        RTS

; ================================================================
; SHA512  -  main routine: pad + loop over blocks
; ================================================================
SHA512
        ; -- H = IV --
        LDX #63
SH_IV   LDA SHA_IV,X
        STA SHA_H,X
        DEX
        BPL SH_IV

        ; -- build padded message in SHA_PAD --
        ; copy SRC[0..MLEN-1] -> SHA_PAD
        LDA SRC
        STA PB
        LDA SRC+1
        STA PB+1
        LDA #<SHA_PAD
        STA PA
        LDA #>SHA_PAD
        STA PA+1
        ; 16-bit copy of SHA5_MLEN bytes
        LDA SHA5_MLEN
        STA SHA_CNT
        LDA SHA5_MLEN+1
        STA SHA_CNT+1
SH_CP   LDA SHA_CNT
        ORA SHA_CNT+1
        BEQ SH_CPD
        LDY #0
        LDA (PB),Y
        STA (PA),Y
        INC PB
        BNE SH_CP1
        INC PB+1
SH_CP1  INC PA
        BNE SH_CP2
        INC PA+1
SH_CP2  LDA SHA_CNT
        BNE SH_CP3
        DEC SHA_CNT+1
SH_CP3  DEC SHA_CNT
        JMP SH_CP
SH_CPD
        ; PA now points to SHA_PAD+MLEN ; write 0x80
        LDA #$80
        LDY #0
        STA (PA),Y
        ; compute total padded length (16-bit):
        ;   m1 = MLEN+1 ; zeros so that (m1+zeros) % 128 == 112 ; +16
        ; we keep it simple: fill from MLEN+1 with 0 until we reach a 128-multiple-112,
        ; then 16 length bytes. Compute total first.
        ; m1 = MLEN+1
        LDA SHA5_MLEN
        CLC
        ADC #1
        STA SHA_M1
        LDA SHA5_MLEN+1
        ADC #0
        STA SHA_M1+1
        ; r = m1 mod 128 = m1 & 127 (only low byte relevant since 128 divides 256)
        LDA SHA_M1
        AND #127
        STA SHA_R
        ; zeros = (112 - r) mod 128
        LDA #112
        SEC
        SBC SHA_R
        AND #127
        STA SHA_ZEROS
        ; total = m1 + zeros + 16
        LDA SHA_M1
        CLC
        ADC SHA_ZEROS
        STA SHA_TOTAL
        LDA SHA_M1+1
        ADC #0
        STA SHA_TOTAL+1
        LDA SHA_TOTAL
        CLC
        ADC #16
        STA SHA_TOTAL
        LDA SHA_TOTAL+1
        ADC #0
        STA SHA_TOTAL+1
        ; fill SHA_PAD[m1 .. total-1] with 0 (we overwrite the length bytes later)
        ; pointer PA = SHA_PAD + m1
        LDA #<SHA_PAD
        CLC
        ADC SHA_M1
        STA PA
        LDA #>SHA_PAD
        ADC SHA_M1+1
        STA PA+1
        ; count = total - m1
        LDA SHA_TOTAL
        SEC
        SBC SHA_M1
        STA SHA_CNT
        LDA SHA_TOTAL+1
        SBC SHA_M1+1
        STA SHA_CNT+1
SH_ZL   LDA SHA_CNT
        ORA SHA_CNT+1
        BEQ SH_ZD
        LDA #0
        LDY #0
        STA (PA),Y
        INC PA
        BNE SH_Z1
        INC PA+1
SH_Z1   LDA SHA_CNT
        BNE SH_Z2
        DEC SHA_CNT+1
SH_Z2   DEC SHA_CNT
        JMP SH_ZL
SH_ZD
        ; write bit length (MLEN*8) big-endian in the last 16 bytes:
        ;   total-1 = LSB, total-2 = next, ...  (only 16-bit bitlen supported)
        ; bitlen16 = MLEN << 3 (16-bit)
        LDA SHA5_MLEN
        STA SHA_BL
        LDA SHA5_MLEN+1
        STA SHA_BL+1
        LDX #2                  ; 3 shifts (X=2..0) = MLEN<<3 (bytes->bits)
SH_SHL  ASL SHA_BL
        ROL SHA_BL+1
        DEX
        BPL SH_SHL
        ; SHA_PAD[total-1] = SHA_BL (lo) ; SHA_PAD[total-2] = SHA_BL+1 (hi)
        LDA #<SHA_PAD
        CLC
        ADC SHA_TOTAL
        STA PA
        LDA #>SHA_PAD
        ADC SHA_TOTAL+1
        STA PA+1                ; PA = SHA_PAD + total
        LDY #0
        ; index total-1
        SEC
        LDA PA
        SBC #1
        STA PA
        BCS SH_B1
        DEC PA+1
SH_B1   LDA SHA_BL
        STA (PA),Y             ; LSB
        SEC
        LDA PA
        SBC #1
        STA PA
        BCS SH_B2
        DEC PA+1
SH_B2   LDA SHA_BL+1
        STA (PA),Y             ; next byte

        ; -- number of blocks = total / 128 --
        ; nblk16 = total >> 7
        LDA SHA_TOTAL+1
        STA SHA_NBLK+1
        LDA SHA_TOTAL
        STA SHA_NBLK
        ; >>7 : 7x LSR over 16-bit
        LDX #6                  ; 7 shifts (X=6..0), total/128
SH_NBL  LSR SHA_NBLK+1
        ROR SHA_NBLK
        DEX
        BPL SH_NBL

        ; -- loop blocks --
        LDA #<SHA_PAD
        STA BP
        LDA #>SHA_PAD
        STA BP+1
        LDA #0
        STA SHA_BI
        STA SHA_BI+1
SH_BLKL
        ; done?  SHA_BI == SHA_NBLK ?
        LDA SHA_BI
        CMP SHA_NBLK
        BNE SH_DOB
        LDA SHA_BI+1
        CMP SHA_NBLK+1
        BNE SH_DOB
        JMP SH_FIN
SH_DOB
        JSR PW_SHA
        ; BP += 128
        LDA BP
        CLC
        ADC #128
        STA BP
        BCC SH_BI1
        INC BP+1
SH_BI1  INC SHA_BI
        BNE SH_BI2
        INC SHA_BI+1
SH_BI2  JMP SH_BLKL
SH_FIN
        ; -- digest = H big-endian --
        LDA #0
        STA SHA_J               ; word 0..7
SH_DW   LDA SHA_J
        ASL
        ASL
        ASL
        STA SHA_OFF             ; J*8
        LDX #0                  ; b
SH_DB   ; DIGEST[J*8 + b] = H[J].byte(7-b)
        TXA
        EOR #7
        CLC
        ADC SHA_OFF             ; source index in SHA_H
        TAY
        LDA SHA_H,Y
        ; dest = SHA_DIGEST + J*8 + b
        TXA
        CLC
        ADC SHA_OFF
        TAY
        STA SHA_DIGEST,Y        ; (A still = byte? no) -- fix below
        JMP SH_DB_FIX
SH_DB_FIX
        ; correcte versie:
        LDX #0
SH_DB2  TXA
        EOR #7
        CLC
        ADC SHA_OFF
        TAY
        LDA SHA_H,Y             ; byte
        STA SHA_DBYTE
        TXA
        CLC
        ADC SHA_OFF
        TAY
        LDA SHA_DBYTE
        STA SHA_DIGEST,Y
        INX
        CPX #8
        BNE SH_DB2
        INC SHA_J
        LDA SHA_J
        CMP #8
        BNE SH_DW
        RTS


; ================================================================
; ==================  modL (from step 4, ML_ prefix)  ===========
; ================================================================


!macro mov32 .d, .s {
        lda .s:sta .d : lda .s+1:sta .d+1 : lda .s+2:sta .d+2 : lda .s+3:sta .d+3
}
!macro zero32 .d {
        lda #0:sta .d:sta .d+1:sta .d+2:sta .d+3
}
!macro add32 .d, .s {
        clc : lda .d:adc .s:sta .d : lda .d+1:adc .s+1:sta .d+1 : lda .d+2:adc .s+2:sta .d+2 : lda .d+3:adc .s+3:sta .d+3
}
!macro sub32 .d, .s {
        sec : lda .d:sbc .s:sta .d : lda .d+1:sbc .s+1:sta .d+1 : lda .d+2:sbc .s+2:sta .d+2 : lda .d+3:sbc .s+3:sta .d+3
}

; ================================================================
MODL
        ; --- cellen vullen: cell[k]=[XIN[k],0,0,0] ---
        ldx #0
ML_FILL txa : asl : asl : tay
        lda XIN,x : sta X64,y
        lda #0 : sta X64+1,y : sta X64+2,y : sta X64+3,y
        inx : cpx #64 : bne ML_FILL

        ; ================= LOOP 1 : i=63..32 =================
        lda #252 : sta IOFF
ML_OUT
        ldx IOFF : jsr PW_LDC
        +mov32 XI, ACC
        +zero32 CRY
        lda IOFF : sec : sbc #128 : sta JOFF
        lda #0 : sta MCNT
ML_IN
        ldx JOFF : jsr LDCELL
        +add32 ACC, CRY
        ; PRD = (16*Lt[m]) * XI
        ldx MCNT
        lda LT,x : sta TMP8
        asl : asl : asl : asl : sta ML_MA
        lda TMP8 : lsr : lsr : lsr : lsr : sta ML_MA+1
        jsr ABS_XI
        jsr UMUL16
        lda XSGN : beq ML_NONEG
        jsr NEG_PRD
ML_NONEG
        +sub32 ACC, PRD
        ; carry = (ACC+128)>>8
        +mov32 ML_TMP, ACC
        clc
        lda ML_TMP   : adc #128 : sta ML_TMP
        lda ML_TMP+1 : adc #0   : sta ML_TMP+1
        lda ML_TMP+2 : adc #0   : sta ML_TMP+2
        lda ML_TMP+3 : adc #0   : sta ML_TMP+3
        jsr ASR8_TMP_TO_CRY
        ; ACC -= (CRY<<8)
        +mov32 OPSH, CRY
        ldx #8
ML_SH8  asl OPSH : rol OPSH+1 : rol OPSH+2 : rol OPSH+3
        dex : bne ML_SH8
        +sub32 ACC, OPSH
        ldx JOFF : jsr STCELL
        lda JOFF : clc : adc #4 : sta JOFF
        inc MCNT
        lda MCNT : cmp #20 : beq ML_INDONE
        jmp ML_IN
ML_INDONE
        ; cell[i-12] += carry  (JOFF=4*(i-12))
        ldx JOFF : jsr LDCELL
        +add32 ACC, CRY
        ldx JOFF : jsr STCELL
        ; cell[i]=0
        ldx IOFF : +zero32 ACC : jsr STCELL
        lda IOFF : sec : sbc #4 : sta IOFF
        cmp #124
        beq ML1_DONE
        jmp ML_OUT
ML1_DONE

        ; ================= LOOP 2 : j=0..31 =================
        +zero32 CRY
        lda #0 : sta JOFF : sta JCNT
ML2
        ; M = cell[31] >> 4 (freshly read)
        ldx #124 : jsr LDCELL
        jsr ASR4_ACC
        jsr ABS_ACC_TO_MB        ; ML_MB=|M|, MSGN
        ldx JCNT
        lda LT,x : sta ML_MA
        lda #0   : sta ML_MA+1
        jsr UMUL16
        lda MSGN : beq ML2_NONEG
        jsr NEG_PRD
ML2_NONEG
        ldx JOFF : jsr LDCELL
        +add32 ACC, CRY
        +sub32 ACC, PRD
        +mov32 ML_TMP, ACC
        jsr ASR8_TMP_TO_CRY      ; new carry
        ; cell[j] = ACC & 255  -> [ACC0,0,0,0]
        ldx JOFF
        lda ACC+0 : sta X64+0,x
        lda #0 : sta X64+1,x : sta X64+2,x : sta X64+3,x
        lda JOFF : clc : adc #4 : sta JOFF
        inc JCNT
        lda JCNT : cmp #32
        beq ML2_DONE
        jmp ML2
ML2_DONE

        ; ================= LOOP 3 : j=0..31 cell -= carry*Lt[j] =====
        lda #0 : sta JOFF : sta JCNT
ML3
        +mov32 ACC, CRY
        jsr ABS_ACC_TO_MB        ; ML_MB=|carry|, MSGN
        ldx JCNT
        lda LT,x : sta ML_MA
        lda #0   : sta ML_MA+1
        jsr UMUL16
        lda MSGN : beq ML3_NONEG
        jsr NEG_PRD
ML3_NONEG
        ldx JOFF : jsr LDCELL
        +sub32 ACC, PRD
        ldx JOFF : jsr STCELL
        lda JOFF : clc : adc #4 : sta JOFF
        inc JCNT
        lda JCNT : cmp #32
        beq ML3_DONE
        jmp ML3
ML3_DONE

        ; ================= FINAL : i=0..31 =====================
        lda #0 : sta JOFF : sta JCNT
ML4
        ldx JOFF : jsr LDCELL    ; ACC = cell[i]
        ldy JCNT
        lda ACC+0 : sta ROUT,y   ; ROUT[i] = low byte
        +mov32 ML_TMP, ACC
        jsr ASR8_TMP_TO_PROP     ; PROP = asr8(cell[i])
        lda JOFF : clc : adc #4 : tax
        jsr LDCELL               ; ACC = cell[i+1]
        +add32 ACC, PROP
        lda JOFF : clc : adc #4 : tax
        jsr STCELL
        lda JOFF : clc : adc #4 : sta JOFF
        inc JCNT
        lda JCNT : cmp #32
        beq ML4_DONE
        jmp ML4
ML4_DONE
        rts

; ---- cell load/store (X = offset) ----
LDCELL
        lda X64+0,x : sta ACC+0
        lda X64+1,x : sta ACC+1
        lda X64+2,x : sta ACC+2
        lda X64+3,x : sta ACC+3
        rts
STCELL
        lda ACC+0 : sta X64+0,x
        lda ACC+1 : sta X64+1,x
        lda ACC+2 : sta X64+2,x
        lda ACC+3 : sta X64+3,x
        rts

; ---- |XI| -> ML_MB(2) + XSGN ----
ABS_XI
        lda XI+3 : bmi AX_NEG
        lda XI+0 : sta ML_MB
        lda XI+1 : sta ML_MB+1
        lda #0   : sta XSGN
        rts
AX_NEG  sec
        lda #0 : sbc XI+0 : sta ML_MB
        lda #0 : sbc XI+1 : sta ML_MB+1
        lda #1 : sta XSGN
        rts

; ---- |ACC|(16-bit) -> ML_MB(2) + MSGN ----
ABS_ACC_TO_MB
        lda ACC+3 : bmi AA_NEG
        lda ACC+0 : sta ML_MB
        lda ACC+1 : sta ML_MB+1
        lda #0    : sta MSGN
        rts
AA_NEG  sec
        lda #0 : sbc ACC+0 : sta ML_MB
        lda #0 : sbc ACC+1 : sta ML_MB+1
        lda #1 : sta MSGN
        rts

; ---- PRD = ML_MA(16)*ML_MB(16) unsigned -> 32-bit ----
UMUL16
        +zero32 PRD
        lda ML_MA   : sta AA
        lda ML_MA+1 : sta AA+1
        lda #0   : sta AA+2 : sta AA+3
        ldx #16
UM_L    lsr ML_MB+1 : ror ML_MB+0
        bcc UM_NA
        +add32 PRD, AA
UM_NA   asl AA : rol AA+1 : rol AA+2 : rol AA+3
        dex : bne UM_L
        rts

; ---- PRD = -PRD ----
NEG_PRD sec
        lda #0 : sbc PRD+0 : sta PRD+0
        lda #0 : sbc PRD+1 : sta PRD+1
        lda #0 : sbc PRD+2 : sta PRD+2
        lda #0 : sbc PRD+3 : sta PRD+3
        rts

; ---- CRY = asr8(ML_TMP) ----
ASR8_TMP_TO_CRY
        lda ML_TMP+1 : sta CRY+0
        lda ML_TMP+2 : sta CRY+1
        lda ML_TMP+3 : sta CRY+2
        lda ML_TMP+3 : bmi A8C_NEG
        lda #0 : sta CRY+3 : rts
A8C_NEG lda #$FF : sta CRY+3 : rts

; ---- PROP = asr8(ML_TMP) ----
ASR8_TMP_TO_PROP
        lda ML_TMP+1 : sta PROP+0
        lda ML_TMP+2 : sta PROP+1
        lda ML_TMP+3 : sta PROP+2
        lda ML_TMP+3 : bmi A8P_NEG
        lda #0 : sta PROP+3 : rts
A8P_NEG lda #$FF : sta PROP+3 : rts

; ---- ACC = asr4(ACC) ----
ASR4_ACC
        ldx #4
A4_L    lda ACC+3 : cmp #$80
        ror ACC+3 : ror ACC+2 : ror ACC+1 : ror ACC+0
        dex : bne A4_L
        rts

; ================================================================
; MLMUL8 : ML_MUL_RES(2) = ML_MUL_A * ML_MUL_B  (8x8 -> 16, unsigned)
; ================================================================
MLMUL8
        lda #0 : sta ML_MUL_RES : sta ML_MUL_RES+1
        ldx #8
ML_M8L     lsr ML_MUL_B
        bcc ML_M8NA
        lda ML_MUL_RES+1 : clc : adc ML_MUL_A : sta ML_MUL_RES+1
ML_M8NA    ror ML_MUL_RES+1 : ror ML_MUL_RES
        dex : bne ML_M8L
        rts

; ================================================================
; MUL256 : PRODUCT(64) = AOP(32) * BOP(32)  unsigned schoolbook
; ================================================================
MUL256
        lda #0 : ldx #63
M256_Z  sta PRODUCT,x : dex : bpl M256_Z
        lda #0 : sta MICNT
M256_I
        lda #0 : sta MCARRY : sta MCARRY+1
        lda MICNT : sta MIDX
        ldx MICNT
        lda AOP,x : sta ML_MUL_A
        lda #0 : sta MJCNT
M256_J
        ldx MJCNT
        lda BOP,x : sta ML_MUL_B
        jsr MLMUL8                  ; ML_MUL_RES = A[i]*B[j]
        ldx MIDX
        clc
        lda ML_MUL_RES   : adc PRODUCT,x : sta ML_TLO
        lda ML_MUL_RES+1 : adc #0        : sta ML_THI
        clc
        lda ML_TLO : adc MCARRY   : sta ML_TLO
        lda ML_THI : adc MCARRY+1 : sta ML_THI
        lda ML_TLO : sta PRODUCT,x
        lda ML_THI : sta MCARRY
        lda #0  : sta MCARRY+1
        inc MIDX
        inc MJCNT
        lda MJCNT : cmp #32 : bne M256_J
        ; PRODUCT[i+32] += carry, propageer
        ldx MIDX
        clc
        lda PRODUCT,x : adc MCARRY : sta PRODUCT,x
        inx
M256_P  lda PRODUCT,x : adc #0 : sta PRODUCT,x
        bcc M256_PD
        inx
        cpx #64 : bne M256_P
M256_PD
        inc MICNT
        lda MICNT : cmp #32
        beq M256_DONE
        jmp M256_I
M256_DONE
        rts

; ================================================================
; MULADD_S : SOUT(32) = (RIN_S + KIN_S*AIN_S) mod L
;   via S = ((k*a) mod L + r) mod L  (reuses MODL, byte input)
; ================================================================
MULADD_S
        ldx #31
MAS_C1  lda KIN_S,x : sta AOP,x
        lda AIN_S,x : sta BOP,x
        dex : bpl MAS_C1
        jsr MUL256                 ; PRODUCT = k*a
        ldx #63
MAS_C2  lda PRODUCT,x : sta XIN,x : dex : bpl MAS_C2
        jsr MODL                   ; ROUT = (k*a) mod L
        lda #0 : ldx #63
MAS_Z   sta XIN,x : dex : bpl MAS_Z
        lda #32 : sta MJCNT     ; carry-safe counter (DEC doesn't touch C)
        ldx #0
        clc
MAS_ADD lda ROUT,x : adc RIN_S,x : sta XIN,x
        inx                     ; INX doesn't touch carry
        dec MJCNT               ; DEC doesn't touch carry
        bne MAS_ADD
        lda #0 : adc #0 : sta XIN+32   ; carry-bit
        jsr MODL                   ; ROUT = S
        ldx #31
MAS_C3  lda ROUT,x : sta SOUT,x : dex : bpl MAS_C3
        rts

; ================================================================
; CLAMP : Ed25519-scalarklem op CLBUF(32) in-place
;   a[0]  &= 0xF8 ; a[31] &= 0x7F ; a[31] |= 0x40
; ================================================================
CLAMP
        lda CLBUF+0  : and #$F8 : sta CLBUF+0
        lda CLBUF+31 : and #$7F : ora #$40 : sta CLBUF+31
        rts


; ================================================================
; SIGN-FLOW  (RFC 8032 / pynacl seed-variant)
; ================================================================
; B -> PIN (load base point)
LOAD_B
        LDX #31
LB_L    LDA BX_CONST,X : STA PIN_X,X
        LDA BY_CONST,X : STA PIN_Y,X
        LDA BZ_CONST,X : STA PIN_Z,X
        LDA BT_CONST,X : STA PIN_T,X
        DEX
        BPL LB_L
        RTS

; ACC (extended) -> PX/PY/PZ (for ENCODE)
ACC_TO_PXYZ
        LDX #31
AP_L    LDA ACC_X,X : STA PX,X
        LDA ACC_Y,X : STA PY,X
        LDA ACC_Z,X : STA PZ,X
        DEX
        BPL AP_L
        RTS

; ----------------------------------------------------------------
; SIGN_SETUP : SEED(32) -> SK_A (geklemde scalar a), SK_PREFIX, SK_PUB(A)
;   h = SHA512(seed) ; a = CLAMP(h[0:32]) ; prefix = h[32:64]
;   A = ENCODE(a*B)   (1 scalar mult, the expensive step)
; ----------------------------------------------------------------
SIGN_SETUP
        PHP
        SEI         ; IRQ off during scalar mult
        ; --- NMI sources OFF during scalar mult --------------------
        ; SIGN_SETUP runs BEFORE INSTALL_RX_NMI; $0318 here still points
        ; to the KERNAL default NMI handler, which on an ACIA-NMI does
        ; RS232 processing and clobbers zeropage $F7-$FA (the scalar-mult
        ; pointers). SEI does not mask NMI -> turn the sources off themselves.
        LDA #$0B : STA $DE02        ; ACIA: RX-IRQ OFF
        LDA #$7F : STA $DD0D        ; CIA2: clear all NMI enables
        LDA $DD0D                   ; clear pending CIA2-NMI
        LDA $DE01                   ; ACIA-status lezen
        LDA $DE00                   ; ACIA-data lezen -> RDRF/NMI weg
        LDA #<SEED : STA SRC
        LDA #>SEED : STA SRC+1
        LDA #32 : STA SHA5_MLEN
        LDA #0  : STA SHA5_MLEN+1
        JSR SHA512
        ; a = CLAMP(h[0:32])
        LDX #31
SS_CA   LDA SHA_DIGEST,X : STA CLBUF,X : DEX : BPL SS_CA
        JSR CLAMP
        LDX #31
SS_CB   LDA CLBUF,X : STA SK_A,X : STA SCALAR,X : DEX : BPL SS_CB
        ; prefix = h[32:64]
        LDX #31
SS_CP   LDA SHA_DIGEST+32,X : STA SK_PREFIX,X : DEX : BPL SS_CP
        ; A = encode(a*B)
        JSR COMB_SCALAR_MUL     ; B: fixed-base comb (was LOAD_B+SCALAR_MUL)
        JSR ACC_TO_PXYZ
        JSR ENCODE
        LDX #31
SS_CK   LDA ENC,X : STA SK_PUB,X : DEX : BPL SS_CK
        LDA #$09 : STA $DE02        ; ACIA: RX-IRQ weer AAN
        PLP         ; restore I flag
        RTS

; ----------------------------------------------------------------
; SIGN : signs (MSG_PTR)[0..MSG_LEN-1] with cached SK_A/SK_PREFIX/SK_PUB
;   r = MODL(SHA512(prefix||M)) ; R = encode(r*B)
;   k = MODL(SHA512(R||A||M))   ; S = (r + k*a) mod L ; sig = R||S
; MSG_LEN is 16-bit (lo,hi); M up to 1280 bytes (wire blob ~1KB).
; M read via MSG_PTR; standalone test sets MSG_PTR = MSG_BUF.
; ----------------------------------------------------------------
SIGN
        PHP
        SEI         ; IRQ off during scalar mult
        JSR SIGN_R            ; -> SC_R = SCALAR = r ; CONCAT verbruikt
        ; R = encode(r*B)
        JSR COMB_SCALAR_MUL     ; B: fixed-base comb (was LOAD_B+SCALAR_MUL)
        JSR ACC_TO_PXYZ
        JSR ENCODE
        LDX #31
SG_RR   LDA ENC,X : STA SIG_R,X : DEX : BPL SG_RR

        ; --- CONCAT = R(32) || A(32) || M ; len = 64+MSG_LEN ---
        LDX #31
SG_P2   LDA SIG_R,X   : STA CONCAT,X
        LDA SK_PUB,X  : STA CONCAT+32,X
        DEX : BPL SG_P2
        LDA #<(CONCAT+64) : STA CDST
        LDA #>(CONCAT+64) : STA CDST+1
        JSR COPY_M
        ; SHA5_MLEN = 64 + MSG_LEN (16-bit, with carry)
        LDA MSG_LEN   : CLC : ADC #64 : STA SHA5_MLEN
        LDA MSG_LEN+1 : ADC #0        : STA SHA5_MLEN+1
        LDA #<CONCAT : STA SRC
        LDA #>CONCAT : STA SRC+1
        JSR SHA512
        ; k = MODL(digest)
        LDX #63
SG_X2   LDA SHA_DIGEST,X : STA XIN,X : DEX : BPL SG_X2
        JSR MODL
        LDX #31
SG_K1   LDA ROUT,X : STA SC_K,X : DEX : BPL SG_K1

        ; --- S = (r + k*a) mod L  via MULADD_S(RIN_S=r,KIN_S=k,AIN_S=a) ---
        LDX #31
SG_MS   LDA SC_R,X : STA RIN_S,X
        LDA SC_K,X : STA KIN_S,X
        LDA SK_A,X : STA AIN_S,X
        DEX : BPL SG_MS
        JSR MULADD_S          ; -> SOUT = S

        ; --- sig = R || S ---
        LDX #31
SG_OUT  LDA SIG_R,X : STA SIG_OUT,X
        LDA SOUT,X  : STA SIG_OUT+32,X
        DEX : BPL SG_OUT
        PLP         ; restore I flag
        RTS

; ----------------------------------------------------------------
; SIGN_R : phase 1 of SIGN + standalone debug entry.
;   CONCAT = prefix(32) || M ; r = MODL(SHA512(CONCAT)) -> SC_R + SCALAR
; No scalar mult -> fast; sim checks r cheaply over many lengths
; (same COPY_M + 16-bit SHA5_MLEN as phase 2, so a full proof).
; ----------------------------------------------------------------
SIGN_R
        LDX #31
SG_P1   LDA SK_PREFIX,X : STA CONCAT,X : DEX : BPL SG_P1
        LDA #<(CONCAT+32) : STA CDST
        LDA #>(CONCAT+32) : STA CDST+1
        JSR COPY_M
        ; SHA5_MLEN = 32 + MSG_LEN (16-bit, with carry)
        LDA MSG_LEN   : CLC : ADC #32 : STA SHA5_MLEN
        LDA MSG_LEN+1 : ADC #0        : STA SHA5_MLEN+1
        LDA #<CONCAT : STA SRC
        LDA #>CONCAT : STA SRC+1
        JSR SHA512
        LDX #63
SG_X1   LDA SHA_DIGEST,X : STA XIN,X : DEX : BPL SG_X1
        JSR MODL
        LDX #31
SG_R1   LDA ROUT,X : STA SC_R,X : STA SCALAR,X : DEX : BPL SG_R1
        RTS

; ----------------------------------------------------------------
; COPY_M : copy (MSG_PTR)[0..MSG_LEN-1] (16-bit) to (CDST).
;   CDST/CDST+1 set beforehand. Clobbers A,Y,CSRC,CDST,CCNT.
;   16-bit down-counter: lo==0 -> hi-- ; then lo-- (wrap 0->FF).
; ----------------------------------------------------------------
COPY_M
        LDA MSG_PTR   : STA CSRC
        LDA MSG_PTR+1 : STA CSRC+1
        LDA MSG_LEN   : STA CCNT
        LDA MSG_LEN+1 : STA CCNT+1
        LDY #0
CM_LP   LDA CCNT : ORA CCNT+1 : BEQ CM_DN
        LDA (CSRC),Y : STA (CDST),Y
        INC CSRC : BNE CM_S1 : INC CSRC+1
CM_S1   INC CDST : BNE CM_S2 : INC CDST+1
CM_S2   LDA CCNT : BNE CM_D1 : DEC CCNT+1
CM_D1   DEC CCNT
        JMP CM_LP
CM_DN   RTS


; ================================================================
; DATA
; ================================================================

MUL_A    !byte 0
MUL_B    !byte 0
MUL_RES  !byte 0,0
CARRY8   !byte 0
CARRY16  !byte 0,0
TLO      !byte 0
THI      !byte 0
II       !byte 0
SM_BIT   !byte 0
SM_CNT   !byte 0
SM_NBITS !byte 0
SM_TMP   !byte 0

MA       !fill 32,0
MB       !fill 32,0
PROD     !fill 64,0
HB       !fill 36,0
TB       !fill 36,0
RES      !fill 33,0
TMP      !fill 33,0

; --- point work buffers (A/B input coords, R output coords) ---
AX       !fill 32,0
AY       !fill 32,0
AZ       !fill 32,0
AT       !fill 32,0
BX_      !fill 32,0
BY_      !fill 32,0
BZ_      !fill 32,0
BT_      !fill 32,0
RX       !fill 32,0
RY       !fill 32,0
RZ       !fill 32,0
RT       !fill 32,0

; --- intermediate-result formulas ---
PvA      !fill 32,0
PvB      !fill 32,0
PvC      !fill 32,0
PvD      !fill 32,0
PvE      !fill 32,0
PvF      !fill 32,0
PvG      !fill 32,0
PvH      !fill 32,0
PT1      !fill 32,0
PT2      !fill 32,0

; --- scalar-mult buffers ---
ACC_X    !fill 32,0
ACC_Y    !fill 32,0
ACC_Z    !fill 32,0
ACC_T    !fill 32,0
PIN_X    !fill 32,0
PIN_Y    !fill 32,0
PIN_Z    !fill 32,0
PIN_T    !fill 32,0
SCALAR   !fill 32,0

; --- test input/output ---

; --- veldconstanten ---
ZERO_CONST !fill 32,0
; p = 2^255-19 little-endian
P_CONST  !byte $ED
         !fill 30,$FF
         !byte $7F
; 2d (little-endian), d = -121665/121666 mod p
; 2d = 0x2406d9dc56dffce7198e80f2eef3d13000e0149a8283b156ebd69b9426b2f159
D2_CONST !byte $59,$F1,$B2,$26,$94,$9B,$D6,$EB,$56,$B1,$83,$82,$9A,$14,$E0,$00
         !byte $30,$D1,$F3,$EE,$F2,$80,$8E,$19,$E7,$FC,$DF,$56,$DC,$D9,$06,$24


; --- FP_INV work buffers (from fp25519test) ---
ZIN      !fill 32,0
OUT      !fill 32,0
SQ_PTR   !byte 0,0
SQN_CNT  !byte 0
z2       !fill 32,0
t1       !fill 32,0
t0       !fill 32,0
z9       !fill 32,0
z11      !fill 32,0
z5_0     !fill 32,0
z10_0    !fill 32,0
z20_0    !fill 32,0
z50_0    !fill 32,0
z100_0   !fill 32,0

; --- ENCODE-buffers ---
PX       !fill 32,0
PY       !fill 32,0
PZ       !fill 32,0
ZI       !fill 32,0
EX       !fill 32,0
EY       !fill 32,0
ENC      !fill 32,0


; ================================================================
; SHA-512 data
; ================================================================

      !source "sha512_const_ml.inc"   ; SHA_IV, SHA5_K (80 words)

SHA_H      !fill 64,0
SHA5_W      = $C000          ; free RAM (work buffer, no PRG bytes)
SHA_AH     !fill 64,0           ; a..h (8 words)
SHA_T1     !fill 8,0
SHA_T2     !fill 8,0
SHA_TA     !fill 8,0            ; rotate-scratch
SHA_TB     !fill 8,0
SHA_TC     !fill 8,0
SHA_ACC    !fill 8,0
SHA_DIGEST !fill 64,0
SHA_PAD    !fill 1664,0         ; padded message (enough for ~12 blocks)

SHA5_MLEN   !byte 0,0            ; 16-bit invoerlengte
SHA_M1     !byte 0,0
SHA_TOTAL  !byte 0,0
SHA_CNT    !byte 0,0
SHA_NBLK   !byte 0,0
SHA_BI     !byte 0,0
SHA_BL     !byte 0,0
SHA_R      !byte 0
SHA_ZEROS  !byte 0
SHA_N      !byte 0
SHA_BK     !byte 0
SHA_BC     !byte 0
SHA_BC2    !byte 0
SHA_J      !byte 0
SHA_OFF    !byte 0
SHA_BTMP   !byte 0
SHA_WBYTE  !byte 0
SHA_DBYTE  !byte 0
SHA_TMPI   !byte 0
SHA_TMPH   !byte 0
SHA_KP     !byte 0,0
SHA_WP     !byte 0,0


; ================================================================
; modL data (ML_-prefix)
; ================================================================

ACC   !fill 4,0
CRY   !fill 4,0
PRD   !fill 4,0
XI    !fill 4,0
OPSH  !fill 4,0
ML_TMP   !fill 4,0
PROP  !fill 4,0
AA    !fill 4,0
ML_MA    !fill 2,0
ML_MB    !fill 2,0
XSGN  !byte 0
MSGN  !byte 0
TMP8  !byte 0
IOFF  !byte 0
JOFF  !byte 0
MCNT  !byte 0
JCNT  !byte 0
ML_MUL_A !byte 0
ML_MUL_B !byte 0
ML_MUL_RES !byte 0,0
MCARRY !byte 0,0
ML_TLO   !byte 0
ML_THI   !byte 0
MIDX  !byte 0
MICNT !byte 0
MJCNT !byte 0
AOP   !fill 32,0
BOP   !fill 32,0
PRODUCT !fill 64,0
RIN_S !fill 32,0
KIN_S !fill 32,0
AIN_S !fill 32,0
SOUT  !fill 32,0
CLBUF !fill 32,0

LT    !byte $ed,$d3,$f5,$5c,$1a,$63,$12,$58,$d6,$9c,$f7,$a2,$de,$f9,$de,$14
      !byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,$10

XIN   !fill 64,0
ROUT  !fill 32,0

      * = $9C00               ; X64 on fixed page boundary (portable, no self-ref)
X64   !fill 256,0


; --- base point B (extended coords, LE) ---
BX_CONST !byte $1A,$D5,$25,$8F,$60,$2D,$56,$C9,$B2,$A7,$25,$95,$60,$C7,$2C,$69
     !byte $5C,$DC,$D6,$FD,$31,$E2,$A4,$C0,$FE,$53,$6E,$CD,$D3,$36,$69,$21
BY_CONST !byte $58,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66
     !byte $66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66
BZ_CONST !byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
     !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BT_CONST !byte $A3,$DD,$B7,$A5,$B3,$8A,$DE,$6D,$F5,$52,$51,$77,$80,$9F,$F0,$20
     !byte $7D,$E3,$AB,$64,$8E,$4E,$EA,$66,$65,$76,$8B,$D7,$0F,$5F,$87,$67

; --- sign-flow buffers ---
SEED       !fill 32,0
SK_A       !fill 32,0
SK_PREFIX  !fill 32,0
SK_PUB     !fill 32,0
SC_R       !fill 32,0
SC_K       !fill 32,0
SIG_R      !fill 32,0
SIG_OUT    !fill 64,0
MSG_PTR    !byte 0,0          ; 16-bit pointer to message to sign (M)
MSG_LEN    !byte 0,0          ; 16-bit length of M (lo,hi)
CCNT       !byte 0,0          ; COPY_M down-counter
MSG_BUF    = $C800          ; vrij RAM (test-scratch; integratie: MSG_PTR)
CONCAT     = $C280          ; vrij RAM $C280-$C7FF (hash-invoerbuffer)

; ================================================================
; Item 2 — relay-auth challenge-response, 256-bit pad (Optie B)
; ----------------------------------------------------------------
; Parallel to the existing WS_AUTH (128-bit). Place WS_AUTH256
; next to WS_AUTH so the 128-bit fallback stays. Call WS_AUTH256
; instead of WS_AUTH when the identity is a 256-bit identity.
;
; Differences from WS_AUTH (all other logic reused identically):
;   step 1: bits:256 + 32-byte enc_key (HKDF_OKM[0:32]) instead of 16
;   step 3: AGD256 (AES-256-GCM-decrypt+verify) instead of AES_GCM_DECRYPT;
;           48-byte data gesplitst -> CTBUF[32] (nonce-CT) + GCM_RECV_TAG[16];
;           VERIFY_FAIL checked (bad tag -> auth failed)
;   step 4: nonce emitted from PTBUF (AGD256 output) instead of GCM_CTBUF
;
; VOORWAARDEN (item 5 / item 4):
;   - AES-256 layer merged in: AGD256, AES_KEY[32], CTBUF/PTBUF,
;     GCM_RECV_TAG[16], VERIFY_FAIL, PTLEN exist (from aes256test.asm).
;   - HKDF_OKM[0:32] = eigen 256-bit encKey (DERIVE_KEYPAIR of paste).
;   - Challenge-nonce is 32 bytes -> data = 48 (32 CT + 16 tag): zelfde
;     length check as 128-bit. (nonce/tag length equal for both paths)
;
; Reason codes from the relay (bad_init/bad_key_length/proof_invalid/
; timeout) are handled generically as auth_fail in WA2_FAIL.
; ================================================================
WS_AUTH256
        LDA #$9E            ; yellow
        JSR PRINT_CHR
        LDA #<STR_AUTH_BUSY
        STA $FB
        LDA #>STR_AUTH_BUSY
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; wit
        JSR PRINT_CHR

        ; -- step 1: auth_init (bits:256, 32-byte enc_key) --
        JSR JOUT_INIT
        LDA #<STR_AUTH1_256
        STA $FB
        LDA #>STR_AUTH1_256
        STA $FC
        JSR JOUT_EMIT_STR
        LDX #0
WA2_KL  LDA HKDF_OKM,X         ; eigen 256-bit encKey = HKDF_OKM[0:32]
        STX BGB_XTMP           ; BYTE_TO_DEC clobbers X
        JSR BYTE_TO_DEC
        LDX BGB_XTMP
        INX
        CPX #32                ; 32 key bytes instead of 16
        BEQ WA2_KLD
        LDA #$2C               ; ','
        JSR JOUT_EMIT
        JMP WA2_KL
WA2_KLD LDA #$5D               ; ']'
        JSR JOUT_EMIT
        LDA #$7D               ; '}'
        JSR JOUT_EMIT
        JSR WS_SEND_EXT

        ; -- step 2: wait for challenge frame (max 8) -- (identical to WS_AUTH)
        LDA #8
        STA WA_TRY
WA2_W1  JSR WS_RECV_FRAME
        BCC WA2_G1
        DEC WA_TRY
        BNE WA2_W1
        JMP WA2_FAIL
WA2_G1  LDA #<RCV_BUF
        STA $FB
        LDA #>RCV_BUF
        STA $FC
        LDA #<JSC_CHAL
        STA JSC_PAT_LO
        LDA #>JSC_CHAL
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC WA2_CH
        DEC WA_TRY
        BNE WA2_W1
        JMP WA2_FAIL
WA2_CH
        ; iv parsen (12 bytes)
        LDA #<JSC_IV
        STA JSC_PAT_LO
        LDA #>JSC_IV
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP WA2_FAIL
        LDA #<RCV_IV
        STA $FD
        LDA #>RCV_IV
        STA $FE
        LDA #12
        STA PRM_CNT
        LDA #0
        STA RCV_CT_LEN
        STA RCV_CT_LEN+1
        JSR JSON_PARSE_ARR
        BCC *+5
        JMP WA2_FAIL
        ; parse data (must be 48 = 32 nonce-CT + 16 tag)
        LDA #<JSC_DATA
        STA JSC_PAT_LO
        LDA #>JSC_DATA
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC *+5
        JMP WA2_FAIL
        LDA #<RCV_CT
        STA $FD
        LDA #>RCV_CT
        STA $FE
        LDA #0
        STA PRM_CNT            ; 0 = variable length
        STA RCV_CT_LEN
        STA RCV_CT_LEN+1
        STA RCV_TOOLONG
        JSR JSON_PARSE_ARR
        BCC *+5
        JMP WA2_FAIL
        LDA RCV_CT_LEN
        CMP #48
        BEQ *+5
        JMP WA2_FAIL

        ; -- step 3: decrypt challenge with AGD256 (AES-256-GCM) --
        ; iv -> AES_NONCE (12)
        LDX #11
WA2_IV  LDA RCV_IV,X
        STA AES_NONCE,X
        DEX
        BPL WA2_IV
        ; eigen encKey -> AES_KEY (32)
        LDX #31
WA2_KS  LDA HKDF_OKM,X
        STA AES_KEY,X
        DEX
        BPL WA2_KS
        ; data[0:32] -> CTBUF  (nonce-ciphertext)
        LDX #31
WA2_CT  LDA RCV_CT,X
        STA CTBUF,X
        DEX
        BPL WA2_CT
        ; data[32:48] -> GCM_RECV_TAG  (16-byte tag)
        LDX #15
WA2_TG  LDA RCV_CT+32,X
        STA GCM_RECV_TAG,X
        DEX
        BPL WA2_TG
        ; PTLEN = 32
        LDA #32
        STA PTLEN+0
        LDA #0
        STA PTLEN+1
        JSR AGD256             ; -> PTBUF[0..31] = nonce ; VERIFY_FAIL
        LDA VERIFY_FAIL
        BEQ WA2_DEC_OK
        JMP WA2_FAIL           ; tag verification failed
WA2_DEC_OK

        ; -- step 4: auth_proof (nonce from PTBUF) --
        JSR JOUT_INIT
        LDA #<STR_AUTH2
        STA $FB
        LDA #>STR_AUTH2
        STA $FC
        JSR JOUT_EMIT_STR
        LDX #0
WA2_NL  LDA PTBUF,X            ; AGD256 output instead of GCM_CTBUF
        STX BGB_XTMP
        JSR BYTE_TO_DEC
        LDX BGB_XTMP
        INX
        CPX #32
        BEQ WA2_NLD
        LDA #$2C               ; ','
        JSR JOUT_EMIT
        JMP WA2_NL
WA2_NLD LDA #$5D               ; ']'
        JSR JOUT_EMIT
        LDA #$7D               ; '}'
        JSR JOUT_EMIT
        JSR WS_SEND_EXT

        ; -- step 5: wait for auth_ok / auth_fail -- (identical to WS_AUTH)
        LDA #8
        STA WA_TRY
WA2_W2  JSR WS_RECV_FRAME
        BCC WA2_G2
        DEC WA_TRY
        BNE WA2_W2
        JMP WA2_FAIL
WA2_G2  LDA #<RCV_BUF
        STA $FB
        LDA #>RCV_BUF
        STA $FC
        LDA #<JSC_AOK
        STA JSC_PAT_LO
        LDA #>JSC_AOK
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCC WA2_OK
        LDA #<RCV_BUF
        STA $FB
        LDA #>RCV_BUF
        STA $FC
        LDA #<JSC_AFAIL
        STA JSC_PAT_LO
        LDA #>JSC_AFAIL
        STA JSC_PAT_HI
        JSR JSON_SCAN
        BCS WA2_NXT
        JMP WA2_FAIL
WA2_NXT DEC WA_TRY
        BNE WA2_W2
        JMP WA2_FAIL
WA2_OK
        LDA #$1E            ; green
        JSR PRINT_CHR
        LDA #<STR_AUTH_OK
        STA $FB
        LDA #>STR_AUTH_OK
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; wit
        JSR PRINT_CHR
        CLC
        RTS
WA2_FAIL
        LDA #$1C            ; red
        JSR PRINT_CHR
        LDA #<STR_AUTH_ERR
        STA $FB
        LDA #>STR_AUTH_ERR
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; wit
        JSR PRINT_CHR
        SEC
        RTS

; --- new string (place with the other STR_AUTH* strings) ---
; {"type":"sig:auth_init","bits":256,"enc_key":[
STR_AUTH1_256
        !byte $7B,$22,$74,$79,$70,$65,$22,$3A,$22,$73,$69,$67,$3A
        !byte $61,$75,$74,$68,$5F,$69,$6E,$69,$74,$22,$2C,$22,$62
        !byte $69,$74,$73,$22,$3A,$32,$35,$36,$2C,$22,$65,$6E,$63   ; "bits":256
        !byte $5F,$6B,$65,$79,$22,$3A,$5B,$00


; ================================================================
; WS_SEND_MSG256 - 256-bit message: AES-256-GCM + Ed25519 sig (Option B)
;   {"type":"app:message","from":..,"to":..,"blob":{iv,data},"sig":[64]}
; Requires: KEY_PEER256[32]=peer encKey ; SIGN_SETUP run once
;          (SK_A/SK_PREFIX/SK_PUB cached with the HKDF signing seed).
; Input : INP_BUF/INP_LEN (like the 128-bit path).
; ================================================================
WS_SEND_MSG256
        ; -- peer 32-byte encKey -> AES_KEY --
        LDX #31
WSM2_K  LDA KEY_PEER256,X
        STA AES_KEY,X
        DEX
        BPL WSM2_K

        ; -- inner JSON -> MSG_INNER_BUF ; GCM_PT_PTR/LEN set --
        JSR BUILD_INNER_JSON

        ; -- inner plaintext -> PTBUF (AGE256 reads PTBUF) ; PTLEN --
        LDA GCM_PT_PTR+0 : STA MSG_PTR+0
        LDA GCM_PT_PTR+1 : STA MSG_PTR+1
        LDA GCM_PT_LEN+0 : STA MSG_LEN+0
        LDA GCM_PT_LEN+1 : STA MSG_LEN+1
        LDA #<PTBUF : STA CDST
        LDA #>PTBUF : STA CDST+1
        JSR COPY_M
        LDA GCM_PT_LEN+0 : STA PTLEN+0
        LDA GCM_PT_LEN+1 : STA PTLEN+1

        ; -- fresh nonce + AES-256-GCM encrypt --
        JSR GCM_NONCE_GEN
        JSR AGE256             ; -> CTBUF, GCM_TAG

        ; -- CTBUF -> GCM_CTBUF (BUILD_GCM_BLOB reads GCM_CTBUF) --
        LDA #<CTBUF : STA MSG_PTR+0
        LDA #>CTBUF : STA MSG_PTR+1
        LDA GCM_PT_LEN+0 : STA MSG_LEN+0
        LDA GCM_PT_LEN+1 : STA MSG_LEN+1
        LDA #<GCM_CTBUF : STA CDST
        LDA #>GCM_CTBUF : STA CDST+1
        JSR COPY_M

        ; -- buitenste header: {"type":..,"from":"<id>","to":"<peer>","blob": --
        JSR JOUT_INIT
        LDA #<STR_MSG_HDR1 : STA $FB
        LDA #>STR_MSG_HDR1 : STA $FC
        JSR JOUT_EMIT_STR
        LDX #0
WSM2_ID LDA C64_IDSTR,X
        BEQ WSM2_IDE
        JSR JOUT_EMIT
        INX
        JMP WSM2_ID
WSM2_IDE
        LDA #<STR_MSG_TO : STA $FB
        LDA #>STR_MSG_TO : STA $FC
        JSR JOUT_EMIT_STR
        LDX #0
WSM2_TO LDA PEER_IDSTR,X
        BEQ WSM2_TOE
        JSR JOUT_EMIT
        INX
        JMP WSM2_TO
WSM2_TOE
        LDA #<STR_MSG_BLOB : STA $FB
        LDA #>STR_MSG_BLOB : STA $FC
        JSR JOUT_EMIT_STR

        ; -- record blob start for the sig --
        LDA JOUT_LO : STA BLOB_PTR+0
        LDA JOUT_HI : STA BLOB_PTR+1
        LDA JOUT_LEN+0 : STA BLOB_LEN0+0
        LDA JOUT_LEN+1 : STA BLOB_LEN0+1

        JSR BUILD_GCM_BLOB     ; {"iv":[AES_NONCE],"data":[GCM_CTBUF..GCM_TAG]}

        ; -- MAC_LEN = JOUT_LEN - BLOB_LEN0 (16-bit; no CPX between SBCs) --
        SEC
        LDA JOUT_LEN+0 : SBC BLOB_LEN0+0 : STA MAC_LEN+0
        LDA JOUT_LEN+1 : SBC BLOB_LEN0+1 : STA MAC_LEN+1

        ; -- sig = Ed25519 over the blob bytes (step C) --
        LDA BLOB_PTR+0 : STA MSG_PTR+0
        LDA BLOB_PTR+1 : STA MSG_PTR+1
        LDA MAC_LEN+0 : STA MSG_LEN+0
        LDA MAC_LEN+1 : STA MSG_LEN+1
        JSR SIGN               ; -> SIG_OUT[0..63]

        ; -- ,"sig":[ 64 decimalen ] --
        LDA #<STR_SIGHDR : STA $FB
        LDA #>STR_SIGHDR : STA $FC
        JSR JOUT_EMIT_STR
        LDX #0
WSM2_SG LDA SIG_OUT,X
        STX BGB_XTMP
        JSR BYTE_TO_DEC
        LDX BGB_XTMP
        INX
        CPX #64
        BEQ WSM2_SGD
        LDA #$2C : JSR JOUT_EMIT
        JMP WSM2_SG
WSM2_SGD
        LDA #$5D : JSR JOUT_EMIT
        LDA #$7D : JSR JOUT_EMIT
        JSR MSG_SEND_GATE
        RTS

; ================================================================
; SETUP_SIGN_ID256 - cache Ed25519-signing-identiteit (item 4)
;   Call ONCE after DERIVE_KEYPAIR (256-bit login):
;     SEED = HKDF_OKM[32:64] (signing-seed) ; SIGN_SETUP -> SK_A/PREFIX/PUB
;   Own encKey = HKDF_OKM[0:32] (used by WS_AUTH256/receive).
;   Kost 1 scalar-mult (~5,7 min @1MHz, <1 min op U64-turbo).
; ================================================================
SETUP_SIGN_ID256
        JSR COPY_SIGN_SEED
        JSR SIGN_SETUP
        RTS
; -- separate seed copy (quickly testable without scalar mult) --
COPY_SIGN_SEED
        LDX #31
CSS_L   LDA HKDF_OKM+32,X
        STA SEED,X
        DEX
        BPL CSS_L
        RTS

; ================================================================
; B64URL_DECODE43 - 43 base64url chars (INP_BUF) -> 32 bytes KEY_PEER256
;   10 groups of 4->3 bytes (30) + last 3 chars -> 2 bytes (30,31).
;   C=0 ok, C=1 error (length/invalid char). Reuses B64D_CHAR/_ERR.
; ================================================================
B64URL_DECODE43
        LDA INP_LEN
        CMP #43
        BEQ B43_GO
        JMP B64D_ERR
B43_GO  LDA #0
        STA B64D_GRP
B43_GLP
        LDA B64D_GRP
        CMP #10
        BNE B43_GC
        JMP B43_LAST        ; trampoline: afstand > 127
B43_GC
        ; input offset = GRP*4
        ASL
        ASL
        STA B64D_IIX
        TAX
        LDA INP_BUF,X
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V0
        LDX B64D_IIX
        LDA INP_BUF+1,X
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V1
        LDX B64D_IIX
        LDA INP_BUF+2,X
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V2
        LDX B64D_IIX
        LDA INP_BUF+3,X
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V3
        ; output offset = GRP*3
        LDA B64D_GRP
        ASL
        CLC
        ADC B64D_GRP
        TAX
        ; byte0 = V0<<2 | V1>>4
        LDA B64D_V0
        ASL
        ASL
        STA B64D_T
        LDA B64D_V1
        LSR
        LSR
        LSR
        LSR
        ORA B64D_T
        STA KEY_PEER256+0,X
        ; byte1 = V1<<4 | V2>>2
        LDA B64D_V1
        ASL
        ASL
        ASL
        ASL
        STA B64D_T
        LDA B64D_V2
        LSR
        LSR
        ORA B64D_T
        STA KEY_PEER256+1,X
        ; byte2 = (V2 and $03)<<6 | V3
        LDA B64D_V2
        ASL
        ASL
        ASL
        ASL
        ASL
        ASL
        STA B64D_T
        LDA B64D_V3
        ORA B64D_T
        STA KEY_PEER256+2,X
        INC B64D_GRP
        JMP B43_GLP
B43_LAST
        ; last 3 chars (index 40/41/42) -> bytes 30,31
        LDA INP_BUF+40
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V0
        LDA INP_BUF+41
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V1
        LDA INP_BUF+42
        JSR B64D_CHAR
        BCC *+5
        JMP B64D_ERR
        STA B64D_V2
        ; byte30 = V0<<2 | V1>>4
        LDA B64D_V0
        ASL
        ASL
        STA B64D_T
        LDA B64D_V1
        LSR
        LSR
        LSR
        LSR
        ORA B64D_T
        STA KEY_PEER256+30
        ; byte31 = V1<<4 | V2>>2
        LDA B64D_V1
        ASL
        ASL
        ASL
        ASL
        STA B64D_T
        LDA B64D_V2
        LSR
        LSR
        ORA B64D_T
        STA KEY_PEER256+31
        CLC
        RTS

; ================================================================
; Mode dispatch (item 2): choose 128- or 256-bit routine on USE_256.
;   Identical calling convention (no args; read global state),
;   so the tail-JMP preserves the RTS semantics to the original caller.
; ================================================================
WS_AUTH_DISPATCH
        LDA USE_256
        BEQ WAD_128
        JMP WS_AUTH256
WAD_128 JMP WS_AUTH
WS_SEND_DISPATCH
        LDA USE_256
        BEQ WSD_128
        JMP WS_SEND_MSG256
WSD_128 JMP WS_SEND_MSG

; ================================================================
; B64URL_ENCODE32 - 32 bytes (B64E_IN) -> 43 base64url chars (B64E_OUT)
;   10 groups of 3->4 chars (40) + last 2 bytes -> 3 chars (40,41,42).
;   6-bit value -> char via B64_TABLE (value = index). No padding.
; ================================================================
B64URL_ENCODE32
        LDA #0
        STA B64E_GRP
B64E_GLP
        LDA B64E_GRP
        CMP #10
        BNE B64E_GC
        JMP B64E_LAST
B64E_GC
        ; in-offset = GRP*3 -> load B0/B1/B2
        ASL
        CLC
        ADC B64E_GRP
        TAX
        LDA B64E_IN,X
        STA B64E_B0
        LDA B64E_IN+1,X
        STA B64E_B1
        LDA B64E_IN+2,X
        STA B64E_B2
        ; out-offset = GRP*4
        LDA B64E_GRP
        ASL
        ASL
        TAX
        ; c0 = B0>>2
        LDA B64E_B0
        LSR
        LSR
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT,X
        ; c1 = ((B0 and 3)<<4) | (B1>>4)
        LDA B64E_B0
        AND #$03
        ASL
        ASL
        ASL
        ASL
        STA B64E_T
        LDA B64E_B1
        LSR
        LSR
        LSR
        LSR
        ORA B64E_T
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT+1,X
        ; c2 = ((B1 and $0F)<<2) | (B2>>6)
        LDA B64E_B1
        AND #$0F
        ASL
        ASL
        STA B64E_T
        LDA B64E_B2
        LSR
        LSR
        LSR
        LSR
        LSR
        LSR
        ORA B64E_T
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT+2,X
        ; c3 = B2 and $3F
        LDA B64E_B2
        AND #$3F
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT+3,X
        INC B64E_GRP
        JMP B64E_GLP
B64E_LAST
        ; last 2 bytes (in 30,31) -> 3 chars (out 40,41,42)
        LDA B64E_IN+30
        STA B64E_B0
        LDA B64E_IN+31
        STA B64E_B1
        ; c0 = B0>>2
        LDA B64E_B0
        LSR
        LSR
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT+40
        ; c1 = ((B0 and 3)<<4) | (B1>>4)
        LDA B64E_B0
        AND #$03
        ASL
        ASL
        ASL
        ASL
        STA B64E_T
        LDA B64E_B1
        LSR
        LSR
        LSR
        LSR
        ORA B64E_T
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT+41
        ; c2 = (B1 and $0F)<<2
        LDA B64E_B1
        AND #$0F
        ASL
        ASL
        TAY
        LDA B64_TABLE,Y
        STA B64E_OUT+42
        RTS

; ================================================================
; COMPUTE_C64_ID256 - 256-bit publicId in C64_IDSTR (16 base64url chars)
;   = base64url( SHA-256(HKDF_OKM[0:32])[0:12] ).  One SHA-256 block
;   (32 data bytes + padding). Jumps to the shared digest/base64 tail.
; ================================================================
COMPUTE_C64_ID256
        ; encKey = HKDF_OKM[0:32] -> SHA_BLK[0:32]
        LDX #31
C256_CP LDA HKDF_OKM,X
        STA SHA_BLK,X
        DEX
        BPL C256_CP
        ; clear SHA_BLK[32:64]
        LDX #32
C256_CL LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE C256_CL
        ; SHA-256 padding: $80 op pos 32; bitlengte = 256 = $0100
        LDA #$80
        STA SHA_BLK+32
        LDA #$01            ; 256 bits high byte
        STA SHA_BLK+62
        LDA #$00            ; 256 bits low byte
        STA SHA_BLK+63
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS
        JMP CC4_DIGEST_TAIL   ; gedeelde digest-copy + B64URL_12BYTES + RTS

; ================================================================
; SHAREABLE_BUILD256 - eigen shareable in SHARE_STR (nul-beeindigd):
;   base64url(HKDF_OKM[0:32]) '.' base64url(SK_PUB)
;   43 + 1 + 43 + null = 88 bytes. Requires SIGN_SETUP run (SK_PUB).
; ================================================================
SHAREABLE_BUILD256
        ; --- segment 1: encKey = HKDF_OKM[0:32] ---
        LDX #31
SB_C1   LDA HKDF_OKM,X
        STA B64E_IN,X
        DEX
        BPL SB_C1
        JSR B64URL_ENCODE32
        LDX #42
SB_O1   LDA B64E_OUT,X
        STA SHARE_STR,X
        DEX
        BPL SB_O1
        ; scheider '.'
        LDA #$2E
        STA SHARE_STR+43
        ; --- segment 2: signPubkey = SK_PUB ---
        LDX #31
SB_C2   LDA SK_PUB,X
        STA B64E_IN,X
        DEX
        BPL SB_C2
        JSR B64URL_ENCODE32
        LDX #42
SB_O2   LDA B64E_OUT,X
        STA SHARE_STR+44,X
        DEX
        BPL SB_O2
        ; scheider '.' na segment 2
        LDA #$2E
        STA SHARE_STR+87
        ; --- segment 3: relayWss = btoa(wssUrl), precomputed base64 ---
        LDX #43
SB_O3   LDA STR_RELAY_B64,X
        STA SHARE_STR+88,X
        DEX
        BPL SB_O3
        ; null-terminator
        LDA #$00
        STA SHARE_STR+132
        RTS

; ================================================================
; SHOW_SHAREABLE - show own shareable (only in 256-bit mode).
;   Builds SHARE_STR fresh (SHAREABLE_BUILD256) and prints label + string.
;   Requires HKDF_OKM[0:32] + SK_PUB filled (DERIVE_KEYPAIR + SIGN_SETUP).
; ================================================================
SHOW_SHAREABLE
        LDA USE_256
        BNE SS_GO
        RTS                 ; 128-bit: show nothing
SS_GO   JSR SHAREABLE_BUILD256
        LDA #$9E            ; yellow
        JSR PRINT_CHR
        LDA #<STR_SHARE_LBL
        STA $FB
        LDA #>STR_SHARE_LBL
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        LDA #$05            ; wit
        JSR PRINT_CHR
        LDA #<SHARE_STR
        STA $FB
        LDA #>SHARE_STR
        STA $FC
        JSR PRINT_STR_FB
        LDA #$0D
        JSR PRINT_CHR
        RTS

; ================================================================
; MC_BOOT_MENU - choose identity path at boot.
;   '1' -> MC_SETUP (128-bit, paste)   '2' -> MC_LOGIN (256-bit, passphrase)
;   Tail-JMP to the chosen routine (which RTSes to the init).
; ================================================================
; ================================================================
; MC_BOOT_MENU REMOVED (AES128 cleanup) - never called,
; ACME itself flagged this as 'unused'. Stub + pin keeps RCV_DECRYPT_
; DISPATCH after this byte-identical.
; ================================================================
MC_BOOT_MENU
        RTS
* = $A4B4                       ; pin: RCV_DECRYPT_DISPATCH at original address

; ================================================================
; RCV_DECRYPT_DISPATCH - decrypt received message per USE_256.
;   Call AFTER loading AES_NONCE (common). Input:
;     RCV_CT (ct||tag), RCV_PT_LEN (= CT_LEN-16, 16-bit), AES_NONCE.
;   Out: GCM_CTBUF = plaintext ; carry=1 on tag error (both paths).
; ================================================================
RCV_DECRYPT_DISPATCH
        LDA USE_256
        BNE RDD_256
        ; --- 128-bit: AES-128-GCM with KEY_SELF ---
        LDX #15
RDD_KL  LDA KEY_SELF,X
        STA GCM_IN_KEY,X
        DEX
        BPL RDD_KL
        LDA #<RCV_CT
        STA GCM_PT_PTR+0
        LDA #>RCV_CT
        STA GCM_PT_PTR+1
        LDA RCV_PT_LEN+0
        STA GCM_PT_LEN+0
        LDA RCV_PT_LEN+1
        STA GCM_PT_LEN+1
        LDA #1
        STA GCM_DO_VERIFY
        JMP AES_GCM_DECRYPT     ; tail: set carry + GCM_CTBUF, RTSes to caller
RDD_256
        ; --- 256-bit: AES-256-GCM with HKDF_OKM[0:32] ---
        LDX #31
RDD_KS  LDA HKDF_OKM,X
        STA AES_KEY,X
        DEX
        BPL RDD_KS
        ; CTBUF = RCV_CT[0:PT_LEN]
        LDA #<RCV_CT : STA MSG_PTR
        LDA #>RCV_CT : STA MSG_PTR+1
        LDA RCV_PT_LEN+0 : STA MSG_LEN
        LDA RCV_PT_LEN+1 : STA MSG_LEN+1
        LDA #<CTBUF : STA CDST
        LDA #>CTBUF : STA CDST+1
        JSR COPY_M
        ; GCM_RECV_TAG = RCV_CT[PT_LEN : PT_LEN+16]
        LDA #<RCV_CT : CLC : ADC RCV_PT_LEN+0 : STA MSG_PTR
        LDA #>RCV_CT : ADC RCV_PT_LEN+1 : STA MSG_PTR+1
        LDA #16 : STA MSG_LEN
        LDA #0  : STA MSG_LEN+1
        LDA #<GCM_RECV_TAG : STA CDST
        LDA #>GCM_RECV_TAG : STA CDST+1
        JSR COPY_M
        ; PTLEN = RCV_PT_LEN
        LDA RCV_PT_LEN+0 : STA PTLEN+0
        LDA RCV_PT_LEN+1 : STA PTLEN+1
        JSR AGD256              ; -> PTBUF ; VERIFY_FAIL
        ; PTBUF -> GCM_CTBUF (so the existing parser works unchanged)
        LDA #<PTBUF : STA MSG_PTR
        LDA #>PTBUF : STA MSG_PTR+1
        LDA RCV_PT_LEN+0 : STA MSG_LEN
        LDA RCV_PT_LEN+1 : STA MSG_LEN+1
        LDA #<GCM_CTBUF : STA CDST
        LDA #>GCM_CTBUF : STA CDST+1
        JSR COPY_M
        ; carry from VERIFY_FAIL (1=error -> C=1)
        LDA VERIFY_FAIL
        BEQ RDD_OK
        SEC
        RTS
RDD_OK  CLC
        RTS

; ================================================================
; COMPUTE_PEER_ID256 - PEER_IDSTR = base64url(SHA-256(KEY_PEER256)[0:12]).
;   Standalone (does not touch C64_IDSTR). Reuses B64E_* scratch.
; ================================================================
COMPUTE_PEER_ID256
        LDX #31
CP2_CP  LDA KEY_PEER256,X
        STA SHA_BLK,X
        DEX
        BPL CP2_CP
        LDX #32
CP2_CL  LDA #$00
        STA SHA_BLK,X
        INX
        CPX #64
        BNE CP2_CL
        LDA #$80
        STA SHA_BLK+32
        LDA #$01
        STA SHA_BLK+62
        LDA #$00
        STA SHA_BLK+63
        JSR SHA_INIT
        JSR SHA_EXPAND
        JSR SHA_COMPRESS
        ; digest 12 bytes (big-endian per word) -> PEER_IDBYTES
        LDA SHA_H0+3 : STA PEER_IDBYTES+0
        LDA SHA_H0+2 : STA PEER_IDBYTES+1
        LDA SHA_H0+1 : STA PEER_IDBYTES+2
        LDA SHA_H0+0 : STA PEER_IDBYTES+3
        LDA SHA_H1+3 : STA PEER_IDBYTES+4
        LDA SHA_H1+2 : STA PEER_IDBYTES+5
        LDA SHA_H1+1 : STA PEER_IDBYTES+6
        LDA SHA_H1+0 : STA PEER_IDBYTES+7
        LDA SHA_H2+3 : STA PEER_IDBYTES+8
        LDA SHA_H2+2 : STA PEER_IDBYTES+9
        LDA SHA_H2+1 : STA PEER_IDBYTES+10
        LDA SHA_H2+0 : STA PEER_IDBYTES+11
        ; base64url 12 bytes -> PEER_IDSTR[16] (4 groepen 3->4)
        LDA #0
        STA B64E_GRP
CP2_GLP LDA B64E_GRP
        CMP #4
        BNE CP2_GC
        JMP CP2_DONE
CP2_GC  ASL
        CLC
        ADC B64E_GRP
        TAX
        LDA PEER_IDBYTES,X
        STA B64E_B0
        LDA PEER_IDBYTES+1,X
        STA B64E_B1
        LDA PEER_IDBYTES+2,X
        STA B64E_B2
        LDA B64E_GRP
        ASL
        ASL
        TAX
        LDA B64E_B0
        LSR
        LSR
        TAY
        LDA B64_TABLE,Y
        STA PEER_IDSTR,X
        LDA B64E_B0
        AND #$03
        ASL
        ASL
        ASL
        ASL
        STA B64E_T
        LDA B64E_B1
        LSR
        LSR
        LSR
        LSR
        ORA B64E_T
        TAY
        LDA B64_TABLE,Y
        STA PEER_IDSTR+1,X
        LDA B64E_B1
        AND #$0F
        ASL
        ASL
        STA B64E_T
        LDA B64E_B2
        LSR
        LSR
        LSR
        LSR
        LSR
        LSR
        ORA B64E_T
        TAY
        LDA B64_TABLE,Y
        STA PEER_IDSTR+2,X
        LDA B64E_B2
        AND #$3F
        TAY
        LDA B64_TABLE,Y
        STA PEER_IDSTR+3,X
        INC B64E_GRP
        JMP CP2_GLP
CP2_DONE
        LDA #0
        STA PEER_IDSTR+16
        RTS

; ================================================================
; MC_PEER_SETUP256 - ask for contact shareable; empty = to yourself.
;   Fills KEY_PEER256 (encrypt outgoing) + PEER_IDSTR ('to' field).
; ================================================================
MC_PEER_SETUP256
        LDA #$0D
        JSR PRINT_CHR
        LDA #$9E            ; yellow
        JSR PRINT_CHR
        LDA #<STR_PEER_P
        STA $FB
        LDA #>STR_PEER_P
        STA $FC
        JSR PRINT_STR_FB
        LDA #$05            ; wit
        JSR PRINT_CHR
        JSR INPUT_LINE      ; -> INP_BUF, INP_LEN
        LDA INP_LEN
        BNE MPS_PEER
        ; --- empty: self ---
        LDX #31
MPS_SK  LDA HKDF_OKM,X
        STA KEY_PEER256,X
        DEX
        BPL MPS_SK
        LDX #16
MPS_SI  LDA C64_IDSTR,X
        STA PEER_IDSTR,X
        DEX
        BPL MPS_SI
        RTS
MPS_PEER
        ; isolate 1st segment (up to '.') -> INP_LEN
        LDX #0
MPS_DOT LDA INP_BUF,X
        CMP #$2E            ; '.'
        BEQ MPS_CUT
        INX
        CPX INP_LEN
        BNE MPS_DOT
        JMP MPS_DEC
MPS_CUT STX INP_LEN
MPS_DEC JSR B64URL_DECODE43 ; INP_BUF[0:43] -> KEY_PEER256 ; C=1 error
        BCC MPS_OK
        LDA #<STR_PEER_ERR
        STA $FB
        LDA #>STR_PEER_ERR
        STA $FC
        JSR PRINT_STR_FB
        JMP MC_PEER_SETUP256
MPS_OK  JSR COMPUTE_PEER_ID256
        RTS

!source "comb_keepalive.inc"

!source "qsq_tables.inc"

; ================================================================
; WATCHDOG - connection self-heal (free RAM @ $B500)
; NET-ZERO: low segment byte-identical to A3BM1 (only JSR target
; changed at line 613). MRP_WD wraps MC_RECV_POLL.
; WD_ON only becomes 1 at the FIRST received frame (after connect);
; during login no frames arrive -> watchdog sleeps.
; Relay pings every ~20s; >~43s silence = dead -> MC_RECONNECT.
; ================================================================
* = $B500
LAST_RX  !byte $00,$00
WD_ON    !byte $00            ; 0 = sleeps until first frame after connect
MRP_WD
        LDA RING_TAIL
        CMP RING_HEAD
        BEQ MRPW_EMPTY          ; ring empty -> watchdog check
        JSR WD_RESET            ; data in -> arm + counter reset
        JMP MC_RECV_POLL        ; process frame (tail-call, X stays)
MRPW_EMPTY
        JSR WD_CHECK
        RTS
WD_RESET
        LDA #1
        STA WD_ON               ; arm bij eerste frame na connect
        LDA $A2
        STA LAST_RX+0
        LDA $A1
        STA LAST_RX+1
        RTS
WD_CHECK
        LDA WD_ON
        BEQ WDC_OFF             ; no frame yet -> sleeps
        SEC
        LDA $A2
        SBC LAST_RX+0
        LDA $A1
        SBC LAST_RX+1
        CMP #$0A                ; delta-high >= 10 -> ~43s
        BCS WDC_RECON
WDC_OFF RTS
WDC_RECON
        ; FIX (reconnect loop): re-arm the watchdog and take a FRESH
        ; LAST_RX snapshot BEFORE redialing. Without this, WD_ON=1 stayed
        ; with a stale LAST_RX, so WD_CHECK fired again right
        ; after every successful reconnect -> endless
        ; CONNECTING/CONNECTED loop (red border). WD_RESET sets WD_ON=1 and
        ; LAST_RX=$A2/$A1 (now) -> fresh ~43s window after the (re)connect.
        JSR WD_RESET
        JMP MC_RECONNECT

; ================================================================
; PD_WRAP - keepalive-pong ingeweven in COMB_SCALAR_MUL (vrije RAM @ $B540)
; The comb loop (CB_LOOP) calls this 64x instead of POINT_DBL. On each
; iteration (~1-3s on a 1MHz C64) we send an UNSOLICITED empty
; masked WebSocket pong (8A 80 + key) so the relay keepalive does not
; expire during the long Ed25519 signing. RFC6455 explicitly allows
; unsolicited pongs as a heartbeat.
; Gated on WD_ON: only send when connected (at SIGN_SETUP during
; login WD_ON=0 -> no modem bytes before connect).
; ACIA_SEND preserves A/X/Y and touches NO signing zeropage; PD_WRAP does a
; tail-call (JMP) to POINT_DBL -> stack balanced and the scalar mult
; (and thus the signature) stays byte-identical.
; ================================================================
* = $B540
PD_WRAP
        LDA WD_ON
        BEQ PDW_GO              ; not connected -> skip pong
        LDA #$8A : JSR ACIA_SEND   ; FIN + pong-opcode (0x0A)
        LDA #$80 : JSR ACIA_SEND   ; mask bit on, payload length 0
        LDA #$37 : JSR ACIA_SEND   ; masking key (same 4 bytes as WS_SEND)
        LDA #$FA : JSR ACIA_SEND
        LDA #$21 : JSR ACIA_SEND
        LDA #$3D : JSR ACIA_SEND
PDW_GO
        JMP POINT_DBL           ; original comb step (tail-call)

!source "meshchat64_sendfix.inc"
!source "meshchat64_fastsq.inc"

!source "meshchat64_combsigned.inc"
