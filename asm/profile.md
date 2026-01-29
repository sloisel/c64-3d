# Rasterizer Performance Profile

## Current Status
- **Cycle count**: ~210,000 cycles (draw_demo_cube)
- **Speedup**: 39% faster than baseline

## Timing Method
- `tic`: Sets up raster interrupt at line 0, waits for counter=0, then returns
- `toc`: Captures counter + raster position
- Cycles = (counter × 19656) + (raster_line × 63)

## Optimization History

| Step | Description | Frames | Raster | ~Cycles | Speedup |
|------|-------------|--------|--------|---------|---------|
| Baseline | Original draw_dual_row | 17 | 289 | 344,000 | - |
| Step 2 | Middle segment tight STA | 12 | 256 | 244,000 | 29% |
| Step 3 | [xl,xr) exclusive + left segment | 10 | 211 | 210,000 | 39% |

## Implementation Notes
- Middle segment: checks if char is in "tight" range (all 4 pixels set)
- Tight chars: direct STA write
- Edge chars: fall back to full inner loop
- tight_mid_start = (max_xl + 1) >> 1
- tight_mid_end = (min_xr - 1) >> 1
