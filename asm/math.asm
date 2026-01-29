; math.asm - C64 Math Library for Rasterizer
; 64tass syntax
;
; Operations needed for C rasterizer port:
;   1. 8-bit unsigned a*b → 16-bit result (for area calculations)
;   2. signed 8-bit / unsigned 8-bit → 8.8 fixed point (for slopes: dx/dy)
;
; All routines use quarter-square multiplication:
;   a*b = ((a+b)²/4) - ((a-b)²/4)

; ============================================================================
; Zero page allocations (adjust as needed)
; ============================================================================
zp_mul_ptr0     = $fb   ; 2 bytes - pointer for multiplication tables
zp_mul_ptr1     = $fd   ; 2 bytes - pointer for multiplication tables

; ============================================================================
; Working memory
; ============================================================================
prod_low        = $02   ; multiplication result low byte
prod_high       = $03   ; multiplication result high byte

; For division: a / b → 8.8 fixed point
div_result_lo   = $04   ; 8.8 result low byte (fractional part)
div_result_hi   = $05   ; 8.8 result high byte (integer part)

; ============================================================================
; ROUTINE: mul8x8_init
; ============================================================================
; Must be called once before using mul8x8_unsigned
; Sets up zero page pointers to multiplication tables
;
; Cycle count: 16 cycles (one-time init)
; ============================================================================

mul8x8_init
        lda #<sqr_lo            ; 2
        sta zp_mul_ptr0         ; 3
        lda #>sqr_lo            ; 2
        sta zp_mul_ptr0+1       ; 3
        lda #<sqr_hi            ; 2
        sta zp_mul_ptr1         ; 3
        lda #>sqr_hi            ; 2
        sta zp_mul_ptr1+1       ; 3
        rts                     ; 6 - Total: 26 cycles

; ============================================================================
; ROUTINE: div8s_8u_v2
; ============================================================================
; Signed 8-bit / unsigned 8-bit division with 8.8 fixed-point result.
;
; Method: a/b = a × (65536/b) >> 8, using precomputed reciprocal table.
; This is a standard reciprocal multiplication technique, not based on
; a specific Toby Lobster algorithm. Uses mul8x8_unsigned (mult66.a style)
; as a building block for the 8×16 multiplication.
;
; Input:  A = dividend (signed, range -80 to +80)
;         X = divisor  (unsigned, range 1-50)
; Output: Y:A = 8.8 fixed point result (Y=integer, A=fraction)
;         Also stored in div_result_hi:div_result_lo
;
; Cycle count: ~21 cycles for divisor=1
;              ~115 cycles for positive dividend (divisor>1)
;              ~135 cycles for negative dividend (divisor>1)
; ============================================================================

div8s_8u_v2
        ; Special case: divisor=1 (recip[1] overflows 16 bits)
        cpx #1                  ; 2
        bne _div2_normal        ; 2/3
        ; b=1: a/1 = a, in 8.8 format = a<<8
        tay                     ; 2 - Y = integer part (the dividend)
        sta div_result_hi       ; 3
        lda #0                  ; 2 - A = fraction part (zero)
        sta div_result_lo       ; 3
        rts                     ; 6
        ; Total for b=1 case: 2+3+2+3+2+3+6 = 21 cycles

_div2_normal
        stx div_divisor         ; 3 - preserve divisor

        ; Check sign
        cmp #$80                ; 2
        bcc _div2_pos           ; 2/3

        ; Negative: negate dividend
        eor #$ff                ; 2
        clc                     ; 2
        adc #1                  ; 2
        jsr _div2_core          ; 6 + core

        ; Negate result (in Y:A)
        eor #$ff                ; 2
        clc                     ; 2
        adc #1                  ; 2
        sta div_result_lo       ; 3
        tya                     ; 2
        eor #$ff                ; 2
        adc #0                  ; 2
        sta div_result_hi       ; 3
        tay                     ; 2
        lda div_result_lo       ; 3
        rts                     ; 6

