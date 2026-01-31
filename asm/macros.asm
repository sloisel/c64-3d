; macros.asm - 64tass Macro Library for C64 Development
;
; 64tass macro syntax:
;   name .macro param1, param2=default
;       ... code using \param1, \param2 ...
;   .endm
;
;   Invoke with: #name arg1, arg2
;             or .name arg1, arg2
;
;   Parameter references:
;     \1 through \9 - positional parameters
;     \name         - named parameter
;     @1 through @9 - parameter as text (for labels, strings)

; ============================================================================
; MEMORY OPERATIONS
; ============================================================================

; Load 16-bit immediate value into zero page location
; Usage: #load16 $fb, $1234
load16 .macro addr, value
        lda #<(\value)
        sta \addr
        lda #>(\value)
        sta \addr+1
.endm

; Copy 16-bit value from one location to another
; Usage: #copy16 dest, src
copy16 .macro dest, src
        lda \src
        sta \dest
        lda \src+1
        sta \dest+1
.endm

; Add 16-bit immediate to memory location (in place)
; Usage: #add16i $fb, 40
add16i .macro addr, value
        clc
        lda \addr
        adc #<(\value)
        sta \addr
        lda \addr+1
        adc #>(\value)
        sta \addr+1
.endm

; Add two 16-bit memory values: dest = dest + src
; Usage: #add16 dest, src
add16 .macro dest, src
        clc
        lda \dest
        adc \src
        sta \dest
        lda \dest+1
        adc \src+1
        sta \dest+1
.endm

; Subtract 16-bit: dest = dest - src
; Usage: #sub16 dest, src
sub16 .macro dest, src
        sec
        lda \dest
        sbc \src
        sta \dest
        lda \dest+1
        sbc \src+1
        sta \dest+1
.endm

; Negate 8-bit signed value in A
; Usage: #neg8
neg8 .macro
        eor #$ff
        clc
        adc #1
.endm

; Negate 16-bit signed value at address
; Usage: #neg16 addr
neg16 .macro addr
        lda \addr
        eor #$ff
        clc
        adc #1
        sta \addr
        lda \addr+1
        eor #$ff
        adc #0
        sta \addr+1
.endm

; ============================================================================
; COMPARISON MACROS
; ============================================================================

; Compare 16-bit values: sets flags like 8-bit CMP
; After: BCC if addr < value, BEQ if equal, BCS if >=
; Usage: #cmp16i addr, $1234
cmp16i .macro addr, value
        lda \addr+1
        cmp #>(\value)
        bne +
        lda \addr
        cmp #<(\value)
+
.endm

; ============================================================================
; BRANCHING HELPERS
; ============================================================================

; Branch if A is negative (bit 7 set)
; Usage: #bmi_long target
bmi_long .macro target
        bpl +
        jmp \target
+
.endm

; Branch if A is positive or zero (bit 7 clear)
; Usage: #bpl_long target
bpl_long .macro target
        bmi +
        jmp \target
+
.endm

; ============================================================================
; SCREEN OUTPUT (for debugging)
; ============================================================================

SCREEN  = $0400
CHROUT  = $ffd2

; Print a character immediate
; Usage: #printc 'A'
printc .macro char
        lda #\char
        jsr CHROUT
.endm

; Print hex nibble (low 4 bits of A)
; Destroys A
print_nibble .macro
        and #$0f
        cmp #10
        bcc +
        adc #6          ; adjust for A-F
+       adc #'0'
        jsr CHROUT
.endm

; Print A as two hex digits
; Usage: #printhex
; Destroys A, preserves X, Y
printhex .macro
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        #print_nibble
        pla
        #print_nibble
.endm

; Print newline (carriage return)
; Usage: #println
println .macro
        lda #13
        jsr CHROUT
.endm

; ============================================================================
; LOOP HELPERS
; ============================================================================

; Decrement 16-bit counter, branch if not zero
; Usage:
;   #load16 counter, 1000
; loop:
;   ... do work ...
;   #dec16_bne counter, loop
dec16_bne .macro addr, target
        lda \addr
        bne +
        dec \addr+1
