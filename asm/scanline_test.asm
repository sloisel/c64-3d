; scanline_test.asm - Test scanline drawing routines in isolation
;
; Tests draw_span and draw_dual_row with known values

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

        ; Test 1: draw_span - single horizontal line
        ; Draw a line at y=10, from x=20 to x=40, color 1
        lda #10
        sta zp_y
        lda #20
        sta zp_xl
        lda #40
        sta zp_xr
        lda #1
        sta zp_color
        jsr draw_span

        ; Test 2: draw_dual_row - two rows at once
        ; Draw at y=20 (even), top row x=10-30, bottom row x=15-35, color 2
        lda #20
        sta zp_y
        lda #10
        sta zp_xl
        lda #30
        sta zp_xr
        lda #15
        sta zp_xl2
        lda #35
        sta zp_xr2
        lda #2
        sta zp_color
        jsr draw_dual_row

        ; Test 3: draw_span at y=30, x=0 to x=79 (full width), color 3
        lda #30
        sta zp_y
        lda #0
        sta zp_xl
        lda #79
        sta zp_xr
        lda #3
        sta zp_color
        jsr draw_span

        ; Test 4: draw_dual_row at y=40, narrow lines
        ; top row x=38-42, bottom row x=38-42, color 1
        lda #40
        sta zp_y
        lda #38
        sta zp_xl
        lda #42
        sta zp_xr
        lda #38
        sta zp_xl2
        lda #42
        sta zp_xr2
        lda #1
        sta zp_color
        jsr draw_dual_row

        ; Compare screen RAM with expected data
        ; Store diff count at $02-$03 (16-bit)
        jsr compare_screen

        ; Infinite loop - result is in $02-$03
-       jmp -

; ============================================================================
; Include dependencies
; ============================================================================

        .include "math.asm"
        .include "rasterizer.asm"

; ============================================================================
; VIC-II Setup (inline)
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
; ============================================================================
compare_screen
        lda #0
        sta $02                 ; diff count lo
        sta $03                 ; diff count hi

        ; Compare 1000 bytes in 4 chunks of 250
        ldx #0
_cmp_loop0
        lda $0400,x
        cmp scanline_expected,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp_loop0

        ldx #0
_cmp_loop1
        lda $0400+250,x
        cmp scanline_expected+250,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp_loop1

        ldx #0
_cmp_loop2
        lda $0400+500,x
        cmp scanline_expected+500,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp_loop2

        ldx #0
_cmp_loop3
        lda $0400+750,x
        cmp scanline_expected+750,x
        beq +
        inc $02
        bne +
        inc $03
+       inx
        cpx #250
        bne _cmp_loop3

        rts

; Chunky Pixel Charset (256 chars × 8 bytes = 2048 bytes)
; NOTE: This must come BEFORE scanline_expected because the charset
; gets copied to $2000-$27FF which would overwrite expected data
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

; Padding to ensure expected data is past $2800 (charset destination is $2000-$27FF)
        .align $2800

; Expected screen data (auto-generated)
        .include "scanline_expected.asm"
