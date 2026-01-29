#include <math.h>
#include "mesh.h"
#include "rasterize.h"

/* LUTs for rotation */
int8_t rcos[256];
int8_t rsin[256];

static int tables_initialized = 0;

void init_mesh_tables(void) {
    if (tables_initialized) return;

    /* Build rcos/rsin tables: cos/sin(theta * 2*pi / 256) * 127
     * s0.7 format: multiply by 127, result in range -127 to +127. */
    for (int i = 0; i < 256; i++) {
        double angle = i * 2.0 * M_PI / 256.0;
        rcos[i] = (int8_t)(cos(angle) * 127.0);
        rsin[i] = (int8_t)(sin(angle) * 127.0);
    }

    tables_initialized = 1;
}

int transform_mesh(const Mesh *m, int16_t *screen_x, int16_t *screen_y) {
    init_mesh_tables();

    int8_t c = rcos[m->theta];
    int8_t s = rsin[m->theta];

    for (int v = 0; v < m->num_vertices; v++) {
        int8_t lx = m->x[v];  /* Local coordinates */
        int8_t ly = m->y[v];
        int8_t lz = m->z[v];

        /* Rotation around Y axis:
         * world_x = cos(theta)*lx + sin(theta)*lz
         * world_z = -sin(theta)*lx + cos(theta)*lz
         * world_y = ly (unchanged)
         *
         * Arithmetic: s8.0 * s0.7 = s8.7, keep high byte for s8.0 result.
         * Then add 16-bit position offset. */
        int16_t rot_x = (c * lx + s * lz) >> 7;  /* s8.0 */
        int16_t rot_z = (-s * lx + c * lz) >> 7; /* s8.0 */

        int16_t world_x = rot_x + m->px;
        int16_t world_z = rot_z + m->pz;
        int16_t world_y = ly + m->py;

        /* Perspective projection:
         * screen_x = 40 + (world_x << 8) / world_z
         * screen_y = 25 - (world_y << 8) / world_z
         *
         * FOCAL = 256, so multiply by 256 is just << 8.
         * Division: s16.8 / s16.0 -> s8.0 (screen coordinates). */
        if (world_z <= 0) {
            return -1;  /* Vertex behind camera */
        }

        screen_x[v] = 40 + ((world_x << 8) / world_z);
        screen_y[v] = 25 - ((world_y << 8) / world_z);
    }

    return 0;
}

void render_mesh(unsigned char *buf, const Mesh *m) {
    int16_t screen_x[256];  /* Max 256 vertices */
    int16_t screen_y[256];

    if (transform_mesh(m, screen_x, screen_y) < 0) {
        return;  /* Some vertex behind camera, skip entire mesh */
    }

    /* Render each face */
    for (int f = 0; f < m->num_faces; f++) {
        int vi = m->i[f];
        int vj = m->j[f];
        int vk = m->k[f];

        /* draw_triangle handles backface culling internally */
        draw_triangle(buf,
                      screen_x[vi], screen_y[vi],
                      screen_x[vj], screen_y[vj],
                      screen_x[vk], screen_y[vk],
                      m->col[f]);
    }
}
