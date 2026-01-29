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
        ; Ensure xl <= xr (swap if needed)
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
        and #1
        beq _check_dual_row     ; Even y: check if we can do dual row
        jmp _odd_scanline       ; Odd y: single span

_check_dual_row
        ; Even y: check if next scanline is within trapezoid
        lda zp_y
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

        ; Get second row endpoints
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
        ; Ensure xl2 <= xr2
        lda zp_xl2
        cmp zp_xr2
        bcc +
        beq +
        ldx zp_xr2
        sta zp_xr2
        stx zp_xl2
+
        ; Draw dual row
        jsr draw_dual_row

        ; Advance edges by 2 * slope
        ; x_long += dx_ac * 2
        clc
        lda zp_x_long_lo
        adc zp_dx_ac_lo
        sta zp_x_long_lo
        lda zp_x_long_hi
        adc zp_dx_ac_hi
        sta zp_x_long_hi
        clc
        lda zp_x_long_lo
        adc zp_dx_ac_lo
        sta zp_x_long_lo
        lda zp_x_long_hi
        adc zp_dx_ac_hi
        sta zp_x_long_hi

        ; x_short += dx_short * 2
        clc
        lda zp_x_short_lo
        adc zp_dx_short_lo
        sta zp_x_short_lo
        lda zp_x_short_hi
        adc zp_dx_short_hi
        sta zp_x_short_hi
        clc
        lda zp_x_short_lo
        adc zp_dx_short_lo
        sta zp_x_short_lo
        lda zp_x_short_hi
        adc zp_dx_short_hi
        sta zp_x_short_hi

        ; Advance y by 2
        lda zp_y
        clc
        adc #2
        sta zp_y
        jmp _trap_loop

_single_even_row
        ; Even y but no second row available
        ; Use draw_dual_row with empty second row (xl2 > xr2)
        lda #1
        sta zp_xl2
        lda #0
        sta zp_xr2
        jsr draw_dual_row
        jmp _advance_one

_odd_scanline
        ; Odd y: draw single span using set_pixel loop
        jsr draw_span

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
; ROUTINE: draw_dual_row
; ============================================================================
; Draw two scanlines at once (dual-row optimization).
; zp_y is the top scanline (must be even).
;
; Input: zp_y = top scanline (even)
;        zp_xl, zp_xr = left/right for top row (inclusive)
;        zp_xl2, zp_xr2 = left/right for bottom row (inclusive)
;        zp_color = color (0-3)
;
; Destroys: A, X, Y
; ============================================================================

draw_dual_row
        ; Bounds check: 0 <= y < SCREEN_HEIGHT-1
        lda zp_y
        cmp #SCREEN_HEIGHT-1
        bcc _dual_row_start
        rts
_dual_row_start

        ; Clamp x bounds to screen
        ; xl1 = max(0, xl1)
        lda zp_xl
        bpl +
        lda #0
        sta zp_xl
+
        ; xl2 = max(0, xl2)
        lda zp_xl2
        bpl +
        lda #0
        sta zp_xl2
+
        ; xr1 = min(SCREEN_WIDTH-1, xr1)
        lda zp_xr
        cmp #SCREEN_WIDTH
        bcc +
        lda #SCREEN_WIDTH-1
        sta zp_xr
+
        ; xr2 = min(SCREEN_WIDTH-1, xr2)
        lda zp_xr2
        cmp #SCREEN_WIDTH
        bcc +
        lda #SCREEN_WIDTH-1
        sta zp_xr2
+
        ; Find overall x range
        ; x_min = min(xl1, xl2)
        lda zp_xl
        cmp zp_xl2
        bcc +
        lda zp_xl2
+       sta _x_min

        ; x_max = max(xr1, xr2)
        lda zp_xr
        cmp zp_xr2
        bcs +
        lda zp_xr2
+       sta _x_max

        ; Character range
        ; char_start = x_min >> 1
        lda _x_min
        lsr a
        sta zp_char_start

        ; char_end = x_max >> 1 (inclusive)
        lda _x_max
        lsr a
        sta zp_char_end

        ; Compute screen row base address
        ; base = row_offset[y >> 1] = (y >> 1) * 40
        lda zp_y
        lsr a                   ; char_y = y >> 1
        tax
        lda row_offset_lo,x
        sta zp_screen_lo
        lda row_offset_hi,x
        clc
        adc #>SCREEN_RAM
        sta zp_screen_hi

        ; Build color pattern byte
        ldx zp_color
        lda color_pattern,x
        sta _color_byte

        ; ----------------------------------------------------------------
        ; Compute segment boundaries
        ; Left segment:  char_start to left_end   (one row active)
        ; Middle segment: mid_start to mid_end    (both rows fully active)
        ; Right segment: right_start to char_end  (one row active)
        ;
        ; left_end   = (max(xl, xl2) - 1) >> 1   ; last char of left segment
        ; mid_start  = max(xl, xl2) >> 1         ; first char of middle segment
        ; mid_end    = min(xr, xr2) >> 1         ; last char of middle segment
        ; right_start= (min(xr, xr2) + 1) >> 1   ; first char of right segment
        ; ----------------------------------------------------------------

        ; max(xl, xl2)
        lda zp_xl
        cmp zp_xl2
        bcs +
        lda zp_xl2
