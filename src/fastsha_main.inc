TBLINIT
  LDX #0
klb
  LDA SHA_K+3,X : STA $cc00,X
  LDA SHA_K+2,X : STA $cc01,X
  LDA SHA_K+1,X : STA $cc02,X
  LDA SHA_K+0,X : STA $cc03,X
  TXA : CLC : ADC #4 : TAX : CPX #0 : BNE klb
  LDX #0
ti_s1
  TXA
  LSR
  STA $c000,X
  INX : BNE ti_s1
  LDX #0
ti_s2
  TXA
  LSR
  LSR
  STA $c100,X
  INX : BNE ti_s2
  LDX #0
ti_s3
  TXA
  LSR
  LSR
  LSR
  STA $c200,X
  INX : BNE ti_s3
  LDX #0
ti_s5
  TXA
  LSR
  LSR
  LSR
  LSR
  LSR
  STA $c300,X
  INX : BNE ti_s5
  LDX #0
ti_s6
  TXA
  LSR
  LSR
  LSR
  LSR
  LSR
  LSR
  STA $c400,X
  INX : BNE ti_s6
  LDX #0
ti_s7
  TXA
  LSR
  LSR
  LSR
  LSR
  LSR
  LSR
  LSR
  STA $c500,X
  INX : BNE ti_s7
  LDX #0
ti_t1
  TXA
  ASL
  STA $c600,X
  INX : BNE ti_t1
  LDX #0
ti_t2
  TXA
  ASL
  ASL
  STA $c700,X
  INX : BNE ti_t2
  LDX #0
ti_t3
  TXA
  ASL
  ASL
  ASL
  STA $c800,X
  INX : BNE ti_t3
  LDX #0
ti_t5
  TXA
  ASL
  ASL
  ASL
  ASL
  ASL
  STA $c900,X
  INX : BNE ti_t5
  LDX #0
ti_t6
  TXA
  ASL
  ASL
  ASL
  ASL
  ASL
  ASL
  STA $ca00,X
  INX : BNE ti_t6
  LDX #0
ti_t7
  TXA
  ASL
  ASL
  ASL
  ASL
  ASL
  ASL
  ASL
  STA $cb00,X
  INX : BNE ti_t7
  RTS
FSHA_IV
  LDA #$67 : STA $ce00
  LDA #$e6 : STA $ce01
  LDA #$09 : STA $ce02
  LDA #$6a : STA $ce03
  LDA #$85 : STA $ce04
  LDA #$ae : STA $ce05
  LDA #$67 : STA $ce06
  LDA #$bb : STA $ce07
  LDA #$72 : STA $ce08
  LDA #$f3 : STA $ce09
  LDA #$6e : STA $ce0a
  LDA #$3c : STA $ce0b
  LDA #$3a : STA $ce0c
  LDA #$f5 : STA $ce0d
  LDA #$4f : STA $ce0e
  LDA #$a5 : STA $ce0f
  LDA #$7f : STA $ce10
  LDA #$52 : STA $ce11
  LDA #$0e : STA $ce12
  LDA #$51 : STA $ce13
  LDA #$8c : STA $ce14
  LDA #$68 : STA $ce15
  LDA #$05 : STA $ce16
  LDA #$9b : STA $ce17
  LDA #$ab : STA $ce18
  LDA #$d9 : STA $ce19
  LDA #$83 : STA $ce1a
  LDA #$1f : STA $ce1b
  LDA #$19 : STA $ce1c
  LDA #$cd : STA $ce1d
  LDA #$e0 : STA $ce1e
  LDA #$5b : STA $ce1f
  RTS
FSHA_BLOCK
  LDX #0
fld16
  LDA $ce20,X : STA $cd03,X
  LDA $ce21,X : STA $cd02,X
  LDA $ce22,X : STA $cd01,X
  LDA $ce23,X : STA $cd00,X
  TXA : CLC : ADC #4 : TAX : CPX #64 : BNE fld16
  LDY #64
