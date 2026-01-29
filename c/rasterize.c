#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rasterize.h"

/* Lookup tables for bit patterns */
static unsigned char top_row_mask[4];    /* Mask for top row pixels */
static unsigned char bottom_row_mask[4]; /* Mask for bottom row pixels */

/* Lookup table for row offset: y * CHAR_WIDTH (avoids multiply by 40) */
static int row_offset[CHAR_HEIGHT];

static int tables_initialized = 0;

static void init_tables(void) {
    if (tables_initialized) return;

    /* For top row (left pixel, right pixel): */
    /* 00 = neither, 01 = right only, 10 = left only, 11 = both */
    top_row_mask[0] = 0;                                      /* neither */
    top_row_mask[1] = PIXEL_TR_MASK;                          /* right only */
    top_row_mask[2] = PIXEL_TL_MASK;                          /* left only */
    top_row_mask[3] = PIXEL_TL_MASK | PIXEL_TR_MASK;          /* both */

    /* Same for bottom row */
    bottom_row_mask[0] = 0;
    bottom_row_mask[1] = PIXEL_BR_MASK;
    bottom_row_mask[2] = PIXEL_BL_MASK;
    bottom_row_mask[3] = PIXEL_BL_MASK | PIXEL_BR_MASK;

    /* Row offsets: 0, 40, 80, 120, ... */
    for (int y = 0; y < CHAR_HEIGHT; y++) {
        row_offset[y] = y * CHAR_WIDTH;
    }

    tables_initialized = 1;
}

void clear_screen(unsigned char *buf, unsigned char color) {
    /* Color occupies 2 bits, replicate to all 4 pixel positions */
    unsigned char byte = (color << PIXEL_TL_SHIFT) |
                         (color << PIXEL_TR_SHIFT) |
                         (color << PIXEL_BL_SHIFT) |
                         (color << PIXEL_BR_SHIFT);
    memset(buf, byte, SCREEN_SIZE);
}

void set_pixel(unsigned char *buf, int x, int y, unsigned char color) {
    init_tables();
    if (x < 0 || x >= SCREEN_WIDTH || y < 0 || y >= SCREEN_HEIGHT) return;

    int char_x = x >> 1;
    int char_y = y >> 1;
    int sub_x = x & 1;  /* 0 = left, 1 = right */
    int sub_y = y & 1;  /* 0 = top, 1 = bottom */

    int offset = row_offset[char_y] + char_x;
    int shift, mask;

    if (sub_y == 0) {
        /* Top row */
        shift = sub_x ? PIXEL_TR_SHIFT : PIXEL_TL_SHIFT;
        mask = sub_x ? PIXEL_TR_MASK : PIXEL_TL_MASK;
    } else {
        /* Bottom row */
        shift = sub_x ? PIXEL_BR_SHIFT : PIXEL_BL_SHIFT;
        mask = sub_x ? PIXEL_BR_MASK : PIXEL_BL_MASK;
    }

    buf[offset] = (buf[offset] & ~mask) | ((color << shift) & mask);
}

unsigned char get_pixel(const unsigned char *buf, int x, int y) {
    init_tables();
    if (x < 0 || x >= SCREEN_WIDTH || y < 0 || y >= SCREEN_HEIGHT) return 0;

    int char_x = x >> 1;
    int char_y = y >> 1;
    int sub_x = x & 1;
    int sub_y = y & 1;

    int offset = row_offset[char_y] + char_x;
    int shift;

    if (sub_y == 0) {
        shift = sub_x ? PIXEL_TR_SHIFT : PIXEL_TL_SHIFT;
    } else {
        shift = sub_x ? PIXEL_BR_SHIFT : PIXEL_BL_SHIFT;
    }

    return (buf[offset] >> shift) & 3;
}

/* Draw a horizontal span on a TOP row (y is even).
 * Only modifies top 4 bits of each character byte, preserving bottom row.
 * Assumes all coordinates are on-screen.
 */
