CC= gcc -O0
CFLAGS=-Wall 
IFLAGS=-lm

RM = /bin/rm -rf

all : varyCpuAndMem

varyCpuAndMem: varyCpuAndMem.o 
	$(CC) $(CFLAGS) $(IFLAGS) varyCpuAndMem.o -lm -o varyCpuAndMem

varyCpuAndMem.o: varyCpuAndMem.c
	$(CC) $(CFLAGS) -c varyCpuAndMem.c
	
clean:
	$(RM) varyCpuAndMem varyCpuAndMem.o
