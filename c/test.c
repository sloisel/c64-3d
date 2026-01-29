#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "rasterize.h"
#include "mesh.h"
#include "grunt_mesh.h"

/* Reference rasterizer using simple scanline algorithm with half-pixel sampling.
 * At scanline y, we sample at y + 0.5 to avoid vertex degeneracy.
 * Uses fixed-point 8.8 arithmetic and shifts (not division) to match crasterizer. */
static void reference_triangle(unsigned char *buf, int ax, int ay, int bx, int by,
                               int cx, int cy, unsigned char color) {
    /* Backface culling: check winding order BEFORE sorting */
    int det = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (det < 0) {
        return;  /* Backface culled */
    }

    /* Sort vertices by y */
    if (ay > by) { int t; t = ax; ax = bx; bx = t; t = ay; ay = by; by = t; }
    if (by > cy) { int t; t = bx; bx = cx; cx = t; t = by; by = cy; cy = t; }
    if (ay > by) { int t; t = ax; ax = bx; bx = t; t = ay; ay = by; by = t; }

    /* Degenerate: zero height */
    if (ay == cy) {
        return;
    }

    /* Compute slope for A-C edge in 8.8 fixed point: 256 * dx / dy */
    int dx_ac = ((cx - ax) << 8) / (cy - ay);

    /* For each scanline from ay to cy-1 */
    for (int y = ay; y < cy; y++) {
        /* At scanline y, sample at y + 0.5
         * x = start_x + slope * (y + 0.5 - start_y)
         *   = start_x + slope * (y - start_y) + slope/2
         * Use >> 1 instead of / 2 for consistency with crasterizer. */

        /* x on A-C edge at y + 0.5 */
        int x_ac_fp = (ax << 8) + dx_ac * (y - ay) + (dx_ac >> 1);

        int x_other_fp;
        if (y < by) {
            /* Top part: use A-B edge */
            if (by != ay) {
                int dx_ab = ((bx - ax) << 8) / (by - ay);
                x_other_fp = (ax << 8) + dx_ab * (y - ay) + (dx_ab >> 1);
            } else {
                x_other_fp = ax << 8;
            }
        } else {
            /* Bottom part: use B-C edge */
            if (cy != by) {
                int dx_bc = ((cx - bx) << 8) / (cy - by);
                x_other_fp = (bx << 8) + dx_bc * (y - by) + (dx_bc >> 1);
            } else {
                x_other_fp = bx << 8;
            }
        }

        int xl = (x_ac_fp < x_other_fp ? x_ac_fp : x_other_fp) >> 8;
        int xr = (x_ac_fp > x_other_fp ? x_ac_fp : x_other_fp) >> 8;

        /* [xl, xr) exclusive convention */
        for (int x = xl; x < xr; x++) {
            set_pixel(buf, x, y, color);
        }
    }
}

/* Compare two screen buffers, return number of differing bytes */
int compare_screens(const unsigned char *a, const unsigned char *b) {
    int diff = 0;
    for (int i = 0; i < SCREEN_SIZE; i++) {
        if (a[i] != b[i]) diff++;
    }
    return diff;
}

/* Compare pixel by pixel, return number of differing pixels */
int compare_pixels(const unsigned char *a, const unsigned char *b) {
    int diff = 0;
    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            if (get_pixel(a, x, y) != get_pixel(b, x, y)) {
                diff++;
            }
        }
    }
    return diff;
}

/* Print difference visualization */
void print_diff(const unsigned char *expected, const unsigned char *actual) {
    printf("Difference map (. = match, X = mismatch):\n");
    for (int y = 0; y < SCREEN_HEIGHT; y++) {
        for (int x = 0; x < SCREEN_WIDTH; x++) {
            if (get_pixel(expected, x, y) != get_pixel(actual, x, y)) {
                putchar('X');
            } else if (get_pixel(expected, x, y) != 0) {
                putchar('#');
            } else {
                putchar('.');
            }
        }
        putchar('\n');
    }
}

/* Run a single test case */
int test_triangle(int ax, int ay, int bx, int by, int cx, int cy,
                  unsigned char color, int verbose) {
    unsigned char expected[SCREEN_SIZE];
    unsigned char actual[SCREEN_SIZE];

    clear_screen(expected, 0);
    clear_screen(actual, 0);

    reference_triangle(expected, ax, ay, bx, by, cx, cy, color);
    draw_triangle(actual, ax, ay, bx, by, cx, cy, color);

    int diff = compare_pixels(expected, actual);

    if (diff > 0 || verbose) {
        printf("Triangle (%d,%d)-(%d,%d)-(%d,%d) color=%d: ",
               ax, ay, bx, by, cx, cy, color);
        if (diff > 0) {
            printf("FAIL (%d pixels differ)\n", diff);
            if (verbose) {
                print_diff(expected, actual);
                save_screen(expected, "expected.bin");
                save_screen(actual, "actual.bin");
            }
        } else {
            printf("PASS\n");
        }
    }

    return diff == 0 ? 0 : 1;
}

