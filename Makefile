PHONY = all example lib
.DEFAULT_GOAL := all
WFLAGS := -Wall -Wextra -Werror
ifeq ($(DEBUGALL),yes)
CHORDCCFLAGS=-DDEBUG_ENABLE
CHASHCCFLAGS=-DDEBUG_ENABLE
CCFLAGS=-DDEBUG_ENABLE
endif

all: example

dep:
	@$(MAKE) CCFLAGS="$(CHORDCCFLAGS)" --directory ../chord/ fresh
	@$(MAKE) CCFLAGS="$(CHASHCCFLAGS)"  --directory ../CHash/ fresh

maketest: clean dep all clean all clean example fresh
	@$(MAKE) CCFLAGS="-DDEBUG_ENABLE" --directory ../chord/ fresh
	@$(MAKE) CCFLAGS="" --directory ../chord/ fresh
	@$(MAKE) CCFLAGS="-DDEBUG_ENABLE"  --directory ../CHash/ fresh
	@$(MAKE) CCFLAGS=""  --directory ../CHash/ fresh


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

autotest: fresh
	perl testsuite.pl -n 8 -m 4 -v || exit
	perl testsuite.pl -n 64 -m 256 -v || exit
	perl testsuite.pl -n 8 -k 10 -v || exit
