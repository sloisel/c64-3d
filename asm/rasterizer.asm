; rasterizer.asm - C64 Triangle Rasterizer
; 64tass syntax
;
; Port of c/rasterize.c to 6502 assembly.
; Uses chunky pixel mode: 80×50 pixels in 1000-byte buffer (40×25 characters).
; Each byte encodes 4 pixels at 2 bits each:
;   bits 7-6: top-left, bits 5-4: top-right
;   bits 3-2: bottom-left, bits 1-0: bottom-right
;
; Requires: main.asm (for zero page allocations, constants, math routines)
;           macros.asm (for mul8x8_signed_m)

; ============================================================================
; ROUTINE: draw_triangle
; ============================================================================
; Draw a filled triangle with backface culling.
;
; Input: zp_ax, zp_ay = Vertex A
;        zp_bx, zp_by = Vertex B
;        zp_cx, zp_cy = Vertex C
;        zp_color = Color (0-3)
;
; Output: Triangle drawn to screen (or culled if backfacing)
;
; Destroys: A, X, Y, all zp temporaries
; ============================================================================

draw_triangle
        ; ----------------------------------------------------------------
        ; Step 1: Backface culling
        ; det = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax)
        ; Cull if det < 0 (clockwise winding)
        ; ----------------------------------------------------------------

        ; Compute (bx - ax)
        lda zp_bx
        sec
        sbc zp_ax
        sta zp_det_t1           ; t1 = bx - ax (signed)

        ; Compute (cy - ay)
        lda zp_cy
        sec
        sbc zp_ay
        sta zp_det_t2           ; t2 = cy - ay (signed)

        ; Compute (by - ay)
        lda zp_by
        sec
        sbc zp_ay
        sta zp_det_t3           ; t3 = by - ay (signed)

        ; Compute (cx - ax)
        lda zp_cx
        sec
        sbc zp_ax
        sta zp_det_t4           ; t4 = cx - ax (signed)

        ; First product: (bx-ax) * (cy-ay)
        lda zp_det_t1
        ldy zp_det_t2
        #mul8x8_signed_m         ; Result in A:Y (high:low)
        ; Save result
        sty _det_prod1_lo
        sta _det_prod1_hi

        ; Second product: (by-ay) * (cx-ax)
        lda zp_det_t3
        ldy zp_det_t4
        #mul8x8_signed_m         ; Result in A:Y (high:low)
        ; A:Y = prod2 (by-ay)*(cx-ax)
        sty _det_prod2_lo
        sta _det_prod2_hi

        ; Compute det = prod1 - prod2 (signed 16-bit subtraction)
        ; If det < 0, cull (check sign bit of result)
        sec
        lda _det_prod1_lo
        sbc _det_prod2_lo
        sta _det_result_lo      ; Low byte of det (not needed, just for completeness)
        lda _det_prod1_hi
        sbc _det_prod2_hi       ; High byte of det - sign bit in bit 7
        bmi _cull               ; det < 0, backface cull
        bne _no_cull            ; det > 0 (high byte != 0 and positive)
        ; High byte is 0, check low byte
        lda _det_result_lo
        beq _cull               ; det == 0, degenerate triangle, cull
        ; det > 0, don't cull
        jmp _no_cull

_cull
        rts                     ; Backface: don't draw

_no_cull
        ; ----------------------------------------------------------------
        ; Step 2: Sort vertices by Y coordinate
        ; Use 3-comparison sorting network (optimal for 3 elements)
        ; Track swap parity for b_on_left derivation
        ; ----------------------------------------------------------------

        lda #0
        sta zp_swaps

        ; Compare A.y vs B.y
        lda zp_ay
        cmp zp_by
        bcc +                   ; A.y < B.y, no swap needed
        beq +                   ; A.y == B.y, no swap needed
        ; Swap A and B
        ldx zp_ax
        lda zp_bx
        sta zp_ax
        stx zp_bx
        ldx zp_ay
        lda zp_by
        sta zp_ay
        stx zp_by
        inc zp_swaps
+
        ; Compare B.y vs C.y
        lda zp_by
        cmp zp_cy
        bcc +                   ; B.y < C.y, no swap needed
        beq +
        ; Swap B and C
        ldx zp_bx
        lda zp_cx
        sta zp_bx
        stx zp_cx
        ldx zp_by
        lda zp_cy
        sta zp_by
        stx zp_cy
        inc zp_swaps
+
        ; Compare A.y vs B.y again (after possible B/C swap)
        lda zp_ay
        cmp zp_by
        bcc +
        beq +
        ; Swap A and B
        ldx zp_ax
        lda zp_bx
        sta zp_ax
        stx zp_bx
        ldx zp_ay
        lda zp_by
        sta zp_ay
        stx zp_by
        inc zp_swaps
+
        ; Now: zp_ay <= zp_by <= zp_cy

        ; ----------------------------------------------------------------
        ; Step 3: Check for degenerate triangle (zero height)
        ; ----------------------------------------------------------------

        lda zp_ay
        cmp zp_cy
        bne +
        rts                     ; ay == cy, degenerate triangle
