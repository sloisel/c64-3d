# Makefile for C64 3D Rasterizer
#
# Usage:
#   make              - Build both octa.prg and zombie.prg
#   make octa.prg     - Build octahedron demo
#   make zombie.prg   - Build zombie/grunt demo
#   make clean        - Remove build artifacts
#   make run-octa     - Run octahedron in VICE
#   make run-zombie   - Run zombie in VICE

ASM = 64tass
ASMFLAGS = -Wall

SOURCES = main.asm rasterizer.asm mesh.asm math.asm macros.asm grunt_anim.asm grunt_data.asm

.PHONY: all clean run-octa run-zombie debug-octa debug-zombie

all: octa.prg zombie.prg

octa.prg: $(SOURCES)
	$(ASM) $(ASMFLAGS) -D GRUNT_MESH=0 -o $@ main.asm

zombie.prg: $(SOURCES)
	$(ASM) $(ASMFLAGS) -D GRUNT_MESH=1 -o $@ main.asm

clean:
	rm -f *.lst

run-octa: octa.prg
	x64sc $<

run-zombie: zombie.prg
	x64sc $<

debug-octa: octa.prg
	x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502 $<

debug-zombie: zombie.prg
	x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502 $<
