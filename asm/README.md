# C64 3D Rasterizer - Assembly Implementation

Assembly routines for the C64 3D rasterizer using 64tass assembler.

## Files

| File | Purpose |
|------|---------|
| `main.asm` | Entry point, VIC-II setup, animation loop, math tables |
| `rasterizer.asm` | Triangle rasterizer (trapezoid decomposition, dual-row blitter) |
| `mesh.asm` | 3D mesh transformation and rendering |
| `math.asm` | Math routines (signed multiplication) |
| `macros.asm` | General-purpose 64tass macro library |
| `grunt_anim.asm` | Grunt animation vertex data (16 frames) |
| `grunt_data.asm` | Grunt mesh face data |
| `octa.prg` | Pre-built demo binary for web player |

## Building

```bash
64tass -o octa.prg main.asm           # Build main program
64tass -o octa.prg -l labels.txt main.asm  # With labels for debugging
```

## Running

```bash
x64sc octa.prg                        # Run in VICE
x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502 octa.prg  # With debug monitor
```

## Architecture

### Memory Map

| Address | Size | Content |
|---------|------|---------|
| `$0801` | ~30 | BASIC stub (SYS 14336) |
| `$2000-$27FF` | 2KB | VIC charset (256 chunky pixel patterns) |
| `$2800-$37FF` | 4KB | Math lookup tables |
| `$3800+` | ~12KB | Code + mesh data |

### Math Tables

| Table | Size | Content |
|-------|------|---------|
| `sqr_lo/hi` | 1KB | Quarter-square (n²/4) for n=0..511 |
| `negsqr_lo/hi` | 512B | Negative index handling |
| `recip_lo/hi` | 128B | Reciprocals (65536/n) for n=1..63 |
| `recip_persp` | 128B | Perspective division (8192/z) for z=128..255 |
| `smult_sq1/sq2` | 2KB | Signed multiplication tables |
| `rcos/rsin` | 512B | Rotation lookup (cos/sin × 127) |

### Zero Page Usage

| Address | Name | Purpose |
|---------|------|---------|
| `$02-$03` | `prod_low/high` | Multiplication result |
| `$04-$05` | `div_result` | Division result (8.8 fixed-point) |
| `$06-$31` | Rasterizer | Triangle vertices, slopes, screen pointers |
| `$F9-$FA` | `zp_anim_ptr` | Animation frame pointer |
| `$FB-$FE` | `zp_mul_ptr0/1` | Multiplication table pointers |

## Math Routines

### mul8x8_unsigned_m (Macro)

8-bit × 8-bit unsigned multiplication → 16-bit result.

```asm
; Input:  X = multiplicand, Y = multiplier
; Output: A = high byte, prod_low ($02) = low byte
; Cycles: ~45

    ldx #50
    ldy #80
    #mul8x8_unsigned_m
    ; Result: A:prod_low = $0FA0 (4000)
```

### div8s_8u_v2 (Subroutine)

Signed 8-bit ÷ unsigned 8-bit → 8.8 fixed-point result.

```asm
; Input:  A = dividend (signed), X = divisor (unsigned, 1-63)
; Output: Y = integer part, A = fractional part
; Cycles: ~21 (divisor=1), ~115 (positive), ~135 (negative)

    lda #60
    ldx #25
    jsr div8s_8u_v2
    ; Result: Y:A = $0266 (2.4 in 8.8)
```

## Macro Reference

### Memory Operations

| Macro | Description |
|-------|-------------|
| `#load16 addr, value` | Load 16-bit immediate |
| `#copy16 dest, src` | Copy 16-bit value |
| `#add16i addr, value` | Add 16-bit immediate in place |
| `#add16 dest, src` | Add 16-bit memory values |
| `#sub16 dest, src` | Subtract 16-bit values |
| `#neg8` | Negate 8-bit signed A |
| `#neg16 addr` | Negate 16-bit signed value |

### Comparison & Branching

| Macro | Description |
|-------|-------------|
| `#cmp16i addr, value` | Compare 16-bit, sets flags for BCC/BCS/BEQ |
| `#bmi_long target` | Long branch if negative |
| `#bpl_long target` | Long branch if positive/zero |

### Fixed-Point (8.8 format)

| Macro | Description |
|-------|-------------|
| `#fp88_int addr` | Load integer part into A |
| `#fp88_add dest, src` | Add two 8.8 values |
| `#fp88_sub dest, src` | Subtract 8.8 values |

### Multiplication

| Macro | Description |
|-------|-------------|
| `#mul8x8_unsigned_m` | Unsigned 8×8→16 (X×Y, result in A:prod_low) |
| `#mul8x8_signed_m` | Signed 8×8→16 |

### VIC-II / Debugging

| Macro | Description |
|-------|-------------|
| `#border color` | Set border color |
| `#background color` | Set background color |
| `#waitraster line` | Busy-wait for raster line |
| `#printc char` | Print character via CHROUT |
| `#printhex` | Print A as two hex digits |
| `#println` | Print newline |

## 64tass Syntax Notes

```asm
; Macro definition
name .macro param1, param2=default
    lda #\param1
    ldx #\param2
.endm

; Macro invocation
#name 42, 10

; Local labels (- and +)
loop    lda something
        beq +           ; branch forward to next +
        jmp loop
+       rts
```

## Multicolor Mode Notes

- Color RAM bit 3 enables multicolor per-character
- Charset can't use $1000-$1FFF in bank 0 (ROM shadow)
- Colors: %00 = $D021, %01 = $D022, %02 = $D023, %11 = color RAM
