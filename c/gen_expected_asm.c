/* Generate expected scanline data as assembly include file */
#include <stdio.h>
#include <string.h>
#include "rasterize.h"

static void test_draw_span(unsigned char *buf, int y, int xl, int xr, unsigned char color) {
    for (int x = xl; x <= xr; x++) {
        set_pixel(buf, x, y, color);
    }
}

static void test_draw_dual_row(unsigned char *buf, int y, int xl1, int xr1,
                                int xl2, int xr2, unsigned char color) {
    for (int x = xl1; x <= xr1; x++) {
        set_pixel(buf, x, y, color);
    }
    for (int x = xl2; x <= xr2; x++) {
        set_pixel(buf, x, y + 1, color);
    }
}

int main(void) {
    unsigned char buf[SCREEN_SIZE];
    
    clear_screen(buf, 0);
    test_draw_span(buf, 10, 20, 40, 1);
    test_draw_dual_row(buf, 20, 10, 30, 15, 35, 2);
    test_draw_span(buf, 30, 0, 79, 3);
    test_draw_dual_row(buf, 40, 38, 42, 38, 42, 1);
    
    FILE *f = fopen("../asm/scanline_expected.asm", "w");
    fprintf(f, "; Expected scanline test output (auto-generated)\n");
    fprintf(f, "scanline_expected\n");
    
    for (int i = 0; i < SCREEN_SIZE; i++) {
        if (i % 16 == 0) fprintf(f, "    .byte ");
        fprintf(f, "$%02x", buf[i]);
        if (i % 16 == 15 || i == SCREEN_SIZE - 1)
            fprintf(f, "\n");
        else
            fprintf(f, ",");
    }
    
    fclose(f);
    printf("Generated ../asm/scanline_expected.asm\n");
    return 0;
}