static void draw_span_top(unsigned char *buf, int y, int xl, int xr, unsigned char color) {
    init_tables();

    if (xl >= xr) return;  /* Empty interval */

    int char_y = y >> 1;
    unsigned char *row = buf + row_offset[char_y];

    /* Top row masks and color pattern */
    unsigned char mask_left  = PIXEL_TR_MASK;                   /* 0x30: right pixel only */
    unsigned char mask_right = PIXEL_TL_MASK;                   /* 0xC0: left pixel only */
    unsigned char mask_full  = PIXEL_TL_MASK | PIXEL_TR_MASK;   /* 0xF0: both pixels */
    unsigned char color_bits = (color << PIXEL_TL_SHIFT) | (color << PIXEL_TR_SHIFT);

    /* Character ranges */
    int char_start = xl >> 1;
    int full_start = (xl + 1) >> 1;
    int full_end   = xr >> 1;
    int char_end   = (xr + 1) >> 1;

    /* Left partial (xl is odd → only right pixel) */
    if (char_start < full_start) {
        row[char_start] = (row[char_start] & ~mask_left) | (color_bits & mask_left);
    }

    /* Full chars (both pixels, preserve bottom row) */
    for (int char_x = full_start; char_x < full_end; char_x++) {
        row[char_x] = (row[char_x] & ~mask_full) | color_bits;
    }

    /* Right partial (xr is odd → only left pixel) */
    if (full_end < char_end) {
        row[full_end] = (row[full_end] & ~mask_right) | (color_bits & mask_right);
    }
}

/* Draw a horizontal span on a BOTTOM row (y is odd).
 * Only modifies bottom 4 bits of each character byte, preserving top row.
 * Assumes all coordinates are on-screen.
 */
static void draw_span_bottom(unsigned char *buf, int y, int xl, int xr, unsigned char color) {
    init_tables();

    if (xl >= xr) return;  /* Empty interval */

    int char_y = y >> 1;
    unsigned char *row = buf + row_offset[char_y];

    /* Bottom row masks and color pattern */
    unsigned char mask_left  = PIXEL_BR_MASK;                   /* 0x03: right pixel only */
    unsigned char mask_right = PIXEL_BL_MASK;                   /* 0x0C: left pixel only */
    unsigned char mask_full  = PIXEL_BL_MASK | PIXEL_BR_MASK;   /* 0x0F: both pixels */
    unsigned char color_bits = (color << PIXEL_BL_SHIFT) | (color << PIXEL_BR_SHIFT);

    /* Character ranges */
    int char_start = xl >> 1;
    int full_start = (xl + 1) >> 1;
    int full_end   = xr >> 1;
    int char_end   = (xr + 1) >> 1;

    /* Left partial (xl is odd → only right pixel) */
    if (char_start < full_start) {
        row[char_start] = (row[char_start] & ~mask_left) | (color_bits & mask_left);
    }

    /* Full chars (both pixels, preserve top row) */
    for (int char_x = full_start; char_x < full_end; char_x++) {
        row[char_x] = (row[char_x] & ~mask_full) | color_bits;
    }

    /* Right partial (xr is odd → only left pixel) */
    if (full_end < char_end) {
        row[full_end] = (row[full_end] & ~mask_right) | (color_bits & mask_right);
    }
}

/* Draw both rows on interval [xl, xr) where BOTH rows are fully active.
 * y is the top scanline (must be even).
 * This is much simpler than the general case - no per-row boundary logic needed.
 * Assumes all coordinates are on-screen and y is even.
 *
 * Optimized structure:
 *   1. Left partial char (if xl is odd): only right pixel active
 *   2. Middle full chars: write color_pattern directly (no masking)
 *   3. Right partial char (if xr is odd): only left pixel active
 */
