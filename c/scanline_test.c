/* scanline_test.c - Generate expected output for scanline tests */
#include <stdio.h>
#include <string.h>
#include "rasterize.h"

/* Draw a horizontal span using set_pixel (matches draw_span in asm) */
static void test_draw_span(unsigned char *buf, int y, int xl, int xr, unsigned char color) {
    for (int x = xl; x <= xr; x++) {
        set_pixel(buf, x, y, color);
    }
}

/* Draw two rows - simplified version matching the asm interface */
static void test_draw_dual_row(unsigned char *buf, int y, int xl1, int xr1,
                                int xl2, int xr2, unsigned char color) {
    /* Top row (y) */
    for (int x = xl1; x <= xr1; x++) {
        set_pixel(buf, x, y, color);
    }
    /* Bottom row (y+1) */
    for (int x = xl2; x <= xr2; x++) {
        set_pixel(buf, x, y + 1, color);
    }
}

int main(void) {
    unsigned char buf[SCREEN_SIZE];

    /* Clear to color 0 */
    clear_screen(buf, 0);

    /* Test 1: draw_span at y=10, x=20 to x=40, color 1 */
    test_draw_span(buf, 10, 20, 40, 1);

    /* Test 2: draw_dual_row at y=20, top x=10-30, bottom x=15-35, color 2 */
    test_draw_dual_row(buf, 20, 10, 30, 15, 35, 2);

    /* Test 3: draw_span at y=30, x=0 to x=79 (full width), color 3 */
    test_draw_span(buf, 30, 0, 79, 3);

    /* Test 4: draw_dual_row at y=40, x=38-42 both rows, color 1 */
    test_draw_dual_row(buf, 40, 38, 42, 38, 42, 1);

    /* Save output */
    save_screen(buf, "scanline_expected.bin");
    printf("Saved scanline_expected.bin\n");

    /* Print what we expect to see */
    printf("\nExpected patterns:\n");
    printf("Test 1: y=10, xl=20, xr=40, color=1 (should be row 5, chars 10-20)\n");
    printf("Test 2: y=20-21, top xl=10 xr=30, bot xl=15 xr=35, color=2 (row 10)\n");
    printf("Test 3: y=30, xl=0, xr=79, color=3 (row 15, full width)\n");
    printf("Test 4: y=40-41, xl=38 xr=42, color=1 (row 20, chars 19-21)\n");

    return 0;
}
