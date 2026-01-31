# C64 3D Rasterizer Performance Profile

## Model Stats
| Model | Vertices | Faces | Animation Frames |
|-------|----------|-------|------------------|
| Octahedron | 6 | 8 | N/A (rotating) |
| Zombie | 151 | 295 (147+148) | 24 |

## Current FPS (PAL 50Hz)
| Model | Full Render | Geometry Only | Rasterization Only |
|-------|-------------|---------------|---------------------|
| Octahedron | 20.76 FPS | 43.31 FPS | - |
| Zombie | 2.06 FPS | 3.75 FPS | - |

## Time Breakdown (ms per frame)
| Model | Total | Geometry | Rasterization | Geometry % |
|-------|-------|----------|---------------|------------|
| Octahedron | 48.9 | 23.1 | 25.8 | 47% |
| Zombie | 490 | 267 | 223 | 54% |

Geometry and rasterization are roughly 50/50 for both models.

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

### Considered but Not Implemented
1. **SMC for single-row endpoints** - patching cost (~20 cycles) exceeds savings (~3 cycles)
2. **Per-color specialized blitters** - 4x code size, marginal gain (~12-14 cycles per partial)
3. **Unrolled inner loops** - code size tradeoff

## Compile-Time Flags
- `BACKFACE_CULL=1` - enable/disable backface culling
- `RASTERIZE=1` - enable/disable rasterization (for geometry-only benchmarks)
- `FLIP_ZSORT=1` - reverse Z-sort order for correct depth
- `GRUNT_MESH=0/1` - octahedron vs zombie build
