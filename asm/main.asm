; main.asm - Main rasterizer program
;
; Build: 64tass -o main.prg -l labels.txt main.asm
; Run:   Load loader.prg first, which loads this and jumps to $3800
;
; Memory Map:
; -----------
; $0000-$00FF: Zero page (our vars at $02-$05, $06-$2B)
; $0100-$01FF: Stack
; $0400-$07E7: Screen buffer 1 (active)
; $0800-$0BFF: (Reserved for future screen buffer 2)
; $0C00-$0FFF: (Reserved for future screen buffer 3)
; $2000-$27FF: VIC charset (2KB) - VIC reads directly from here
; $2800-$29FF: sqr_lo (512 bytes)
; $2A00-$2BFF: sqr_hi (512 bytes)
; $2C00-$2CFF: negsqr_lo (256 bytes)
; $2D00-$2DFF: negsqr_hi (256 bytes)
; $2E00-$2E3F: recip_lo (64 bytes)
; $2E40-$2E7F: recip_hi (64 bytes)
; $2E80-$2EFF: (padding)
; $2F00-$30FF: smult_sq1_lo (512 bytes)
; $3100-$32FF: smult_sq1_hi (512 bytes)
; $3300-$34FF: smult_sq2_lo (512 bytes)
; $3500-$36FF: smult_sq2_hi (512 bytes)
; $3700-$37FF: smult_eorx (256 bytes)
; $3800+:      Code + test data

        .include "macros.asm"

; ============================================================================
; BASIC stub at $0801
; ============================================================================
        * = $0801

; BASIC: 10 SYS14336 (=$3800)
        .word (+), 10
        .null $9e, "14336"
+       .word 0

; Padding to $2000
        .fill $2000 - *, 0

; ============================================================================
; CHARSET at $2000 (VIC reads directly from here)
; ============================================================================

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
; MATH LOOKUP TABLES at $2800
; ============================================================================
        * = $2800

; Quarter-square tables for unsigned multiplication
; sqr[n] = floor(n²/4), for n = 0..511
sqr_lo
        .for n = 0, n < 512, n += 1
            .byte <((n*n)/4)
        .endfor

        * = $2a00
sqr_hi
        .for n = 0, n < 512, n += 1
            .byte >((n*n)/4)
        .endfor

; Negative index tables for Y<X case (mult66.a style with -1 offset)
        * = $2c00
negsqr_lo
        .for n = 0, n < 256, n += 1
            .byte <(((256-n)*(256-n))/4 - 1)
        .endfor

        * = $2d00
negsqr_hi
        .for n = 0, n < 256, n += 1
            .byte >(((256-n)*(256-n))/4 - 1)
        .endfor

; Reciprocal tables for division: recip[n] = floor(65536/n)
        * = $2e00
recip_lo
        .byte 0                 ; [0] undefined
        .for n = 1, n < 64, n += 1
            .byte <(65536/n)
        .endfor

        * = $2e40
recip_hi
        .byte 0                 ; [0] undefined
        .for n = 1, n < 64, n += 1
            .byte >(65536/n)
        .endfor

; Padding to next page
        * = $2f00

; Signed multiplication tables (smult11 style)
smult_sq1_lo
        .for i = -256, i <= 254, i += 1
            .byte <((i*i)/4)
        .endfor
        .byte 0                 ; padding

        * = $3100
smult_sq1_hi
        .for i = -256, i <= 254, i += 1
            .byte >((i*i)/4)
        .endfor
        .byte 0                 ; padding

        * = $3300
smult_sq2_lo
        .for i = -255, i <= 255, i += 1
            .byte <((i*i)/4)
        .endfor
        .byte 0                 ; padding

        * = $3500
smult_sq2_hi
        .for i = -255, i <= 255, i += 1
            .byte >((i*i)/4)
        .endfor
        .byte 0                 ; padding

        * = $3700
smult_eorx
        .for i = 0, i < 256, i += 1
            .byte i ^ 128
        .endfor

; ============================================================================
; CODE starts at $3800
; ============================================================================
        * = $3800

; ----------------------------------------------------------------------------
; Zero page allocations
; ----------------------------------------------------------------------------
zp_mul_ptr0     = $fb   ; 2 bytes - pointer for multiplication tables
zp_mul_ptr1     = $fd   ; 2 bytes - pointer for multiplication tables
prod_low        = $02   ; multiplication result low byte
prod_high       = $03   ; multiplication result high byte
div_result_lo   = $04   ; 8.8 result low byte (fractional part)
div_result_hi   = $05   ; 8.8 result high byte (integer part)

