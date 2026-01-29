#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rasterize.h"

/* ANSI color codes for the 4 C64-style colors */
static const char *ansi_colors[] = {
    "\033[40m",   /* 0: Black background */
    "\033[41m",   /* 1: Red background */
    "\033[42m",   /* 2: Green background */
    "\033[43m",   /* 3: Yellow background */
};
static const char *ansi_reset = "\033[0m";

/* Unicode block characters for half-block rendering */
/* Each character cell is 2 chunky pixels wide, so we print 2 half-blocks */

void print_screen(const unsigned char *buf) {
    printf("\033[2J\033[H");  /* Clear screen, home cursor */

    /* Process two chunky rows at a time (one character row) */
    for (int char_y = 0; char_y < CHAR_HEIGHT; char_y++) {
        for (int char_x = 0; char_x < CHAR_WIDTH; char_x++) {
            int offset = char_y * CHAR_WIDTH + char_x;
            unsigned char byte = buf[offset];

            /* Extract the 4 pixels */
            int tl = (byte >> PIXEL_TL_SHIFT) & 3;
            int tr = (byte >> PIXEL_TR_SHIFT) & 3;
            int bl = (byte >> PIXEL_BL_SHIFT) & 3;
            int br = (byte >> PIXEL_BR_SHIFT) & 3;

            /* Print left half of character (top-left and bottom-left) */
            if (tl == bl) {
                /* Same color top and bottom - full block */
                printf("%s  ", ansi_colors[tl]);
            } else {
                /* Different colors - use half block */
                /* Upper half block: U+2580 */
                printf("\033[%dm\033[%dm\u2580 ",
                       30 + tl,  /* Foreground for top */
                       40 + bl); /* Background for bottom */
            }

            /* Print right half of character (top-right and bottom-right) */
            if (tr == br) {
                printf("%s  ", ansi_colors[tr]);
            } else {
                printf("\033[%dm\033[%dm\u2580 ",
                       30 + tr,
                       40 + br);
            }
        }
        printf("%s\n", ansi_reset);
    }
    printf("%s", ansi_reset);
}

/* Alternative simpler print using only background colors */
void print_screen_simple(const unsigned char *buf) {
    printf("\033[2J\033[H");

    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            unsigned char color = get_pixel(buf, x, y);
            printf("%s ", ansi_colors[color]);
        }
        printf("%s\n", ansi_reset);
    }
}

/* Print with ASCII characters for no-color terminals */
void print_screen_ascii(const unsigned char *buf) {
    static const char chars[] = " .+#";

    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            unsigned char color = get_pixel(buf, x, y);
            putchar(chars[color]);
        }
        putchar('\n');
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <image.bin> [--ascii|--simple]\n", argv[0]);
        return 1;
    }

    unsigned char buf[SCREEN_SIZE];
    load_screen(buf, argv[1]);

    if (argc >= 3) {
        if (strcmp(argv[2], "--ascii") == 0) {
            print_screen_ascii(buf);
        } else if (strcmp(argv[2], "--simple") == 0) {
            print_screen_simple(buf);
        } else {
            print_screen(buf);
        }
    } else {
        print_screen(buf);
    }

    return 0;
}
