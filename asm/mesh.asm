; mesh.asm - 3D Mesh Transform and Render
; 64tass syntax
;
; Transforms mesh vertices from local 3D coordinates to 2D screen coordinates
; using Y-axis rotation and perspective projection.
;
; Algorithm:
; 1. Rotate each vertex around Y axis by theta
; 2. Add world position (px, py, pz)
; 3. Project to screen using perspective division
; 4. Render each face using draw_triangle
;
; Requires: main.asm (for math routines, LUTs)
;           rasterizer.asm (for draw_triangle)
;           macros.asm (for mul8x8_signed_m)

; ============================================================================
; Zero page allocations for mesh transform
; ============================================================================
zp_mesh_c       = $32   ; cos(theta) in s0.7 format
zp_mesh_s       = $33   ; sin(theta) in s0.7 format
zp_rot_x_lo     = $34   ; rotated X (16-bit signed, 8.8 accumulator)
zp_rot_x_hi     = $35
zp_rot_z_lo     = $36   ; rotated Z (16-bit signed, 8.8 accumulator)
zp_rot_z_hi     = $37
zp_world_x_lo   = $38   ; world X (16-bit signed)
zp_world_x_hi   = $39
zp_world_y_lo   = $3a   ; world Y (16-bit signed)
zp_world_y_hi   = $3b
zp_world_z_lo   = $3c   ; world Z (16-bit signed)
zp_world_z_hi   = $3d
zp_mesh_temp1   = $3e   ; temporary
zp_mesh_temp2   = $3f
zp_z8           = $40   ; z8 = world_z >> 3 for perspective lookup
zp_recip        = $41   ; perspective reciprocal
zp_vtx_idx      = $42   ; current vertex index
zp_face_idx     = $43   ; current face index
zp_mul16_lo     = $44   ; 16-bit signed value for multiply (low)
zp_mul16_hi     = $45   ; 16-bit signed value for multiply (high)

; ============================================================================
; Mesh data structure (in main memory)
; ============================================================================
; These labels should be defined by the calling code with actual mesh data

; Maximum mesh size
MESH_MAX_VERTICES = 256
MESH_MAX_FACES    = 256

; Mesh vertex data (s8 local coordinates)
mesh_vx         .fill MESH_MAX_VERTICES, 0
mesh_vy         .fill MESH_MAX_VERTICES, 0
mesh_vz         .fill MESH_MAX_VERTICES, 0

; Mesh face data (u8 vertex indices and colors)
mesh_fi         .fill MESH_MAX_FACES, 0
mesh_fj         .fill MESH_MAX_FACES, 0
mesh_fk         .fill MESH_MAX_FACES, 0
mesh_fcol       .fill MESH_MAX_FACES, 0

; Mesh properties
mesh_num_verts  .byte 0
mesh_num_faces  .byte 0

