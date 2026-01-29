CC = cc
CFLAGS = -Wall -Wextra -O2 -std=c99
LDFLAGS =

.PHONY: all clean test demo

all: visualize test

rasterize.o: rasterize.c rasterize.h
	$(CC) $(CFLAGS) -c rasterize.c -o rasterize.o

mesh.o: mesh.c mesh.h rasterize.h
	$(CC) $(CFLAGS) -c mesh.c -o mesh.o

visualize: visualize.c rasterize.o rasterize.h
	$(CC) $(CFLAGS) visualize.c rasterize.o -o visualize $(LDFLAGS)

test: test.c rasterize.o mesh.o rasterize.h mesh.h
	$(CC) $(CFLAGS) test.c rasterize.o mesh.o -o test $(LDFLAGS) -lm

demo: test visualize
	./test --demo
	./visualize demo.bin --simple

clean:
	rm -f *.o visualize test demo.bin cube.bin expected.bin actual.bin

run-test: test
	./test