static void draw_dual_row_simple(unsigned char *buf, int y, int xl, int xr,
                                 unsigned char color) {
    init_tables();

    if (xl >= xr) return;  /* Empty interval */

    int char_y = y >> 1;
    unsigned char *row = buf + row_offset[char_y];

    /* Build the color pattern once */
    unsigned char color_pattern = (color << PIXEL_TL_SHIFT) |
                                  (color << PIXEL_TR_SHIFT) |
                                  (color << PIXEL_BL_SHIFT) |
                                  (color << PIXEL_BR_SHIFT);

    /* Character ranges:
     * - char_start to char_end: all chars that have any coverage
     * - full_start to full_end: chars with full coverage (all 4 pixels)
     */
    int char_start = xl >> 1;
    int char_end = (xr + 1) >> 1;
    int full_start = (xl + 1) >> 1;  /* First full char (skips left partial) */
    int full_end = xr >> 1;          /* One past last full char */

    /* Left partial character (xl is odd → only right pixel active) */
    if (char_start < full_start) {
        unsigned char mask = top_row_mask[1] | bottom_row_mask[1];  /* right only */
        row[char_start] = (row[char_start] & ~mask) | (color_pattern & mask);
    }

    /* Full characters: all 4 pixels, no masking needed */
    for (int char_x = full_start; char_x < full_end; char_x++) {
        row[char_x] = color_pattern;
    }

    /* Right partial character (xr is odd → only left pixel active) */
    if (full_end < char_end) {
        unsigned char mask = top_row_mask[2] | bottom_row_mask[2];  /* left only */
        row[full_end] = (row[full_end] & ~mask) | (color_pattern & mask);
    }
}

/* Interval-based dual-row blitter using decision tree.
 * y is the top scanline (must be even).
 * xl1, xr1: interval for row 1 (top row, y)
 * xl2, xr2: interval for row 2 (bottom row, y+1)
 *
 * Uses 2-3 comparisons to determine ordering, then calls appropriate
 * blitter (single-row or dual-row) for each interval.
 */
static void draw_dual_row_intervals(unsigned char *buf, int y, int xl1, int xr1,
                                    int xl2, int xr2, unsigned char color) {
    /* Handle empty rows */
    if (xl1 >= xr1 && xl2 >= xr2) return;  /* Both empty */
    if (xl1 >= xr1) {
        /* Only row 2 (bottom) */
        draw_span_bottom(buf, y + 1, xl2, xr2, color);
        return;
    }
    if (xl2 >= xr2) {
        /* Only row 1 (top) */
        draw_span_top(buf, y, xl1, xr1, color);
        return;
    }

    /* Decision tree: 2-3 comparisons to determine ordering of {xl1, xr1, xl2, xr2} */
    if (xl1 <= xl2) {
        if (xr2 <= xr1) {
            /* CASE 1: Row 2 inside row 1
             * Order: xl1 <= xl2 <= xr2 <= xr1
             * Intervals: [xl1,xl2)={1}, [xl2,xr2)={1,2}, [xr2,xr1)={1} */
            draw_span_top(buf, y, xl1, xl2, color);              /* {1} */
            draw_dual_row_simple(buf, y, xl2, xr2, color);       /* {1,2} */
            draw_span_top(buf, y, xr2, xr1, color);              /* {1} */
        } else {
            /* xr1 < xr2: Need third comparison for overlap check */
            if (xl2 <= xr1) {
                /* CASE 2.1: Overlapping
                 * Order: xl1 <= xl2 <= xr1 <= xr2
                 * Intervals: [xl1,xl2)={1}, [xl2,xr1)={1,2}, [xr1,xr2)={2} */
                draw_span_top(buf, y, xl1, xl2, color);              /* {1} */
                draw_dual_row_simple(buf, y, xl2, xr1, color);       /* {1,2} */
                draw_span_bottom(buf, y + 1, xr1, xr2, color);       /* {2} */
            } else {
                /* CASE 2.2: Disjoint (empty middle)
                 * Order: xl1 <= xr1 < xl2 <= xr2
                 * Intervals: [xl1,xr1)={1}, [xr1,xl2)={}, [xl2,xr2)={2} */
                draw_span_top(buf, y, xl1, xr1, color);              /* {1} */
                /* gap [xr1, xl2) has active set {} - nothing to draw */
                draw_span_bottom(buf, y + 1, xl2, xr2, color);       /* {2} */
            }
        }
    } else {
        /* xl2 < xl1 */
        if (xr1 < xr2) {
            /* CASE 4: Row 1 inside row 2
             * Order: xl2 < xl1 <= xr1 < xr2
             * Intervals: [xl2,xl1)={2}, [xl1,xr1)={1,2}, [xr1,xr2)={2} */
            draw_span_bottom(buf, y + 1, xl2, xl1, color);       /* {2} */
            draw_dual_row_simple(buf, y, xl1, xr1, color);       /* {1,2} */
            draw_span_bottom(buf, y + 1, xr1, xr2, color);       /* {2} */
        } else {
            /* xr2 <= xr1: Need third comparison for overlap check */
            if (xl1 <= xr2) {
                /* CASE 3.1: Overlapping
                 * Order: xl2 < xl1 <= xr2 <= xr1
                 * Intervals: [xl2,xl1)={2}, [xl1,xr2)={1,2}, [xr2,xr1)={1} */
                draw_span_bottom(buf, y + 1, xl2, xl1, color);       /* {2} */
                draw_dual_row_simple(buf, y, xl1, xr2, color);       /* {1,2} */
                draw_span_top(buf, y, xr2, xr1, color);              /* {1} */
            } else {
                /* CASE 3.2: Disjoint (empty middle)
                 * Order: xl2 <= xr2 < xl1 <= xr1
                 * Intervals: [xl2,xr2)={2}, [xr2,xl1)={}, [xl1,xr1)={1} */
                draw_span_bottom(buf, y + 1, xl2, xr2, color);       /* {2} */
                /* gap [xr2, xl1) has active set {} - nothing to draw */
                draw_span_top(buf, y, xl1, xr1, color);              /* {1} */
            }
        }
    }
}

