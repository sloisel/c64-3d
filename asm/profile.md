# Rasterizer Performance Profile

## Current Status
- **Cycle count**: ~46,000 cycles (draw_demo_cube)
- **Speedup**: 87% faster than baseline

## Timing Method
- `tic`: Disables CIA interrupts, sets up VIC raster interrupt at line 0, waits for counter=0
- `toc`: Captures counter + raster position with stable reads
- Cycles = (counter × 19656) + (raster_line × 63)
- IRQ handler skips KERNAL (jmp $ea81) for minimal overhead
- Timing is now rock-solid: same values every run

## Optimization History

| Step | Description | Frames | Raster | ~Cycles | Speedup |
|------|-------------|--------|--------|---------|---------|
| Baseline | Original draw_dual_row | 17 | 289 | 344,000 | - |
| Step 2 | Middle segment tight STA | 12 | 256 | 244,000 | 29% |
| Step 3 | [xl,xr) exclusive + left segment | 10 | 211 | 210,000 | 39% |
| Step 4 | Interval-based blitter | 5 | 64 | 102,000 | 70% |
| Step 5 | SMC dual-row + ZP single-row | 5 | 91 | 100,000 | 71% |
| Step 6 | Skip KERNAL IRQ handler | 2 | 108 | 46,000 | 87% |

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
- **10-cycle SMC inner loop** in draw_dual_row_simple:
  - Self-modifying code patches STA absolute address
  - `sta $xxxx,x / dex / bpl` = 5+2+3 = 10 cycles per char
- **Zero-page optimization** in single-row blitters:
  - Color bits and full_end stored in ZP (zp_adj_lo/hi)
  - Saves 2 cycles per char (27 vs 29 cycles)

### Timing Improvements
- Disabled CIA-1 interrupts during timing (prevents KERNAL keyboard scan)
- IRQ handler uses `asl $d019` to acknowledge + `jmp $ea81` to skip KERNAL
- Stable reads in toc() prevent raster position jitter

### Code Size
- Old draw_dual_row + draw_span: ~500 lines
- New interval-based blitters: ~450 lines
- Net: similar size, 2x faster