+       sta _max_xl

        ; min(xr, xr2)
        lda zp_xr
        cmp zp_xr2
        bcc +
        lda zp_xr2
+       sta _min_xr

        ; Segment boundaries (from plan):
        ; left_end   = (max(xl, xl2) - 1) >> 1   ; last char of left segment
        ; mid_start  = max(xl, xl2) >> 1         ; first char of middle segment
        ; mid_end    = min(xr, xr2) >> 1         ; last char of middle segment
        ; right_start= (min(xr, xr2) + 1) >> 1   ; first char of right segment

        ; left_end = (max_xl - 1) >> 1
        ; Handle case where max_xl=0: result would underflow
        lda _max_xl
        beq _left_end_zero
        sec
        sbc #1
        lsr a
        sta _left_end
        jmp _calc_mid_start
_left_end_zero
        ; max_xl=0 means left segment is empty (char_start would be 0, left_end would be -1)
        lda #$ff                ; Set to "before" char_start so loop won't run
        sta _left_end

_calc_mid_start
        ; mid_start = max_xl >> 1
        lda _max_xl
        lsr a
        sta _mid_start

        ; mid_end = min_xr >> 1
        lda _min_xr
        lsr a
        sta _mid_end

        ; right_start = (min_xr + 1) >> 1
        lda _min_xr
        clc
        adc #1
        lsr a
        sta _right_start

        ; Compute "tight" middle range where ALL 4 pixels are set:
        ; tight_mid_start = (max_xl + 1) >> 1  (first char fully inside)
        ; tight_mid_end = (min_xr - 1) >> 1    (last char fully inside)
        lda _max_xl
        clc
        adc #1
        lsr a
        sta _tight_mid_start

        lda _min_xr
        beq _tight_end_zero
        sec
        sbc #1
        lsr a
        sta _tight_mid_end
        jmp _begin_left_segment
_tight_end_zero
        lda #$ff                ; No tight middle
        sta _tight_mid_end

_begin_left_segment
        ; ----------------------------------------------------------------
        ; LEFT SEGMENT: char_start to left_end
        ; For now, just use inner loop (will optimize later)
        ; ----------------------------------------------------------------
        lda zp_char_start
        sta zp_char_x

_left_seg_loop
        lda zp_char_x
        cmp _left_end
        beq _left_seg_char
        bcc _left_seg_char
        jmp _middle_segment     ; char_x > left_end, done with left segment

_left_seg_char
        ; Process this char using the existing inner loop code
        jsr _process_char_inner
        inc zp_char_x
        jmp _left_seg_loop

        ; ----------------------------------------------------------------
        ; MIDDLE SEGMENT: mid_start to mid_end
        ; Edge chars may be partial, tight middle has all 4 pixels
        ; ----------------------------------------------------------------
_middle_segment
        lda _mid_start
        sta zp_char_x

_middle_loop
        ; Check if done
        lda zp_char_x
        cmp _mid_end
        beq _middle_process
        bcs _right_segment

_middle_process
        ; Check if in tight range (all 4 pixels set)
        lda zp_char_x
        cmp _tight_mid_start
        bcc _middle_partial     ; char_x < tight_start
        cmp _tight_mid_end
        beq _middle_direct      ; char_x == tight_end
        bcs _middle_partial     ; char_x > tight_end

_middle_direct
        ; Direct write
        ldy zp_char_x
        lda _color_byte
        sta (zp_screen_lo),y
        inc zp_char_x
        jmp _middle_loop

_middle_partial
        ; Partial char - use inner loop
        jsr _process_char_inner
        inc zp_char_x
        jmp _middle_loop

        ; ----------------------------------------------------------------
        ; RIGHT SEGMENT: right_start to char_end
        ; ----------------------------------------------------------------
_right_segment
        lda _right_start
        sta zp_char_x

_right_seg_loop
        lda zp_char_x
        cmp zp_char_end
        beq _right_seg_char
        bcc _right_seg_char
        jmp _dual_row_done      ; char_x > char_end, done

_right_seg_char
        ; Process this char using the existing inner loop code
        jsr _process_char_inner
        inc zp_char_x
        jmp _right_seg_loop

