# C64 Rasterizer - Assembly Library

Assembly routines for the C64 rasterizer port, using 64tass assembler.

## Files

| File | Purpose |
|------|---------|
| `macros.asm` | General-purpose 64tass macro library |
| `math.asm` | Math routines (multiplication, division) |
| `math_test.asm` | Math test program |
| `vic2_simple.asm` | **Working** VIC-II chunky pixel display |
| `vic2.asm` | VIC-II library (older, needs multicolor fix) |
| `chunky_test.asm` | Chunky pixel test using vic2.asm |
| `vice_test.py` | Python test harness using VICE binary monitor |
| `Makefile` | Build and test automation |

## Building and Testing

```bash
make                 # Build math_test.prg
make test            # Run tests (requires VICE, vice-mcp must be disconnected)
make test-launch     # Launch separate VICE instance on port 6503 for testing
make clean           # Remove build artifacts
```

VICE must be running with binary monitor:
```bash
x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502
```

## 64tass Macro Syntax

```asm
; Definition
name .macro param1, param2=default
    lda #\param1
    ldx #\param2
.endm

; Invocation (two equivalent forms)
#name 42, 10
.name 42, 10

; Parameter references
\1 through \9    ; positional
\name            ; named
@1 through @9    ; as text (for labels)
```

## BASIC Stub (Important!)

**Use `format()` for the SYS address** - don't hardcode it:

```asm
        * = $0801
        ; CORRECT: compute address dynamically
        .word (+), 2024
        .null $9e, format("%d", main)
+       .word 0

main
        ; your code here
```

Hardcoding `"2062"` will be wrong if your code layout changes.

## Multicolor Character Mode Gotchas

1. **Color RAM bit 3** controls per-character multicolor:
   - Bit 3 = 0: hi-res mode (2 colors)
   - Bit 3 = 1: multicolor mode (4 colors)

   To use multicolor, store `8 + color` in color RAM, not just `color`.

2. **Charset location**: Can't use $1000-$1FFF in bank 0 due to ROM shadow bug. Use $2000.

3. **Colors in multicolor text mode**:
   - %00 = $D021 (background)
   - %01 = $D022
   - %10 = $D023
   - %11 = color RAM (bits 0-2 only, colors 0-7)

---

## Math Routines

### mul8x8_unsigned

**8-bit × 8-bit unsigned multiplication → 16-bit result**

```asm
; Input:  X = multiplicand (0-255)
;         Y = multiplier (0-255)
; Output: A = high byte of product
;         prod_low ($02) = low byte of product
; Destroys: X, Y, A
; Cycles: ~45

    jsr mul8x8_init     ; Call once at startup

    ldx #50
    ldy #80
    jsr mul8x8_unsigned
    ; Result: A:prod_low = $0FA0 (4000)
```

**Method:** Quarter-square multiplication using lookup tables:
`a × b = (a+b)²/4 - (a-b)²/4`

---

### div8s_8u_v2

**Signed 8-bit ÷ unsigned 8-bit → 8.8 fixed-point result**

```asm
; Input:  A = dividend (signed, -128 to +127, typically -80 to +80)
;         X = divisor (unsigned, 1-255, typically 1-50)
; Output: Y = integer part (high byte, signed)
;         A = fractional part (low byte)
;         div_result_hi ($05) = integer part
;         div_result_lo ($04) = fractional part
; Destroys: X, Y, A
; Cycles: ~21 (divisor=1), ~115 (positive), ~135 (negative)

    lda #80             ; dividend = 80
    ldx #50             ; divisor = 50
    jsr div8s_8u_v2
    ; Result: Y:A = $019A (1.601 in 8.8, i.e., 410/256)

    lda #-40            ; dividend = -40 (signed)
    ldx #10             ; divisor = 10
    jsr div8s_8u_v2
    ; Result: Y:A = $FC00 (-4.0 in 8.8 signed)

    lda #60             ; dividend = 60
    ldx #1              ; divisor = 1 (special case)
    jsr div8s_8u_v2
    ; Result: Y:A = $3C00 (60.0 in 8.8)
```

**Method:** Reciprocal multiplication: `a/b = a × (65536/b) >> 8`

The reciprocal table stores `65536/b` as 16-bit values. Special case for `b=1` since `65536/1` overflows 16 bits.

**8.8 Fixed-Point Format:**
- High byte = signed integer part (-128 to +127)
- Low byte = fractional part (0-255, representing 0/256 to 255/256)
- Example: `$019A` = 1 + 154/256 = 1.601

