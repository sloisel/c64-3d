#ifndef RASTERIZE_H
#define RASTERIZE_H

/* Screen dimensions */
#define SCREEN_WIDTH  80   /* Chunky pixels */
#define SCREEN_HEIGHT 50   /* Chunky pixels */
#define CHAR_WIDTH    40   /* Characters */
#define CHAR_HEIGHT   25   /* Characters */
#define SCREEN_SIZE   1000 /* Bytes in buffer */

/* Fixed-point 8.8 format */
#define FP_SHIFT 8
#define FP_ONE   (1 << FP_SHIFT)
#define FP_HALF  (1 << (FP_SHIFT - 1))

/* Convert integer to fixed-point */
#define INT_TO_FP(x) ((x) << FP_SHIFT)

/* Convert fixed-point to integer (truncate) */
#define FP_TO_INT(x) ((x) >> FP_SHIFT)

/* Chunky pixel bit positions within a character byte:
 * bits 7-6: top-left
 * bits 5-4: top-right
 * bits 3-2: bottom-left
 * bits 1-0: bottom-right
 */
#define PIXEL_TL_SHIFT 6
#define PIXEL_TR_SHIFT 4
#define PIXEL_BL_SHIFT 2
#define PIXEL_BR_SHIFT 0

#define PIXEL_TL_MASK (3 << PIXEL_TL_SHIFT)
#define PIXEL_TR_MASK (3 << PIXEL_TR_SHIFT)
#define PIXEL_BL_MASK (3 << PIXEL_BL_SHIFT)
#define PIXEL_BR_MASK (3 << PIXEL_BR_SHIFT)

/* Clear the screen buffer to a single color (0-3) */
void clear_screen(unsigned char *buf, unsigned char color);

/* Draw a filled triangle with vertices (ax,ay), (bx,by), (cx,cy) and color (0-3) */
void draw_triangle(unsigned char *buf, int ax, int ay, int bx, int by,
                   int cx, int cy, unsigned char color);

/* Set a single chunky pixel (for reference rasterizer) */
void set_pixel(unsigned char *buf, int x, int y, unsigned char color);

/* Get a single chunky pixel value */
unsigned char get_pixel(const unsigned char *buf, int x, int y);

/* Save screen buffer to a raw binary file */
void save_screen(const unsigned char *buf, const char *filename);

/* Load screen buffer from a raw binary file */
void load_screen(unsigned char *buf, const char *filename);

#endif /* RASTERIZE_H */
