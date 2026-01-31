; main.asm - Main rasterizer program
;
; Build: 64tass -o main.prg -l labels.txt main.asm
; Run:   Load loader.prg first, which loads this and jumps to $3800
;
; Memory Map:
; -----------
; $0000-$00FF: Zero page (our vars at $02-$05, $06-$50)
; $0100-$01FF: Stack
; $0400-$07E7: Screen buffer 1 (active)
; $0800-$0BFF: (Reserved for future screen buffer 2)
; $0C00-$0FFF: (Reserved for future screen buffer 3)
; $2000-$27FF: VIC charset (2KB) - VIC reads directly from here
; $2800+:      Math lookup tables (page-aligned where needed, ~8KB total)
;              - sqr_lo/hi (512 bytes each, page-aligned)
;              - negsqr_lo/hi (256 bytes each)
;              - recip_persp (256 bytes)
;              - smult_sq1/sq2 lo/hi (512 bytes each, page-aligned)
;              - smult_eorx (256 bytes)
;              - recip_lo/hi (64 bytes each)
;              - su_sum/diff lo/hi (512 bytes each, page-aligned)
; (After tables): Code
; (After code): rcos (256 bytes), rsin (256 bytes) - rotation tables

        .include "macros.asm"

; ============================================================================
; BASIC stub at $0801
; ============================================================================
        * = $0801

; BASIC: 10 SYS <main>
        .word (+), 10
        .null $9e, format("%d", main)
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
; MATH LOOKUP TABLES - starts at $2800 (after VIC charset)
; Tables needing page alignment use .align 256
; ============================================================================
        * = $2800

; Quarter-square tables for unsigned multiplication (need page alignment for SMC)
; sqr[n] = floor(n²/4), for n = 0..511
        .align 256
sqr_lo
        .for n = 0, n < 512, n += 1
            .byte <((n*n)/4)
        .endfor

        .align 256
sqr_hi
        .for n = 0, n < 512, n += 1
            .byte >((n*n)/4)
        .endfor

; Negative index tables for Y<X case (mult66.a style with -1 offset)
; These don't need page alignment - just 256 bytes each
negsqr_lo
        .for n = 0, n < 256, n += 1
            .byte <(((256-n)*(256-n))/4 - 1)
        .endfor

negsqr_hi
        .for n = 0, n < 256, n += 1
            .byte >(((256-n)*(256-n))/4 - 1)
        .endfor

; Perspective reciprocal table for 3D projection (256 bytes, no alignment needed)
; recip_persp[z8] = 4096 / z8 for z8 = 17..255
recip_persp
        .for i = 0, i < 256, i += 1
            .if i < 17
                .byte 0         ; invalid (would overflow)
            .else
                .byte (4096 / i)
            .endif
        .endfor

; Signed multiplication tables (smult11 style) - need page alignment for SMC
        .align 256
smult_sq1_lo
        .for i = -256, i <= 254, i += 1
            .byte <((i*i)/4)
        .endfor
        .byte 0                 ; padding to 512

        .align 256
smult_sq1_hi
        .for i = -256, i <= 254, i += 1
            .byte >((i*i)/4)
        .endfor
        .byte 0                 ; padding to 512

        .align 256
smult_sq2_lo
        .for i = -255, i <= 255, i += 1
            .byte <((i*i)/4)
        .endfor
        .byte 0                 ; padding to 512

        .align 256
smult_sq2_hi
        .for i = -255, i <= 255, i += 1
            .byte >((i*i)/4)
        .endfor
        .byte 0                 ; padding to 512

; smult_eorx doesn't need page alignment
smult_eorx
        .for i = 0, i < 256, i += 1
            .byte i ^ 128
        .endfor

; Reciprocal tables for division: recip[n] = floor(65536/n) (small, no alignment)
recip_lo
        .byte 0                 ; [0] undefined
        .for n = 1, n < 64, n += 1
            .byte <(65536/n)
        .endfor

recip_hi
        .byte 0                 ; [0] undefined
        .for n = 1, n < 64, n += 1
            .byte >(65536/n)
        .endfor