_div2_pos
        jsr _div2_core          ; 6 + core
        sta div_result_lo       ; 3
        sty div_result_hi       ; 3
        rts                     ; 6

; Core unsigned multiply: A × recip[div_divisor]
; Returns 8.8 result in Y:A (Y=high, A=low which is bits 8-15 of 24-bit product)
;
; Product breakdown:
;   A × recip_lo = P0 (16 bits: contributes to bits 0-15)
;   A × recip_hi = P1 (16 bits: contributes to bits 8-23)
;   Total = P0 + P1<<8
;   We want bits 8-23 of this sum
;
; Cycles: ~83 cycles (uses inlined multiplication macros)
_div2_core
        sta div_dividend        ; 3

        ; First: A × recip_lo
        ldx div_divisor         ; 3
        tay                     ; 2 - Y = dividend
        lda recip_lo,x          ; 4 - A = recip_lo[divisor]
        tax                     ; 2 - X = recip_lo
        #mul8x8_unsigned_m      ; ~39 - result in A:prod_low
        ; A = bits 8-15, prod_low = bits 0-7
        sta div_p0_hi           ; 3 - save P0 high byte

        ; Second: A × recip_hi
        ldx div_divisor         ; 3
        ldy div_dividend        ; 3 - Y = dividend
        lda recip_hi,x          ; 4 - A = recip_hi[divisor]
        tax                     ; 2 - X = recip_hi
        #mul8x8_unsigned_m      ; ~39 - result in A:prod_low
        ; A = bits 8-15 (our bits 16-23), prod_low = bits 0-7 (our bits 8-15)

        ; Combine: result = P0_hi + P1_lo (with carry into P1_hi)
        ; bits 8-15 of final = P0_hi + P1_lo (= prod_low)
        ; bits 16-23 of final = A + carry
        tay                     ; 2 - Y = P1 high (bits 16-23)
        lda div_p0_hi           ; 3
        clc                     ; 2
        adc prod_low            ; 3 - A = bits 8-15 of result
        bcc +                   ; 2/3
        iny                     ; 2 - carry into high byte
+       ; Y:A = 8.8 result
        rts                     ; 6
        ; Total: ~83 cycles (was ~97 with subroutine calls)

div_divisor     .byte 0
div_dividend    .byte 0
div_p0_hi       .byte 0

; ============================================================================
; LOOKUP TABLES
; ============================================================================
; Quarter-square tables for multiplication
; sqr[n] = floor(n²/4), for n = 0..511
; We need 512 entries to handle a+b where a,b are 0..255
; Each table is 512 bytes
;
; Table generation (done at assembly time):

        .align 256              ; Page-align for faster indexed access

sqr_lo  ; Low bytes of n²/4 for n = 0..511
        .for n = 0, n < 512, n += 1
            .byte <((n*n)/4)
        .endfor

sqr_hi  ; High bytes of n²/4 for n = 0..511
        .for n = 0, n < 512, n += 1
            .byte >((n*n)/4)
        .endfor

; Negative index tables for Y<X case, following mult66.a's approach:
; negsqr[n] = sqr[256-n] - 1
; The -1 offset compensates for the extra -1 from SBC with carry clear,
; eliminating the need for an explicit SEC before the subtraction.
; (SBC with C=0 computes A - M - 1, so we use M = sqr - 1 to get A - sqr)
negsqr_lo
        .for n = 0, n < 256, n += 1
            .byte <(((256-n)*(256-n))/4 - 1)
        .endfor

negsqr_hi
        .for n = 0, n < 256, n += 1
            .byte >(((256-n)*(256-n))/4 - 1)
        .endfor