+
        ; ----------------------------------------------------------------
        ; Step 4: Determine b_on_left from swap parity
        ; b_on_left = (swaps & 1)
        ; ----------------------------------------------------------------

        lda zp_swaps
        and #1
        sta zp_b_on_left

        ; ----------------------------------------------------------------
        ; Step 5: Compute long edge slope (A to C)
        ; dx_ac = ((cx - ax) << 8) / (cy - ay)
        ; ----------------------------------------------------------------

        lda zp_cx
        sec
        sbc zp_ax
        sta zp_dx_temp          ; dx = cx - ax (signed)

        lda zp_cy
        sec
        sbc zp_ay               ; dy = cy - ay (unsigned, > 0)
        tax                     ; X = divisor

        lda zp_dx_temp          ; A = dividend (signed)
        jsr div8s_8u_v2         ; Result in Y:A (hi:lo), also in div_result_hi:div_result_lo

        sta zp_dx_ac_lo
        sty zp_dx_ac_hi

        ; Precompute dx_ac * 2 for dual-row advancement
        asl a                   ; A still has dx_ac_lo
        sta zp_dx_ac2_lo
        tya                     ; Y has dx_ac_hi
        rol a
        sta zp_dx_ac2_hi

        ; ----------------------------------------------------------------
        ; Step 6: Initialize x_long with half-pixel offset
        ; x_long = (ax << 8) + (dx_ac >> 1)
        ; ----------------------------------------------------------------

        ; Start with ax << 8
        lda #0
        sta zp_x_long_lo
        lda zp_ax
        sta zp_x_long_hi

        ; Add dx_ac >> 1 (arithmetic right shift for signed)
        lda zp_dx_ac_hi
        cmp #$80                ; Check sign
        ror a                   ; Arithmetic right shift high byte
        sta _temp_half_hi
        lda zp_dx_ac_lo
        ror a                   ; Rotate through carry
        sta _temp_half_lo

        ; Add to x_long
        clc
        lda zp_x_long_lo
        adc _temp_half_lo
        sta zp_x_long_lo
        lda zp_x_long_hi
        adc _temp_half_hi
        sta zp_x_long_hi

        ; ----------------------------------------------------------------
        ; Step 7: Initialize current Y
        ; ----------------------------------------------------------------

        lda zp_ay
        sta zp_y

        ; ----------------------------------------------------------------
        ; Step 8: Top trapezoid (A.y to B.y)
        ; ----------------------------------------------------------------

        lda zp_ay
        cmp zp_by
        bcs _skip_top_trap      ; ay >= by, skip top trapezoid

        ; Compute short edge slope (A to B)
        ; dx_ab = ((bx - ax) << 8) / (by - ay)
        lda zp_bx
        sec
        sbc zp_ax
        sta zp_dx_temp          ; dx = bx - ax (signed)

        lda zp_by
        sec
        sbc zp_ay               ; dy = by - ay (unsigned, > 0)
        tax

        lda zp_dx_temp
        jsr div8s_8u_v2

        sta zp_dx_short_lo
        sty zp_dx_short_hi

        ; Precompute dx_short * 2 for dual-row advancement
        asl a                   ; A still has dx_short_lo
        sta zp_dx_short2_lo
        tya                     ; Y has dx_short_hi
        rol a
        sta zp_dx_short2_hi

        ; Initialize x_short = (ax << 8) + (dx_ab >> 1)
        lda #0
        sta zp_x_short_lo
        lda zp_ax
        sta zp_x_short_hi

        ; Add dx_short >> 1 (arithmetic right shift)
        lda zp_dx_short_hi
        cmp #$80
        ror a
        sta _temp_half_hi
        lda zp_dx_short_lo
        ror a
        sta _temp_half_lo

        clc
        lda zp_x_short_lo
        adc _temp_half_lo
        sta zp_x_short_lo
        lda zp_x_short_hi
        adc _temp_half_hi
        sta zp_x_short_hi

        ; Set trapezoid end
        lda zp_by
        sta zp_y_end

        ; Rasterize top trapezoid
        jsr rasterize_trapezoid

_skip_top_trap
        ; ----------------------------------------------------------------
        ; Step 9: Bottom trapezoid (B.y to C.y)
        ; ----------------------------------------------------------------

        lda zp_by
        cmp zp_cy
        bcs _done_triangle      ; by >= cy, skip bottom trapezoid

        ; Compute short edge slope (B to C)
        ; dx_bc = ((cx - bx) << 8) / (cy - by)
        lda zp_cx
        sec
        sbc zp_bx
        sta zp_dx_temp          ; dx = cx - bx (signed)

        lda zp_cy
        sec
        sbc zp_by               ; dy = cy - by (unsigned, > 0)
        tax

        lda zp_dx_temp
        jsr div8s_8u_v2

        sta zp_dx_short_lo
        sty zp_dx_short_hi

        ; Precompute dx_short * 2 for dual-row advancement
        asl a                   ; A still has dx_short_lo
        sta zp_dx_short2_lo
        tya                     ; Y has dx_short_hi
        rol a
        sta zp_dx_short2_hi

        ; Initialize x_short = (bx << 8) + (dx_bc >> 1)
        ; NOTE: x_long continues from where top trapezoid left off
        lda #0
        sta zp_x_short_lo
        lda zp_bx
        sta zp_x_short_hi

        ; Add dx_short >> 1
        lda zp_dx_short_hi
        cmp #$80
        ror a
        sta _temp_half_hi
        lda zp_dx_short_lo
        ror a
        sta _temp_half_lo

        clc
        lda zp_x_short_lo
        adc _temp_half_lo
        sta zp_x_short_lo
        lda zp_x_short_hi
        adc _temp_half_hi
        sta zp_x_short_hi

        ; Update Y position (should already be at by from top trap, or ay if no top trap)
        lda zp_by
        sta zp_y

        ; Set trapezoid end
        lda zp_cy
        sta zp_y_end

        ; Rasterize bottom trapezoid
        jsr rasterize_trapezoid

_done_triangle
        rts

