#include <stdio.h>
#include "rasterize.h"

int main(void) {
    unsigned char buf[SCREEN_SIZE];
    clear_screen(buf, 0);
    
    // Same triangle: (40,25), (56,34), (40,43) color 1
    draw_triangle(buf, 40, 25, 56, 34, 40, 43, 1);
    
    // Generate assembly include
    FILE *f = fopen("../asm/single_tri_expected.asm", "w");
    fprintf(f, "; Expected single triangle output\n");
    fprintf(f, "single_tri_expected\n");
    for (int i = 0; i < 1000; i++) {
        if (i % 16 == 0) fprintf(f, "    .byte ");
        fprintf(f, "$%02x", buf[i]);
        if (i % 16 == 15 || i == 999) fprintf(f, "\n");
        else fprintf(f, ",");
    }
    fclose(f);
    
    printf("Generated single_tri_expected.asm\n");
    return 0;
}