+       dec \addr
        lda \addr
        ora \addr+1
        bne \target
.endm

; ============================================================================
; VIC-II HELPERS
; ============================================================================

VIC_BORDER      = $d020
VIC_BACKGROUND  = $d021
VIC_CTRL1       = $d011
VIC_RASTER      = $d012

; Set border color
; Usage: #border 0  (black)
border .macro color
        lda #\color
        sta VIC_BORDER
.endm

; Set background color
; Usage: #background 6  (blue)
background .macro color
        lda #\color
        sta VIC_BACKGROUND
.endm

; Wait for specific raster line (busy wait)
; Usage: #waitraster 251
waitraster .macro line
-       lda VIC_RASTER
        cmp #\line
        bne -
.endm

; ============================================================================
; FIXED-POINT MACROS (8.8 format)
; ============================================================================

; Convert integer to 8.8 fixed point (compile-time)
; Usage: .word #fp88(3)  ; stores $0300
fp88 .function value
        .endf value * 256

; Extract integer part from 8.8 at runtime
; Usage: #fp88_int addr  ; A = integer part
fp88_int .macro addr
        lda \addr+1
.endm

; Add two 8.8 fixed-point values: dest = dest + src
; (Same as 16-bit add)
fp88_add .macro dest, src
        #add16 \dest, \src
.endm

; Subtract 8.8: dest = dest - src
fp88_sub .macro dest, src
        #sub16 \dest, \src
.endm

; ============================================================================
; DEBUG TIMING
; ============================================================================

; Flash border during code section (for cycle counting via visual)
; Usage:
;   #time_start
;   ... code to time ...
;   #time_end
time_start .macro
        inc VIC_BORDER
.endm

time_end .macro
        dec VIC_BORDER
.endm

; ============================================================================
; 8×8=16 MULTIPLICATION MACROS
; ============================================================================

; mul8x8_unsigned_m - Unsigned 8×8=16 multiplication (inline macro)
; Based on mult66.a from TobyLobster/multiply_test.
;
; Input:  X = multiplicand (0-255)
;         Y = multiplier   (0-255)
; Output: A = high byte of product
;         prod_low = low byte of product
;
; Requires: zp_mul_ptr0/ptr1 initialized via mul8x8_init
mul8x8_unsigned_m .macro
        stx zp_mul_ptr0         ; store X for table indexing
        stx zp_mul_ptr1
        tya                     ; A = Y
        sec
        sbc zp_mul_ptr0         ; A = Y - X
        tax                     ; X = Y - X (may be negative)
        lda (zp_mul_ptr0),y     ; sqr_lo[X+Y]
        bcc _mu_neg             ; branch if Y < X
        ; Y >= X case
        sbc sqr_lo,x
        sta prod_low
        lda (zp_mul_ptr1),y
        sbc sqr_hi,x
        jmp _mu_done            ; skip negative case
_mu_neg
        ; Y < X case: use negsqr tables (with -1 offset for carry compensation)
        sbc negsqr_lo,x
        sta prod_low
        lda (zp_mul_ptr1),y
        sbc negsqr_hi,x
_mu_done
.endm

; mul8x8_signed_m - Signed 8×8=16 multiplication (inline macro)
; Based on smult11.a from TobyLobster/multiply_test.
; Original by Piotr Fusik (Syzygy 6, 1999)
;
; Input:  A = first signed 8-bit value (-128 to 127)
;         Y = second signed 8-bit value (-128 to 127)
; Output: Y = low byte of product
;         A = high byte of product
;         (16-bit signed result in A:Y, high:low)
mul8x8_signed_m .macro
        eor #$80
        sta _ms_sm1+1
        sta _ms_sm3+1
        eor #$ff
        sta _ms_sm2+1
        sta _ms_sm4+1
        ldx smult_eorx,y
        sec
_ms_sm1 lda smult_sq1_lo,x
_ms_sm2 sbc smult_sq2_lo,x
        tay