; Temporary storage
_det_prod1_lo   .byte 0
_det_prod1_hi   .byte 0
_det_prod2_lo   .byte 0
_det_prod2_hi   .byte 0
_det_result_lo  .byte 0
_temp_half_lo   .byte 0
_temp_half_hi   .byte 0

; ============================================================================
; ROUTINE: rasterize_trapezoid
; ============================================================================
; Rasterize a trapezoid from zp_y to zp_y_end.
; Uses x_long and x_short edges with their respective slopes.
;
; Input: zp_y = starting scanline
;        zp_y_end = ending scanline (exclusive)
;        zp_x_long_*, zp_dx_ac_* = long edge state
;        zp_x_short_*, zp_dx_short_* = short edge state
;        zp_b_on_left = which edge is left
;        zp_color = triangle color
;
; Destroys: A, X, Y, various temporaries
; ============================================================================

rasterize_trapezoid
_trap_loop
        ; Check if done
        lda zp_y
        cmp zp_y_end
        bcc _trap_continue
        rts                     ; Done with trapezoid

_trap_continue
        ; Get x endpoints for current scanline
        ; xl = (b_on_left ? x_short : x_long) >> 8
        ; xr = (b_on_left ? x_long : x_short) >> 8
        lda zp_b_on_left
        beq _long_is_left

        ; b_on_left: short is left, long is right
        ; [xl, xr) convention - xl inclusive, xr exclusive
        lda zp_x_short_hi
        sta zp_xl
        lda zp_x_long_hi
        sta zp_xr
        jmp _got_endpoints

_long_is_left
        ; !b_on_left: long is left, short is right
        lda zp_x_long_hi
        sta zp_xl
        lda zp_x_short_hi
        sta zp_xr

_got_endpoints
        ; Ensure xl < xr (swap if needed)
        lda zp_xl
        cmp zp_xr
        bcc _no_swap_xl
        beq _no_swap_xl
        ; Swap
        ldx zp_xr
        sta zp_xr
        stx zp_xl
_no_swap_xl
        ; Check if we can do dual-row optimization
        lda zp_y
        tax                     ; Save original Y in X
        and #1
        bne _odd_scanline       ; Odd y: single span
        ; Even y: check if next scanline is within trapezoid (X still has zp_y)
        txa
        clc
        adc #1
        cmp zp_y_end
        bcc _do_dual_row        ; y+1 < y_end, can do dual row
        jmp _single_even_row    ; y+1 >= y_end, no second row

_do_dual_row

        ; ----------------------------------------------------------------
        ; Dual-row case: process two scanlines at once
        ; ----------------------------------------------------------------

        ; Compute second row edge positions
        ; x_long2 = x_long + dx_ac
        clc
        lda zp_x_long_lo
        adc zp_dx_ac_lo
        sta zp_x_long2_lo
        lda zp_x_long_hi
        adc zp_dx_ac_hi
        sta zp_x_long2_hi

        ; x_short2 = x_short + dx_short
        clc
        lda zp_x_short_lo
        adc zp_dx_short_lo
        sta zp_x_short2_lo
        lda zp_x_short_hi
        adc zp_dx_short_hi
        sta zp_x_short2_hi

        ; Get second row endpoints [xl2, xr2)
        lda zp_b_on_left
        beq _long_is_left2

        lda zp_x_short2_hi
        sta zp_xl2
        lda zp_x_long2_hi
        sta zp_xr2
        jmp _got_endpoints2

_long_is_left2
        lda zp_x_long2_hi
        sta zp_xl2
        lda zp_x_short2_hi
        sta zp_xr2

_got_endpoints2
        ; Ensure xl2 < xr2 (swap if needed)
        lda zp_xl2
        cmp zp_xr2
        bcc +
        beq +
        ldx zp_xr2
        sta zp_xr2
        stx zp_xl2
+
        ; Draw dual row using interval-based blitter
        jsr draw_dual_row_intervals

        ; Advance edges by 2 * slope (using precomputed dx*2)
        ; x_long += dx_ac * 2
        clc
        lda zp_x_long_lo
        adc zp_dx_ac2_lo
        sta zp_x_long_lo
        lda zp_x_long_hi
        adc zp_dx_ac2_hi
        sta zp_x_long_hi

        ; x_short += dx_short * 2
        clc
        lda zp_x_short_lo
        adc zp_dx_short2_lo
        sta zp_x_short_lo
        lda zp_x_short_hi
        adc zp_dx_short2_hi
        sta zp_x_short_hi

        ; Advance y by 2
        lda zp_y
        clc
        adc #2
        sta zp_y
        jmp _trap_loop

_single_even_row
        ; Even y but no second row available - draw top row only
        jsr draw_span_top
        jmp _advance_one

_odd_scanline
        ; Odd y: draw single span on bottom row
        jsr draw_span_bottom

_advance_one
        ; Advance edges by one slope
        clc
        lda zp_x_long_lo
        adc zp_dx_ac_lo
        sta zp_x_long_lo
        lda zp_x_long_hi
        adc zp_dx_ac_hi
        sta zp_x_long_hi

        clc
        lda zp_x_short_lo
        adc zp_dx_short_lo
        sta zp_x_short_lo
        lda zp_x_short_hi
        adc zp_dx_short_hi
        sta zp_x_short_hi

        ; Advance y by 1
        inc zp_y
        jmp _trap_loop

; ============================================================================
; ROUTINE: draw_span_top
; ============================================================================
; Draw a horizontal span on a TOP row (y is even).
; Only modifies top 4 bits of each character byte, preserving bottom row.
; Assumes all coordinates are on-screen.
;
; Input: zp_y = scanline (even)
;        zp_xl = left X (inclusive)
;        zp_xr = right X (exclusive)
;        zp_color = color (0-3)
;
; Destroys: A, X, Y
; ============================================================================

