; single_tri_test.asm - Test a single triangle
;
; Draw one triangle and compare with expected output

        .include "macros.asm"

        * = $0801

        ; BASIC stub: SYS <main>
        .word (+), 2024
        .null $9e, format("%d", main)
+       .word 0

main
        jsr vic2_init
        jsr mul8x8_init
        lda #0
        jsr clear_screen

        ; Draw one triangle: (40,25), (56,34), (40,43) color 1
        ; This is the first bottom face triangle from the cube
        lda #40
        sta zp_ax
        lda #25
        sta zp_ay
        lda #56
        sta zp_bx
        lda #34
        sta zp_by
        lda #40
        sta zp_cx
        lda #43
        sta zp_cy
        lda #1
        sta zp_color
        jsr draw_triangle

        ; Save debug info to $C000
        ; After sorting: ax,ay,bx,by,cx,cy at $C000-$C005
        lda zp_ax
        sta $c000
        lda zp_ay
        sta $c001
        lda zp_bx
        sta $c002
        lda zp_by
        sta $c003
        lda zp_cx
        sta $c004
        lda zp_cy
        sta $c005
        ; b_on_left at $C006
        lda zp_b_on_left
        sta $c006
        ; dx_ac (long edge slope) at $C007-$C008
        lda zp_dx_ac_lo
        sta $c007
        lda zp_dx_ac_hi
        sta $c008
        ; dx_short (last short edge slope) at $C009-$C00A
        lda zp_dx_short_lo
        sta $c009
        lda zp_dx_short_hi
        sta $c00a
        ; x_long current position at $C00B-$C00C
        lda zp_x_long_lo
        sta $c00b
        lda zp_x_long_hi
        sta $c00c

        ; Compare with expected
        jsr compare_screen

        ; Result in $02-$03
-       jmp -

; Compare screen RAM with expected
compare_screen
        lda #0
        sta $02
        sta $03

        ldx #0
_cmp0   lda $0400,x
        cmp single_tri_expected,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp0

        ldx #0
_cmp1   lda $0400+250,x
        cmp single_tri_expected+250,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp1

        ldx #0
_cmp2   lda $0400+500,x
        cmp single_tri_expected+500,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp2

        ldx #0
_cmp3   lda $0400+750,x
        cmp single_tri_expected+750,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp3

        rts

        .include "math.asm"
        .include "rasterizer.asm"

vic2_init
        lda $dd00
        ora #$03
        sta $dd00
        lda #$18
        sta $d018
        lda $d016
        ora #$10
        sta $d016
        lda #0
        sta $d020
        sta $d021
        lda #11
        sta $d022
        lda #12
        sta $d023
        lda #9
        ldx #0
-       sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $db00,x
        inx
        bne -
        jsr copy_charset
        rts

copy_charset
        ldx #0
-       lda chunky_charset,x
        sta $2000,x
        lda chunky_charset+$100,x
        sta $2100,x
        lda chunky_charset+$200,x
        sta $2200,x
        lda chunky_charset+$300,x
        sta $2300,x
        lda chunky_charset+$400,x
        sta $2400,x
        lda chunky_charset+$500,x
        sta $2500,x
        lda chunky_charset+$600,x
        sta $2600,x
        lda chunky_charset+$700,x
        sta $2700,x
        inx
        bne -
        rts

; Align BEFORE charset to avoid overlap with copy destination ($2000-$27FF)
        .align $2800

chunky_charset
        .for ch = 0, ch < 256, ch += 1
            .byte ((ch >> 6) & 3) * $50 + ((ch >> 4) & 3) * $05
            .byte ((ch >> 6) & 3) * $50 + ((ch >> 4) & 3) * $05
            .byte ((ch >> 6) & 3) * $50 + ((ch >> 4) & 3) * $05
            .byte ((ch >> 6) & 3) * $50 + ((ch >> 4) & 3) * $05
            .byte ((ch >> 2) & 3) * $50 + (ch & 3) * $05
            .byte ((ch >> 2) & 3) * $50 + (ch & 3) * $05
            .byte ((ch >> 2) & 3) * $50 + (ch & 3) * $05
            .byte ((ch >> 2) & 3) * $50 + (ch & 3) * $05
        .endfor

        .include "single_tri_expected.asm"
