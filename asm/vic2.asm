; vic2.asm - VIC-II Setup for Chunky Pixel Mode
;
; Configures VIC-II for multicolor character mode with 80x50 chunky pixels.
; Each character cell (8x8) displays a 2x2 grid of "chunky pixels" using
; multicolor mode (4 colors, 2 bits per pixel).
;
; Memory Layout (Bank 0: $0000-$3FFF):
;   $0400-$07E7 - Screen RAM (40x25 = 1000 bytes)
;   $2000-$27FF - Character set (256 chars × 8 bytes = 2KB)
;   $D800-$DBE7 - Color RAM (not in VIC bank, always at $D800)
;
; Note: Can't use $1000-$1FFF for charset due to VIC-II ROM shadow bug.
;
; Colors in multicolor character mode:
;   %00 = Background ($D021)
;   %01 = Extra color 1 ($D022)
;   %10 = Extra color 2 ($D023)
;   %11 = Color RAM ($D800+), lower 3 bits only (colors 0-7)

; ============================================================================
; VIC-II Register Definitions
; ============================================================================

VIC_D011        = $d011     ; Control register 1 (vertical scroll, screen height, mode)
VIC_D016        = $d016     ; Control register 2 (horizontal scroll, multicolor, width)
VIC_D018        = $d018     ; Memory pointers (screen and charset location)
; VIC_BORDER defined in macros.asm
VIC_BG0         = $d021     ; Background color 0
VIC_BG1         = $d022     ; Background color 1 (multicolor bit %01)
VIC_BG2         = $d023     ; Background color 2 (multicolor bit %10)

CIA2_PRA        = $dd00     ; CIA2 Port A (VIC bank selection)

SCREEN_RAM      = $0400     ; Screen memory (1000 bytes)
COLOR_RAM       = $d800     ; Color memory (1000 bytes)
CHARSET_ADDR    = $2000     ; Character set (2048 bytes)

; ============================================================================
; Default Colors (can be changed)
; ============================================================================

COLOR_BG        = 0         ; Black - background (%00)
COLOR_1         = 11        ; Dark grey - color 1 (%01)
COLOR_2         = 12        ; Medium grey - color 2 (%10)
COLOR_3         = 1         ; White - color 3 (%11, via color RAM)

; ============================================================================
; vic2_init - Initialize VIC-II for chunky pixel mode
; ============================================================================
; Sets up multicolor character mode with custom character set.
; Call this once at program start.
;
; Destroys: A, X, Y
; ============================================================================

vic2_init
        ; Set VIC bank to 0 ($0000-$3FFF)
        ; CIA2 Port A bits 0-1: %11=bank 0, %10=bank 1, %01=bank 2, %00=bank 3
        lda CIA2_PRA
        ora #$03            ; Set bits 0-1 to select bank 0
        sta CIA2_PRA

        ; Set memory pointers ($D018)
        ; Bits 4-7: Screen memory offset (×$400)
        ;   $0400 → offset 1 → %0001xxxx
        ; Bits 1-3: Character memory offset (×$800)
        ;   $2000 → offset 4 → %xxxx100x
        ; So $D018 = %0001 100 0 = $18
        lda #$18
        sta VIC_D018

        ; Enable multicolor mode ($D016 bit 4 = 1)
        lda VIC_D016
        ora #$10            ; Set bit 4
        sta VIC_D016

        ; Make sure we're in character mode, not bitmap ($D011 bit 5 = 0)
        lda VIC_D011
        and #$df            ; Clear bit 5
        sta VIC_D011

        ; Set colors
        lda #COLOR_BG
        sta VIC_BG0         ; Background
        lda #COLOR_1
        sta VIC_BG1         ; Color for %01
        lda #COLOR_2
        sta VIC_BG2         ; Color for %10
        lda #0              ; Black border
        sta VIC_BORDER

        ; Fill color RAM with COLOR_3 + multicolor enable bit
        ; Bit 3 must be set for per-character multicolor mode
        ; Color RAM bits 0-2 = color, bit 3 = multicolor enable
        lda #(COLOR_3 | 8)
        ldx #0
-       sta COLOR_RAM,x
        sta COLOR_RAM+$100,x
        sta COLOR_RAM+$200,x
        sta COLOR_RAM+$2e8,x    ; Only need 1000 bytes, but fill extra for safety
        inx
        bne -

        ; Copy chunky pixel charset to $2000
        jsr copy_charset

        ; Clear screen
        jsr vic2_clear_screen

        rts