fext
  ; sigma0(W[t-15])->T2
  LDA $ccc4,Y : STA $3c
  LDA $ccc5,Y : STA $3d
  LDA $ccc6,Y : STA $3e
  LDA $ccc7,Y : STA $3f
  LDX $3c : LDA $c500,X
  LDX $3d : ORA $c600,X
  STA $34
  LDX $3d : LDA $c500,X
  LDX $3e : ORA $c600,X
  STA $35
  LDX $3e : LDA $c500,X
  LDX $3f : ORA $c600,X
  STA $36
  LDX $3f : LDA $c500,X
  LDX $3c : ORA $c600,X
  STA $37
  LDX $3e : LDA $c100,X
  LDX $3f : ORA $ca00,X
  STA $38
  LDX $3f : LDA $c100,X
  LDX $3c : ORA $ca00,X
  STA $39
  LDX $3c : LDA $c100,X
  LDX $3d : ORA $ca00,X
  STA $3a
  LDX $3d : LDA $c100,X
  LDX $3e : ORA $ca00,X
  STA $3b
  LDA $34 : EOR $38 : STA $34
  LDA $35 : EOR $39 : STA $35
  LDA $36 : EOR $3a : STA $36
  LDA $37 : EOR $3b : STA $37
  LDX $3c : LDA $c200,X
  LDX $3d : ORA $c900,X
  STA $38
  LDX $3d : LDA $c200,X
  LDX $3e : ORA $c900,X
  STA $39
  LDX $3e : LDA $c200,X
  LDX $3f : ORA $c900,X
  STA $3a
  LDX $3f : LDA $c200,X
  STA $3b
  LDA $34 : EOR $38 : STA $34
  LDA $35 : EOR $39 : STA $35
  LDA $36 : EOR $3a : STA $36
  LDA $37 : EOR $3b : STA $37
  ; sigma1(W[t-2])->T1
  LDA $ccf8,Y : STA $3c
  LDA $ccf9,Y : STA $3d
  LDA $ccfa,Y : STA $3e
  LDA $ccfb,Y : STA $3f
  LDX $3e : LDA $c000,X
  LDX $3f : ORA $cb00,X
  STA $30
  LDX $3f : LDA $c000,X
  LDX $3c : ORA $cb00,X
  STA $31
  LDX $3c : LDA $c000,X
  LDX $3d : ORA $cb00,X
  STA $32
  LDX $3d : LDA $c000,X
  LDX $3e : ORA $cb00,X
  STA $33
  LDX $3e : LDA $c200,X
  LDX $3f : ORA $c900,X
  STA $38
  LDX $3f : LDA $c200,X
  LDX $3c : ORA $c900,X
  STA $39
  LDX $3c : LDA $c200,X
  LDX $3d : ORA $c900,X
  STA $3a
  LDX $3d : LDA $c200,X
  LDX $3e : ORA $c900,X
  STA $3b
  LDA $30 : EOR $38 : STA $30
  LDA $31 : EOR $39 : STA $31
  LDA $32 : EOR $3a : STA $32
  LDA $33 : EOR $3b : STA $33
  LDX $3d : LDA $c100,X
  LDX $3e : ORA $ca00,X
  STA $38
  LDX $3e : LDA $c100,X
  LDX $3f : ORA $ca00,X
  STA $39
  LDX $3f : LDA $c100,X
  STA $3a
  LDA #0
  STA $3b
  LDA $30 : EOR $38 : STA $30
  LDA $31 : EOR $39 : STA $31
  LDA $32 : EOR $3a : STA $32
  LDA $33 : EOR $3b : STA $33
  CLC
  LDA $30 : ADC $34 : STA $30
  LDA $31 : ADC $35 : STA $31
  LDA $32 : ADC $36 : STA $32
  LDA $33 : ADC $37 : STA $33
  CLC
  LDA $30 : ADC $cce4,Y : STA $30
  LDA $31 : ADC $cce5,Y : STA $31
  LDA $32 : ADC $cce6,Y : STA $32
  LDA $33 : ADC $cce7,Y : STA $33
  CLC
  LDA $30 : ADC $ccc0,Y : STA $30
  LDA $31 : ADC $ccc1,Y : STA $31
  LDA $32 : ADC $ccc2,Y : STA $32
  LDA $33 : ADC $ccc3,Y : STA $33
  LDA $30 : STA $cd00,Y
  LDA $31 : STA $cd01,Y
  LDA $32 : STA $cd02,Y
  LDA $33 : STA $cd03,Y
  INY : INY : INY : INY : CPY #0 : BEQ fextd : JMP fext
