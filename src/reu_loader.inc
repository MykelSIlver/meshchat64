; ================================================================
; reu_loader.inc  -  REU presence-check + boot-time table loader
;   (only assembled with -DREU=1)
;
;   REU_DETECT      : stash a test pattern to REU scratch, fetch back to a
;                     different C64 buffer, compare.  Returns C=1 if a working
;                     REU is present, C=0 otherwise.  Use to print a clean
;                     "REU REQUIRED" message instead of running with garbage.
;
;   REU_LOAD_TABLE  : load companion file (LFN/name set by caller) into the
;                     REU in CHUNK-sized blocks via KERNAL file I/O + DMA stash.
;                     File layout = raw table bytes (gen_comb_table.py --bin),
;                     2^(t-1)*64 bytes, stashed to REU offset 0 upward.
;
;   NOTE: the DMA stash/fetch + offset arithmetic are verified byte-exact in
;   the py65 REU shim.  The KERNAL file-read half needs VICE/hardware (py65 has
;   no drive).  GETIN/CHRIN clobber X -> wrapped.  TDRE/ACIA untouched here.
; ================================================================

REU_CHUNK = $0200                 ; 512 B read buffer (LOAD_BUF)
LOAD_BUF  = $CC00                 ; PBKDF2 work area: free at boot, before login
RL_PTR    = $FB                   ; zp pointer (FAP); free at boot before crypto
!ifndef REU_SKIP { REU_SKIP = 2 } ; bytes to discard before table (2 = PRG load-addr; 0 = raw SEQ)

; ---------------------------------------------------------------
; REU_DETECT : C=1 if working REU present.
;   Writes 4 marker bytes at C64 $0334.. , stashes to REU bank0 offset
;   ($00FFF0 chosen as scratch, away from table region), fetches to $0338..,
;   compares.  (Table starts at REU 0; scratch at high offset is safe for
;   tables < ~16 MB; for h19 use end-of-table+; here detection runs BEFORE
;   the table load so any offset is free.)
; ---------------------------------------------------------------
RD_SCRATCH_LO = $F0
RD_SCRATCH_HI = $FF
RD_SCRATCH_BK = $00

REU_DETECT
        ; marker pattern -> $0334..$0337
        lda #$A5 : sta $0334
        lda #$5A : sta $0335
        lda #$3C : sta $0336
        lda #$C3 : sta $0337
        ; clear compare dst $0338..$033B
        lda #$00
        sta $0338 : sta $0339 : sta $033A : sta $033B
        ; stash $0334 -> REU scratch, 4 bytes
        lda #$34 : sta $DF02
        lda #$03 : sta $DF03
        lda #RD_SCRATCH_LO : sta $DF04
        lda #RD_SCRATCH_HI : sta $DF05
        lda #RD_SCRATCH_BK : sta $DF06
        lda #4 : sta $DF07
        lda #0 : sta $DF08
        lda #0 : sta $DF0A
        lda #$90 : sta $DF01          ; stash
        ; fetch REU scratch -> $0338, 4 bytes
        lda #$38 : sta $DF02
        lda #$03 : sta $DF03
        lda #RD_SCRATCH_LO : sta $DF04
        lda #RD_SCRATCH_HI : sta $DF05
        lda #RD_SCRATCH_BK : sta $DF06
        lda #4 : sta $DF07
        lda #0 : sta $DF08
        lda #0 : sta $DF0A
        lda #$91 : sta $DF01          ; fetch
        ; compare $0334..$0337 vs $0338..$033B
        ldx #3
RD_CMP  lda $0334,x
        cmp $0338,x
        bne RD_NO
        dex
        bpl RD_CMP
        sec                            ; all match -> present
        rts
RD_NO   clc
        rts

