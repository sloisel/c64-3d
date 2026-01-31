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
;
; Configuration:
;   DUAL_MESH = 1 : Two sub-meshes with merge-sort render (up to 512 faces)
;   DUAL_MESH = 0 : Single mesh, simpler/faster (up to 256 faces)
;
; Set DUAL_MESH before including this file, or default to 1
; FLIP_ZSORT = 1 reverses Z-sort order (correct for our coordinate system)
; RASTERIZE = 0 skips rasterization (for benchmarking geometry cost)
.weak
DUAL_MESH = 1
FLIP_ZSORT = 1
RASTERIZE = 1
.endweak

; XOR value for signed-to-unsigned conversion in radix sort
; $80 = normal order (back-to-front), $7f = reversed (front-to-back)
.if FLIP_ZSORT
SORT_XOR = $7f
.else
SORT_XOR = $80
.endif

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

; Transform temporaries (in ZP for speed)
zp_tm_lx        = $46
zp_tm_lz        = $47
zp_tm_clx_lo    = $48
zp_tm_clx_hi    = $49
zp_tm_slz_lo    = $4a
zp_tm_slz_hi    = $4b
zp_tm_clz_lo    = $4c
zp_tm_clz_hi    = $4d
zp_tm_slx_lo    = $4e
; Note: zp_m16m_u = $4f, zp_m16m_p1_hi = $50 used by mul16s_8u_hi_m
zp_tm_slx_hi    = $51
zp_tm_rot_x     = $52
zp_tm_rot_z     = $53

; ============================================================================
; Mesh data structure (in main memory)
; ============================================================================
; These labels should be defined by the calling code with actual mesh data

; Maximum mesh size
MESH_MAX_VERTICES = 256
MESH_MAX_FACES    = 256         ; Per sub-mesh (total 512 faces possible)

; Mesh vertex data (s8 local coordinates) - shared by both sub-meshes
mesh_vx         .fill MESH_MAX_VERTICES, 0
mesh_vy         .fill MESH_MAX_VERTICES, 0
mesh_vz         .fill MESH_MAX_VERTICES, 0

; Sub-mesh 0 face data (faces 0-255)
mesh_fi_0       .fill MESH_MAX_FACES, 0
mesh_fj_0       .fill MESH_MAX_FACES, 0
mesh_fk_0       .fill MESH_MAX_FACES, 0
mesh_fcol_0     .fill MESH_MAX_FACES, 0

; Sub-mesh 1 face data (faces 256-511)
mesh_fi_1       .fill MESH_MAX_FACES, 0
mesh_fj_1       .fill MESH_MAX_FACES, 0
mesh_fk_1       .fill MESH_MAX_FACES, 0
mesh_fcol_1     .fill MESH_MAX_FACES, 0

; Mesh properties are now in ZP (zp_mesh_num_verts, zp_mesh_num_faces_0/1)

