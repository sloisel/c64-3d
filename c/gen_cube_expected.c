/* Generate expected cube data as assembly include file */
#include <stdio.h>

int main(void) {
    FILE *in = fopen("demo.bin", "rb");
    if (!in) { perror("demo.bin"); return 1; }
    
    unsigned char buf[1000];
    fread(buf, 1, 1000, in);
    fclose(in);
    
    FILE *f = fopen("../asm/cube_expected.asm", "w");
    fprintf(f, "; Expected cube output (auto-generated from C demo)\n");
    fprintf(f, "cube_expected\n");
    
    for (int i = 0; i < 1000; i++) {
        if (i % 16 == 0) fprintf(f, "    .byte ");
        fprintf(f, "$%02x", buf[i]);
        if (i % 16 == 15 || i == 999)
            fprintf(f, "\n");
        else
            fprintf(f, ",");
    }
    
    fclose(f);
    printf("Generated ../asm/cube_expected.asm\n");
    return 0;
}