fextd
  LDA $ce00 : STA $10
  LDA $ce01 : STA $11
  LDA $ce02 : STA $12
  LDA $ce03 : STA $13
  LDA $ce04 : STA $14
  LDA $ce05 : STA $15
  LDA $ce06 : STA $16
  LDA $ce07 : STA $17
  LDA $ce08 : STA $18
  LDA $ce09 : STA $19
  LDA $ce0a : STA $1a
  LDA $ce0b : STA $1b
  LDA $ce0c : STA $1c
  LDA $ce0d : STA $1d
  LDA $ce0e : STA $1e
  LDA $ce0f : STA $1f
  LDA $ce10 : STA $20
  LDA $ce11 : STA $21
  LDA $ce12 : STA $22
  LDA $ce13 : STA $23
  LDA $ce14 : STA $24
  LDA $ce15 : STA $25
  LDA $ce16 : STA $26
  LDA $ce17 : STA $27
  LDA $ce18 : STA $28
  LDA $ce19 : STA $29
  LDA $ce1a : STA $2a
  LDA $ce1b : STA $2b
  LDA $ce1c : STA $2c
  LDA $ce1d : STA $2d
  LDA $ce1e : STA $2e
  LDA $ce1f : STA $2f
  LDY #0
fround
  LDX $20 : LDA $c400,X
  LDX $21 : ORA $c700,X
  STA $30
  LDX $21 : LDA $c400,X
  LDX $22 : ORA $c700,X
  STA $31
  LDX $22 : LDA $c400,X
  LDX $23 : ORA $c700,X
  STA $32
  LDX $23 : LDA $c400,X
  LDX $20 : ORA $c700,X
  STA $33
  LDX $21 : LDA $c200,X
  LDX $22 : ORA $c900,X
  STA $38
  LDX $22 : LDA $c200,X
  LDX $23 : ORA $c900,X
  STA $39
  LDX $23 : LDA $c200,X
  LDX $20 : ORA $c900,X
  STA $3a
  LDX $20 : LDA $c200,X
  LDX $21 : ORA $c900,X
  STA $3b
  LDA $30 : EOR $38 : STA $30
  LDA $31 : EOR $39 : STA $31
  LDA $32 : EOR $3a : STA $32
  LDA $33 : EOR $3b : STA $33
  LDX $23 : LDA $c000,X
  LDX $20 : ORA $cb00,X
  STA $38
  LDX $20 : LDA $c000,X
  LDX $21 : ORA $cb00,X
  STA $39
  LDX $21 : LDA $c000,X
  LDX $22 : ORA $cb00,X
  STA $3a
  LDX $22 : LDA $c000,X
  LDX $23 : ORA $cb00,X
  STA $3b
  LDA $30 : EOR $38 : STA $30
  LDA $31 : EOR $39 : STA $31
  LDA $32 : EOR $3a : STA $32
  LDA $33 : EOR $3b : STA $33
  LDA $20 : AND $24 : STA $3c
  LDA $21 : AND $25 : STA $3d
  LDA $22 : AND $26 : STA $3e
  LDA $23 : AND $27 : STA $3f
  LDA $20 : EOR #$ff : AND $28 : STA $38
  LDA $21 : EOR #$ff : AND $29 : STA $39
  LDA $22 : EOR #$ff : AND $2a : STA $3a
  LDA $23 : EOR #$ff : AND $2b : STA $3b
  LDA $3c : EOR $38 : STA $3c
  LDA $3d : EOR $39 : STA $3d
  LDA $3e : EOR $3a : STA $3e
  LDA $3f : EOR $3b : STA $3f
  CLC
  LDA $30 : ADC $3c : STA $30
  LDA $31 : ADC $3d : STA $31
  LDA $32 : ADC $3e : STA $32
  LDA $33 : ADC $3f : STA $33
  CLC
  LDA $30 : ADC $2c : STA $30
  LDA $31 : ADC $2d : STA $31
  LDA $32 : ADC $2e : STA $32
  LDA $33 : ADC $2f : STA $33
  CLC
  LDA $30 : ADC $cc00,Y : STA $30
  LDA $31 : ADC $cc01,Y : STA $31
  LDA $32 : ADC $cc02,Y : STA $32
  LDA $33 : ADC $cc03,Y : STA $33
  CLC
  LDA $30 : ADC $cd00,Y : STA $30
  LDA $31 : ADC $cd01,Y : STA $31
  LDA $32 : ADC $cd02,Y : STA $32
  LDA $33 : ADC $cd03,Y : STA $33
  LDX $10 : LDA $c100,X
  LDX $11 : ORA $ca00,X
  STA $34
  LDX $11 : LDA $c100,X
  LDX $12 : ORA $ca00,X
  STA $35
  LDX $12 : LDA $c100,X
  LDX $13 : ORA $ca00,X
  STA $36
  LDX $13 : LDA $c100,X
  LDX $10 : ORA $ca00,X
  STA $37
  LDX $11 : LDA $c300,X
  LDX $12 : ORA $c800,X
  STA $38
  LDX $12 : LDA $c300,X
  LDX $13 : ORA $c800,X
  STA $39
  LDX $13 : LDA $c300,X
  LDX $10 : ORA $c800,X
  STA $3a
  LDX $10 : LDA $c300,X
  LDX $11 : ORA $c800,X
  STA $3b
  LDA $34 : EOR $38 : STA $34
  LDA $35 : EOR $39 : STA $35
  LDA $36 : EOR $3a : STA $36
  LDA $37 : EOR $3b : STA $37
  LDX $12 : LDA $c400,X
  LDX $13 : ORA $c700,X
  STA $38
  LDX $13 : LDA $c400,X
  LDX $10 : ORA $c700,X
  STA $39
  LDX $10 : LDA $c400,X
  LDX $11 : ORA $c700,X
  STA $3a
  LDX $11 : LDA $c400,X
  LDX $12 : ORA $c700,X
  STA $3b
  LDA $34 : EOR $38 : STA $34
  LDA $35 : EOR $39 : STA $35
  LDA $36 : EOR $3a : STA $36
  LDA $37 : EOR $3b : STA $37
  LDA $10 : AND $14 : STA $3c
  LDA $11 : AND $15 : STA $3d
  LDA $12 : AND $16 : STA $3e
  LDA $13 : AND $17 : STA $3f
  LDA $10 : AND $18 : STA $38
  LDA $11 : AND $19 : STA $39
  LDA $12 : AND $1a : STA $3a
  LDA $13 : AND $1b : STA $3b
  LDA $3c : EOR $38 : STA $3c
  LDA $3d : EOR $39 : STA $3d
  LDA $3e : EOR $3a : STA $3e
  LDA $3f : EOR $3b : STA $3f
  LDA $14 : AND $18 : STA $38
  LDA $15 : AND $19 : STA $39
  LDA $16 : AND $1a : STA $3a
  LDA $17 : AND $1b : STA $3b
  LDA $3c : EOR $38 : STA $3c
  LDA $3d : EOR $39 : STA $3d
  LDA $3e : EOR $3a : STA $3e
  LDA $3f : EOR $3b : STA $3f
  CLC
  LDA $34 : ADC $3c : STA $34
  LDA $35 : ADC $3d : STA $35
  LDA $36 : ADC $3e : STA $36
  LDA $37 : ADC $3f : STA $37
  LDA $28 : STA $2c
  LDA $29 : STA $2d
  LDA $2a : STA $2e
  LDA $2b : STA $2f
  LDA $24 : STA $28
  LDA $25 : STA $29
  LDA $26 : STA $2a
  LDA $27 : STA $2b
  LDA $20 : STA $24
  LDA $21 : STA $25
  LDA $22 : STA $26
  LDA $23 : STA $27
  LDA $1c : STA $20
  LDA $1d : STA $21
  LDA $1e : STA $22
  LDA $1f : STA $23
  LDA $18 : STA $1c
  LDA $19 : STA $1d
  LDA $1a : STA $1e
  LDA $1b : STA $1f
  LDA $14 : STA $18
  LDA $15 : STA $19
  LDA $16 : STA $1a
  LDA $17 : STA $1b
  LDA $10 : STA $14
  LDA $11 : STA $15
  LDA $12 : STA $16
  LDA $13 : STA $17
  CLC
  LDA $20 : ADC $30 : STA $20
  LDA $21 : ADC $31 : STA $21
  LDA $22 : ADC $32 : STA $22
  LDA $23 : ADC $33 : STA $23
  LDA $30 : STA $10
  LDA $31 : STA $11
  LDA $32 : STA $12
  LDA $33 : STA $13
  CLC
  LDA $10 : ADC $34 : STA $10
  LDA $11 : ADC $35 : STA $11
  LDA $12 : ADC $36 : STA $12
  LDA $13 : ADC $37 : STA $13
  INY : INY : INY : INY : CPY #0 : BEQ froundd : JMP fround
