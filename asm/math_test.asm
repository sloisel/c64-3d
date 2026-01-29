; math_test.asm - Test harness for C64 math library
; Assembles to a runnable PRG file

        .include "macros.asm"

; ============================================================================
; C64 PRG header - starts at $0801 with BASIC stub
; ============================================================================
        * = $0801

        ; BASIC stub: SYS <main>
        .word (+), 2024
        .null $9e, format("%d", main)
+       .word 0

; ============================================================================
; Main program starts at 2062 ($080e)
; ============================================================================
main
        jsr mul8x8_init         ; Initialize multiplication tables

        ; Test 1: 8x8 unsigned multiplication
        ; 10 * 20 = 200 ($00C8)
        ldx #10
        ldy #20
        jsr mul8x8_unsigned
        ; Result: A = $00, prod_low = $C8

        ; Display result
        #printc 'M'
        #printc 'U'
        #printc 'L'
        #printc ':'
        #printc ' '
        #printhex               ; print high byte
        lda prod_low
        #printhex               ; print low byte
        #println

        ; Test 2: 50 * 80 = 4000 ($0FA0)
        ldx #50
        ldy #80
        jsr mul8x8_unsigned
        ; Result: A = $0F, prod_low = $A0

        #printc '5'
        #printc '0'
        #printc '*'
        #printc '8'
        #printc '0'
        #printc '='
        #printhex
        lda prod_low
        #printhex
        #println

        ; Test 3: Division 40/10 = 4.0 (should be $0400 in 8.8)
        lda #40
        ldx #10
        jsr div8s_8u_v2
        ; Result: Y = $04, A = $00

        #printc 'D'
        #printc 'I'
        #printc 'V'
        #printc ':'
        #printc ' '
        tya
        #printhex
        #printc '.'
        lda div_result_lo
        #printhex
        #println

        ; Test 4: Division -40/10 = -4.0 (should be $FC00 in 8.8 signed)
        lda #-40                ; $D8
        ldx #10
        jsr div8s_8u_v2

        #printc '-'
        #printc '4'
        #printc '0'
        #printc '/'
        #printc '1'
        #printc '0'
        #printc '='
        lda div_result_hi
        #printhex
        #printc '.'
        lda div_result_lo
        #printhex
        #println

        ; Test 5: Division 50/25 = 2.0 (should be $0200)
        lda #50
        ldx #25
        jsr div8s_8u_v2

        #printc '5'
        #printc '0'
        #printc '/'
        #printc '2'
        #printc '5'
        #printc '='
        lda div_result_hi
        #printhex
        #printc '.'
        lda div_result_lo
        #printhex
        #println

        ; Test 6: Division 1/2 = 0.5 (should be $0080 in 8.8)
        lda #1
        ldx #2
        jsr div8s_8u_v2

        #printc '1'
        #printc '/'
        #printc '2'
        #printc '='
        lda div_result_hi
        #printhex
        #printc '.'
        lda div_result_lo
        #printhex
        #println

        ; Test 7: Division 80/50 = 1.6 (should be ~$019A in 8.8)
        ; 1.6 * 256 = 409.6 ≈ 410 = $019A
        lda #80
        ldx #50
        jsr div8s_8u_v2

        #printc '8'
        #printc '0'
        #printc '/'
        #printc '5'
        #printc '0'
        #printc '='
        lda div_result_hi
        #printhex
        #printc '.'
        lda div_result_lo
        #printhex
        #println

        rts                     ; Return to BASIC

; ============================================================================
; Include math library
; ============================================================================
        .include "math.asm"
