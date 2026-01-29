; rasterizer_test.asm - Test harness for rasterizer
;
; Draws the same isometric cube as the C test program (--demo mode)
; so output can be compared byte-for-byte.
;
; Build: 64tass -o rasterizer_test.prg rasterizer_test.asm
; Run: x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502 rasterizer_test.prg

        .include "macros.asm"

; ============================================================================
; C64 PRG header
; ============================================================================
        * = $0801

        ; BASIC stub: SYS <main>
        .word (+), 2024
        .null $9e, format("%d", main)
+       .word 0

; ============================================================================
; Main program
; ============================================================================
main
        ; Initialize VIC-II for chunky pixel mode
        jsr vic2_init

        ; Initialize math library
        jsr mul8x8_init

        ; Clear screen to color 0
        lda #0
        jsr clear_screen

        ; Draw isometric cube (same as C --demo)
        jsr draw_demo_cube

        ; Compare screen RAM with expected data
        ; Store diff count at $02-$03 (16-bit)
        jsr compare_screen

        ; Infinite loop - result is in $02-$03 (0 = PASS)
-       jmp -

; ============================================================================
; draw_demo_cube - Draw the test cube
; ============================================================================
; Draws 6 triangles forming an isometric cube.
; Matches the C test program's run_demo() function.

draw_demo_cube
        ; Vertex coordinates (matching C code exactly):
        ; Center C (front corner): (40, 25)
        ; p100 (bottom-right): (56, 34)
        ; p010 (bottom-left): (24, 34)
        ; p001 (top): (40, 7)
        ; p110 (bottom): (40, 43)
        ; p101 (top-right): (56, 16)
        ; p011 (top-left): (24, 16)

        ; ----------------------------------------------------------------
        ; Bottom face (color 1) - 2 triangles
        ; ----------------------------------------------------------------

        ; Triangle 1: C, p100, p110 = (40,25), (56,34), (40,43)
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

        ; Triangle 2: C, p110, p010 = (40,25), (40,43), (24,34)
        lda #40
        sta zp_ax
        lda #25
        sta zp_ay
        lda #40
        sta zp_bx
        lda #43
        sta zp_by
        lda #24
        sta zp_cx
        lda #34
        sta zp_cy
        lda #1
        sta zp_color
        jsr draw_triangle

        ; ----------------------------------------------------------------
        ; Right face (color 2) - 2 triangles
        ; ----------------------------------------------------------------

        ; Triangle 3: C, p001, p101 = (40,25), (40,7), (56,16)
        lda #40
        sta zp_ax
        lda #25
        sta zp_ay
        lda #40
        sta zp_bx
        lda #7
        sta zp_by
        lda #56
        sta zp_cx
        lda #16
        sta zp_cy
        lda #2
        sta zp_color
        jsr draw_triangle

        ; Triangle 4: C, p101, p100 = (40,25), (56,16), (56,34)
        lda #40
        sta zp_ax
        lda #25
        sta zp_ay
        lda #56
        sta zp_bx
        lda #16
        sta zp_by
        lda #56
        sta zp_cx
        lda #34
        sta zp_cy
        lda #2
        sta zp_color
        jsr draw_triangle

        ; ----------------------------------------------------------------
        ; Left face (color 3) - 2 triangles
        ; ----------------------------------------------------------------

        ; Triangle 5: C, p010, p011 = (40,25), (24,34), (24,16)
        lda #40
        sta zp_ax
        lda #25
        sta zp_ay
        lda #24
        sta zp_bx
        lda #34
        sta zp_by
        lda #24
        sta zp_cx
        lda #16
        sta zp_cy
        lda #3
        sta zp_color
        jsr draw_triangle

        ; Triangle 6: C, p011, p001 = (40,25), (24,16), (40,7)
        lda #40
        sta zp_ax
        lda #25
        sta zp_ay
        lda #24
        sta zp_bx
        lda #16
        sta zp_by
        lda #40
        sta zp_cx
        lda #7
        sta zp_cy
        lda #3
        sta zp_color
        jsr draw_triangle

        rts

; ============================================================================
; Include dependencies
; ============================================================================

        .include "math.asm"
        .include "rasterizer.asm"

; ============================================================================
; VIC-II Setup (inline to avoid duplicate main)
; ============================================================================

vic2_init
        ; Set VIC bank to 0 ($0000-$3FFF) via CIA2
        lda $dd00
        ora #$03
        sta $dd00

        ; Screen at $0400, charset at $2000
        lda #$18
        sta $d018

        ; Enable multicolor mode
        lda $d016
        ora #$10
        sta $d016

        ; Set colors
        lda #0              ; black
        sta $d020           ; border
        sta $d021           ; background (color %00)
        lda #11             ; dark grey
        sta $d022           ; color %01
        lda #12             ; medium grey
        sta $d023           ; color %10

        ; Fill color RAM with white + multicolor bit
        lda #9              ; white (1) + multicolor enable (8)
        ldx #0
-       sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $db00,x
        inx
        bne -

        ; Copy chunky charset to $2000
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

; ============================================================================
; Compare screen RAM with expected data
; Result: $02-$03 = number of differences (0 = PASS)
;         $04-$05 = offset of first difference (or $FFFF if none)
; ============================================================================
compare_screen
        lda #0
        sta $02
        sta $03
        lda #$ff
        sta $04                 ; first diff offset lo
        sta $05                 ; first diff offset hi

        ldx #0
_cmp_loop0
        lda $0400,x
        cmp cube_expected,x
        beq _cmp0_next
        inc $02
        bne _cmp0_rec
        inc $03
_cmp0_rec
        lda $04
        cmp #$ff
        bne _cmp0_next
        stx $04
        lda #0
        sta $05
_cmp0_next
        inx
        cpx #250
        bne _cmp_loop0

        ldx #0
_cmp_loop1
        lda $0400+250,x
        cmp cube_expected+250,x
        beq _cmp1_next
        inc $02
        bne _cmp1_rec
        inc $03
_cmp1_rec
        lda $04
        cmp #$ff
        bne _cmp1_next
        txa
        clc
        adc #250
        sta $04
        lda #0
        adc #0
        sta $05
_cmp1_next
        inx
        cpx #250
        bne _cmp_loop1

        ldx #0
_cmp_loop2
        lda $0400+500,x
        cmp cube_expected+500,x
        beq _cmp2_next
        inc $02
        bne _cmp2_rec
        inc $03
_cmp2_rec
        lda $04
        cmp #$ff
        bne _cmp2_next
        txa
        clc
        adc #<500
        sta $04
        lda #0
        adc #>500
        sta $05
_cmp2_next
        inx
        cpx #250
        bne _cmp_loop2

        ldx #0
_cmp_loop3
        lda $0400+750,x
        cmp cube_expected+750,x
        beq _cmp3_next
        inc $02
        bne _cmp3_rec
        inc $03
_cmp3_rec
        lda $04
        cmp #$ff
        bne _cmp3_next
        txa
        clc
        adc #<750
        sta $04
        lda #0
        adc #>750
        sta $05
_cmp3_next
        inx
        cpx #250
        bne _cmp_loop3

        rts

; Align BEFORE charset to avoid overlap with copy destination ($2000-$27FF)
        .align $2800

; Chunky Pixel Charset (256 chars × 8 bytes = 2048 bytes)
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

; Expected cube output (auto-generated)
        .include "cube_expected.asm"