; ============================================================================
; vic2_clear_screen - Clear screen to all zeros (color %00)
; ============================================================================

vic2_clear_screen
        lda #0
        ldx #0
-       sta SCREEN_RAM,x
        sta SCREEN_RAM+$100,x
        sta SCREEN_RAM+$200,x
        sta SCREEN_RAM+$2e8,x
        inx
        bne -
        rts

; ============================================================================
; copy_charset - Copy pre-generated charset to VIC memory
; ============================================================================

copy_charset
        ldx #0
-       lda chunky_charset,x
        sta CHARSET_ADDR,x
        lda chunky_charset+$100,x
        sta CHARSET_ADDR+$100,x
        lda chunky_charset+$200,x
        sta CHARSET_ADDR+$200,x
        lda chunky_charset+$300,x
        sta CHARSET_ADDR+$300,x
        lda chunky_charset+$400,x
        sta CHARSET_ADDR+$400,x
        lda chunky_charset+$500,x
        sta CHARSET_ADDR+$500,x
        lda chunky_charset+$600,x
        sta CHARSET_ADDR+$600,x
        lda chunky_charset+$700,x
        sta CHARSET_ADDR+$700,x
        inx
        bne -
        rts

; ============================================================================
; load_demo_screen - Load demo buffer to screen RAM
; ============================================================================
; If demo_buffer is included, copy it to screen RAM for visual testing.

load_demo_screen
        ldx #0
-       lda demo_buffer,x
        sta SCREEN_RAM,x
        lda demo_buffer+$100,x
        sta SCREEN_RAM+$100,x
        lda demo_buffer+$200,x
        sta SCREEN_RAM+$200,x
        inx
        bne -
        ; Last 232 bytes
        ldx #0
-       lda demo_buffer+$300,x
        sta SCREEN_RAM+$300,x
        inx
        cpx #232
        bne -
        rts

; ============================================================================
; Chunky Pixel Character Set (256 characters × 8 bytes = 2048 bytes)
; ============================================================================
;
; Each character N encodes a 2×2 grid of chunky pixels:
;   Bits 7-6: Top-left pixel color (0-3)
;   Bits 5-4: Top-right pixel color (0-3)
;   Bits 3-2: Bottom-left pixel color (0-3)
;   Bits 1-0: Bottom-right pixel color (0-3)
;
; In multicolor mode, each row is 4 double-wide pixels (2 bits each).
; Character rows 0-3 show top-left and top-right.
; Character rows 4-7 show bottom-left and bottom-right.
;
; Row byte = (left_color × $50) + (right_color × $05)
;   where $50 = %01010000 (color in positions 0-1 and 2-3)
;   and   $05 = %00000101 (color in positions 4-5 and 6-7)

chunky_charset
        ; Generate all 256 characters at assembly time
        .for ch = 0, ch < 256, ch += 1
            ; Extract the 4 pixel colors from character code
            ;   tl = (ch >> 6) & 3  (top-left)
            ;   tr = (ch >> 4) & 3  (top-right)
            ;   bl = (ch >> 2) & 3  (bottom-left)
            ;   br = ch & 3         (bottom-right)
            ;
            ; Top row byte: TL in positions 0-1 and 2-3, TR in positions 4-5 and 6-7
            ;   top_row = (tl * $50) + (tr * $05)
            ; Bottom row byte: similarly for BL and BR
            ;   bot_row = (bl * $50) + (br * $05)

            ; 8 rows per character: 4 top, 4 bottom
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
; Demo Buffer (optional - uncomment to include)
; ============================================================================
; This is the output from the C rasterizer's demo mode.
; Load with: ./test --demo && xxd -i demo.bin

demo_buffer
        .binary "demo.bin"      ; Include the 1000-byte demo buffer

; ============================================================================
; Notes on Memory and Colors
; ============================================================================
;
; To change colors at runtime:
;   lda #new_color
;   sta VIC_BG0        ; Background (pixel %00)
;   sta VIC_BG1        ; Color 1 (pixel %01)
;   sta VIC_BG2        ; Color 2 (pixel %10)
;   ; For pixel %11, update COLOR_RAM (lower 3 bits only, colors 0-7)
;
; C64 Color Values:
;   0 = Black       4 = Purple      8 = Orange      12 = Med Grey
;   1 = White       5 = Green       9 = Brown       13 = Lt Green
;   2 = Red         6 = Blue        10 = Lt Red     14 = Lt Blue
;   3 = Cyan        7 = Yellow      11 = Dk Grey    15 = Lt Grey
;
; ============================================================================