; ============================================================================
; RECIPROCAL TABLE for division
; ============================================================================
; recip[n] = floor(65536/n) for n = 1..63 (we only need 1-50)
; Stored as 16-bit values (recip_lo, recip_hi)
;
; When we compute A × recip[n], we get A×65536/n
; The upper 16 bits of this 24-bit product give us A/n in 8.8 format
;
; LIMITATIONS:
;   recip[0] = 0 (division by zero, should never happen)
;   recip[1] = 0 (65536/1 overflows 16 bits; handled as special case in div8s_8u_v2)

recip_lo        ; Low byte of 65536/n
        .byte 0                 ; [0] undefined
        .for n = 1, n < 64, n += 1
            .byte <(65536/n)
        .endfor

recip_hi        ; High byte of 65536/n
        .byte 0                 ; [0] undefined
        .for n = 1, n < 64, n += 1
            .byte >(65536/n)
        .endfor

; ============================================================================
; SIGNED MULTIPLICATION TABLES (for mul8x8_signed_m macro)
; ============================================================================
; Tables for quarter-square signed multiplication.
; square1: (i²)/4 for i = -256..254 (511 entries)
; square2: (i²)/4 for i = -255..255 (511 entries)
; eorx: i XOR 128 for i = 0..255

        .align 256

smult_sq1_lo    ; Low bytes of (i²)/4 for i = -256..254
        .for i = -256, i <= 254, i += 1
            .byte <((i*i)/4)
        .endfor
        .byte 0                 ; Padding for alignment

smult_sq1_hi    ; High bytes of (i²)/4 for i = -256..254
        .for i = -256, i <= 254, i += 1
            .byte >((i*i)/4)
        .endfor
        .byte 0                 ; Padding for alignment

smult_sq2_lo    ; Low bytes of (i²)/4 for i = -255..255
        .for i = -255, i <= 255, i += 1
            .byte <((i*i)/4)
        .endfor
        .byte 0                 ; Padding for alignment

smult_sq2_hi    ; High bytes of (i²)/4 for i = -255..255
        .for i = -255, i <= 255, i += 1
            .byte >((i*i)/4)
        .endfor
        .byte 0                 ; Padding for alignment

smult_eorx      ; i XOR 128 for i = 0..255
        .for i = 0, i < 256, i += 1
            .byte i ^ 128
        .endfor

; ============================================================================
; TABLE SIZES
; ============================================================================
; sqr_lo:       512 bytes (unsigned mul)
; sqr_hi:       512 bytes (unsigned mul)
; negsqr_lo:    256 bytes (unsigned mul)
; negsqr_hi:    256 bytes (unsigned mul)
; recip_lo:      64 bytes (division)
; recip_hi:      64 bytes (division)
; smult_sq1_lo: 512 bytes (signed mul)
; smult_sq1_hi: 512 bytes (signed mul)
; smult_sq2_lo: 512 bytes (signed mul)
; smult_sq2_hi: 512 bytes (signed mul)
; smult_eorx:   256 bytes (signed mul)
; Total:       3968 bytes for lookup tables
;
; ============================================================================
; CYCLE COUNT SUMMARY
; ============================================================================
; Multiplication macros (in macros.asm, inlined for performance):
;   mul8x8_unsigned_m: ~39 cycles (based on mult66.a, no JSR/RTS overhead)
;   mul8x8_signed_m:   ~46 cycles (based on smult11.a, no JSR/RTS overhead)
;
; Division subroutine:
;   div8s_8u_v2:       ~103 cycles (positive dividend, uses inlined muls)
;                      ~123 cycles (negative dividend)
;
; Reference (TobyLobster/multiply_test):
;   mult66.a (8×8=16 unsigned): 45.49 cycles average (as subroutine)
;   smult11.a (8×8=16 signed): 51.99 cycles average (as subroutine)
;
; Division uses reciprocal multiplication (custom implementation):
;   a/b = a × recip[b] >> 8, where recip[b] = 65536/b
;   Implemented as two inlined 8×8 multiplies plus combine step.
; ============================================================================