; Rotated Z per vertex (s8, for painter's algorithm sorting)
mesh_rot_z      .fill MESH_MAX_VERTICES, 0

; Face render order for each sub-mesh (sorted back-to-front by radix sort)
face_order_0    .fill MESH_MAX_FACES, 0
face_order_1    .fill MESH_MAX_FACES, 0

; Radix sort count array (temporary, shared between sorts)
; Page-aligned for SMC inc optimization
        .align 256
radix_count     .fill 256, 0

; Radix sort temp variables (shared between sort_faces_0 and sort_faces_1)
sf_position     .byte 0
sf_face_idx     .byte 0
sf_pos_temp     .byte 0

; Mesh position is now in ZP (zp_mesh_px/py/pz_lo/hi)
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
        cmp zp_mesh_num_verts
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
        sta zp_tm_lx
        lda mesh_vz,x
        sta zp_tm_lz

        ; Compute c * lx (s0.7 * s8.0 = s8.7)
        lda zp_mesh_c
        ldy zp_tm_lx
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty zp_tm_clx_lo
        sta zp_tm_clx_hi

        ; Compute s * lz (s0.7 * s8.0 = s8.7)
        lda zp_mesh_s
        ldy zp_tm_lz
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty zp_tm_slz_lo
        sta zp_tm_slz_hi

        ; rot_x_raw = c*lx + s*lz (16-bit signed)
        clc
        lda zp_tm_clx_lo
        adc zp_tm_slz_lo
        sta zp_rot_x_lo
        lda zp_tm_clx_hi
        adc zp_tm_slz_hi
        sta zp_rot_x_hi

        ; Extract rot_x = rot_x_raw >> 7 (arithmetic shift)
        ; = (hi << 1) | (lo >> 7)
        lda zp_rot_x_lo
        rol a                   ; Shift lo left, bit 7 into carry
        lda zp_rot_x_hi
        rol a                   ; Shift hi left, carry in
        sta zp_tm_rot_x         ; This is rot_x in s8.0 format

        ; Compute s * lx
        lda zp_mesh_s
        ldy zp_tm_lx
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty zp_tm_slx_lo
        sta zp_tm_slx_hi

        ; Compute c * lz
        lda zp_mesh_c
        ldy zp_tm_lz
        #mul8x8_signed_m         ; A:Y = hi:lo
        sty zp_tm_clz_lo
        sta zp_tm_clz_hi

        ; rot_z_raw = c*lz - s*lx (16-bit signed)
        sec
        lda zp_tm_clz_lo
        sbc zp_tm_slx_lo
        sta zp_rot_z_lo
        lda zp_tm_clz_hi
        sbc zp_tm_slx_hi
        sta zp_rot_z_hi

        ; Extract rot_z = rot_z_raw >> 7 (arithmetic shift)
        lda zp_rot_z_lo
        rol a                   ; bit 7 into carry
        lda zp_rot_z_hi
        rol a                   ; carry in
        sta zp_tm_rot_z

        ; Store rot_z for painter's algorithm sorting (pre-XOR for radix sort)
        eor #SORT_XOR           ; convert signed to unsigned for sorting
        ldx zp_vtx_idx
        sta mesh_rot_z,x

        ; ----------------------------------------------------------------
        ; Step 2: Add world position
        ; world_x = rot_x + px
        ; world_y = ly + py
        ; world_z = rot_z + pz
        ; ----------------------------------------------------------------

        ; world_x = rot_x (s8) + px (s16) - sign extend rot_x to 16 bits
        lda zp_tm_rot_x
        sta zp_world_x_lo
        ; Sign extend to high byte
        ora #$7f                ; A = $7f if positive, $ff if negative
        bmi +
        lda #0
+       sta zp_world_x_hi
        ; Add px
        clc
        lda zp_world_x_lo
        adc zp_mesh_px_lo
        sta zp_world_x_lo
        lda zp_world_x_hi
        adc zp_mesh_px_hi
        sta zp_world_x_hi

        ; world_y = ly + py (ly is s8, sign extend)
        ldx zp_vtx_idx
        lda mesh_vy,x
        sta zp_world_y_lo
        ora #$7f
        bmi +
        lda #0
+       sta zp_world_y_hi
        clc
        lda zp_world_y_lo
        adc zp_mesh_py_lo
        sta zp_world_y_lo
        lda zp_world_y_hi
        adc zp_mesh_py_hi
        sta zp_world_y_hi

        ; world_z = rot_z + pz (rot_z is s8, sign extend)
        lda zp_tm_rot_z
        sta zp_world_z_lo
        ora #$7f
        bmi +
        lda #0
+       sta zp_world_z_hi
        clc
        lda zp_world_z_lo
        adc zp_mesh_pz_lo
        sta zp_world_z_lo
        lda zp_world_z_hi
        adc zp_mesh_pz_hi
        sta zp_world_z_hi

        ; ----------------------------------------------------------------
        ; Step 3: Check if vertex is behind camera (world_z <= 0)
        ; ----------------------------------------------------------------

        lda zp_world_z_hi
        bpl +                   ; Not negative, check further
        jmp _tm_behind_camera   ; Negative = behind camera
+       bne _tm_z_ok            ; High byte > 0, definitely in front
        ; High byte = 0, check low byte
        lda zp_world_z_lo
        bne _tm_z_ok            ; z > 0, ok
        jmp _tm_behind_camera   ; z = 0, on camera plane, reject
_tm_z_ok

        ; ----------------------------------------------------------------
        ; Step 4: Perspective projection
        ; screen_x = 40 + highbyte(world_x * recip)
        ; screen_y = 25 - highbyte(world_y * recip)
        ;
        ; z8 = world_z >> 3
        ; recip = recip_persp[z8 - 128]
        ; ----------------------------------------------------------------

        ; Compute z8 = world_z >> 1 (k=1 shift for wider FOV)
        ; This is a simple 16-bit right shift by 1
        lda zp_world_z_hi
        lsr a                   ; Carry = bit 0 of high byte
        lda zp_world_z_lo
        ror a                   ; A = (carry << 7) | (lo >> 1) = z8
        sta zp_z8

        ; Check z8 >= 17 (below this, recip would overflow 8 bits)
        lda zp_z8
        cmp #17
        bcs +                   ; z8 >= 17, ok
        jmp _tm_too_close       ; z8 < 17, object too close
+

        ; Look up reciprocal: direct index by z8
        tax
        lda recip_persp,x
        sta zp_recip

        ; Compute screen_x = 40 + highbyte(world_x * recip)
        ; world_x is s16, use 16-bit signed multiply
        lda zp_world_x_lo
        sta zp_mul16_lo
        lda zp_world_x_hi
        sta zp_mul16_hi
        ldy zp_recip
        #mul16s_8u_hi_m         ; Returns A = high byte of signed product
        clc
        adc #40                 ; Add screen center
        ldx zp_vtx_idx
        sta screen_x,x

        ; Compute screen_y = 25 - highbyte(world_y * recip)
        lda zp_world_y_lo
        sta zp_mul16_lo
        lda zp_world_y_hi
        sta zp_mul16_hi
        ldy zp_recip
        #mul16s_8u_hi_m         ; Returns A = high byte of signed product
        ; Compute 25 - value: ~value + 1 + 25 = ~value + 26
        eor #$ff
        sec
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

; Temporaries for transform - now in zero page (zp_tm_*)

; ============================================================================
; ROUTINE: sort_faces_0
; ============================================================================
; Sort sub-mesh 0 faces back-to-front using radix sort on rot_z of first vertex.
; ============================================================================

sort_faces_0
        ; --- Phase 1: Clear count array (8x unrolled with stride) ---
        lda #0
        ldx #31
_sf0_clear
        sta radix_count,x
        sta radix_count+32,x
        sta radix_count+64,x
        sta radix_count+96,x
        sta radix_count+128,x
        sta radix_count+160,x
        sta radix_count+192,x
        sta radix_count+224,x
        dex
        bpl _sf0_clear

        ; --- Phase 2: Count occurrences (SMC inc for speed) ---
        ldx #0
_sf0_count_loop
        cpx zp_mesh_num_faces_0
        beq _sf0_count_done
        lda mesh_fi_0,x
        tay
        lda mesh_rot_z,y        ; already XORed when stored
        sta _sf0_inc+1          ; SMC: patch low byte of inc address
_sf0_inc
        inc radix_count         ; becomes inc radix_count+Z
        inx
        bne _sf0_count_loop     ; Always branches (X wraps at 256, but we exit before)
_sf0_count_done

        ; --- Phase 3: Prefix sum (backwards, 4x unrolled) ---
        ; A holds running position, eliminating redundant loads
        lda zp_mesh_num_faces_0
        ldx #255
_sf0_prefix_loop
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        cpx #$ff
        bne _sf0_prefix_loop

        ; --- Phase 4: Scatter (SMC for face index) ---
        ldx #0
_sf0_scatter_loop
        cpx zp_mesh_num_faces_0
        beq _sf0_scatter_done
        stx _sf0_face+1         ; SMC: patch immediate operand
        lda mesh_fi_0,x
        tay
        lda mesh_rot_z,y        ; already XORed when stored
        tay
        lda radix_count,y
        tax
        clc
        adc #1
        sta radix_count,y
_sf0_face
        lda #0                  ; SMC: immediate gets patched with face index
        sta face_order_0,x
        tax                     ; restore loop index
        inx
        bne _sf0_scatter_loop   ; Always branches (exits via beq above)
_sf0_scatter_done
        rts

; ============================================================================
; ROUTINE: sort_faces_1
; ============================================================================
; Sort sub-mesh 1 faces back-to-front using radix sort on rot_z of first vertex.
; ============================================================================

sort_faces_1
        ; --- Phase 1: Clear count array (8x unrolled with stride) ---
        lda #0
        ldx #31
_sf1_clear
        sta radix_count,x
        sta radix_count+32,x
        sta radix_count+64,x
        sta radix_count+96,x
        sta radix_count+128,x
        sta radix_count+160,x
        sta radix_count+192,x
        sta radix_count+224,x
        dex
        bpl _sf1_clear

        ; --- Phase 2: Count occurrences (SMC inc for speed) ---
        ldx #0
_sf1_count_loop
        cpx zp_mesh_num_faces_1
        beq _sf1_count_done
        lda mesh_fi_1,x
        tay
        lda mesh_rot_z,y        ; already XORed when stored
        sta _sf1_inc+1          ; SMC: patch low byte of inc address
_sf1_inc
        inc radix_count         ; becomes inc radix_count+Z
        inx
        bne _sf1_count_loop     ; Always branches (X wraps at 256, but we exit before)
_sf1_count_done

        ; --- Phase 3: Prefix sum (backwards, 4x unrolled) ---
        ; A holds running position, eliminating redundant loads
        lda zp_mesh_num_faces_1
        ldx #255
_sf1_prefix_loop
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        sec
        sbc radix_count,x
        sta radix_count,x
        dex
        cpx #$ff
        bne _sf1_prefix_loop

        ; --- Phase 4: Scatter (SMC for face index) ---
        ldx #0
_sf1_scatter_loop
        cpx zp_mesh_num_faces_1
        beq _sf1_scatter_done
        stx _sf1_face+1         ; SMC: patch immediate operand
        lda mesh_fi_1,x
        tay
        lda mesh_rot_z,y        ; already XORed when stored
        tay
        lda radix_count,y
        tax
        clc
        adc #1
        sta radix_count,y
_sf1_face
        lda #0                  ; SMC: immediate gets patched with face index
        sta face_order_1,x
        tax                     ; restore loop index
        inx
        bne _sf1_scatter_loop   ; Always branches (exits via beq above)
_sf1_scatter_done
        rts

; ============================================================================
; ROUTINE: render_mesh
; ============================================================================
; Render all faces from both sub-meshes using merge-sort style traversal.
; Faces are rendered back-to-front (largest rot_z first).
;
; Input: screen_x[], screen_y[] must be valid (from transform_mesh)
;        Both sub-meshes must have face data set up
;
; Output: Triangles drawn to screen
;
; Destroys: A, X, Y, rasterizer zero page vars
; ============================================================================

render_mesh
.if DUAL_MESH
        ; === DUAL MESH MODE: Sort both sub-meshes and merge-render ===
        jsr sort_faces_0
        jsr sort_faces_1

        ; Initialize merge indices
        lda #0
        sta _rm_idx_0
        sta _rm_idx_1

_rm_merge_loop
        ; Check if sub-mesh 0 exhausted
        lda _rm_idx_0
        cmp zp_mesh_num_faces_0
        bcs _rm_only_1

        ; Check if sub-mesh 1 exhausted
        lda _rm_idx_1
        cmp zp_mesh_num_faces_1
        bcs _rm_only_0

        ; Both have faces - compare rot_z (want larger z first = back-to-front)
        ; Get rot_z for current face in sub-mesh 0
        ldx _rm_idx_0
        lda face_order_0,x
        tax
        lda mesh_fi_0,x
        tay
        lda mesh_rot_z,y
        sta _rm_z0

        ; Get rot_z for current face in sub-mesh 1
        ldx _rm_idx_1
        lda face_order_1,x
        tax
        lda mesh_fi_1,x
        tay
        lda mesh_rot_z,y

        ; Compare: signed comparison (z1 vs z0)
        ; We want larger Z first, so if z0 >= z1, render mesh 0
        sec
        sbc _rm_z0              ; A = z1 - z0
        bvc _rm_no_overflow
        eor #$80                ; Fix sign on overflow
_rm_no_overflow
        bmi _rm_render_1        ; z1 < z0, render mesh 1... wait, backwards
        ; Actually: if (z1 - z0) < 0, then z1 < z0, so z0 is larger, render mesh 0
        ; if (z1 - z0) >= 0, then z1 >= z0, render mesh 1
        bpl _rm_render_1        ; z1 >= z0, render from mesh 1 first

_rm_render_0
        ; Render face from sub-mesh 0
        ldx _rm_idx_0
        lda face_order_0,x
        jsr _rm_draw_face_0
        inc _rm_idx_0
        jmp _rm_merge_loop

_rm_render_1
        ; Render face from sub-mesh 1
        ldx _rm_idx_1
        lda face_order_1,x
        jsr _rm_draw_face_1
        inc _rm_idx_1
        jmp _rm_merge_loop

_rm_only_0
        ; Render remaining faces from sub-mesh 0
        lda _rm_idx_0
        cmp zp_mesh_num_faces_0
        bcs _rm_done
        ldx _rm_idx_0
        lda face_order_0,x
        jsr _rm_draw_face_0
        inc _rm_idx_0
        jmp _rm_only_0

_rm_only_1
        ; Render remaining faces from sub-mesh 1
        lda _rm_idx_1
        cmp zp_mesh_num_faces_1
        bcs _rm_done
        ldx _rm_idx_1
        lda face_order_1,x
        jsr _rm_draw_face_1
        inc _rm_idx_1
        jmp _rm_only_1

_rm_done
        rts

.else
        ; === SINGLE MESH MODE: Sort and render directly (faster) ===
        jsr sort_faces_0

        ; Simple loop through sorted faces
        ldx #0
_rm_single_loop
        cpx zp_mesh_num_faces_0
        bcs _rm_single_done
        lda face_order_0,x
        stx _rm_idx_0           ; Save loop counter
        jsr _rm_draw_face_0
        ldx _rm_idx_0           ; Restore loop counter
        inx
        jmp _rm_single_loop

_rm_single_done
        rts
.endif

; Helper: draw face from sub-mesh 0
; Input: A = face index in sub-mesh 0
_rm_draw_face_0
        tax
        lda mesh_fi_0,x
        tay
        lda screen_x,y
        sta zp_ax
        lda screen_y,y
        sta zp_ay

        lda mesh_fj_0,x
        tay
        lda screen_x,y
        sta zp_bx
        lda screen_y,y
        sta zp_by

        lda mesh_fk_0,x
        tay
        lda screen_x,y
        sta zp_cx
        lda screen_y,y
        sta zp_cy

        lda mesh_fcol_0,x
        sta zp_color
.if RASTERIZE
        jmp draw_triangle       ; tail call
.else
        rts                     ; skip rasterization
.endif

; Helper: draw face from sub-mesh 1
; Input: A = face index in sub-mesh 1
_rm_draw_face_1
        tax
        lda mesh_fi_1,x
        tay
        lda screen_x,y
        sta zp_ax
        lda screen_y,y
        sta zp_ay

        lda mesh_fj_1,x
        tay
        lda screen_x,y
        sta zp_bx
        lda screen_y,y
        sta zp_by

        lda mesh_fk_1,x
        tay
        lda screen_x,y
        sta zp_cx
        lda screen_y,y
        sta zp_cy

        lda mesh_fcol_1,x
        sta zp_color
.if RASTERIZE
        jmp draw_triangle       ; tail call
.else
        rts                     ; skip rasterization
.endif

_rm_idx_0       .byte 0
_rm_idx_1       .byte 0
_rm_z0          .byte 0
