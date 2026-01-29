# Rasterizer Performance Profile

## Current Status
- **Cycle count**: ~102,000 cycles (draw_demo_cube)
- **Speedup**: 70% faster than baseline

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
| Step 4 | Interval-based blitter | 5 | 64 | 102,000 | 70% |

## Current Architecture (Step 4)

### Interval-Based Dual-Row Blitter
Replaced segment-based draw_dual_row with decision tree dispatcher:

1. **draw_dual_row_intervals**: Uses 2-3 comparisons to classify row relationships:
   - CASE 1: Row 2 inside row 1 → {1}, {1,2}, {1}
   - CASE 2.1: Overlapping, row 2 extends right → {1}, {1,2}, {2}
   - CASE 2.2: Disjoint, row 2 to the right → {1}, {2}
   - CASE 3.1: Overlapping, row 1 extends right → {2}, {1,2}, {1}
   - CASE 3.2: Disjoint, row 1 to the right → {2}, {1}
   - CASE 4: Row 1 inside row 2 → {2}, {1,2}, {2}

2. **draw_span_top**: Top row only (even y), masks $30/$C0/$F0
3. **draw_span_bottom**: Bottom row only (odd y), masks $03/$0C/$0F
4. **draw_dual_row_simple**: Both rows on same interval, full chars use direct STA

### Key Optimizations
- No per-pixel inner loop - processes intervals directly
- Full characters in draw_dual_row_simple: direct write, no masking
- Lookup tables for color patterns: color_top, color_bottom, color_pattern
- Bifurcated routines: no runtime y&1 check in span routines

### Code Size
- Old draw_dual_row + draw_span: ~500 lines
- New interval-based blitters: ~450 lines
- Net: similar size, 2x faster