; Signed × Unsigned multiplication tables - need page alignment for SMC
; For signed a (-128..127) × unsigned b (0..255):
;   a+b ranges from -128 to 382, indexed as (a^$80) + b = 0..510
;   a-b ranges from -383 to 127, indexed as ~(a^$80) + b = 0..510
        .align 256
su_sum_lo       ; (n²)/4 for n = -128..382
        .for n = -128, n <= 382, n += 1
            .byte <((n*n)/4)
        .endfor
        .byte 0                 ; padding to 512

        .align 256
su_sum_hi
        .for n = -128, n <= 382, n += 1
            .byte >((n*n)/4)
        .endfor
        .byte 0                 ; padding to 512

        .align 256
su_diff_lo      ; (n²)/4 for n = 127..-383 (reversed for correct indexing)
        .for n = 127, n >= -383, n -= 1
            .byte <((n*n)/4)
        .endfor
        .byte 0                 ; padding to 512

        .align 256
su_diff_hi
        .for n = 127, n >= -383, n -= 1
            .byte >((n*n)/4)
        .endfor
        .byte 0                 ; padding to 512

; ============================================================================
; CODE starts here (after all tables)
; ============================================================================

; ----------------------------------------------------------------------------
; Zero page allocations
; ----------------------------------------------------------------------------
zp_mul_ptr0     = $fb   ; 2 bytes - pointer for multiplication tables
zp_mul_ptr1     = $fd   ; 2 bytes - pointer for multiplication tables
zp_anim_ptr     = $f9   ; 2 bytes - pointer for animation frame data
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
zp_adj_lo       = $2c   ; Adjusted pointer for fast blitter
zp_adj_hi       = $2d
zp_dx_ac2_lo    = $2e   ; dx_ac * 2 (low) - precomputed for dual-row
zp_dx_ac2_hi    = $2f   ; dx_ac * 2 (high)
zp_dx_short2_lo = $30   ; dx_short * 2 (low)
zp_dx_short2_hi = $31   ; dx_short * 2 (high)