---

## Macro Reference

### Memory Operations

| Macro | Cycles | Description |
|-------|--------|-------------|
| `#load16 addr, value` | 10 | Load 16-bit immediate into zero page |
| `#copy16 dest, src` | 12 | Copy 16-bit value between addresses |
| `#add16i addr, value` | 16 | Add 16-bit immediate to memory (in place) |
| `#add16 dest, src` | 18 | Add two 16-bit memory values |
| `#sub16 dest, src` | 18 | Subtract 16-bit: dest = dest - src |
| `#neg8` | 6 | Negate 8-bit signed value in A |
| `#neg16 addr` | 24 | Negate 16-bit signed value at address |

### Comparison & Branching

| Macro | Cycles | Description |
|-------|--------|-------------|
| `#cmp16i addr, value` | 7-12 | Compare 16-bit; sets flags for BCC/BCS/BEQ |
| `#bmi_long target` | 5-6 | Long branch if negative |
| `#bpl_long target` | 5-6 | Long branch if positive/zero |

### Fixed-Point (8.8 format)

| Macro | Cycles | Description |
|-------|--------|-------------|
| `#fp88(value)` | — | Compile-time: convert integer to 8.8 |
| `#fp88_int addr` | 3 | Load integer part of 8.8 into A |
| `#fp88_add dest, src` | 18 | Add two 8.8 values |
| `#fp88_sub dest, src` | 18 | Subtract 8.8 values |

### Screen Output (debugging)

| Macro | Cycles | Description |
|-------|--------|-------------|
| `#printc char` | ~100+ | Print single character via CHROUT |
| `#printhex` | ~230+ | Print A as two hex digits |
| `#println` | ~100+ | Print newline |

### VIC-II

| Macro | Cycles | Description |
|-------|--------|-------------|
| `#border color` | 6 | Set border color |
| `#background color` | 6 | Set background color |
| `#waitraster line` | 8/iter | Busy-wait for raster line |
| `#time_start` | 6 | Inc border (for visual timing) |
| `#time_end` | 6 | Dec border |

### Loop Helpers

| Macro | Cycles | Description |
|-------|--------|-------------|
| `#dec16_bne addr, target` | 15-17 | Decrement 16-bit counter, branch if non-zero |

---

## Memory Map

After assembly, the math library uses:

| Address | Size | Content |
|---------|------|---------|
| $02 | 1 | `prod_low` - multiplication result low byte |
| $03 | 1 | `prod_high` - multiplication result high byte |
| $04 | 1 | `div_result_lo` - division result fractional part |
| $05 | 1 | `div_result_hi` - division result integer part |
| $FB-$FC | 2 | `zp_mul_ptr0` - multiplication table pointer |
| $FD-$FE | 2 | `zp_mul_ptr1` - multiplication table pointer |

**Lookup Tables (1664 bytes total):**

| Table | Size | Content |
|-------|------|---------|
| `sqr_lo` | 512 | Low bytes of n²/4 for n=0..511 |
| `sqr_hi` | 512 | High bytes of n²/4 for n=0..511 |
| `negsqr_lo` | 256 | For negative index handling |
| `negsqr_hi` | 256 | For negative index handling |
| `recip_lo` | 64 | Low bytes of 65536/n for n=0..63 |
| `recip_hi` | 64 | High bytes of 65536/n for n=0..63 |

---

## Usage Example

```asm
.include "macros.asm"

* = $0801
; BASIC stub
.word (+), 2024
.byte $9e
.text "2062"
.byte 0
+ .word 0

main:
    jsr mul8x8_init         ; Initialize multiplication tables (once)

    ; Compute slope = dx / dy for rasterizer
    ; dx = 60, dy = 25 → slope = 2.4 (8.8: $0266)
    lda #60
    ldx #25
    jsr div8s_8u_v2
    ; Y:A now contains slope in 8.8 format

    ; Store slope
    sty slope+1
    sta slope

    ; Accumulate slope (x_pos += slope)
    #fp88_add x_pos, slope

    rts

slope:      .word 0
x_pos:      .word 0

.include "math.asm"
```

---

## Testing

The Python test harness (`vice_test.py`) connects to VICE's binary monitor to:
1. Load the PRG file
2. Verify lookup tables are correctly generated
3. (Future: execute routines and verify results)

**Note:** VICE binary monitor only supports one connection at a time. Disconnect vice-mcp before running `make test`.