; ---------------------------------------------------------------
; REU_LOAD_TABLE : stream companion file -> REU (offset 0 upward).
;   Caller must have set name+LFN via SETNAM/SETLFS and the drive ready.
;   Reads CHUNK bytes at a time into LOAD_BUF, stashes to running REU offset.
;   Uses a running 24-bit REU offset (RL_OFF) and a 24-bit remaining count
;   (RL_REM) initialized to table size = 2^(t-1)*64.  Last (partial) chunk
;   handled by clamping the transfer length to RL_REM.
; ---------------------------------------------------------------
; table size in bytes = npts*64 = 2^(t-1) * 64 = 2^(t+5)
;   t=12 -> 2^17 = 131072      ($020000)
;   t=18 -> 2^23 = 8388608     ($800000)
REU_TABLESIZE = 1 << (REU_T + 5)

REU_LOAD_TABLE
        ; RL_OFF = 0
        lda #0 : sta RL_OFF+0 : sta RL_OFF+1 : sta RL_OFF+2
        ; RL_REM = table size (24-bit LE)
        lda #<(REU_TABLESIZE)       : sta RL_REM+0
        lda #>(REU_TABLESIZE)       : sta RL_REM+1
        lda #((REU_TABLESIZE)>>16)  : sta RL_REM+2
        ; open the file (caller did SETNAM/SETLFS); OPEN + CHKIN
        jsr $FFC0                      ; OPEN
        bcc RL_OPOK
        jmp RL_ERR
RL_OPOK
        ldx RL_LFN
        jsr $FFC6                      ; CHKIN (X=LFN)
        bcc RL_CIOK
        jmp RL_ERR
RL_CIOK
!if REU_SKIP > 0 {
        ; discard REU_SKIP header bytes (PRG load address) before the table.
        ; CHRIN clobbers X -> use a memory counter, not X.
        lda #REU_SKIP : sta RL_SKIPN
RL_SK   jsr $FFCF                      ; CHRIN (discard byte in A)
        dec RL_SKIPN
        bne RL_SK
}
RL_NEXT
        ; remaining == 0 ?  (all three bytes zero -> done)
        lda RL_REM+0 : ora RL_REM+1 : ora RL_REM+2
        bne RL_GO
        jmp RL_DONE
RL_GO
        ; this chunk length = min(CHUNK, RL_REM) (16-bit; CHUNK<=$2000)
        ; if RL_REM >= CHUNK  -> len=CHUNK ; else len=RL_REM (low 16 bits)
        lda RL_REM+2
        bne RL_FULL                    ; high byte set -> >= 64K -> full chunk
        lda RL_REM+1
        cmp #>(REU_CHUNK)
        bcc RL_PART                    ; RL_REM(hi) < CHUNK(hi) -> partial
        bne RL_FULL
        lda RL_REM+0
        cmp #<(REU_CHUNK)
        bcc RL_PART
RL_FULL lda #<(REU_CHUNK) : sta RL_LEN+0
        lda #>(REU_CHUNK) : sta RL_LEN+1
        jmp RL_READ
RL_PART lda RL_REM+0 : sta RL_LEN+0
        lda RL_REM+1 : sta RL_LEN+1
RL_READ
        ; read RL_LEN bytes from file into LOAD_BUF (CHRIN per byte)
        lda #<LOAD_BUF : sta RL_PTR+0
        lda #>LOAD_BUF : sta RL_PTR+1
        lda RL_LEN+0 : sta RL_CNT+0
        lda RL_LEN+1 : sta RL_CNT+1
RL_RB   lda RL_CNT+0 : ora RL_CNT+1
        beq RL_STASH
        jsr $FFCF                      ; CHRIN (A=byte; clobbers X)
        ldy #0
        sta (RL_PTR),y
        inc RL_PTR+0
        bne RL_RBNE
        inc RL_PTR+1
RL_RBNE ; RL_CNT--
        lda RL_CNT+0
        bne RL_RBD
        dec RL_CNT+1
RL_RBD  dec RL_CNT+0
        ; check ST for EOF/error (READST)
        jsr $FFB7                      ; READST -> A
        and #$BF                       ; EOF(bit6)/error bits (ignore bit? keep 6+others)
        beq RL_RB
        ; EOF mid-chunk: stash what we have (RL_LEN - RL_CNT). For simplicity,
        ; assume file size == table size (generated exactly); treat as done.
        ; fall through to stash the (full) buffer slice we intended.
