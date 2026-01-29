CC = cc
CFLAGS = -Wall -Wextra -O2 -std=c99
LDFLAGS =

.PHONY: all clean test demo

all: visualize test

rasterize.o: rasterize.c rasterize.h
	$(CC) $(CFLAGS) -c rasterize.c -o rasterize.o

visualize: visualize.c rasterize.o rasterize.h
	$(CC) $(CFLAGS) visualize.c rasterize.o -o visualize $(LDFLAGS)

test: test.c rasterize.o rasterize.h
	$(CC) $(CFLAGS) test.c rasterize.o -o test $(LDFLAGS)

demo: test visualize
	./test --demo
	./visualize demo.bin --simple

clean:
	rm -f *.o visualize test demo.bin expected.bin actual.bin

run-test: test
	./test
