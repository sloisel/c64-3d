#include <stdio.h>
#include "rasterize.h"

int main(void) {
    unsigned char buf[SCREEN_SIZE];
    clear_screen(buf, 0);
    draw_triangle(buf, 40, 25, 56, 34, 40, 43, 1);
    save_screen(buf, "single_tri.bin");
    printf("Saved single_tri.bin\n");
    return 0;
}