froundd
  CLC
  LDA $ce00 : ADC $10 : STA $ce00
  LDA $ce01 : ADC $11 : STA $ce01
  LDA $ce02 : ADC $12 : STA $ce02
  LDA $ce03 : ADC $13 : STA $ce03
  CLC
  LDA $ce04 : ADC $14 : STA $ce04
  LDA $ce05 : ADC $15 : STA $ce05
  LDA $ce06 : ADC $16 : STA $ce06
  LDA $ce07 : ADC $17 : STA $ce07
  CLC
  LDA $ce08 : ADC $18 : STA $ce08
  LDA $ce09 : ADC $19 : STA $ce09
  LDA $ce0a : ADC $1a : STA $ce0a
  LDA $ce0b : ADC $1b : STA $ce0b
  CLC
  LDA $ce0c : ADC $1c : STA $ce0c
  LDA $ce0d : ADC $1d : STA $ce0d
  LDA $ce0e : ADC $1e : STA $ce0e
  LDA $ce0f : ADC $1f : STA $ce0f
  CLC
  LDA $ce10 : ADC $20 : STA $ce10
  LDA $ce11 : ADC $21 : STA $ce11
  LDA $ce12 : ADC $22 : STA $ce12
  LDA $ce13 : ADC $23 : STA $ce13
  CLC
  LDA $ce14 : ADC $24 : STA $ce14
  LDA $ce15 : ADC $25 : STA $ce15
  LDA $ce16 : ADC $26 : STA $ce16
  LDA $ce17 : ADC $27 : STA $ce17
  CLC
  LDA $ce18 : ADC $28 : STA $ce18
  LDA $ce19 : ADC $29 : STA $ce19
  LDA $ce1a : ADC $2a : STA $ce1a
  LDA $ce1b : ADC $2b : STA $ce1b
  CLC
  LDA $ce1c : ADC $2c : STA $ce1c
  LDA $ce1d : ADC $2d : STA $ce1d
  LDA $ce1e : ADC $2e : STA $ce1e
  LDA $ce1f : ADC $2f : STA $ce1f
  RTS
