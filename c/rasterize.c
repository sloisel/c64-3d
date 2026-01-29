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

/* Draw a horizontal span on a single scanline */
static void draw_span(unsigned char *buf, int y, int xl, int xr, unsigned char color) {
    for (int x = xl; x < xr; x++) {
        set_pixel(buf, x, y, color);
    }
}

/* Draw two scanlines at once (dual-row optimization)
 * y is the top scanline (must be even)
 * xl1, xr1: left and right endpoints for top row
 * xl2, xr2: left and right endpoints for bottom row
 */
static void draw_dual_row(unsigned char *buf, int y, int xl1, int xr1,
                          int xl2, int xr2, unsigned char color) {
    init_tables();

    if (y < 0 || y >= SCREEN_HEIGHT - 1) return;
    if (y & 1) return;  /* Must be even */

    int char_y = y >> 1;
    int base_offset = row_offset[char_y];

    /* Clamp to screen bounds */
    if (xl1 < 0) xl1 = 0;
    if (xl2 < 0) xl2 = 0;
    if (xr1 > SCREEN_WIDTH) xr1 = SCREEN_WIDTH;
    if (xr2 > SCREEN_WIDTH) xr2 = SCREEN_WIDTH;

    /* Find the overall x range and align to character boundaries */
    int x_min = (xl1 < xl2) ? xl1 : xl2;
    int x_max = (xr1 > xr2) ? xr1 : xr2;

    /* Start at character boundary containing x_min */
    int char_start = x_min >> 1;
    int char_end = (x_max + 1) >> 1;

    /* Process each character column */
    for (int char_x = char_start; char_x < char_end; char_x++) {
        if (char_x < 0 || char_x >= CHAR_WIDTH) continue;

        int offset = base_offset + char_x;

        /* Determine which pixels in this character are covered */
        int px_left = char_x << 1;
        int px_right = (char_x << 1) + 1;

        /* Top row coverage */
        int top_left = (px_left >= xl1 && px_left < xr1) ? 1 : 0;
        int top_right = (px_right >= xl1 && px_right < xr1) ? 1 : 0;
        int top_bits = (top_left << 1) | top_right;

        /* Bottom row coverage */
        int bot_left = (px_left >= xl2 && px_left < xr2) ? 1 : 0;
        int bot_right = (px_right >= xl2 && px_right < xr2) ? 1 : 0;
        int bot_bits = (bot_left << 1) | bot_right;

        /* Build the masks */
        unsigned char set_mask = top_row_mask[top_bits] | bottom_row_mask[bot_bits];

        if (set_mask == 0) continue;

        /* Build the color pattern */
        unsigned char color_pattern = (color << PIXEL_TL_SHIFT) |
                                      (color << PIXEL_TR_SHIFT) |
                                      (color << PIXEL_BL_SHIFT) |
                                      (color << PIXEL_BR_SHIFT);

        /* If all 4 pixels are set, just write */
        if (set_mask == 0xFF) {
            buf[offset] = color_pattern;
        } else {
            /* Read-modify-write */
            buf[offset] = (buf[offset] & ~set_mask) | (color_pattern & set_mask);
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

                draw_dual_row(buf, y, xl, xr, xl2, xr2, color);

                x_long += dx_ac << 1;
                x_short += dx_ab << 1;
                y += 2;
            } else if (((y & 1) == 0) && (y_next >= by)) {
                /* Single row at even y, use dual row with empty second row */
                draw_dual_row(buf, y, xl, xr, 0, 0, color);
                x_long += dx_ac;
                x_short += dx_ab;
                y++;
            } else {
                /* Odd y - draw single span */
                draw_span(buf, y, xl, xr, color);
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

                draw_dual_row(buf, y, xl, xr, xl2, xr2, color);

                x_long += dx_ac << 1;
                x_short += dx_bc << 1;
                y += 2;
            } else if (((y & 1) == 0) && (y_next >= cy)) {
                draw_dual_row(buf, y, xl, xr, 0, 0, color);
                x_long += dx_ac;
                x_short += dx_bc;
                y++;
            } else {
                draw_span(buf, y, xl, xr, color);
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