_ms_sm3 lda smult_sq1_hi,x
_ms_sm4 sbc smult_sq2_hi,x
.endm

; mul8s_8u_m - Signed × Unsigned 8×8=16 multiplication (inline macro)
; Uses quarter-square identity with dedicated tables for the asymmetric ranges.
;
; Input:  A = signed 8-bit value (-128 to 127)
;         Y = unsigned 8-bit value (0 to 255)
; Output: A = high byte of product
;         X = low byte of product
;         Y = preserved
;         (16-bit signed result in A:X, high:low)
;
; Cycle count: ~40 cycles (no table lookup for Y conversion)
mul8s_8u_m .macro
        eor #$80                ; 2 - convert signed to offset form
        sta _su_sm1+1           ; 4 - self-mod for sum table base
        sta _su_sm3+1           ; 4
        eor #$ff                ; 2 - complement for diff table
        sta _su_sm2+1           ; 4
        sta _su_sm4+1           ; 4
        sec                     ; 2
_su_sm1 lda su_sum_lo,y         ; 4 - (a+b)²/4 low byte
_su_sm2 sbc su_diff_lo,y        ; 4 - subtract (a-b)²/4 low
        tax                     ; 2 - save low byte in X
_su_sm3 lda su_sum_hi,y         ; 4 - (a+b)²/4 high byte
_su_sm4 sbc su_diff_hi,y        ; 4 - subtract (a-b)²/4 high
        ; Result: A = high byte, X = low byte
.endm

; mul16s_8u_hi_m - 16-bit Signed × 8-bit Unsigned, returns high byte (inline macro)
; Computes (signed_hi:signed_lo) × unsigned, returns bits 15-8 of 24-bit result.
;
; Input:  zp_mul16_lo = low byte of signed 16-bit value
;         zp_mul16_hi = high byte of signed 16-bit value (sign in bit 7)
;         Y = unsigned 8-bit value (0 to 255)
; Output: A = bits 15-8 of the 24-bit signed product
;         X, Y = clobbered
;
; Method: result = (hi × u) << 8 + (lo × u)
;         Bits 15-8 = high_byte(lo × u) + low_byte(hi × u)
;
; Requires: zp_m16m_u ($4f), zp_m16m_p1_hi ($50) defined in main.asm
;
; Cycle count: ~93 cycles (vs ~142-175 for subroutine version)
mul16s_8u_hi_m .macro
        ; First: lo × u (unsigned × unsigned)
        sty zp_m16m_u           ; 3 - save unsigned multiplier
        ldx zp_mul16_lo         ; 3
        #mul8x8_unsigned_m      ; ~41 - A = high byte, prod_low = low byte
        sta zp_m16m_p1_hi       ; 3 - save high byte of (lo × u)

        ; Second: hi × u (signed × unsigned)
        lda zp_mul16_hi         ; 3
        ldy zp_m16m_u           ; 3
        #mul8s_8u_m             ; ~40 - A = high, X = low

        ; Combine: result byte 1 = p1_hi + p2_lo
        clc                     ; 2
        txa                     ; 2 - get low byte of (hi × u)
        adc zp_m16m_p1_hi       ; 3 - add high byte of (lo × u)
        ; A = bits 15-8 of result
.endm

; ============================================================================
; ASSEMBLER HELPERS
; ============================================================================

; Align to page boundary
; Usage: #page_align
page_align .macro
        .align 256
.endm

; Assert at compile time
; Usage: #assert value < 256, "Value too large!"
assert .macro condition, message=""
        .if !(\condition)
            .error \message
        .endif
.endm

; ============================================================================
; USAGE NOTES
; ============================================================================
;
; To use this library:
;
;   .include "macros.asm"
;
;   * = $0801
;   ; BASIC stub to auto-run
;   .word (+), 2024
;   .null $9e, format("%d", main)
; + .word 0
;
;   main:
;       #border 0
;       #background 6
;       #load16 $fb, $0400
;       ...
;       rts
;
; ============================================================================