draw_span_top
        ; Early exit if xl >= xr
        lda zp_xl
        cmp zp_xr
        bcc _dst_start
        rts
_dst_start
        ; Compute screen row address
        lda zp_y
        lsr a
        tax
        lda row_offset_lo,x
        sta zp_screen_lo
        lda row_offset_hi,x
        clc
smc_screen_hi_1 = * + 1         ; SMC: patch this byte
        adc #>SCREEN_RAM
        sta zp_screen_hi

        ; Build color bits for top row: (color << 6) | (color << 4)
        ; Store in zp_adj_lo for fast inner loop access
        ldx zp_color
        lda color_top,x
        sta zp_adj_lo           ; reuse as color_bits (ZP = 3 cycle ora)

        ; Compute char ranges
        ; char_start = xl >> 1
        lda zp_xl
        lsr a
        sta _dst_char_start
        ; full_start = (xl + 1) >> 1
        lda zp_xl
        clc
        adc #1
        lsr a
        sta _dst_full_start
        ; full_end = xr >> 1 - store in ZP for fast cpy
        lda zp_xr
        lsr a
        sta zp_adj_hi           ; reuse as full_end (ZP = 3 cycle cpy)

        ; Left partial (if char_start < full_start, i.e., xl is odd)
        lda _dst_char_start
        cmp _dst_full_start
        bcs _dst_full_loop
        ; RMW with mask $30 (right pixel only)
        tay
        lda zp_adj_lo
        and #$30                ; mask to right pixel only
        sta _dst_temp
        lda (zp_screen_lo),y
        and #$cf                ; ~$30, clear right pixel
        ora _dst_temp           ; set right pixel with color
        sta (zp_screen_lo),y

_dst_full_loop
        ldy _dst_full_start
_dst_full_next
        cpy zp_adj_hi           ; 3 cycles (ZP) vs 4 cycles (abs)
        bcs _dst_right_partial
        ; RMW with mask $F0 (both pixels)
        lda (zp_screen_lo),y
        and #$0f                ; ~$F0
        ora zp_adj_lo           ; 3 cycles (ZP) vs 4 cycles (abs)
        sta (zp_screen_lo),y
        iny
        bne _dst_full_next      ; Always taken (Y < 40)

_dst_right_partial
        ; Check if xr is odd (right partial needed)
        lda zp_xr
        lsr a
        bcc _dst_done
        ; RMW with mask $C0 (left pixel only)
        ; Y = full_end
        lda zp_adj_lo
        and #$c0                ; mask to left pixel only
        sta _dst_temp
        lda (zp_screen_lo),y
        and #$3f                ; ~$C0, clear left pixel
        ora _dst_temp           ; set left pixel with color
        sta (zp_screen_lo),y

_dst_done
        rts

; Temporaries for draw_span_top
_dst_char_start .byte 0
_dst_full_start .byte 0
_dst_temp       .byte 0

; ============================================================================
; ROUTINE: draw_span_bottom
; ============================================================================
; Draw a horizontal span on a BOTTOM row (y is odd).
; Only modifies bottom 4 bits of each character byte, preserving top row.
; Assumes all coordinates are on-screen.
;
; Input: zp_y = scanline (odd)
;        zp_xl = left X (inclusive)
;        zp_xr = right X (exclusive)
;        zp_color = color (0-3)
;
; Destroys: A, X, Y
; ============================================================================

draw_span_bottom
        ; Early exit if xl >= xr
        lda zp_xl
        cmp zp_xr
        bcc _dsb_start
        rts
_dsb_start
        ; Compute screen row address (same char row as y-1 for odd y)
        lda zp_y
        lsr a
        tax
        lda row_offset_lo,x
        sta zp_screen_lo
        lda row_offset_hi,x
        clc
smc_screen_hi_2 = * + 1         ; SMC: patch this byte
        adc #>SCREEN_RAM
        sta zp_screen_hi

        ; Build color bits for bottom row: (color << 2) | color
        ; Store in zp_adj_lo for fast inner loop access
        ldx zp_color
        lda color_bottom,x
        sta zp_adj_lo           ; reuse as color_bits (ZP = 3 cycle ora)

        ; Compute char ranges (same as draw_span_top)
        ; char_start = xl >> 1
        lda zp_xl
        lsr a
        sta _dsb_char_start
        ; full_start = (xl + 1) >> 1
        lda zp_xl
        clc
        adc #1
        lsr a
        sta _dsb_full_start
        ; full_end = xr >> 1 - store in ZP for fast cpy
        lda zp_xr
        lsr a
        sta zp_adj_hi           ; reuse as full_end (ZP = 3 cycle cpy)

        ; Left partial (if char_start < full_start, i.e., xl is odd)
        lda _dsb_char_start
        cmp _dsb_full_start
        bcs _dsb_full_loop
        ; RMW with mask $03 (right pixel only)
        tay
        lda zp_adj_lo
        and #$03                ; mask to right pixel only
        sta _dsb_temp
        lda (zp_screen_lo),y
        and #$fc                ; ~$03, clear right pixel
        ora _dsb_temp           ; set right pixel with color
        sta (zp_screen_lo),y

_dsb_full_loop
        ldy _dsb_full_start