; Rasterizer zero page
zp_ax           = $06
zp_ay           = $07
zp_bx           = $08
zp_by           = $09
zp_cx           = $0a
zp_cy           = $0b
zp_swaps        = $0c
zp_color        = $0d
zp_dx_ac_lo     = $0e
zp_dx_ac_hi     = $0f
zp_dx_short_lo  = $10
zp_dx_short_hi  = $11
zp_x_long_lo    = $12
zp_x_long_hi    = $13
zp_x_short_lo   = $14
zp_x_short_hi   = $15
zp_y            = $16
zp_y_end        = $17
zp_xl           = $18
zp_xr           = $19
zp_screen_lo    = $1a
zp_screen_hi    = $1b
zp_det_t1       = $1c
zp_det_t2       = $1d
zp_det_t3       = $1e
zp_det_t4       = $1f
zp_xl2          = $20
zp_xr2          = $21
zp_char_x       = $22
zp_char_start   = $23
zp_char_end     = $24
zp_b_on_left    = $25
zp_x_long2_lo   = $26
zp_x_long2_hi   = $27
zp_x_short2_lo  = $28
zp_x_short2_hi  = $29
zp_dx_temp      = $2a
zp_dy_temp      = $2b

; ----------------------------------------------------------------------------
; Constants
; ----------------------------------------------------------------------------
SCREEN_RAM      = $0400
SCREEN_WIDTH    = 80
SCREEN_HEIGHT   = 50
CHAR_WIDTH      = 40
CHAR_HEIGHT     = 25

; Pixel masks for 2x2 chunky pixels in multicolor char
PIXEL_TL_MASK   = $c0
PIXEL_TR_MASK   = $30
PIXEL_BL_MASK   = $0c
PIXEL_BR_MASK   = $03
PIXEL_TL_SHIFT  = 6
PIXEL_TR_SHIFT  = 4
PIXEL_BL_SHIFT  = 2
PIXEL_BR_SHIFT  = 0

; ============================================================================
; Main entry point
; ============================================================================
main
        ; Initialize VIC-II for chunky pixel mode
        jsr vic2_init

        ; Initialize math library
        jsr mul8x8_init

        ; Clear screen to color 0
        lda #0
        jsr clear_screen

        ; Start timing
        jsr tic

        ; Draw isometric cube (same as C --demo)
        jsr draw_demo_cube

        ; Stop timing
        jsr toc

        ; Compare screen RAM with expected data
        jsr compare_screen

        ; Infinite loop - result is in $02-$03 (0 = PASS)
-       jmp -

; ============================================================================
; tic - Start raster-based timing
; Sets up raster interrupt at line $80 that increments counter
; ============================================================================
tic
        sei                     ; Disable interrupts

        ; Initialize counter to $FF (-1, so first interrupt makes it 0)
        lda #$ff
        sta tic_counter

        ; Save old IRQ vector
        lda $0314
        sta tic_old_irq
        lda $0315
        sta tic_old_irq+1

        ; Set up our IRQ handler
        lda #<tic_irq_handler
        sta $0314
        lda #>tic_irq_handler
        sta $0315

        ; Set raster line $80 for interrupt
        lda $d011
        and #$7f                ; Clear bit 8 of raster compare
        sta $d011
        lda #$80
        sta $d012               ; Raster line $80

        ; Enable raster interrupt
        lda #$01
        sta $d01a               ; Enable raster IRQ

        ; Acknowledge any pending VIC IRQ
        sta $d019

        cli                     ; Enable interrupts
        rts

tic_irq_handler
        ; Acknowledge VIC interrupt
        lda #$01
        sta $d019

        ; Increment counter
        inc tic_counter

        ; Jump to KERNAL IRQ handler (handles keyboard etc)
        jmp $ea31

; ============================================================================
; toc - Stop timing and capture raster position
; Stores: A (counter before), B (raster), C (counter after), D (raster)
; ============================================================================
toc
        ; Capture A = counter
        lda tic_counter
        sta toc_a

        ; Read raster position B (9-bit, need careful read)
        ; Read hi, lo, hi, lo - if hi1==hi2 use (hi1,lo1), else (hi2,lo2)
        lda $d011
        and #$80                ; Bit 7 = raster bit 8
        sta toc_b_hi_1
        lda $d012
        sta toc_b_lo_1
        lda $d011
        and #$80
        sta toc_b_hi_2
        lda $d012
        sta toc_b_lo_2

        ; Capture C = counter
        lda tic_counter
        sta toc_c

        ; Read raster position D
        lda $d011
        and #$80
        sta toc_d_hi_1
        lda $d012
        sta toc_d_lo_1
        lda $d011
        and #$80
        sta toc_d_hi_2
        lda $d012
        sta toc_d_lo_2

        ; Disable raster interrupt
        sei
        lda #$00
        sta $d01a

        ; Restore old IRQ vector
        lda tic_old_irq
        sta $0314
        lda tic_old_irq+1
        sta $0315

        cli
        rts