; ============================================================================
; Inner loop processing for a single character (extracted for reuse)
; Input: zp_char_x = character column to process
;        zp_screen_lo/hi = row base address
;        zp_xl, zp_xr, zp_xl2, zp_xr2 = edge positions
;        _color_byte = color pattern
; ============================================================================
_process_char_inner
        ; Determine pixel coverage for this character
        ; px_left = char_x << 1
        ; px_right = (char_x << 1) + 1
        lda zp_char_x
        asl a
        sta _px_left
        ora #1
        sta _px_right

        ; Top row coverage (bits 1=left, 0=right in top_bits)
        ; top_left = (px_left >= xl1 && px_left <= xr1) ? 1 : 0
        ; top_right = (px_right >= xl1 && px_right <= xr1) ? 1 : 0
        ; top_bits = (top_left << 1) | top_right

        lda #0
        sta _top_bits

        ; Check left pixel of top row: px_left >= xl && px_left <= xr
        lda _px_left
        cmp zp_xl
        bcc _tl_skip            ; px_left < xl1, not covered
        cmp zp_xr
        beq _tl_covered         ; px_left == xr1, covered
        bcs _tl_skip            ; px_left > xr1, not covered
_tl_covered
        lda _top_bits
        ora #2                  ; Set left bit
        sta _top_bits
_tl_skip

        ; Check right pixel of top row
        lda _px_right
        cmp zp_xl
        bcc _tr_skip
        cmp zp_xr
        beq _tr_covered
        bcs _tr_skip
_tr_covered
        lda _top_bits
        ora #1                  ; Set right bit
        sta _top_bits
_tr_skip

        ; Bottom row coverage
        lda #0
        sta _bot_bits

        ; Check left pixel of bottom row
        lda _px_left
        cmp zp_xl2
        bcc _bl_skip
        cmp zp_xr2
        beq _bl_covered
        bcs _bl_skip
_bl_covered
        lda _bot_bits
        ora #2
        sta _bot_bits
_bl_skip

        ; Check right pixel of bottom row
        lda _px_right
        cmp zp_xl2
        bcc _br_skip
        cmp zp_xr2
        beq _br_covered
        bcs _br_skip
_br_covered
        lda _bot_bits
        ora #1
        sta _bot_bits
_br_skip
        ; Build mask
        ldx _top_bits
        lda top_row_mask,x
        ldx _bot_bits
        ora bottom_row_mask,x
        sta _set_mask

        ; Skip if no pixels to set
        beq _process_char_done

        ; Calculate screen offset
        ldy zp_char_x

        ; If all 4 pixels, just write
        lda _set_mask
        cmp #$ff
        bne _read_modify_write

        ; Full character: direct write
        lda _color_byte
        sta (zp_screen_lo),y
        rts                     ; Return from _process_char_inner

_read_modify_write
        ; Partial: read-modify-write
        lda (zp_screen_lo),y
        eor _color_byte         ; XOR with color
        and _set_mask           ; Keep only bits we're changing
        eor (zp_screen_lo),y    ; XOR back to get final value
        sta (zp_screen_lo),y

_process_char_done
        rts                     ; Return from _process_char_inner

_dual_row_done
        rts

; Temporaries for draw_dual_row
_x_min          .byte 0
_x_max          .byte 0
_px_left        .byte 0
_px_right       .byte 0
_top_bits       .byte 0
_bot_bits       .byte 0
_set_mask       .byte 0
_color_byte     .byte 0
; Segment boundaries
_max_xl         .byte 0         ; max(xl, xl2)
_min_xr         .byte 0         ; min(xr, xr2)
_left_end       .byte 0         ; last char of left segment
_mid_start      .byte 0         ; first char of middle segment
_mid_end        .byte 0         ; last char of middle segment
_right_start    .byte 0         ; first char of right segment
_tight_mid_start .byte 0        ; first char with all 4 pixels set
_tight_mid_end  .byte 0         ; last char with all 4 pixels set
_tight_start_clamped .byte 0    ; clamped to [mid_start, mid_end]
_tight_end_clamped .byte 0      ; clamped to [mid_start, mid_end]
_left_mask      .byte 0         ; $F0 (top) or $0F (bottom) for left segment
_left_color     .byte 0         ; color byte masked for left segment
_tight_left_start .byte 0       ; first char with full coverage in left segment

; ============================================================================
; ROUTINE: draw_span
; ============================================================================
; Draw a horizontal span on a single scanline (pixel by pixel).
; Used for odd scanlines where dual-row optimization doesn't apply.
;
; Input: zp_y = scanline
;        zp_xl = left X (inclusive)
;        zp_xr = right X (inclusive)
;        zp_color = color (0-3)
;
; Destroys: A, X, Y
; ============================================================================

draw_span
        ; For each x from xl to xr (inclusive), call set_pixel_v2
        lda zp_xl
        sta _span_x

_span_loop
        lda _span_x
        cmp zp_xr
        beq +
        bcs _span_done          ; x > xr, done
+
        ; Set pixel at (x, y)
        ldx _span_x
        ldy zp_y
        lda zp_color
        jsr set_pixel_v2

        inc _span_x
        jmp _span_loop

_span_done
        rts

_span_x .byte 0

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
        ldx #0
-       sta SCREEN_RAM,x
        sta SCREEN_RAM+$100,x
        sta SCREEN_RAM+$200,x
        inx
        bne -
        ; Last 232 bytes
        ldx #0
-       sta SCREEN_RAM+$300,x
        inx
        cpx #232
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