; Blitter temps (after mesh.asm's $32-$45)
zp_blit_color   = $46   ; color pattern byte
zp_blit_cstart  = $47   ; char_start
zp_blit_fstart  = $48   ; full_start
zp_blit_fend    = $49   ; full_end
zp_blit_temp    = $4a   ; temp for RMW
; Single-row blitter temps
zp_span_cstart  = $4b   ; char_start for draw_span_top/bottom
zp_span_fstart  = $4c   ; full_start for draw_span_top/bottom
zp_span_temp    = $4d   ; temp for draw_span_top/bottom
zp_dri_saved_y  = $4e   ; saved y for draw_dual_row_intervals
zp_m16m_u       = $4f   ; unsigned multiplier for mul16s_8u_hi_m
zp_m16m_p1_hi   = $50   ; high byte of first product for mul16s_8u_hi_m

; Division routine ZP temps (saves ~7 cycles per div call)
zp_div_divisor  = $54
zp_div_dividend = $55
zp_div_p0_hi    = $56

; Rasterizer temp for half-step calculation (saves ~12 cycles per triangle)
zp_temp_half_lo = $57
zp_temp_half_hi = $58

; Mesh properties in ZP (saves ~1 cycle per access)
zp_mesh_num_verts   = $59
zp_mesh_num_faces_0 = $5a
zp_mesh_num_faces_1 = $5b
zp_mesh_px_lo   = $5c
zp_mesh_px_hi   = $5d
zp_mesh_py_lo   = $5e
zp_mesh_py_hi   = $5f
zp_mesh_pz_lo   = $60
zp_mesh_pz_hi   = $61

; ----------------------------------------------------------------------------
; Constants
; ----------------------------------------------------------------------------
SCREEN_RAM      = $0400
SCREEN_WIDTH    = 80
SCREEN_HEIGHT   = 50
CHAR_WIDTH      = 40
CHAR_HEIGHT     = 25

; Triple buffer addresses (high bytes)
SCREEN_BUF_0    = $04           ; $0400
SCREEN_BUF_1    = $08           ; $0800
SCREEN_BUF_2    = $0c           ; $0C00

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
; Build configuration: define GRUNT_MESH=1 for zombie, 0 for octahedron
; Use: 64tass -D GRUNT_MESH=1 -o zombie.prg main.asm
;      64tass -D GRUNT_MESH=0 -o octa.prg main.asm
; ============================================================================

; ============================================================================
; Main entry point
; ============================================================================
main
        ; Initialize VIC-II for chunky pixel mode
        jsr vic2_init

        ; Initialize math library
        jsr mul8x8_init

        ; Initialize triple buffering
        jsr triple_buf_init

        ; Initialize mesh data
.if GRUNT_MESH
        jsr init_grunt
.else
        jsr init_octahedron
.endif

        ; Animation loop
_anim_loop
        ; Wait until we can draw (display buffer != draw buffer)
        ; This should rarely block with triple buffering
-       lda buf_display
        cmp buf_draw
        beq -

        ; Clear screen to color 0
        lda #0
        jsr clear_screen

        ; Draw mesh
        jsr draw_octahedron

        ; Queue page flip: the buffer we just drew becomes the next to display
        lda buf_draw
        sta buf_ready

        ; Advance to next draw buffer (0 -> 1 -> 2 -> 0)
        jsr advance_draw_buffer

        ; Increment theta
        lda mesh_theta
        clc
        adc #3
        sta mesh_theta

.if GRUNT_MESH
        ; Advance animation frame (grunt only)
        jsr advance_grunt_frame
.endif

        jmp _anim_loop

; ============================================================================
; Triple buffer management
; ============================================================================

; Buffer state variables
buf_display     .byte SCREEN_BUF_0      ; Currently displayed (VIC reads this)
buf_ready       .byte SCREEN_BUF_0      ; Ready to display (queued for next vblank)
buf_draw        .byte SCREEN_BUF_1      ; Currently being drawn to

; Buffer table for cycling (0->1->2->0)
buf_table       .byte SCREEN_BUF_0, SCREEN_BUF_1, SCREEN_BUF_2
buf_next        .byte 1, 2, 0           ; Index of next buffer

; Timing counters for FPS measurement
vsync_counter   .word 0                 ; Incremented every vblank IRQ
frame_counter   .word 0                 ; Incremented on actual page flip

; ----------------------------------------------------------------------------
; triple_buf_init - Initialize triple buffering with raster IRQ
; ----------------------------------------------------------------------------
triple_buf_init
        sei

        ; Initialize buffer state
        lda #SCREEN_BUF_0
        sta buf_display
        sta buf_ready
        lda #SCREEN_BUF_1
        sta buf_draw

        ; Patch SMC for initial draw buffer
        jsr patch_screen_base

        ; Disable CIA-1 interrupts
        lda #$7f
        sta $dc0d
        sta $dd0d               ; Also CIA-2

        ; Set up raster interrupt at line 250 (in vblank)
        lda $d011
        and #$7f                ; Clear bit 8 of raster
        sta $d011
        lda #250
        sta $d012

        ; Install our IRQ handler
        lda #<vblank_irq
        sta $0314
        lda #>vblank_irq
        sta $0315

        ; Enable raster interrupt
        lda #$01
        sta $d01a

        ; Acknowledge any pending
        asl $d019

        cli
        rts

; ----------------------------------------------------------------------------
; vblank_irq - Raster interrupt handler for page flipping
; ----------------------------------------------------------------------------
vblank_irq
        ; Increment vsync counter (always, every vblank)
        inc vsync_counter
        bne +
        inc vsync_counter+1
+
        ; Check if we're flipping to a new buffer
        lda buf_ready
        cmp buf_display
        beq _no_flip
        ; New frame - increment frame counter
        inc frame_counter
        bne +
        inc frame_counter+1
+
_no_flip
        ; Page flip: display the ready buffer
        lda buf_ready
        sta buf_display

        ; Update VIC screen pointer ($D018)
        ; Screen at $0400: bits 7-4 = 1 ($1x)
        ; Screen at $0800: bits 7-4 = 2 ($2x)
        ; Screen at $0C00: bits 7-4 = 3 ($3x)
        ; Charset at $2000: bits 3-0 = 8 ($x8)
        ; So: $0400 = $18, $0800 = $28, $0C00 = $38
        asl a                   ; $04->$08, $08->$10, $0C->$18
        asl a                   ; $08->$10, $10->$20, $18->$30
        asl a                   ; $10->$20, $20->$40, $30->$60... wait this is wrong

        ; Let me recalculate. buf_display is $04, $08, or $0C
        ; VIC $D018: high nibble = screen/1024, low nibble = charset/2048 * 2
        ; Screen $0400 = 1*1024, so high nibble = 1
        ; Screen $0800 = 2*1024, so high nibble = 2
        ; Screen $0C00 = 3*1024, so high nibble = 3
        ; Charset $2000 = 4*2048, low nibble = 8
        ; So we need: ($04 -> $18), ($08 -> $28), ($0C -> $38)
        ; That's: (buf >> 2) << 4 | 8 = (buf << 2) | 8
        lda buf_display
        asl a
        asl a                   ; $04->$10, $08->$20, $0C->$30
        ora #$08                ; Add charset bits
        sta $d018

        ; Acknowledge interrupt
        asl $d019

        ; Return from interrupt (skip KERNAL)
        pla
        tay
        pla
        tax
        pla
        rti

; ----------------------------------------------------------------------------
; advance_draw_buffer - Move to next draw buffer and patch SMC
; ----------------------------------------------------------------------------
advance_draw_buffer
        ; Find current buffer index
        ldx #0
        lda buf_draw
-       cmp buf_table,x
        beq +
        inx
        cpx #3
        bne -
        ; Shouldn't happen, default to 0
        ldx #0
+
        ; Get next buffer
        lda buf_next,x
        tax
        lda buf_table,x
        sta buf_draw

        ; Patch SMC locations
        jsr patch_screen_base
        rts

; ----------------------------------------------------------------------------
; patch_screen_base - Patch all SMC locations with current draw buffer
; ----------------------------------------------------------------------------
patch_screen_base
        lda buf_draw

        ; Patch drawing routines (4 locations) - labels point directly to byte
        sta smc_screen_hi_1
        sta smc_screen_hi_2
        sta smc_screen_hi_3
        sta smc_screen_hi_4

        ; Patch clear_screen (4 high bytes) - labels point directly to byte
        sta smc_clear_1
        clc
        adc #1
        sta smc_clear_2
        adc #1
        sta smc_clear_3
        adc #1
        sta smc_clear_4

        rts

; ============================================================================
; draw_octahedron - Transform and render the octahedron
; ============================================================================
draw_octahedron
        jsr transform_mesh
        cmp #0
        bne _do_err             ; Transform failed
        jsr render_mesh
_do_err
        rts

; ============================================================================
; init_octahedron - Initialize octahedron mesh data (8 faces, 6 vertices)
; ============================================================================
.if !GRUNT_MESH
init_octahedron
        ; Octahedron vertices: 6 points
        ; 0: +X (104, 60, 0)   1: -X (-104, -60, 0)
        ; 2: +Y (-60, 104, 0)  3: -Y (60, -104, 0)
        ; 4: +Z (0, 0, 120)    5: -Z (0, 0, -120)
        lda #6
        sta zp_mesh_num_verts

        ; Vertex 0: (104, 60, 0)
        lda #104
        sta mesh_vx+0
        lda #60
        sta mesh_vy+0
        lda #0
        sta mesh_vz+0

        ; Vertex 1: (-104, -60, 0)
        lda #<(-104)
        sta mesh_vx+1
        lda #<(-60)
        sta mesh_vy+1
        lda #0
        sta mesh_vz+1

        ; Vertex 2: (-60, 104, 0)
        lda #<(-60)
        sta mesh_vx+2
        lda #104
        sta mesh_vy+2
        lda #0
        sta mesh_vz+2

        ; Vertex 3: (60, -104, 0)
        lda #60
        sta mesh_vx+3
        lda #<(-104)
        sta mesh_vy+3
        lda #0
        sta mesh_vz+3

        ; Vertex 4: (0, 0, 120)
        lda #0
        sta mesh_vx+4
        sta mesh_vy+4
        lda #120
        sta mesh_vz+4

        ; Vertex 5: (0, 0, -120)
        lda #0
        sta mesh_vx+5
        sta mesh_vy+5
        lda #<(-120)
        sta mesh_vz+5

        ; 8 faces (all in mesh_0 for single-mesh mode)
        lda #8
        sta zp_mesh_num_faces_0
        lda #0
        sta zp_mesh_num_faces_1

        ; Face 0: i=0, j=4, k=3, color=1
        lda #0
        sta mesh_fi_0+0
        lda #4
        sta mesh_fj_0+0
        lda #3
        sta mesh_fk_0+0
        lda #1
        sta mesh_fcol_0+0

        ; Face 1: i=1, j=3, k=4, color=2
        lda #1
        sta mesh_fi_0+1
        lda #3
        sta mesh_fj_0+1
        lda #4
        sta mesh_fk_0+1
        lda #2
        sta mesh_fcol_0+1

        ; Face 2: i=0, j=3, k=5, color=3
        lda #0
        sta mesh_fi_0+2
        lda #3
        sta mesh_fj_0+2
        lda #5
        sta mesh_fk_0+2
        lda #3
        sta mesh_fcol_0+2

        ; Face 3: i=1, j=5, k=3, color=1
        lda #1
        sta mesh_fi_0+3
        lda #5
        sta mesh_fj_0+3
        lda #3
        sta mesh_fk_0+3
        lda #1
        sta mesh_fcol_0+3

        ; Face 4: i=0, j=2, k=4, color=2
        lda #0
        sta mesh_fi_0+4
        lda #2
        sta mesh_fj_0+4
        lda #4
        sta mesh_fk_0+4
        lda #2
        sta mesh_fcol_0+4

        ; Face 5: i=1, j=4, k=2, color=3
        lda #1
        sta mesh_fi_0+5
        lda #4
        sta mesh_fj_0+5
        lda #2
        sta mesh_fk_0+5
        lda #3
        sta mesh_fcol_0+5

        ; Face 6: i=0, j=5, k=2, color=1
        lda #0
        sta mesh_fi_0+6
        lda #5
        sta mesh_fj_0+6
        lda #2
        sta mesh_fk_0+6
        lda #1
        sta mesh_fcol_0+6

        ; Face 7: i=1, j=2, k=5, color=2
        lda #1
        sta mesh_fi_0+7
        lda #2
        sta mesh_fj_0+7
        lda #5
        sta mesh_fk_0+7
        lda #2
        sta mesh_fcol_0+7

        ; Transform parameters: px=0, py=-25, pz=256, theta=20
        lda #0
        sta zp_mesh_px_lo
        sta zp_mesh_px_hi

        lda #<(-25)
        sta zp_mesh_py_lo
        lda #>(-25)
        sta zp_mesh_py_hi

        lda #<256
        sta zp_mesh_pz_lo
        lda #>256
        sta zp_mesh_pz_hi

        lda #20
        sta mesh_theta

        rts
.endif

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
        stx zp_div_divisor

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
        sta zp_div_dividend

        ; First: A × recip_lo
        ldx zp_div_divisor
        tay
        lda recip_lo,x
        tax
        #mul8x8_unsigned_m
        sta zp_div_p0_hi

        ; Second: A × recip_hi
        ldx zp_div_divisor
        ldy zp_div_dividend
        lda recip_hi,x
        tax
        #mul8x8_unsigned_m

        ; Combine
        tay
        lda zp_div_p0_hi
        clc
        adc prod_low
        bcc +
        iny
+       rts

cycle_count_lo  .byte 0
cycle_count_hi  .byte 0

; ============================================================================
; Include rasterizer and mesh rendering
; ============================================================================
        .include "rasterizer.asm"
DUAL_MESH = GRUNT_MESH          ; 1 = dual-mesh for grunt (295 faces), 0 = single for octahedron (8 faces)
        .include "mesh.asm"

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
        lda #12
        sta $d022           ; color %01 medium grey
        lda #15
        sta $d023           ; color %10 light grey

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
; Grunt mesh data (151 vertices, 295 faces split 147+148, 24 animation frames)
; ============================================================================
        .include "grunt_anim.asm"

grunt_frame .byte 0     ; Current animation frame (0-15)

; ============================================================================
; init_grunt - Initialize grunt mesh data using loops
; ============================================================================
init_grunt
        ; Start at frame 0
        lda #0
        sta grunt_frame

        ; Load first frame vertices
        jsr load_grunt_frame

        lda #GRUNT_NUM_VERTICES
        sta zp_mesh_num_verts

        ; Copy sub-mesh 0 faces (147 faces)
        ldx #0
_ig_faces0
        lda grunt_fi_0,x
        sta mesh_fi_0,x
        lda grunt_fj_0,x
        sta mesh_fj_0,x
        lda grunt_fk_0,x
        sta mesh_fk_0,x
        lda grunt_fcol_0,x
        sta mesh_fcol_0,x
        inx
        cpx #GRUNT_NUM_FACES_0
        bne _ig_faces0

        lda #GRUNT_NUM_FACES_0
        sta zp_mesh_num_faces_0

        ; Copy sub-mesh 1 faces (148 faces)
        ldx #0
_ig_faces1
        lda grunt_fi_1,x
        sta mesh_fi_1,x
        lda grunt_fj_1,x
        sta mesh_fj_1,x
        lda grunt_fk_1,x
        sta mesh_fk_1,x
        lda grunt_fcol_1,x
        sta mesh_fcol_1,x
        inx
        cpx #GRUNT_NUM_FACES_1
        bne _ig_faces1

        lda #GRUNT_NUM_FACES_1
        sta zp_mesh_num_faces_1

        ; Transform parameters: px=0, py=0, pz=1500, theta=20
        lda #0
        sta zp_mesh_px_lo
        sta zp_mesh_px_hi
        sta zp_mesh_py_lo
        sta zp_mesh_py_hi

        ; pz = 200 (s16) = $00C8
        lda #<200
        sta zp_mesh_pz_lo
        lda #>200
        sta zp_mesh_pz_hi

        ; theta = 20
        lda #20
        sta mesh_theta

        rts

; ============================================================================
; load_grunt_frame - Load vertex data for current animation frame
; ============================================================================
; Uses grunt_frame to index into pointer tables
; Copies 151 vertices from frame data to mesh_vx/vy/vz
load_grunt_frame
        ; Set up source pointers based on grunt_frame
        ldx grunt_frame

        ; X axis pointer -> zp_anim_ptr
        lda grunt_vx_lo,x
        sta zp_anim_ptr
        lda grunt_vx_hi,x
        sta zp_anim_ptr+1

        ; Copy X coordinates
        ldy #0
_lgf_x  lda (zp_anim_ptr),y
        sta mesh_vx,y
        iny
        cpy #GRUNT_NUM_VERTICES
        bne _lgf_x

        ; Y axis pointer -> zp_anim_ptr
        ldx grunt_frame
        lda grunt_vy_lo,x
        sta zp_anim_ptr
        lda grunt_vy_hi,x
        sta zp_anim_ptr+1

        ; Copy Y coordinates
        ldy #0
_lgf_y  lda (zp_anim_ptr),y
        sta mesh_vy,y
        iny
        cpy #GRUNT_NUM_VERTICES
        bne _lgf_y

        ; Z axis pointer -> zp_anim_ptr
        ldx grunt_frame
        lda grunt_vz_lo,x
        sta zp_anim_ptr
        lda grunt_vz_hi,x
        sta zp_anim_ptr+1

        ; Copy Z coordinates
        ldy #0
_lgf_z  lda (zp_anim_ptr),y
        sta mesh_vz,y
        iny
        cpy #GRUNT_NUM_VERTICES
        bne _lgf_z

        rts

; ============================================================================
; advance_grunt_frame - Move to next animation frame
; ============================================================================
advance_grunt_frame
        inc grunt_frame
        lda grunt_frame
        cmp #GRUNT_NUM_FRAMES
        bcc _agf_ok
        lda #0
        sta grunt_frame
_agf_ok
        jmp load_grunt_frame    ; Tail call

; ============================================================================
; 3D MESH LOOKUP TABLES
; ============================================================================

; Rotation tables: cos(theta) * 127 and sin(theta) * 127 in s0.7 format
; theta = 0..255 maps to 0..2*pi radians
; Values range from -127 to +127
rcos
        .for i = 0, i < 256, i += 1
            .char round(cos(i * 2 * 3.14159265358979 / 256) * 127)
        .endfor

rsin
        .for i = 0, i < 256, i += 1
            .char round(sin(i * 2 * 3.14159265358979 / 256) * 127)
        .endfor
