# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

C64 3D rendering project using 6502 assembly language targeting the Commodore 64. Includes a C prototype rasterizer for algorithm development before porting to assembly.

## C Rasterizer Prototype (c/ directory)

Build and test:
```bash
cd c && make        # Build all
./test              # Run test suite (manual + 10k random + exhaustive)
./test --demo       # Generate demo.bin
./visualize demo.bin --ascii   # View in terminal (or --simple for colors)
```

### Architecture

**Chunky pixel model**: 80×50 pixels in 1000-byte buffer (40×25 characters). Each byte encodes 4 pixels at 2 bits each:
- bits 7-6: top-left, bits 5-4: top-right, bits 3-2: bottom-left, bits 1-0: bottom-right

**Triangle rasterizer** (`rasterize.c`):
- Backface culling: rejects clockwise triangles via det(B-A, C-A) < 0 check BEFORE sorting (det fits in 16 bits)
- Trapezoid decomposition: sorts vertices by Y, splits at middle vertex
- Half-pixel sampling (y+0.5) to avoid vertex acne when triangles share vertices
- Fixed-point 8.8 arithmetic for edge slopes
- Dual-row blitting processes two scanlines at once to match character cells
- Critical: edge X positions are accumulated incrementally, never recomputed at trapezoid transitions

**Test harness** (`test.c`): Reference rasterizer for comparison, random and exhaustive testing.

## 6502 Assembly

Assemble a program:
```bash
64tass -o output.prg source.asm
64tass -o output.prg -l labels.txt source.asm  # With labels for debugging
```

## Running and Debugging

Start VICE emulator with binary monitor for MCP integration:
```bash
x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502
```

The vice-mcp server provides debugging tools (breakpoints, memory inspection, VIC-II state, sprite debugging) when VICE is running with the binary monitor.

## C64 Memory Map Reference

- `$0000-$00FF` - Zero page (fast access, use for frequently accessed variables)
- `$0100-$01FF` - Stack
- `$0400-$07FF` - Default screen memory (40x25 characters)
- `$D000-$D3FF` - VIC-II registers (graphics chip)
- `$D800-$DBFF` - Color RAM

## Project Memory Layout (main.asm)

- `$0400-$07E7` - Screen buffer 1 (active)
- `$2000-$27FF` - VIC charset (2KB)
- `$2800-$37FF` - Math lookup tables (sqr, negsqr, recip, smult)
- `$3800+` - **Code starts here** (all executable code goes after tables)

## VIC-II Key Registers

- `$D000-$D00F` - Sprite X/Y positions
- `$D010` - Sprite X MSB (bit 8 for each sprite)
- `$D011` - Screen control (vertical scroll, screen height, bitmap mode)
- `$D016` - Screen control (horizontal scroll, multicolor, 40/38 columns)
- `$D020` - Border color
- `$D021` - Background color

## Current Debug Session (2026-01-31)

**Problem:** octa.prg crashes on startup. Border turns green, background black, junk characters visible. VIC is in multicolor mode but charset isn't rendering correctly.

**What was changed:**
1. Added signed×unsigned quarter-square multiplication tables (su_sum_lo/hi, su_diff_lo/hi) - 2KB new tables
2. Created `mul8s_8u_m` macro (~40 cycles) for 8-bit signed × unsigned multiply
3. Created `mul16s_8u_hi_m` macro (~93 cycles) - inlined version of perspective projection multiply
4. Removed old `mul16s_8u_hi` subroutine (was ~142-175 cycles with branching)
5. Changed table layout to use `.align 256` instead of hardcoded addresses
6. Fixed BASIC stub to use `format("%d", main)` instead of hardcoded address

**Current table layout (from labels.txt):**
- sqr_lo/hi: $2800, $2a00
- negsqr_lo/hi: $2c00, $2d00
- recip_persp: $2e00
- smult tables: $2f00-$36ff
- smult_eorx: $3700
- recip_lo/hi: $3800, $3840
- su_sum_lo/hi: $3900, $3b00
- su_diff_lo/hi: $3d00, $3f00
- main: $4100

**To debug:**
1. Start VICE: `x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502 asm/octa.prg`
2. Use vice-mcp to inspect memory, set breakpoints, check if main is reached
3. Check if VIC setup ($d018, $d016) is correct
4. Verify charset at $2000 is intact