FHH2BE
  RTS
FHMAC_INIT
  LDX #0
fhi_ip
  LDA $ce60,X : EOR #$36 : STA $ce20,X
  INX : CPX #64 : BNE fhi_ip
  JSR FSHA_IV
  JSR FSHA_BLOCK
  LDA $ce00 : STA $cf20
  LDA $ce01 : STA $cf21
  LDA $ce02 : STA $cf22
  LDA $ce03 : STA $cf23
  LDA $ce04 : STA $cf24
  LDA $ce05 : STA $cf25
  LDA $ce06 : STA $cf26
  LDA $ce07 : STA $cf27
  LDA $ce08 : STA $cf28
  LDA $ce09 : STA $cf29
  LDA $ce0a : STA $cf2a
  LDA $ce0b : STA $cf2b
  LDA $ce0c : STA $cf2c
  LDA $ce0d : STA $cf2d
  LDA $ce0e : STA $cf2e
  LDA $ce0f : STA $cf2f
  LDA $ce10 : STA $cf30
  LDA $ce11 : STA $cf31
  LDA $ce12 : STA $cf32
  LDA $ce13 : STA $cf33
  LDA $ce14 : STA $cf34
  LDA $ce15 : STA $cf35
  LDA $ce16 : STA $cf36
  LDA $ce17 : STA $cf37
  LDA $ce18 : STA $cf38
  LDA $ce19 : STA $cf39
  LDA $ce1a : STA $cf3a
  LDA $ce1b : STA $cf3b
  LDA $ce1c : STA $cf3c
  LDA $ce1d : STA $cf3d
  LDA $ce1e : STA $cf3e
  LDA $ce1f : STA $cf3f
  LDX #0