; Rotated Z per vertex (s8, for painter's algorithm sorting)
mesh_rot_z      .fill MESH_MAX_VERTICES, 0

; Face render order (sorted back-to-front by radix sort)
face_order      .fill MESH_MAX_FACES, 0

; Radix sort count array (temporary)
radix_count     .fill 256, 0
mesh_px_lo      .byte 0    ; 16-bit signed world position X
mesh_px_hi      .byte 0
mesh_py_lo      .byte 0    ; 16-bit signed world position Y
mesh_py_hi      .byte 0
mesh_pz_lo      .byte 0    ; 16-bit signed world position Z
mesh_pz_hi      .byte 0
mesh_theta      .byte 0    ; u8 rotation angle (0-255 = 0 to 2pi)

; Transformed screen coordinates (s8)
screen_x        .fill 256, 0
screen_y        .fill 256, 0

; ============================================================================
; ROUTINE: transform_mesh
; ============================================================================
; Transform all vertices from local to screen coordinates.
;
; Input: Mesh data must be set up in mesh_* variables
;
; Output: screen_x[], screen_y[] filled with 2D coordinates
;         Returns: A = 0 on success, A = $FF if any vertex behind camera
;
; Destroys: A, X, Y, temp zero page vars
; ============================================================================

transform_mesh
        ; Load sin/cos for rotation
        ldx mesh_theta
        lda rcos,x
        sta zp_mesh_c
        lda rsin,x
        sta zp_mesh_s

        ; Process each vertex
        lda #0
        sta zp_vtx_idx

_tm_vertex_loop
        ; Check if done
        lda zp_vtx_idx
        cmp mesh_num_verts
        bcc _tm_do_vertex
        ; All vertices done, return success
        lda #0
        rts

_tm_do_vertex
        ldx zp_vtx_idx

        ; ----------------------------------------------------------------
        ; Step 1: Y-axis rotation
        ; rot_x = (c * lx + s * lz) >> 7
        ; rot_z = (-s * lx + c * lz) >> 7
        ; ----------------------------------------------------------------

        ; Load local coordinates
        lda mesh_vx,x
        sta _tm_lx
        lda mesh_vz,x
        sta _tm_lz

        ; Compute c * lx (s0.7 * s8.0 = s8.7)
        lda zp_mesh_c
        ldy _tm_lx
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty _tm_clx_lo
        sta _tm_clx_hi

        ; Compute s * lz (s0.7 * s8.0 = s8.7)
        lda zp_mesh_s
        ldy _tm_lz
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty _tm_slz_lo
        sta _tm_slz_hi

        ; rot_x_raw = c*lx + s*lz (16-bit signed)
        clc
        lda _tm_clx_lo
        adc _tm_slz_lo
        sta zp_rot_x_lo
        lda _tm_clx_hi
        adc _tm_slz_hi
        sta zp_rot_x_hi

        ; Extract rot_x = rot_x_raw >> 7 (arithmetic shift)
        ; = (hi << 1) | (lo >> 7)
        lda zp_rot_x_lo
        rol a                   ; Shift lo left, bit 7 into carry
        lda zp_rot_x_hi
        rol a                   ; Shift hi left, carry in
        sta _tm_rot_x           ; This is rot_x in s8.0 format

        ; Compute -s * lx (negate s first)
        lda zp_mesh_s
        eor #$ff
        clc
        adc #1                  ; A = -s
        ldy _tm_lx
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty _tm_nslx_lo
        sta _tm_nslx_hi

        ; Compute c * lz
        lda zp_mesh_c
        ldy _tm_lz
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty _tm_clz_lo
        sta _tm_clz_hi

        ; rot_z_raw = -s*lx + c*lz (16-bit signed)
        clc
        lda _tm_nslx_lo
        adc _tm_clz_lo
        sta zp_rot_z_lo
        lda _tm_nslx_hi
        adc _tm_clz_hi
        sta zp_rot_z_hi

        ; Extract rot_z = rot_z_raw >> 7 (arithmetic shift)
        lda zp_rot_z_lo
        rol a                   ; bit 7 into carry
        lda zp_rot_z_hi
        rol a                   ; carry in
        sta _tm_rot_z

        ; Store rot_z for painter's algorithm sorting
        ldx zp_vtx_idx
        sta mesh_rot_z,x

        ; ----------------------------------------------------------------
        ; Step 2: Add world position
        ; world_x = rot_x + px
        ; world_y = ly + py
        ; world_z = rot_z + pz
        ; ----------------------------------------------------------------

        ; world_x = rot_x (s8) + px (s16) - sign extend rot_x to 16 bits
        lda _tm_rot_x
        sta zp_world_x_lo
        ; Sign extend to high byte
        bpl _wx_pos             ; If positive, high byte = 0
        lda #$ff                ; Negative: high byte = $ff
        jmp _wx_done
_wx_pos lda #0                  ; Positive: high byte = 0
_wx_done
        sta zp_world_x_hi
        ; Add px
        clc
        lda zp_world_x_lo
        adc mesh_px_lo
        sta zp_world_x_lo
        lda zp_world_x_hi
        adc mesh_px_hi
        sta zp_world_x_hi

        ; world_y = ly + py (ly is s8, sign extend)
        ldx zp_vtx_idx
        lda mesh_vy,x
        sta zp_world_y_lo
        bpl _wy_pos
        lda #$ff
        jmp _wy_done
_wy_pos lda #0
_wy_done
        sta zp_world_y_hi
        clc
        lda zp_world_y_lo
        adc mesh_py_lo
        sta zp_world_y_lo
        lda zp_world_y_hi
        adc mesh_py_hi
        sta zp_world_y_hi

        ; world_z = rot_z + pz (rot_z is s8, sign extend)
        lda _tm_rot_z
        sta zp_world_z_lo
        bpl _wz_pos
        lda #$ff
        jmp _wz_done
_wz_pos lda #0
_wz_done
        sta zp_world_z_hi
        clc
        lda zp_world_z_lo
        adc mesh_pz_lo
        sta zp_world_z_lo
        lda zp_world_z_hi
        adc mesh_pz_hi
        sta zp_world_z_hi

        ; ----------------------------------------------------------------
        ; Step 3: Check if vertex is behind camera (world_z <= 0)
        ; ----------------------------------------------------------------

        lda zp_world_z_hi
        bmi _tm_behind_camera   ; Negative = behind camera
        bne _tm_z_ok            ; High byte > 0, definitely in front
        ; High byte = 0, check low byte
        lda zp_world_z_lo
        beq _tm_behind_camera   ; z = 0, on camera plane, reject
        ; z > 0, ok
_tm_z_ok

        ; ----------------------------------------------------------------
        ; Step 4: Perspective projection
        ; screen_x = 40 + highbyte(world_x * recip)
        ; screen_y = 25 - highbyte(world_y * recip)
        ;
        ; z8 = world_z >> 3
        ; recip = recip_persp[z8 - 128]
        ; ----------------------------------------------------------------

        ; Compute z8 = world_z >> 3
        ; world_z is 16-bit, we want bits 10..3 (high bits of low byte + low bits of high byte)
        lda zp_world_z_lo
        lsr a
        lsr a
        lsr a                   ; A = world_z_lo >> 3
        sta zp_z8
        lda zp_world_z_hi
        asl a
        asl a
        asl a
        asl a
        asl a                   ; A = (world_z_hi & 7) << 5
        ora zp_z8
        sta zp_z8               ; z8 = ((world_z_hi & 7) << 5) | (world_z_lo >> 3)

        ; Actually, let me simplify: z8 = world_z >> 3 means dividing by 8
        ; For 16-bit shift: result_lo = (hi << 5) | (lo >> 3)
        ; But for pz=1500 ($5DC), z >> 3 = 187 ($BB)
        ; High byte = 5, low byte = $DC
        ; (5 << 5) | ($DC >> 3) = $A0 | $1B = $BB = 187. Correct!

        ; Check z8 >= 128 (required for table)
        lda zp_z8
        cmp #128
        bcc _tm_too_close       ; z8 < 128, object too close

        ; Look up reciprocal: index = z8 - 128
        sec
        sbc #128
        tax
        lda recip_persp,x
        sta zp_recip

        ; Compute screen_x = 40 + highbyte(world_x * recip)
        ; world_x is s16, use 16-bit signed multiply
        lda zp_world_x_lo
        sta zp_mul16_lo
        lda zp_world_x_hi
        sta zp_mul16_hi
        ldx zp_recip
        jsr mul16s_8u_hi        ; Returns A = high byte of signed product
        clc
        adc #40                 ; Add screen center
        ldx zp_vtx_idx
        sta screen_x,x

        ; Compute screen_y = 25 - highbyte(world_y * recip)
        lda zp_world_y_lo
        sta zp_mul16_lo
        lda zp_world_y_hi
        sta zp_mul16_hi
        ldx zp_recip
        jsr mul16s_8u_hi        ; Returns A = high byte of signed product
        ; Negate and add 25
        eor #$ff
        clc
        adc #1
        clc
        adc #25
        ldx zp_vtx_idx
        sta screen_y,x

        ; Next vertex
        inc zp_vtx_idx
        jmp _tm_vertex_loop

_tm_behind_camera
_tm_too_close
        ; Return error
        lda #$ff
        rts

; Temporaries for transform
_tm_lx          .byte 0
_tm_lz          .byte 0
_tm_prod_lo     .byte 0
_tm_prod_hi     .byte 0
_tm_clx_lo      .byte 0
_tm_clx_hi      .byte 0
_tm_slz_lo      .byte 0
_tm_slz_hi      .byte 0
_tm_clz_lo      .byte 0
_tm_clz_hi      .byte 0
_tm_nslx_lo     .byte 0
_tm_nslx_hi     .byte 0
_tm_rot_x       .byte 0
_tm_rot_z       .byte 0

; ============================================================================
; ROUTINE: mul8s_8u_hi
; ============================================================================
; Signed 8-bit * unsigned 8-bit multiply, returns high byte.
;
; Input: A = signed value (-128 to 127)
;        X = unsigned value (0 to 255)
;
; Output: A = high byte of signed 16-bit product
;
; Uses quarter-square multiplication method.
; For negative A, negates A, multiplies, then negates result.
; ============================================================================

mul8s_8u_hi
        sta _m8_signed
        stx _m8_unsigned

        ; Check if signed value is negative
        cmp #$80
        bcc _m8_positive

        ; Negative: negate A, multiply, negate result
        eor #$ff
        clc
        adc #1
        tay                     ; Y = |A|
        ldx _m8_unsigned
        jsr _m8_do_mul          ; Returns A = high byte

        ; Negate high byte (2's complement the whole result)
        ; Since we only return high byte, we need to consider low byte
        ; For proper 2's complement: if low byte was 0, high = ~high + 1
        ; If low byte was non-zero, high = ~high
        lda prod_low
        bne +
        ; Low byte is 0, add 1 to negated high
        lda _m8_result
        eor #$ff
        clc
        adc #1
        rts
+       ; Low byte non-zero
        lda _m8_result
        eor #$ff
        rts

_m8_positive
        tay                     ; Y = A (positive signed value)
        ldx _m8_unsigned
        jsr _m8_do_mul
        lda _m8_result
        rts

_m8_do_mul
        ; Y = first factor (unsigned), X = second factor (unsigned)
        ; Use the unsigned multiply macro
        #mul8x8_unsigned_m      ; Returns A = high byte, prod_low = low byte
        sta _m8_result
        rts

_m8_signed      .byte 0
_m8_unsigned    .byte 0
_m8_result      .byte 0

; ============================================================================
; ROUTINE: mul16s_8u_hi
; ============================================================================
; Signed 16-bit * unsigned 8-bit multiply, returns high byte of 24-bit result.
; (Actually returns bits 15-8 of the result, which is what we need for perspective)
;
; Input: zp_mul16_lo/hi = signed 16-bit value
;        X = unsigned 8-bit value
;
; Output: A = byte 1 (bits 15-8) of signed 24-bit product
;
; For negative input, negates, multiplies unsigned, then negates result.
; ============================================================================

mul16s_8u_hi
        stx _m16_unsigned

        ; Check sign of 16-bit value
        lda zp_mul16_hi
        bmi _m16_negative

        ; Positive: do unsigned 16x8 multiply
        jsr _m16_do_unsigned
        rts

_m16_negative
        ; Negative: negate input, multiply, negate result
        ; Negate 16-bit value: ~value + 1
        lda zp_mul16_lo
        eor #$ff
        clc
        adc #1
        sta _m16_abs_lo
        lda zp_mul16_hi
        eor #$ff
        adc #0
        sta _m16_abs_hi

        ; Now multiply the absolute value
        jsr _m16_do_unsigned_abs

        ; Negate 24-bit result: need to return negated byte 1
        ; Full negate: ~result + 1
        ; Byte 0 (prod_low from lo*recip): if 0, add 1 to byte 1
        ; Actually we have: result = (p1_hi + p2_lo + carry) in _m16_byte1
        ; and prod_low has the low byte from the last multiply

        ; The low byte of full result is in _m16_byte0
        lda _m16_byte0
        bne _m16_neg_no_carry
        ; Low byte is 0, so ~byte1 + 1
        lda _m16_byte1
        eor #$ff
        clc
        adc #1
        rts

_m16_neg_no_carry
        ; Low byte non-zero, so just ~byte1
        lda _m16_byte1
        eor #$ff
        rts

_m16_do_unsigned
        ; Multiply zp_mul16 by _m16_unsigned (unsigned)
        ; Result = (hi * 256 + lo) * recip = (hi * recip) << 8 + (lo * recip)
        ; We want byte 1 (bits 15-8)

        ; First: lo * recip
        ldy zp_mul16_lo
        ldx _m16_unsigned
        #mul8x8_unsigned_m      ; A = hi, prod_low = lo
        sta _m16_p1_hi          ; p1_hi = highbyte(lo * recip)
        lda prod_low
        sta _m16_byte0          ; byte 0 = lowbyte(lo * recip)

        ; Second: hi * recip
        ldy zp_mul16_hi
        ldx _m16_unsigned
        #mul8x8_unsigned_m      ; A = hi, prod_low = lo
        ; p2_hi in A, p2_lo in prod_low

        ; Byte 1 = p1_hi + p2_lo
        clc
        lda _m16_p1_hi
        adc prod_low
        sta _m16_byte1

        rts

_m16_do_unsigned_abs
        ; Same as above but uses _m16_abs_lo/hi instead
        ldy _m16_abs_lo
        ldx _m16_unsigned
        #mul8x8_unsigned_m
        sta _m16_p1_hi
        lda prod_low
        sta _m16_byte0

        ldy _m16_abs_hi
        ldx _m16_unsigned
        #mul8x8_unsigned_m

        clc
        lda _m16_p1_hi
        adc prod_low
        sta _m16_byte1

        rts

_m16_unsigned   .byte 0
_m16_abs_lo     .byte 0
_m16_abs_hi     .byte 0
_m16_p1_hi      .byte 0
_m16_byte0      .byte 0
_m16_byte1      .byte 0

; ============================================================================
; ROUTINE: sort_faces
; ============================================================================
; Sort faces back-to-front using radix sort on rot_z of first vertex.
;
; Uses XOR $80 to convert signed rot_z to unsigned for sorting.
; Processes count array from high to low for back-to-front order.
;
; Input: mesh_num_faces, mesh_fi[], mesh_rot_z[]
; Output: face_order[] contains sorted face indices
;
; Destroys: A, X, Y
; ============================================================================

sort_faces
        ; --- Phase 1: Clear count array ---
        lda #0
        ldx #0
_sf_clear
        sta radix_count,x
        inx
        bne _sf_clear

        ; --- Phase 2: Count occurrences ---
        ; For each face, increment count[rot_z[fi[face]] XOR $80]
        ldx #0
_sf_count_loop
        cpx mesh_num_faces
        beq _sf_count_done

        ; Get first vertex of face
        lda mesh_fi,x
        tay
        ; Get rot_z of that vertex, XOR $80 for unsigned sort key
        lda mesh_rot_z,y
        eor #$80
        tay
        ; Increment count (no inc abs,y on 6502, so load/inc/store)
        lda radix_count,y
        clc
        adc #1
        sta radix_count,y

        inx
        jmp _sf_count_loop
_sf_count_done

        ; --- Phase 3: Convert counts to ending positions (backwards for back-to-front) ---
        ; We want largest Z first, so we build positions from the end backwards.
        ; Start with position = num_faces, process from index 255 down to 0.
        ; After each count, position -= count; that position becomes the start for that bucket.

        lda mesh_num_faces
        sta _sf_position

        ldx #255
_sf_prefix_loop
        lda _sf_position
        sec
        sbc radix_count,x
        sta _sf_position
        sta radix_count,x       ; count[x] now holds starting position for bucket x

        dex
        cpx #$ff
        bne _sf_prefix_loop

        ; --- Phase 4: Scatter faces into face_order ---
        ; For each face, place at count[key]++
        ldx #0
_sf_scatter_loop
        cpx mesh_num_faces
        beq _sf_scatter_done
        stx _sf_face_idx

        ; Get sort key for this face
        lda mesh_fi,x
        tay
        lda mesh_rot_z,y
        eor #$80
        tay                     ; Y = sort key

        ; Get position and increment it
        lda radix_count,y
        sta _sf_pos_temp
        clc
        adc #1
        sta radix_count,y

        ; Store face index at that position
        ldx _sf_pos_temp        ; X = position (before increment)
        lda _sf_face_idx
        sta face_order,x

        ldx _sf_face_idx
        inx
        jmp _sf_scatter_loop
_sf_scatter_done
        rts

_sf_position    .byte 0
_sf_face_idx    .byte 0
_sf_pos_temp    .byte 0

; ============================================================================
; ROUTINE: render_mesh
; ============================================================================
; Render all faces of the mesh using transformed screen coordinates.
; Faces are rendered in face_order[] order (call sort_faces first for painter's).
;
; Input: screen_x[], screen_y[] must be valid (from transform_mesh)
;        face_order[] should be sorted (from sort_faces)
;        Mesh face data in mesh_fi, mesh_fj, mesh_fk, mesh_fcol
;
; Output: Triangles drawn to screen
;
; Destroys: A, X, Y, rasterizer zero page vars
; ============================================================================

render_mesh
        ; First sort faces for painter's algorithm
        jsr sort_faces

        lda #0
        sta zp_face_idx

_rm_face_loop
        ; Check if done
        lda zp_face_idx
        cmp mesh_num_faces
        bcc _rm_do_face
        rts

_rm_do_face
        ; Get actual face index from sorted order
        ldx zp_face_idx
        lda face_order,x
        sta _rm_actual_face

        ; Get vertex indices
        tax
        lda mesh_fi,x
        tay
        lda screen_x,y
        sta zp_ax
        lda screen_y,y
        sta zp_ay

        ldx _rm_actual_face
        lda mesh_fj,x
        tay
        lda screen_x,y
        sta zp_bx
        lda screen_y,y
        sta zp_by

        ldx _rm_actual_face
        lda mesh_fk,x
        tay
        lda screen_x,y
        sta zp_cx
        lda screen_y,y
        sta zp_cy

        ldx _rm_actual_face
        lda mesh_fcol,x
        sta zp_color

        ; Draw triangle (handles backface culling internally)
        jsr draw_triangle

        ; Next face
        inc zp_face_idx
        jmp _rm_face_loop

_rm_actual_face .byte 0