/* Swap two integers */
static void swap_int(int *a, int *b) {
    int t = *a; *a = *b; *b = t;
}

void draw_triangle(unsigned char *buf, int ax, int ay, int bx, int by,
                   int cx, int cy, unsigned char color) {
    /* Backface culling: check winding order BEFORE sorting.
     * det(B-A, C-A) = (bx-ax)*(cy-ay) - (by-ay)*(cx-ax)
     * If det < 0, triangle is backfacing (clockwise), reject it.
     * Fits in 16 bits: coords are 0-79 x 0-49, max det magnitude ~7742. */
    int det = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (det < 0) {
        return;  /* Backface: clockwise winding, cull */
    }

    /* Sort vertices by y-coordinate: A.y <= B.y <= C.y
     * Track swap parity to derive b_on_left from original det. */
    int swaps = 0;
    if (ay > by) { swap_int(&ax, &bx); swap_int(&ay, &by); swaps++; }
    if (by > cy) { swap_int(&bx, &cx); swap_int(&by, &cy); swaps++; }
    if (ay > by) { swap_int(&ax, &bx); swap_int(&ay, &by); swaps++; }

    /* Now: ay <= by <= cy */

    /* Degenerate: all points on same scanline */
    if (ay == cy) {
        return;  /* Zero-height triangle, nothing to draw */
    }

    /* b_on_left: derived from original det and swap parity.
     * Each swap negates the cross product sign.
     * det >= 0, so b_on_left = true iff odd number of swaps. */
    int b_on_left = (swaps & 1);

    /* Compute edge slopes in 8.8 fixed point: 256 * dx / dy */
    int dx_ac = ((cx - ax) << 8) / (cy - ay);

    /* Start positions: at scanline ay, we sample at ay + 0.5
     * So x = ax + slope * 0.5 = ax + dx/2 */
    int x_long = (ax << 8) + (dx_ac >> 1);
    int x_short;

    int y = ay;

    /* Top trapezoid: from A.y to B.y */
    if (ay < by) {
        int dx_ab = ((bx - ax) << 8) / (by - ay);
        x_short = (ax << 8) + (dx_ab >> 1);

        while (y < by) {
            int y_next = y + 1;

            /* Get x endpoints for current scanline [xl, xr) */
            int xl = (b_on_left ? x_short : x_long) >> 8;
            int xr = (b_on_left ? x_long : x_short) >> 8;
            if (xl > xr) swap_int(&xl, &xr);

            /* Check if we can process two rows */
            if (((y & 1) == 0) && (y_next < by)) {
                /* Advance to get second row endpoints */
                int x_long2 = x_long + dx_ac;
                int x_short2 = x_short + dx_ab;

                int xl2 = (b_on_left ? x_short2 : x_long2) >> 8;
                int xr2 = (b_on_left ? x_long2 : x_short2) >> 8;
                if (xl2 > xr2) swap_int(&xl2, &xr2);

                draw_dual_row_intervals(buf, y, xl, xr, xl2, xr2, color);

                x_long += dx_ac << 1;
                x_short += dx_ab << 1;
                y += 2;
            } else if (((y & 1) == 0) && (y_next >= by)) {
                /* Single row at even y - draw top row only */
                draw_span_top(buf, y, xl, xr, color);
                x_long += dx_ac;
                x_short += dx_ab;
                y++;
            } else {
                /* Odd y - draw single span on bottom row */
                draw_span_bottom(buf, y, xl, xr, color);
                x_long += dx_ac;
                x_short += dx_ab;
                y++;
            }
        }
    }

    /* Bottom trapezoid: from B.y to C.y */
    if (by < cy) {
        int dx_bc = ((cx - bx) << 8) / (cy - by);

        /* x_long continues from where the top trapezoid left off.
         * Do NOT recompute - that would accumulate rounding differently.
         * For flat-top triangles (ay == by), x_long was initialized correctly. */

        /* Short edge starts at B, sampling at by + 0.5 */
        x_short = (bx << 8) + (dx_bc >> 1);

        while (y < cy) {
            int y_next = y + 1;

            /* [xl, xr) */
            int xl = (b_on_left ? x_short : x_long) >> 8;
            int xr = (b_on_left ? x_long : x_short) >> 8;
            if (xl > xr) swap_int(&xl, &xr);

            if (((y & 1) == 0) && (y_next < cy)) {
                int x_long2 = x_long + dx_ac;
                int x_short2 = x_short + dx_bc;

                int xl2 = (b_on_left ? x_short2 : x_long2) >> 8;
                int xr2 = (b_on_left ? x_long2 : x_short2) >> 8;
                if (xl2 > xr2) swap_int(&xl2, &xr2);

                draw_dual_row_intervals(buf, y, xl, xr, xl2, xr2, color);

                x_long += dx_ac << 1;
                x_short += dx_bc << 1;
                y += 2;
            } else if (((y & 1) == 0) && (y_next >= cy)) {
                /* Single row at even y - draw top row only */
                draw_span_top(buf, y, xl, xr, color);
                x_long += dx_ac;
                x_short += dx_bc;
                y++;
            } else {
                /* Odd y - draw single span on bottom row */
                draw_span_bottom(buf, y, xl, xr, color);
                x_long += dx_ac;
                x_short += dx_bc;
                y++;
            }
        }
    }
}

void save_screen(const unsigned char *buf, const char *filename) {
    FILE *f = fopen(filename, "wb");
    if (!f) {
        fprintf(stderr, "Error: cannot open %s for writing\n", filename);
        return;
    }
    fwrite(buf, 1, SCREEN_SIZE, f);
    fclose(f);
}

void load_screen(unsigned char *buf, const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "Error: cannot open %s for reading\n", filename);
        memset(buf, 0, SCREEN_SIZE);
        return;
    }
    size_t n = fread(buf, 1, SCREEN_SIZE, f);
    if (n != SCREEN_SIZE) {
        fprintf(stderr, "Warning: read only %zu bytes from %s\n", n, filename);
    }
    fclose(f);
}