fhi_op
  LDA $ce60,X : EOR #$5c : STA $ce20,X
  INX : CPX #64 : BNE fhi_op
  JSR FSHA_IV
  JSR FSHA_BLOCK
  LDA $ce00 : STA $cf40
  LDA $ce01 : STA $cf41
  LDA $ce02 : STA $cf42
  LDA $ce03 : STA $cf43
  LDA $ce04 : STA $cf44
  LDA $ce05 : STA $cf45
  LDA $ce06 : STA $cf46
  LDA $ce07 : STA $cf47
  LDA $ce08 : STA $cf48
  LDA $ce09 : STA $cf49
  LDA $ce0a : STA $cf4a
  LDA $ce0b : STA $cf4b
  LDA $ce0c : STA $cf4c
  LDA $ce0d : STA $cf4d
  LDA $ce0e : STA $cf4e
  LDA $ce0f : STA $cf4f
  LDA $ce10 : STA $cf50
  LDA $ce11 : STA $cf51
  LDA $ce12 : STA $cf52
  LDA $ce13 : STA $cf53
  LDA $ce14 : STA $cf54
  LDA $ce15 : STA $cf55
  LDA $ce16 : STA $cf56
  LDA $ce17 : STA $cf57
  LDA $ce18 : STA $cf58
  LDA $ce19 : STA $cf59
  LDA $ce1a : STA $cf5a
  LDA $ce1b : STA $cf5b
  LDA $ce1c : STA $cf5c
  LDA $ce1d : STA $cf5d
  LDA $ce1e : STA $cf5e
  LDA $ce1f : STA $cf5f
  RTS
FHMAC_ITER
  LDA $cf20 : STA $ce00
  LDA $cf21 : STA $ce01
  LDA $cf22 : STA $ce02
  LDA $cf23 : STA $ce03
  LDA $cf24 : STA $ce04
  LDA $cf25 : STA $ce05
  LDA $cf26 : STA $ce06
  LDA $cf27 : STA $ce07
  LDA $cf28 : STA $ce08
  LDA $cf29 : STA $ce09
  LDA $cf2a : STA $ce0a
  LDA $cf2b : STA $ce0b
  LDA $cf2c : STA $ce0c
  LDA $cf2d : STA $ce0d
  LDA $cf2e : STA $ce0e
  LDA $cf2f : STA $ce0f
  LDA $cf30 : STA $ce10
  LDA $cf31 : STA $ce11
  LDA $cf32 : STA $ce12
  LDA $cf33 : STA $ce13
  LDA $cf34 : STA $ce14
  LDA $cf35 : STA $ce15
  LDA $cf36 : STA $ce16
  LDA $cf37 : STA $ce17
  LDA $cf38 : STA $ce18
  LDA $cf39 : STA $ce19
  LDA $cf3a : STA $ce1a
  LDA $cf3b : STA $ce1b
  LDA $cf3c : STA $ce1c
  LDA $cf3d : STA $ce1d
  LDA $cf3e : STA $ce1e
  LDA $cf3f : STA $ce1f
  LDX #0
