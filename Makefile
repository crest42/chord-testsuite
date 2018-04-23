PHONY = all example lib
.DEFAULT_GOAL := all
WFLAGS := -Wall -Wextra -Werror
all: example

example: example.o
	$(CC) example.o -o example -lpthread -lcrypto ../CHash/libchash.a ../chord/libchord.a $(CCFLAGS) $(WFLAGS)

small: clean
	@$(MAKE) CCFLAGS="-Os -m32" all

example.o: example.c
	$(CC) -c example.c $(CCFLAGS) $(WFLAGS)

clean:
	rm -rf *.a *.o example