/* Manual test cases */
int run_manual_tests(void) {
    int failures = 0;

    printf("=== Manual Test Cases ===\n");

    /* Simple triangle */
    failures += test_triangle(40, 10, 20, 40, 60, 40, 1, 1);

    /* Flat-top triangle */
    failures += test_triangle(20, 10, 60, 10, 40, 40, 2, 1);

    /* Flat-bottom triangle */
    failures += test_triangle(40, 10, 20, 40, 60, 40, 3, 1);

    /* Very small triangle */
    failures += test_triangle(40, 25, 41, 26, 42, 25, 1, 1);

    /* Single pixel */
    failures += test_triangle(40, 25, 40, 25, 40, 25, 2, 1);

    /* Horizontal line */
    failures += test_triangle(30, 25, 35, 25, 40, 25, 1, 1);

    /* Vertical line */
    failures += test_triangle(40, 20, 40, 25, 40, 30, 1, 1);

    /* Right-angled triangle */
    failures += test_triangle(10, 10, 10, 30, 30, 30, 2, 1);

    /* Very thin triangle */
    failures += test_triangle(10, 10, 70, 40, 10, 40, 1, 1);

    return failures;
}

/* Random test cases */
int run_random_tests(int count) {
    int failures = 0;

    printf("\n=== Random Tests (%d cases) ===\n", count);

    for (int i = 0; i < count; i++) {
        int ax = rand() % SCREEN_WIDTH;
        int ay = rand() % SCREEN_HEIGHT;
        int bx = rand() % SCREEN_WIDTH;
        int by = rand() % SCREEN_HEIGHT;
        int cx = rand() % SCREEN_WIDTH;
        int cy = rand() % SCREEN_HEIGHT;
        unsigned char color = (rand() % 3) + 1;  /* 1-3 */

        int fail = test_triangle(ax, ay, bx, by, cx, cy, color, 0);
        if (fail) {
            failures++;
            /* Save first few failures for debugging */
            if (failures <= 3) {
                printf("  First failure: (%d,%d)-(%d,%d)-(%d,%d) color=%d\n",
                       ax, ay, bx, by, cx, cy, color);
                test_triangle(ax, ay, bx, by, cx, cy, color, 1);
            }
        }
    }

    printf("Random tests: %d/%d passed\n", count - failures, count);
    return failures;
}

/* Exhaustive small region tests */
int run_exhaustive_tests(int region_size) {
    int failures = 0;
    int tests = 0;

    printf("\n=== Exhaustive Tests (region %dx%d) ===\n", region_size, region_size);

    int ox = 35;  /* Offset to center the test region */
    int oy = 20;

    for (int ay = 0; ay < region_size; ay++) {
        for (int ax = 0; ax < region_size; ax++) {
            for (int by = 0; by < region_size; by++) {
                for (int bx = 0; bx < region_size; bx++) {
                    for (int cy = 0; cy < region_size; cy++) {
                        for (int cx = 0; cx < region_size; cx++) {
                            int fail = test_triangle(
                                ox + ax, oy + ay,
                                ox + bx, oy + by,
                                ox + cx, oy + cy,
                                1, 0);
                            if (fail) failures++;
                            tests++;
                        }
                    }
                }
            }
        }
    }

    printf("Exhaustive tests: %d/%d passed\n", tests - failures, tests);
    return failures;
}

/* Demo: rotating octahedron using 3D mesh rendering */
void run_cube_demo(void) {
    unsigned char buf[SCREEN_SIZE];

    init_mesh_tables();

    /* Octahedron vertices: 6 points on axes (maximize 8-bit range) */
    int8_t vx[] = { 120, -120,    0,    0,    0,    0 };  /* +X, -X */
    int8_t vy[] = {   0,    0,  120, -120,    0,    0 };  /* +Y, -Y */
    int8_t vz[] = {   0,    0,    0,    0,  120, -120 };  /* +Z, -Z */

    /* Octahedron faces: 8 triangles with CCW winding viewed from outside
     * Upper hemisphere (y < 0, appears as top on screen)
     * Lower hemisphere (y > 0, appears as bottom on screen) */
    uint8_t fi[] = { 0, 1, 0, 1,  0, 1, 0, 1 };
    uint8_t fj[] = { 4, 3, 3, 5,  2, 4, 5, 2 };
    uint8_t fk[] = { 3, 4, 5, 3,  4, 2, 2, 5 };

    /* Face colors: alternate between colors 1, 2, 3 */
    uint8_t fcol[] = { 1, 2, 3, 1,  2, 3, 1, 2 };

    Mesh octa = {
        .i = fi, .j = fj, .k = fk, .col = fcol,
        .num_faces = 8,
        .x = vx, .y = vy, .z = vz,
        .num_vertices = 6,
        .px = 0, .py = -25, .pz = 1500,
        .theta = 20  /* Angle that shows 4 faces */
    };

    clear_screen(buf, 0);
    render_mesh(buf, &octa);
    save_screen(buf, "cube.bin");
    printf("Octahedron demo saved to cube.bin\n");
}