fhit_cp
  LDA $cea0,X : STA $ce20,X
  INX : CPX $cf60 : BNE fhit_cp
  LDX $cf60 : LDA #$80 : STA $ce20,X : INX
fhit_z
  LDA #0 : STA $ce20,X : INX : CPX #62 : BNE fhit_z
  LDA $cf60 : CLC : ADC #64 : STA $3c
  LDA #0 : STA $3d
  ASL $3c : ROL $3d
  ASL $3c : ROL $3d
  ASL $3c : ROL $3d
  LDA $3d : STA $ce5e
  LDA $3c : STA $ce5f
  JSR FSHA_BLOCK
  LDA $ce03 : STA $cf00
  LDA $ce02 : STA $cf01
  LDA $ce01 : STA $cf02
  LDA $ce00 : STA $cf03
  LDA $ce07 : STA $cf04
  LDA $ce06 : STA $cf05
  LDA $ce05 : STA $cf06
  LDA $ce04 : STA $cf07
  LDA $ce0b : STA $cf08
  LDA $ce0a : STA $cf09
  LDA $ce09 : STA $cf0a
  LDA $ce08 : STA $cf0b
  LDA $ce0f : STA $cf0c
  LDA $ce0e : STA $cf0d
  LDA $ce0d : STA $cf0e
  LDA $ce0c : STA $cf0f
  LDA $ce13 : STA $cf10
  LDA $ce12 : STA $cf11
  LDA $ce11 : STA $cf12
  LDA $ce10 : STA $cf13
  LDA $ce17 : STA $cf14
  LDA $ce16 : STA $cf15
  LDA $ce15 : STA $cf16
  LDA $ce14 : STA $cf17
  LDA $ce1b : STA $cf18
  LDA $ce1a : STA $cf19
  LDA $ce19 : STA $cf1a
  LDA $ce18 : STA $cf1b
  LDA $ce1f : STA $cf1c
  LDA $ce1e : STA $cf1d
  LDA $ce1d : STA $cf1e
  LDA $ce1c : STA $cf1f
  LDA $cf40 : STA $ce00
  LDA $cf41 : STA $ce01
  LDA $cf42 : STA $ce02
  LDA $cf43 : STA $ce03
  LDA $cf44 : STA $ce04
  LDA $cf45 : STA $ce05
  LDA $cf46 : STA $ce06
  LDA $cf47 : STA $ce07
  LDA $cf48 : STA $ce08
  LDA $cf49 : STA $ce09
  LDA $cf4a : STA $ce0a
  LDA $cf4b : STA $ce0b
  LDA $cf4c : STA $ce0c
  LDA $cf4d : STA $ce0d
  LDA $cf4e : STA $ce0e
  LDA $cf4f : STA $ce0f
  LDA $cf50 : STA $ce10
  LDA $cf51 : STA $ce11
  LDA $cf52 : STA $ce12
  LDA $cf53 : STA $ce13
  LDA $cf54 : STA $ce14
  LDA $cf55 : STA $ce15
  LDA $cf56 : STA $ce16
  LDA $cf57 : STA $ce17
  LDA $cf58 : STA $ce18
  LDA $cf59 : STA $ce19
  LDA $cf5a : STA $ce1a
  LDA $cf5b : STA $ce1b
  LDA $cf5c : STA $ce1c
  LDA $cf5d : STA $ce1d
  LDA $cf5e : STA $ce1e
  LDA $cf5f : STA $ce1f
  LDX #0
fhit_co
  LDA $cf00,X : STA $ce20,X : INX : CPX #32 : BNE fhit_co
  LDA #$80 : STA $ce40
  LDX #33
