# C64 3D Rasterizer Performance Profile

## Model Stats
| Model | Vertices | Faces | Animation Frames |
|-------|----------|-------|------------------|
| Octahedron | 6 | 8 | N/A (rotating) |
| Zombie | 151 | 295 (147+148) | 24 |

## Current FPS (PAL 50Hz)
| Model | Full Render | Geometry Only | Rasterization Only |
|-------|-------------|---------------|---------------------|
| Octahedron | 24.88 FPS | 43.31 FPS | - |
| Zombie | 2.50 FPS | 3.75 FPS | - |

### FPS History
| Date | Octahedron | Zombie | Notes |
|------|------------|--------|-------|
| Baseline | 20.76 FPS | 2.06 FPS | Before optimizations |
| 2026-01-31a | 21.26 FPS | 2.17 FPS | Inline mul16s_8u_hi_m macro |
| 2026-01-31b | 22.43 FPS | 2.22 FPS | ZP temps, radix sort, sign extend |
| 2026-01-31c | 24.68 FPS | 2.47 FPS | Backface culling ZP reuse |
| 2026-01-31d | 24.88 FPS | 2.50 FPS | Radix sort SMC optimizations |

## Time Breakdown (ms per frame)
| Model | Total | Geometry | Rasterization | Geometry % |
|-------|-------|----------|---------------|------------|
| Octahedron | 40.2 | ~19 | ~21 | ~47% |
| Zombie | 400 | ~216 | ~184 | ~54% |

Geometry and rasterization are roughly 50/50 for both models.

## Cycle Estimates (from FPS)
PAL C64: 985,248 Hz, 50 Hz refresh, ~19,705 cycles/vsync

| Model | Vsyncs/Frame | Cycles/Frame |
|-------|--------------|--------------|
| Octahedron | 2.01 | ~39,600 |
| Zombie | 20.00 | ~394,000 |

## Backface Culling Impact (measured at baseline)
| Model | Culling ON | Culling OFF | Speedup |
|-------|------------|-------------|---------|
| Octahedron | 20.47 FPS | 12.37 FPS | 1.65x |
| Zombie | 2.04 FPS | 1.54 FPS | 1.32x |

Backface culling is definitely worth keeping.

## Cycle Counts

### Screen Clear
- Total: ~6,413 cycles (~6.4 ms)
- 4 stores per iteration, 256 iterations

### Dual-Row Blitter (draw_dual_row_simple)
- Inner loop: 10 cycles/char (full overwrite, no RMW)
- Endpoints: ~22-27 cycles each (RMW with indirect indexed)

### Single-Row Blitter (draw_span_top/bottom)
- Inner loop: 26 cycles/char (must preserve other half-row, RMW required)
- Endpoints: similar to dual-row

### Why Single-Row is Slower
Single-row must read-modify-write to preserve the other half of the character:
```
cpy zp_adj_hi           ; 3
bcs done                ; 2/3
lda (zp_screen_lo),y    ; 5 (read)
and #$0f                ; 2
ora zp_adj_lo           ; 3
sta (zp_screen_lo),y    ; 6 (write)
iny                     ; 2
bne loop                ; 3
                        ; = 26 cycles/char
```

vs dual-row which overwrites entirely:
```
lda zp_blit_color       ; (outside loop)
sta $ffff,x             ; 5 (SMC address)
dex                     ; 2
bpl loop                ; 3
                        ; = 10 cycles/char
```

## Optimizations Applied

### Implemented
1. **Backface culling** - 1.32-1.65x speedup
2. **Z-sort with XOR trick** - compile-time constant instead of per-vertex negation
3. **Wider FOV** - 32*x/z projection with direct z8 indexing
4. **ZP temps for blitters** - saves 1 cycle per access
5. **Pre-masked color tables** - saves AND instruction (2 cycles) per partial
6. **Triple buffering** - smooth animation without tearing
7. **Inlined draw_dual_row_intervals** - eliminates JSR/RTS overhead
8. **Rotation: subtraction instead of negation** - rot_z = c*lz - s*lx instead of -s*lx + c*lz, saves 9 cycles/vertex (~1,359 cycles/frame for zombie)
9. **Eliminate y restore in intervals** - use saved_y directly at return point, saves 7 cycles on restore paths (~4,200 cycles/frame for zombie)
10. **Inline mul16s_8u_hi_m macro** (2026-01-31) - replaced subroutine call (~142-175 cycles) with inline macro (~93 cycles) for perspective projection. Added signed×unsigned quarter-square tables (su_sum/su_diff, 2KB). Speedup: 2.4% octahedron (20.76→21.26), 5.3% zombie (2.06→2.17)
11. **Geometry micro-optimizations** (2026-01-31) - ZP temps for transform (~1 cycle/access), radix sort prefix sum redundant load removal, compact sign extension pattern, jmp→bne in loops. Speedup: 5.5% octahedron (21.26→22.43), 2.3% zombie (2.17→2.22)
12. **Backface culling ZP reuse** (2026-01-31) - Reuse zp_det_t1-t4 for intermediate products instead of main memory temporaries, use X/Y registers to hold values. Saves ~8 cycles per triangle from ZP access and reduced stores. Speedup: 10% octahedron (22.43→24.68), 11% zombie (2.22→2.47)
13. **Radix sort SMC optimizations** (2026-01-31) - Pre-XOR rot_z when storing (saves eor in count+scatter), page-aligned radix_count with SMC `inc` in count phase (saves lda/clc/adc/sta), SMC for face index in scatter. Saves ~10 cycles/face in sort. Speedup: 0.8% octahedron (24.68→24.88), 1.2% zombie (2.47→2.50)

### Considered but Not Implemented
1. **SMC for single-row endpoints** - patching cost (~20 cycles) exceeds savings (~3 cycles)
2. **Per-color specialized blitters** - 4x code size, marginal gain (~12-14 cycles per partial)
3. **Unrolled inner loops** - code size tradeoff

## Compile-Time Flags
- `BACKFACE_CULL=1` - enable/disable backface culling
- `RASTERIZE=1` - enable/disable rasterization (for geometry-only benchmarks)
- `FLIP_ZSORT=1` - reverse Z-sort order for correct depth
- `GRUNT_MESH=0/1` - octahedron vs zombie build