/* Demo: render the Quake grunt model */
void run_grunt_demo(void) {
    unsigned char buf[SCREEN_SIZE];

    /* Mesh data is already properly oriented by the converter:
     * X = left/right, Y = up/down (screen coords), Z = depth */
    Mesh grunt = {
        .i = grunt_faces_i, .j = grunt_faces_j, .k = grunt_faces_k,
        .col = NULL,
        .num_faces = GRUNT_NUM_FACES,
        .x = grunt_vertices_x, .y = grunt_vertices_y, .z = grunt_vertices_z,
        .num_vertices = GRUNT_NUM_VERTICES,
        .px = 0, .py = 0, .pz = 1500,
        .theta = 20  /* Slight rotation to show some depth */
    };

    /* Allocate colors - alternate */
    uint8_t *fcol = malloc(GRUNT_NUM_FACES);
    for (int i = 0; i < GRUNT_NUM_FACES; i++) {
        fcol[i] = 1 + (i % 3);
    }
    grunt.col = fcol;

    clear_screen(buf, 0);
    render_mesh(buf, &grunt);
    save_screen(buf, "grunt.bin");
    printf("Grunt demo saved to grunt.bin (%d vertices, %d faces)\n",
           GRUNT_NUM_VERTICES, GRUNT_NUM_FACES);

    free(fcol);
}

/* Demo: draw an isometric cube (6 triangles, 3 visible faces) */
void run_demo(void) {
    unsigned char buf[SCREEN_SIZE];
    clear_screen(buf, 0);

    /* Isometric cube viewed from corner. Hexagon silhouette.
     * Center C is the front corner of the cube.
     * 3 faces visible, 2 triangles each, all CCW winding. */

    /* Vertex coordinates - boundary test cube (x: 0-80, y: 0-50) */
    int cx = 40, cy = 25;   /* C: front corner (center) */
    int p100x = 80, p100y = 37;  /* bottom-right */
    int p010x = 0, p010y = 37;   /* bottom-left */
    int p001x = 40, p001y = 0;   /* top */
    int p110x = 40, p110y = 50;  /* bottom */
    int p101x = 80, p101y = 13;  /* top-right */
    int p011x = 0, p011y = 13;   /* top-left */

    /* Bottom face (color 1) */
    draw_triangle(buf, cx, cy, p100x, p100y, p110x, p110y, 1);
    draw_triangle(buf, cx, cy, p110x, p110y, p010x, p010y, 1);

    /* Right face (color 2) */
    draw_triangle(buf, cx, cy, p001x, p001y, p101x, p101y, 2);
    draw_triangle(buf, cx, cy, p101x, p101y, p100x, p100y, 2);

    /* Left face (color 3) */
    draw_triangle(buf, cx, cy, p010x, p010y, p011x, p011y, 3);
    draw_triangle(buf, cx, cy, p011x, p011y, p001x, p001y, 3);

    save_screen(buf, "demo.bin");
    printf("Demo saved to demo.bin\n");
}

int main(int argc, char **argv) {
    int failures = 0;

    if (argc > 1 && strcmp(argv[1], "--demo") == 0) {
        run_demo();
        return 0;
    }

    if (argc > 1 && strcmp(argv[1], "--cube") == 0) {
        run_cube_demo();
        return 0;
    }

    if (argc > 1 && strcmp(argv[1], "--grunt") == 0) {
        run_grunt_demo();
        return 0;
    }

    srand(time(NULL));

    failures += run_manual_tests();
    failures += run_random_tests(10000);
    failures += run_exhaustive_tests(5);

    printf("\n=== Summary ===\n");
    if (failures == 0) {
        printf("All tests passed!\n");
    } else {
        printf("Total failures: %d\n", failures);
    }

    return failures > 0 ? 1 : 0;
}