; Timing variables
tic_counter     .byte 0
tic_old_irq     .word 0
toc_a           .byte 0         ; Counter before raster read
toc_b_hi_1      .byte 0         ; Raster B high (first read)
toc_b_lo_1      .byte 0         ; Raster B low (first read)
toc_b_hi_2      .byte 0         ; Raster B high (second read)
toc_b_lo_2      .byte 0         ; Raster B low (second read)
toc_c           .byte 0         ; Counter after raster read
toc_d_hi_1      .byte 0         ; Raster D high (first read)
toc_d_lo_1      .byte 0         ; Raster D low (first read)
toc_d_hi_2      .byte 0         ; Raster D high (second read)
toc_d_lo_2      .byte 0         ; Raster D low (second read)

; ============================================================================
; draw_demo_cube - Draw the test cube
; ============================================================================
draw_demo_cube
        ; Triangle 1: C, p100, p110 = (40,25), (56,34), (40,43) color 1
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

        ; Triangle 2: C, p110, p010 = (40,25), (40,43), (24,34) color 1
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

        ; Triangle 3: C, p001, p101 = (40,25), (40,7), (56,16) color 2
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

        ; Triangle 4: C, p101, p100 = (40,25), (56,16), (56,34) color 2
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

        ; Triangle 5: C, p010, p011 = (40,25), (24,34), (24,16) color 3
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

        ; Triangle 6: C, p011, p001 = (40,25), (24,16), (40,7) color 3
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
; mul8x8_init - Initialize multiplication table pointers
; ============================================================================
mul8x8_init
        lda #<sqr_lo
        sta zp_mul_ptr0
        lda #>sqr_lo
        sta zp_mul_ptr0+1
        lda #<sqr_hi
        sta zp_mul_ptr1
        lda #>sqr_hi
        sta zp_mul_ptr1+1
        rts

; ============================================================================
; div8s_8u_v2 - Signed 8-bit / unsigned 8-bit = 8.8 fixed point
; ============================================================================
; Input:  A = dividend (signed, -80 to +80)
;         X = divisor  (unsigned, 1-50)
; Output: Y:A = 8.8 result (Y=integer, A=fraction)

div8s_8u_v2
        cpx #1
        bne _div2_normal
        tay
        sta div_result_hi
        lda #0
        sta div_result_lo
        rts

_div2_normal
        stx div_divisor

        cmp #$80
        bcc _div2_pos

        ; Negative: negate dividend
        eor #$ff
        clc
        adc #1
        jsr _div2_core

        ; Negate result
        eor #$ff
        clc
        adc #1
        sta div_result_lo
        tya
        eor #$ff
        adc #0
        sta div_result_hi
        tay
        lda div_result_lo
        rts

_div2_pos
        jsr _div2_core
        sta div_result_lo
        sty div_result_hi
        rts

_div2_core
        sta div_dividend

        ; First: A × recip_lo
        ldx div_divisor
        tay
        lda recip_lo,x
        tax
        #mul8x8_unsigned_m
        sta div_p0_hi

        ; Second: A × recip_hi
        ldx div_divisor
        ldy div_dividend
        lda recip_hi,x
        tax
        #mul8x8_unsigned_m

        ; Combine
        tay
        lda div_p0_hi
        clc
        adc prod_low
        bcc +
        iny
+       rts

div_divisor     .byte 0
div_dividend    .byte 0
div_p0_hi       .byte 0

cycle_count_lo  .byte 0
cycle_count_hi  .byte 0

; ============================================================================
; Include rasterizer
; ============================================================================
        .include "rasterizer.asm"

; ============================================================================
; VIC-II Setup
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
        lda #0
        sta $d020           ; border black
        sta $d021           ; background (color %00)
        lda #11
        sta $d022           ; color %01 dark grey
        lda #12
        sta $d023           ; color %10 medium grey

        ; Fill color RAM with white + multicolor
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
; Compare screen RAM with expected data
; ============================================================================
compare_screen
        lda #0
        sta $02
        sta $03
        lda #$ff
        sta $04
        sta $05

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

; ============================================================================
; Expected cube output
; ============================================================================
        .include "cube_expected.asm"
