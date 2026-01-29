#ifndef MESH_H
#define MESH_H

#include <stdint.h>

/* Mesh structure for 3D rendering with C64-style fixed-point arithmetic */
typedef struct {
    /* Faces: triangles defined by vertex indices and color */
    uint8_t *i, *j, *k;     /* 8-bit indices into vertex arrays */
    uint8_t *col;           /* 8-bit face colors (0-3) */
    int num_faces;

    /* Vertices: 8-bit signed local coordinates */
    int8_t *x, *y, *z;      /* Range: -128 to +127 */
    int num_vertices;

    /* Transform: position and rotation */
    int16_t px, py, pz;     /* 16-bit world position */
    uint8_t theta;          /* 8-bit rotation (0-255 = 0 to 2pi) */
} Mesh;

/* LUTs for rotation: 0.9*cos(theta) and 0.9*sin(theta) in s0.7 format
 * Range approximately -115 to +115. Factor 0.9 for PAL aspect ratio. */
extern int8_t rcos[256];
extern int8_t rsin[256];

/* Initialize rcos/rsin lookup tables. Call once before using mesh functions. */
void init_mesh_tables(void);

/* Transform mesh vertices from local to screen coordinates.
 * Applies Y-axis rotation and perspective projection.
 * Results stored in screen_x[], screen_y[] arrays (must be num_vertices long).
 * Returns 0 on success, -1 if any vertex is behind camera (z <= 0). */
int transform_mesh(const Mesh *m, int16_t *screen_x, int16_t *screen_y);

/* Render all faces of a mesh to the screen buffer.
 * Uses backface culling from the rasterizer.
 * Face colors come from mesh->col array. */
void render_mesh(unsigned char *buf, const Mesh *m);

#endif /* MESH_H */