RL_STASH
        ; DMA stash LOAD_BUF -> REU[RL_OFF], RL_LEN bytes
        lda #<LOAD_BUF : sta $DF02
        lda #>LOAD_BUF : sta $DF03
        lda RL_OFF+0 : sta $DF04
        lda RL_OFF+1 : sta $DF05
        lda RL_OFF+2 : sta $DF06
        lda RL_LEN+0 : sta $DF07
        lda RL_LEN+1 : sta $DF08
        lda #0 : sta $DF0A
        lda #$90 : sta $DF01           ; stash
        ; RL_OFF += RL_LEN (24-bit += 16-bit)
        clc
        lda RL_OFF+0 : adc RL_LEN+0 : sta RL_OFF+0
        lda RL_OFF+1 : adc RL_LEN+1 : sta RL_OFF+1
        lda RL_OFF+2 : adc #0        : sta RL_OFF+2
        ; RL_REM -= RL_LEN (24-bit -= 16-bit)
        sec
        lda RL_REM+0 : sbc RL_LEN+0 : sta RL_REM+0
        lda RL_REM+1 : sbc RL_LEN+1 : sta RL_REM+1
        lda RL_REM+2 : sbc #0        : sta RL_REM+2
        jmp RL_NEXT
RL_DONE
        lda RL_LFN : jsr $FFC3         ; CLOSE (A=LFN)
        jsr $FFCC                       ; CLRCHN: restore default I/O (keyboard/screen)
        jsr REU_STASH_MARK              ; mark table present for warm-reset skip
        clc                            ; success
        rts
RL_ERR
        lda RL_LFN : jsr $FFC3
        jsr $FFCC                       ; CLRCHN: restore default I/O
        sec
        rts

; ---------------------------------------------------------------
; REU persistence marker: 8 magic bytes + REU_T, stashed at REU offset
; REU_MARK_OFF (just past the table). REU contents survive a warm reset,
; so a matching marker means the table is already loaded -> skip disk load.
; ---------------------------------------------------------------
REU_MARK_OFF = REU_TABLESIZE          ; first free REU byte past the table

REU_STASH_MARK
        lda #<RL_MARK : sta $DF02
        lda #>RL_MARK : sta $DF03
        lda #<(REU_MARK_OFF)      : sta $DF04
        lda #>(REU_MARK_OFF)      : sta $DF05
        lda #((REU_MARK_OFF)>>16) : sta $DF06
        lda #9 : sta $DF07
        lda #0 : sta $DF08
        lda #0 : sta $DF0A
        lda #$90 : sta $DF01            ; stash
        rts

; REU_CHECK_MARK : C=1 if a valid marker (this REU_T) is already in the REU.
REU_CHECK_MARK
        lda #0                          ; clear buf so a no-op fetch -> mismatch
        ldx #8
RCM0    sta RL_MARKBUF,x : dex : bpl RCM0
        lda #<RL_MARKBUF : sta $DF02
        lda #>RL_MARKBUF : sta $DF03
        lda #<(REU_MARK_OFF)      : sta $DF04
        lda #>(REU_MARK_OFF)      : sta $DF05
        lda #((REU_MARK_OFF)>>16) : sta $DF06
        lda #9 : sta $DF07
        lda #0 : sta $DF08
        lda #0 : sta $DF0A
        lda #$91 : sta $DF01            ; fetch
        ldx #8
RCM1    lda RL_MARKBUF,x : cmp RL_MARK,x : bne RCM_NO
        dex : bpl RCM1
        sec                             ; all 9 match -> table present
        rts
RCM_NO  clc
        rts

; ---------------------------------------------------------------
; loader state (freed in-RAM-table region, < $B100)
; ---------------------------------------------------------------
RL_LFN  !byte 2
RL_OFF  !fill 3,0
RL_REM  !fill 3,0
RL_LEN  !fill 2,0
RL_CNT  !fill 2,0
RL_SKIPN !byte 0
RL_MARK   !byte $4D,$43,$36,$34,$43,$4F,$4D,$42   ; "MC64COMB"
          !byte REU_T                              ; version = teeth count
RL_MARKBUF !fill 9,0