_dsb_full_next
        cpy zp_adj_hi           ; 3 cycles (ZP) vs 4 cycles (abs)
        bcs _dsb_right_partial
        ; RMW with mask $0F (both pixels)
        lda (zp_screen_lo),y
        and #$f0                ; ~$0F
        ora zp_adj_lo           ; 3 cycles (ZP) vs 4 cycles (abs)
        sta (zp_screen_lo),y
        iny
        bne _dsb_full_next      ; Always taken (Y < 40)

_dsb_right_partial
        ; Check if xr is odd (right partial needed)
        lda zp_xr
        lsr a
        bcc _dsb_done
        ; RMW with mask $0C (left pixel only)
        ; Y = full_end
        lda zp_adj_lo
        and #$0c                ; mask to left pixel only
        sta _dsb_temp
        lda (zp_screen_lo),y
        and #$f3                ; ~$0C, clear left pixel
        ora _dsb_temp           ; set left pixel with color
        sta (zp_screen_lo),y

_dsb_done
        rts

; Temporaries for draw_span_bottom
_dsb_char_start .byte 0
_dsb_full_start .byte 0
_dsb_temp       .byte 0

; ============================================================================
; ROUTINE: draw_dual_row_simple
; ============================================================================
; Draw both rows on interval [xl, xr) where BOTH rows are fully active.
; y is the top scanline (must be even).
; This is much simpler than the general case - no per-row boundary logic.
;
; Input: zp_y = scanline (even)
;        zp_xl = left X (inclusive)
;        zp_xr = right X (exclusive)
;        zp_color = color (0-3)
;
; Destroys: A, X, Y
; ============================================================================

draw_dual_row_simple
        ; Early exit if xl >= xr
        lda zp_xl
        cmp zp_xr
        bcc _drs_start
        rts
_drs_start
        ; Compute screen row address
        lda zp_y
        lsr a
        tax
        lda row_offset_lo,x
        sta zp_screen_lo
        lda row_offset_hi,x
        clc
smc_screen_hi_3 = * + 1         ; SMC: patch this byte
        adc #>SCREEN_RAM
        sta zp_screen_hi

        ; Build full color pattern
        ldx zp_color
        lda color_pattern,x
        sta _drs_color_byte

        ; Compute char ranges
        ; char_start = xl >> 1
        lda zp_xl
        lsr a
        sta _drs_char_start
        ; full_start = (xl + 1) >> 1
        lda zp_xl
        clc
        adc #1
        lsr a
        sta _drs_full_start
        ; full_end = xr >> 1
        lda zp_xr
        lsr a
        sta _drs_full_end

        ; Left partial (if char_start < full_start, i.e., xl is odd)
        lda _drs_char_start
        cmp _drs_full_start
        bcs _drs_full_loop
        ; RMW with mask $33 (right pixels only)
        tay
        lda _drs_color_byte
        and #$33                ; mask to right pixels only
        sta _drs_temp
        lda (zp_screen_lo),y
        and #$cc                ; ~$33, clear right pixels
        ora _drs_temp           ; set right pixels with color
        sta (zp_screen_lo),y

