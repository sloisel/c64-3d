; vic2_simple.asm - VIC-II setup for chunky pixel mode
;
; Multicolor character mode with custom charset at $2000

        * = $0801

        ; BASIC stub: SYS <main>
        .word (+), 2024
        .null $9e, format("%d", main)
+       .word 0

main
        jsr vic2_init
        jsr copy_charset
        jsr load_demo_screen

        ; Infinite loop
-       jmp -

; ============================================================================
; vic2_init - Set up VIC-II for multicolor character mode
; ============================================================================
vic2_init
        ; Set VIC bank to 0 ($0000-$3FFF) via CIA2
        ; Bits 0-1: %11=bank 0
        lda $dd00
        ora #$03
        sta $dd00

        ; Set memory pointers ($D018)
        ; Bits 4-7: Screen at $0400 → %0001
        ; Bits 1-3: Charset at $2000 → %100
        ; $D018 = %0001_1000 = $18
        lda #$18
        sta $d018

        ; Enable multicolor mode ($D016 bit 4)
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
        ; Bit 3 must be set for multicolor mode per-character
        ; Color 1 (white) + bit 3 = 1 + 8 = 9
        lda #9
        ldx #0
-       sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $db00,x
        inx
        bne -

        rts

; ============================================================================
; copy_charset - Copy chunky charset to $2000
; ============================================================================
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
; load_demo_screen - Copy demo buffer to screen RAM
; ============================================================================
load_demo_screen
        ldx #0
-       lda demo_buffer,x
        sta $0400,x
        lda demo_buffer+$100,x
        sta $0500,x
        lda demo_buffer+$200,x
        sta $0600,x
        inx
        bne -
        ; Last 232 bytes ($0700-$07E7)
        ldx #0
-       lda demo_buffer+$300,x
        sta $0700,x
        inx
        cpx #232
        bne -
        rts

; ============================================================================
; Chunky Pixel Charset (256 chars × 8 bytes = 2048 bytes)
; ============================================================================
; Each char N encodes 2×2 chunky pixels:
;   bits 7-6: top-left, bits 5-4: top-right
;   bits 3-2: bottom-left, bits 1-0: bottom-right
;
; Row byte = (left × $50) + (right × $05)

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

; ============================================================================
; Demo buffer (1000 bytes from C rasterizer)
; ============================================================================
demo_buffer
        .binary "demo.bin"