fhit_zo
  LDA #0 : STA $ce20,X : INX : CPX #62 : BNE fhit_zo
  LDA #$03 : STA $ce5e
  LDA #$00 : STA $ce5f
  JSR FSHA_BLOCK
  LDA $ce03 : STA $cee0
  LDA $ce02 : STA $cee1
  LDA $ce01 : STA $cee2
  LDA $ce00 : STA $cee3
  LDA $ce07 : STA $cee4
  LDA $ce06 : STA $cee5
  LDA $ce05 : STA $cee6
  LDA $ce04 : STA $cee7
  LDA $ce0b : STA $cee8
  LDA $ce0a : STA $cee9
  LDA $ce09 : STA $ceea
  LDA $ce08 : STA $ceeb
  LDA $ce0f : STA $ceec
  LDA $ce0e : STA $ceed
  LDA $ce0d : STA $ceee
  LDA $ce0c : STA $ceef
  LDA $ce13 : STA $cef0
  LDA $ce12 : STA $cef1
  LDA $ce11 : STA $cef2
  LDA $ce10 : STA $cef3
  LDA $ce17 : STA $cef4
  LDA $ce16 : STA $cef5
  LDA $ce15 : STA $cef6
  LDA $ce14 : STA $cef7
  LDA $ce1b : STA $cef8
  LDA $ce1a : STA $cef9
  LDA $ce19 : STA $cefa
  LDA $ce18 : STA $cefb
  LDA $ce1f : STA $cefc
  LDA $ce1e : STA $cefd
  LDA $ce1d : STA $cefe
  LDA $ce1c : STA $ceff
  RTS
PBKDF2_FAST
  LDA #$31 : STA $0428   ; '1' PBKDF2_FAST gestart (geen banking)
  JSR TBLINIT
  LDX #0
pf_ck
  LDA #0 : STA $ce60,X : INX : CPX #64 : BNE pf_ck
  LDX #0
pf_cp
  LDA PBKDF2_PWD,X : STA $ce60,X : INX : CPX PBKDF2_PWDLEN : BNE pf_cp
  JSR FHMAC_INIT
  LDX #0
pf_cs
  LDA PBKDF2_SALT,X : STA $cea0,X : INX : CPX PBKDF2_SALTLEN : BNE pf_cs
  LDX PBKDF2_SALTLEN
  LDA #0 : STA $cea0,X : INX
  LDA #0 : STA $cea0,X : INX
  LDA #0 : STA $cea0,X : INX
  LDA #1 : STA $cea0,X : INX
  STX $cf60
  JSR FHMAC_ITER
  LDX #0
pf_dk
  LDA $cee0,X : STA PBKDF2_DK,X : STA $cea0,X : INX : CPX #32 : BNE pf_dk
  LDA #32 : STA $cf60
  LDA PBKDF2_ITRLO : STA PBKDF2_CTRLO
  LDA PBKDF2_ITRMID : STA PBKDF2_CTRMID
  LDA PBKDF2_ITRHI : STA PBKDF2_CTRHI
  SEC : LDA PBKDF2_CTRLO : SBC #1 : STA PBKDF2_CTRLO
  LDA PBKDF2_CTRMID : SBC #0 : STA PBKDF2_CTRMID
  LDA PBKDF2_CTRHI : SBC #0 : STA PBKDF2_CTRHI
pf_loop
  LDA PBKDF2_CTRLO : ORA PBKDF2_CTRMID : ORA PBKDF2_CTRHI : BEQ pf_done
  LDA PBKDF2_CTRLO : BNE pf_nop
  INC $D020
pf_nop
  JSR FHMAC_ITER
  LDX #0
pf_xor
  LDA PBKDF2_DK,X : EOR $cee0,X : STA PBKDF2_DK,X
  LDA $cee0,X : STA $cea0,X
  INX : CPX #32 : BNE pf_xor
  SEC : LDA PBKDF2_CTRLO : SBC #1 : STA PBKDF2_CTRLO
  LDA PBKDF2_CTRMID : SBC #0 : STA PBKDF2_CTRMID
  LDA PBKDF2_CTRHI : SBC #0 : STA PBKDF2_CTRHI
  JMP pf_loop
pf_done
  RTS
