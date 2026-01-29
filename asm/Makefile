# Makefile for C64 Math Library
#
# Usage:
#   make              - Build math_test.prg
#   make test         - Run tests (requires VICE not occupied by vice-mcp)
#   make test-launch  - Launch fresh VICE instance and run tests
#   make clean        - Remove build artifacts

ASM = 64tass
ASMFLAGS = -Wall

.PHONY: all clean test test-launch

all: math_test.prg chunky_test.prg

math_test.prg: math_test.asm math.asm macros.asm
	$(ASM) $(ASMFLAGS) -o $@ -l math_test.lst $<

chunky_test.prg: chunky_test.asm vic2.asm macros.asm demo.bin
	$(ASM) $(ASMFLAGS) -o $@ -l chunky_test.lst $<

# Generate demo.bin from C rasterizer
demo.bin:
	cd ../c && ./test --demo && cp demo.bin ../asm/

# Run tests against existing VICE instance
# NOTE: vice-mcp must be disconnected first, or use test-launch instead
test: math_test.prg
	@echo "Running tests against VICE at localhost:6502..."
	@echo "(If vice-mcp is connected, disconnect it first or use 'make test-launch')"
	python3 vice_test.py --prg math_test.prg

# Launch a fresh VICE instance on alternate port for testing
test-launch: math_test.prg
	@echo "Launching VICE on port 6503 for testing..."
	python3 vice_test.py --launch --port 6503 --prg math_test.prg

clean:
	rm -f *.prg *.lst

# Convenience targets
run: math_test.prg
	x64sc $<

debug: math_test.prg
	x64sc -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502 $<