_drs_full_loop
        ; SMC version: 10 cycles/char inner loop
        ; Patch address = screen + full_start, X counts down from count-1 to 0
        clc
        lda zp_screen_lo
        adc _drs_full_start
        sta _drs_smc_sta + 1
        lda zp_screen_hi
        adc #0
        sta _drs_smc_sta + 2

        ; X = count - 1 = full_end - full_start - 1
        lda _drs_full_end
        sec
        sbc _drs_full_start
        beq _drs_right_partial  ; count = 0, skip
        tax
        dex
        bmi _drs_right_partial  ; count = 1 but underflowed (shouldn't happen, but safe)

        lda _drs_color_byte
_drs_smc_sta
        sta $ffff,x             ; 5 cycles - address gets patched
        dex                     ; 2 cycles
        bpl _drs_smc_sta        ; 3 cycles = 10 total

_drs_right_partial
        ; Check if xr is odd (right partial needed)
        lda zp_xr
        lsr a                   ; carry = xr & 1
        bcc _drs_done           ; xr even, no right partial
        ; RMW with mask $CC (left pixels only)
        ldy _drs_full_end       ; Restore Y (was 0 after fast loop)
        lda _drs_color_byte
        and #$cc                ; Keep only left pixel bits
        sta _drs_temp
        lda (zp_screen_lo),y
        and #$33                ; ~$CC
        ora _drs_temp
        sta (zp_screen_lo),y

_drs_done
        rts

; Temporaries for draw_dual_row_simple
_drs_color_byte .byte 0
_drs_char_start .byte 0
_drs_full_start .byte 0
_drs_full_end   .byte 0
_drs_temp       .byte 0

; ============================================================================
; ROUTINE: draw_dual_row_intervals
; ============================================================================
; Interval-based dual-row blitter using decision tree.
; y is the top scanline (must be even).
; xl1, xr1: interval for row 1 (top row, y)
; xl2, xr2: interval for row 2 (bottom row, y+1)
;
; Uses 2-3 comparisons to determine ordering, then calls appropriate
; blitter (single-row or dual-row) for each interval.
;
; Input: zp_y = top scanline (even)
;        zp_xl, zp_xr = top row interval [xl1, xr1)
;        zp_xl2, zp_xr2 = bottom row interval [xl2, xr2)
;        zp_color = color (0-3)
;
; Destroys: A, X, Y
; ============================================================================

draw_dual_row_intervals
        ; Save original y for restoration
        lda zp_y
        sta _dri_saved_y

        ; Handle empty rows first
        ; Check if row 1 empty (xl >= xr)
        lda zp_xl
        cmp zp_xr
        bcc _dri_row1_valid
        ; Row 1 empty, check row 2
        lda zp_xl2
        cmp zp_xr2
        bcc +                   ; Row 2 valid, draw it
        rts                     ; Both empty, return
+
        ; Only row 2: draw_span_bottom(y+1, xl2, xr2)
        ; Need to set up zp_xl/xr from xl2/xr2, and y = y+1
        inc zp_y                ; y+1 for bottom row
        lda zp_xl2
        sta zp_xl
        lda zp_xr2
        sta zp_xr
        jsr draw_span_bottom
        jmp _dri_restore_y

_dri_row1_valid
        ; Row 1 valid, check row 2
        lda zp_xl2
        cmp zp_xr2
        bcc _dri_both_valid
        ; Only row 1: draw_span_top(y, xl1, xr1)
        jmp draw_span_top

_dri_both_valid
        ; Both rows valid - use decision tree
        ; Compare xl1 vs xl2
        lda zp_xl               ; xl1
        cmp zp_xl2              ; xl2
        beq _dri_xl1_le_xl2     ; xl1 == xl2
        bcc _dri_xl1_le_xl2     ; xl1 < xl2
        jmp _dri_xl2_less       ; xl1 > xl2 (so xl2 < xl1)
_dri_xl1_le_xl2
        ; xl1 <= xl2
        ; Compare xr2 vs xr1
        lda zp_xr2              ; xr2
        cmp zp_xr               ; xr1
        beq _dri_case1          ; xr2 == xr1
        bcs _dri_xr2_gt_xr1     ; xr2 > xr1
        ; xr2 < xr1: CASE 1
_dri_case1
        ; CASE 1: Row 2 inside row 1
        ; Order: xl1 <= xl2 <= xr2 <= xr1
        ; Intervals: [xl1,xl2)={1}, [xl2,xr2)={1,2}, [xr2,xr1)={1}

        ; Save xr1 for third segment
        lda zp_xr
        sta _dri_saved_xr1

        ; First: draw_span_top(y, xl1, xl2)
        lda zp_xl2
        sta zp_xr               ; xr = xl2
        jsr draw_span_top

        ; Second: draw_dual_row_simple(y, xl2, xr2)
        lda zp_xl2
        sta zp_xl               ; xl = xl2
        lda zp_xr2
        sta zp_xr               ; xr = xr2
        jsr draw_dual_row_simple

        ; Third: draw_span_top(y, xr2, xr1)
        lda zp_xr2
        sta zp_xl               ; xl = xr2
        lda _dri_saved_xr1
        sta zp_xr               ; xr = xr1
        jmp draw_span_top

_dri_xr2_gt_xr1
        ; xr2 > xr1: need third comparison for overlap check
        ; Compare xl2 vs xr1
        lda zp_xl2              ; xl2
        cmp zp_xr               ; xr1
        beq _dri_case2_1        ; xl2 == xr1 (overlapping at boundary)
        bcs _dri_case2_2        ; xl2 > xr1 (disjoint)
        ; xl2 < xr1: CASE 2.1 (overlapping)
_dri_case2_1
        ; CASE 2.1: Overlapping
        ; Order: xl1 <= xl2 <= xr1 <= xr2
        ; Intervals: [xl1,xl2)={1}, [xl2,xr1)={1,2}, [xr1,xr2)={2}

        ; Save xr1, xr2 for later segments
        lda zp_xr
        sta _dri_saved_xr1
        lda zp_xr2
        sta _dri_saved_xr2

        ; First: draw_span_top(y, xl1, xl2)
        lda zp_xl2
        sta zp_xr               ; xr = xl2
        jsr draw_span_top

        ; Second: draw_dual_row_simple(y, xl2, xr1)
        lda zp_xl2
        sta zp_xl               ; xl = xl2
        lda _dri_saved_xr1
        sta zp_xr               ; xr = xr1
        jsr draw_dual_row_simple

        ; Third: draw_span_bottom(y+1, xr1, xr2)
        inc zp_y                ; y+1 for bottom row
        lda _dri_saved_xr1
        sta zp_xl               ; xl = xr1
        lda _dri_saved_xr2
        sta zp_xr               ; xr = xr2
        jsr draw_span_bottom
        jmp _dri_restore_y

_dri_case2_2
        ; CASE 2.2: Disjoint (empty middle)
        ; Order: xl1 <= xr1 < xl2 <= xr2
        ; Intervals: [xl1,xr1)={1}, [xr1,xl2)={}, [xl2,xr2)={2}

        ; Save xl2, xr2 for second segment
        lda zp_xl2
        sta _dri_saved_xl2
        lda zp_xr2
        sta _dri_saved_xr2

        ; First: draw_span_top(y, xl1, xr1)
        jsr draw_span_top

        ; Second: draw_span_bottom(y+1, xl2, xr2)
        inc zp_y                ; y+1 for bottom row
        lda _dri_saved_xl2
        sta zp_xl               ; xl = xl2
        lda _dri_saved_xr2
        sta zp_xr               ; xr = xr2
        jsr draw_span_bottom
        jmp _dri_restore_y

_dri_xl2_less
        ; xl2 < xl1
        ; Compare xr1 vs xr2
        lda zp_xr               ; xr1
        cmp zp_xr2              ; xr2
        bcs _dri_xr2_le_xr1     ; xr2 <= xr1
        ; xr1 < xr2: CASE 4
_dri_case4
        ; CASE 4: Row 1 inside row 2
        ; Order: xl2 < xl1 <= xr1 < xr2
        ; Intervals: [xl2,xl1)={2}, [xl1,xr1)={1,2}, [xr1,xr2)={2}

        ; Save xl1, xr1, xr2 for later segments
        lda zp_xl
        sta _dri_saved_xl1
        lda zp_xr
        sta _dri_saved_xr1
        lda zp_xr2
        sta _dri_saved_xr2

        ; First: draw_span_bottom(y+1, xl2, xl1)
        inc zp_y                ; y+1 for bottom row
        lda zp_xl2
        sta zp_xl               ; xl = xl2
        lda _dri_saved_xl1
        sta zp_xr               ; xr = xl1
        jsr draw_span_bottom

        ; Second: draw_dual_row_simple(y, xl1, xr1)
        dec zp_y                ; back to y for dual row
        lda _dri_saved_xl1
        sta zp_xl               ; xl = xl1
        lda _dri_saved_xr1
        sta zp_xr               ; xr = xr1
        jsr draw_dual_row_simple

        ; Third: draw_span_bottom(y+1, xr1, xr2)
        inc zp_y                ; y+1 for bottom row
        lda _dri_saved_xr1
        sta zp_xl               ; xl = xr1
        lda _dri_saved_xr2
        sta zp_xr               ; xr = xr2
        jsr draw_span_bottom
        jmp _dri_restore_y

_dri_xr2_le_xr1
        ; xr2 <= xr1: need third comparison for overlap check
        ; Compare xl1 vs xr2
        lda zp_xl               ; xl1
        cmp zp_xr2              ; xr2
        beq _dri_case3_1        ; xl1 == xr2 (overlapping at boundary)
        bcs _dri_case3_2        ; xl1 > xr2 (disjoint)
        ; xl1 < xr2: CASE 3.1 (overlapping)
_dri_case3_1
        ; CASE 3.1: Overlapping
        ; Order: xl2 < xl1 <= xr2 <= xr1
        ; Intervals: [xl2,xl1)={2}, [xl1,xr2)={1,2}, [xr2,xr1)={1}

        ; Save xl1, xr1, xr2 for later segments
        lda zp_xl
        sta _dri_saved_xl1
        lda zp_xr
        sta _dri_saved_xr1
        lda zp_xr2
        sta _dri_saved_xr2

        ; First: draw_span_bottom(y+1, xl2, xl1)
        inc zp_y                ; y+1 for bottom row
        lda zp_xl2
        sta zp_xl               ; xl = xl2
        lda _dri_saved_xl1
        sta zp_xr               ; xr = xl1
        jsr draw_span_bottom

        ; Second: draw_dual_row_simple(y, xl1, xr2)
        dec zp_y                ; back to y for dual row
        lda _dri_saved_xl1
        sta zp_xl               ; xl = xl1
        lda _dri_saved_xr2
        sta zp_xr               ; xr = xr2
        jsr draw_dual_row_simple

        ; Third: draw_span_top(y, xr2, xr1)
        lda _dri_saved_xr2
        sta zp_xl               ; xl = xr2
        lda _dri_saved_xr1
        sta zp_xr               ; xr = xr1
        jmp draw_span_top

_dri_case3_2
        ; CASE 3.2: Disjoint (empty middle)
        ; Order: xl2 <= xr2 < xl1 <= xr1
        ; Intervals: [xl2,xr2)={2}, [xr2,xl1)={}, [xl1,xr1)={1}

        ; Save xl1, xr1 for second segment
        lda zp_xl
        sta _dri_saved_xl1
        lda zp_xr
        sta _dri_saved_xr1

        ; First: draw_span_bottom(y+1, xl2, xr2)
        inc zp_y                ; y+1 for bottom row
        lda zp_xl2
        sta zp_xl               ; xl = xl2
        lda zp_xr2
        sta zp_xr               ; xr = xr2
        jsr draw_span_bottom

        ; Second: draw_span_top(y, xl1, xr1)
        dec zp_y                ; back to y for top row
        lda _dri_saved_xl1
        sta zp_xl               ; xl = xl1
        lda _dri_saved_xr1
        sta zp_xr               ; xr = xr1
        jmp draw_span_top

_dri_restore_y
        lda _dri_saved_y
        sta zp_y
        rts

; Temporaries for draw_dual_row_intervals
_dri_saved_y    .byte 0
_dri_saved_xl1  .byte 0
_dri_saved_xr1  .byte 0
_dri_saved_xl2  .byte 0
_dri_saved_xr2  .byte 0

; ============================================================================
; ROUTINE: set_pixel_v2
; ============================================================================
; Set a single chunky pixel.
;
; Input: X = x coordinate (0-79)
;        Y = y coordinate (0-49)
;        A = color (0-3)
;
; Destroys: A, X, Y, zp_screen_lo/hi (temporarily)
; ============================================================================

set_pixel_v2
        ; Save inputs
        sta _sp2_color
        stx _sp2_x
        sty _sp2_y

        ; Bounds check
        cpx #SCREEN_WIDTH
        bcs _sp2_done
        cpy #SCREEN_HEIGHT
        bcs _sp2_done

        ; char_x = x >> 1
        txa
        lsr a
        sta _sp2_char_x

        ; char_y = y >> 1
        tya
        lsr a
        tax                     ; X = char_y for table lookup

        ; Screen address = SCREEN_RAM + row_offset[char_y] + char_x
        lda row_offset_lo,x
        clc
        adc _sp2_char_x
        sta zp_screen_lo
        lda row_offset_hi,x
smc_screen_hi_4 = * + 1         ; SMC: patch this byte
        adc #>SCREEN_RAM
        sta zp_screen_hi

        ; Determine pixel position within character
        ; sub_x = x & 1, sub_y = y & 1
        lda _sp2_x
        and #1
        sta _sp2_sub_x          ; 0=left, 1=right

        lda _sp2_y
        and #1
        sta _sp2_sub_y          ; 0=top, 1=bottom

        ; Compute shift and mask based on position
        ; Position: TL=00, TR=01, BL=10, BR=11 (sub_y*2 + sub_x)
        asl a                   ; sub_y << 1
        ora _sp2_sub_x          ; | sub_x
        tax                     ; X = position index (0-3)

        lda pixel_shift,x
        sta _sp2_shift
        lda pixel_mask,x
        sta _sp2_mask

        ; Read current character
        ldy #0
        lda (zp_screen_lo),y

        ; Clear pixel: AND with inverse mask
        lda _sp2_mask
        eor #$ff                ; ~mask
        sta _sp2_inv_mask

        lda (zp_screen_lo),y
        and _sp2_inv_mask       ; Clear the pixel
        sta _sp2_temp

        ; Shift color to position
        lda _sp2_color
        ldx _sp2_shift
        beq _sp2_no_shift
_sp2_shift_loop
        asl a
        dex
        bne _sp2_shift_loop
_sp2_no_shift
        and _sp2_mask           ; Mask to just the pixel bits
        ora _sp2_temp           ; Combine with cleared screen byte
        sta (zp_screen_lo),y

_sp2_done
        rts

_sp2_color      .byte 0
_sp2_x          .byte 0
_sp2_y          .byte 0
_sp2_char_x     .byte 0
_sp2_sub_x      .byte 0
_sp2_sub_y      .byte 0
_sp2_shift      .byte 0
_sp2_mask       .byte 0
_sp2_inv_mask   .byte 0
_sp2_temp       .byte 0

; ============================================================================
; ROUTINE: clear_screen
; ============================================================================
; Clear the screen to a single color.
;
; Input: A = color (0-3)
;
; Destroys: A, X
; ============================================================================

clear_screen
        tax
        lda color_pattern,x     ; Get replicated color byte
        ldy #0
        ; SMC: patch high bytes (opcode $99, then lo, then hi)
smc_clear_1 = * + 2             ; High byte of first sta
-       sta SCREEN_RAM,y
smc_clear_2 = * + 2
        sta SCREEN_RAM+$100,y
smc_clear_3 = * + 2
        sta SCREEN_RAM+$200,y
smc_clear_4 = * + 2
        sta SCREEN_RAM+$300,y   ; Writes 24 extra bytes past screen (harmless)
        iny
        bne -
        rts

; ============================================================================
; LOOKUP TABLES
; ============================================================================

; Row offset table: maps character row (0-24) to byte offset
; row_offset[y] = y * 40
row_offset_lo
        .for y = 0, y < CHAR_HEIGHT, y += 1
            .byte <(y * CHAR_WIDTH)
        .endfor

row_offset_hi
        .for y = 0, y < CHAR_HEIGHT, y += 1
            .byte >(y * CHAR_WIDTH)
        .endfor

; Top row pixel mask: maps coverage bits to mask
; bits: 1=left pixel set, 0=right pixel set (reversed from intuitive)
; Actually from C: top_bits = (top_left << 1) | top_right
; So: 0=%00=neither, 1=%01=right, 2=%10=left, 3=%11=both
top_row_mask
        .byte $00               ; 0: neither
        .byte PIXEL_TR_MASK     ; 1: right only ($30)
        .byte PIXEL_TL_MASK     ; 2: left only ($C0)
        .byte PIXEL_TL_MASK | PIXEL_TR_MASK  ; 3: both ($F0)

; Bottom row pixel mask
bottom_row_mask
        .byte $00               ; 0: neither
        .byte PIXEL_BR_MASK     ; 1: right only ($03)
        .byte PIXEL_BL_MASK     ; 2: left only ($0C)
        .byte PIXEL_BL_MASK | PIXEL_BR_MASK  ; 3: both ($0F)

; Color pattern: replicate 2-bit color to all 4 pixel positions
; color_pattern[c] = c<<6 | c<<4 | c<<2 | c
color_pattern
        .byte $00               ; Color 0: %00000000
        .byte $55               ; Color 1: %01010101
        .byte $aa               ; Color 2: %10101010
        .byte $ff               ; Color 3: %11111111

; Color patterns for top row only: (c<<6) | (c<<4)
color_top
        .byte $00               ; Color 0
        .byte $50               ; Color 1
        .byte $a0               ; Color 2
        .byte $f0               ; Color 3

; Color patterns for bottom row only: (c<<2) | c
color_bottom
        .byte $00               ; Color 0
        .byte $05               ; Color 1
        .byte $0a               ; Color 2
        .byte $0f               ; Color 3

; Pixel shift amounts for set_pixel
; Index = sub_y*2 + sub_x: TL=0, TR=1, BL=2, BR=3
pixel_shift
        .byte PIXEL_TL_SHIFT    ; 0: top-left = 6
        .byte PIXEL_TR_SHIFT    ; 1: top-right = 4
        .byte PIXEL_BL_SHIFT    ; 2: bottom-left = 2
        .byte PIXEL_BR_SHIFT    ; 3: bottom-right = 0

; Pixel masks for set_pixel
pixel_mask
        .byte PIXEL_TL_MASK     ; 0: top-left = $C0
        .byte PIXEL_TR_MASK     ; 1: top-right = $30
        .byte PIXEL_BL_MASK     ; 2: bottom-left = $0C
        .byte PIXEL_BR_MASK     ; 3: bottom-right = $03

; ============================================================================
; END OF RASTERIZER
; ============================================================================
