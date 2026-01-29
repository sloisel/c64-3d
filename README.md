# C64 3D Rasterizer

Real-time 3D graphics on a Commodore 64's 1MHz 6502 processor.

**Author:** S. Loisel

## Live Demo

**[Click here to try it in your browser](https://sloisel.github.io/c64-3d/)** — runs in a C64 emulator, no installation required.

## Features

- Real-time 3D mesh rendering at ~10 FPS
- 80×50 chunky pixel display using multicolor character mode
- Backface culling and painter's algorithm depth sorting
- Triple-buffered display for tear-free animation
- Fixed-point 8.8 arithmetic throughout
- Animated mesh support (Quake grunt with 24 frames)

## Code Organization

```
c64-3d/
├── asm/                    # 6502 assembly (the actual C64 code)
│   ├── main.asm           # Entry point, VIC-II setup, animation loop
│   ├── rasterizer.asm     # Triangle rasterizer (trapezoid decomposition)
│   ├── mesh.asm           # 3D transform, projection, depth sorting
│   ├── math.asm           # Fixed-point multiply/divide via lookup tables
│   ├── macros.asm         # Assembly macros for multiplication etc.
│   └── grunt_anim.asm     # Baked animation frames for Quake grunt
│
├── c/                      # C prototype (algorithm development)
│   ├── rasterize.c        # Reference triangle rasterizer
│   ├── mesh.c             # 3D transform reference implementation
│   ├── test.c             # Test harness with random/exhaustive tests
│   └── visualize.c        # ASCII/terminal visualizer
│
└── index.html             # Web demo page (EmulatorJS)
```

## How It Works

### Display Mode

The C64's multicolor character mode gives us 4 colors per 8×8 cell. By carefully designing a 256-character set, we pack 2×2 "chunky pixels" into each character, yielding an 80×50 pixel framebuffer in just 1000 bytes.

### Triangle Rasterization

1. **Backface culling**: Reject clockwise triangles via cross-product sign check
2. **Sort vertices** by Y coordinate (top to bottom)
3. **Trapezoid decomposition**: Split triangle at middle vertex into up to two trapezoids
4. **Scanline fill**: Walk edges with 8.8 fixed-point X coordinates, fill horizontal spans
5. **Dual-row blitting**: Process two scanlines at once to match character cell boundaries

### 3D Pipeline

1. **Rotation**: Y-axis rotation using precomputed sin/cos tables (s0.7 fixed-point)
2. **Translation**: Add camera offset to rotated vertices
3. **Projection**: Perspective divide using reciprocal lookup table
4. **Depth sort**: Painter's algorithm — sort faces by average Z, draw back-to-front

### Performance Tricks

- Quarter-square multiplication tables for fast 8×8→16 multiply
- Reciprocal tables for division-free perspective projection
- Self-modifying code for screen buffer base address
- Incremental edge walking (no per-scanline division)
- Triple buffering to decouple rendering from display refresh

## Building

### Requirements

- [64tass](https://sourceforge.net/projects/tass64/) — 6502 cross-assembler
- [VICE](https://vice-emu.sourceforge.io/) — C64 emulator (for testing)
- C compiler (gcc/clang) for the prototype

### Assemble the demo

```bash
cd asm
64tass -o octa.prg main.asm      # Octahedron demo
64tass -o main.prg main.asm      # Animated grunt (modify main.asm)
```

### Run in VICE

```bash
x64sc octa.prg
```

### Build and test the C prototype

```bash
cd c
make
./test              # Run test suite
./test --demo       # Generate demo.bin
./visualize demo.bin --ascii
```

## Using This Code

To render your own 3D models:

1. **Prepare your mesh**: Convert to signed 8-bit vertex coordinates (−128 to +127). Keep models small — the octahedron uses 6 vertices and 8 faces.

2. **Define vertices** in `mesh_vx`, `mesh_vy`, `mesh_vz` arrays

3. **Define faces** as triplets of vertex indices with CCW winding (for correct backface culling)

4. **Set transform parameters**:
   - `mesh_px/py/pz` — camera position (pz ~1500 works well)
   - `mesh_theta` — rotation angle (0–255 maps to 0–360°)

5. **Call the pipeline**:
   ```asm
   jsr transform_mesh   ; Rotate, translate, project
   jsr render_mesh      ; Sort and draw faces
   ```

## Limitations

- Single rotation axis (Y) — extending to full 3D rotation would need more trig tables
- ~256 vertices max (8-bit indices)
- No texture mapping or lighting — just flat-shaded polygons
- Painter's algorithm can fail on intersecting triangles

## License

MIT License. See source files for details.
