PHONY = all example lib
.DEFAULT_GOAL := all
WFLAGS := -Wall -Wextra -Werror
all: example

dep: 
	@$(MAKE) --directory ../chord/ fresh
	@$(MAKE) --directory ../CHash/ fresh

fresh: clean dep all

example: example.o
	$(CC) example.o -o example -lpthread -lcrypto ../CHash/libchash.a ../chord/libchord.a $(CCFLAGS) $(WFLAGS)

small: clean
	@$(MAKE) CCFLAGS="-Os -m32" all

example.o: example.c
	$(CC) -c example.c $(CCFLAGS) $(WFLAGS)

clean:
	rm -rf *.a *.o example

test: clean all
	perl testsuite.pl $(TARGS)

autotest: clean all
	perl testsuite.pl -n 8 -m 4 -v || exit
	perl testsuite.pl -n 64 -m 256 -v || exit
	perl testsuite.pl -n 8 -k 10 -v || exit
