OS=LINUX
F77=gfortran -fPIC -funroll-loops -ffast-math  -std=legacy --fixed-line-length-none -fd-lines-as-comments -fbackslash
ARCH=x86_64
ROOT=/home/fitteia
PERLVERSION=5.36
PERLCORE=/usr/lib/$(ARCH)-linux-gnu/perl/$(PERLVERSION)/CORE
PREFIX=
LIBNUMBER=4.0.4
INTERFACE=UserLib

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	# macOS's own /usr/bin/gcc is Apple's clang wearing a gcc name, not
	# GNU GCC - GCCPATH (a real Homebrew gcc prefix) was already being
	# discovered here for LIBGFORTRAN's own -L flag, but never actually
	# used to pick the compiler itself, so CC stayed plain "gcc" (Apple's
	# clang) even with a real gcc installed alongside it. Homebrew's own
	# gcc formula installs a versioned binary (gcc-15, gcc-14, ...),
	# deliberately not plain "gcc", so finding it needs an explicit
	# search. Same fix as etc/OFE/default/makefile's own (OneFit-Engine/
	# onefite-native) - this repo builds the libraries THAT makefile
	# links into every fit, so this side matters at least as much.
	GCCPATH := $(shell brew --prefix gcc 2>/dev/null)
	REAL_GCC :=
	ifneq ($(GCCPATH),)
		REAL_GCC := $(shell ls $(GCCPATH)/bin/gcc-[0-9]* 2>/dev/null | sort -t- -k2 -n | tail -1)
	endif
	ifeq ($(REAL_GCC),)
		REAL_GCC := gcc
	endif
	LIBGFORTRAN = -L$(GCCPATH)/lib/gcc/current
else
	REAL_GCC := gcc
	LIBGFORTRAN=
endif

CC=$(REAL_GCC)

CCFLAGS= -D$(OS) -O3 -g -fpic -pipe -I$(PERLCORE) -I$(ROOT)$(PREFIX)/include 

#CCFLAGS= -D$(OS) -D_REENTRANT -D_GNU_SOURCE -DDEBIAN -fstack-protector -fno-strict-aliasing -pipe -I$(ROOT)$(PREFIX)/include -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g -fPIC -I$(PERLCORE) -I$(ROOT)$(PREFIX)/include -I$(ROOT)/C/core/onefit-3.1 -I$(ROOT)/C/core/onefit-3.1/modelos

LDFLAGS= $(LIBGFORTRAN) -L$(PERLCORE) -shared -L/usr/local/lib -fstack-protector -O3 -g -lgfortran
LIBS= -lperl -L$(ROOT)$(PREFIX)/lib/ -lonefit-modelos-$(LIBNUMBER) -lonefit-util-$(LIBNUMBER) -I$(ROOT)$(PREFIX)/include

CSRCS := $(wildcard *.c)
FSRCS := $(wildcard *.f)

# turn them into object names
OBJS  := $(CSRCS:.c=.o) $(FSRCS:.f=.o)

%.o: %.c
	$(CC) $(CCFLAGS) -c $< -o $@

%.o: %.f
	$(F77) -O3 -c $< -o $@

lib: $(OBJS) 
#	$(CC) $(CCFLAGS) -c *.c
	rm -f libuserlib.a
	ar -rvs libuserlib.a *.o

module: *.c  $(INTERFACE).i
	swig -perl $(INTERFACE).i
	$(CC) -c $(CCFLAGS) *.c 
	$(CC)  $(LDFLAGS)  *.o -o $(INTERFACE).so $(LIBS)
	rm $(INTERFACE)_wrap.o $(INTERFACE)_wrap.c

module-test:
	perl -e 'use lib "./"; use UserLib; print UserLib::BPP(1,1,1)."\n";'
	perl -e 'use lib "./"; use UserLib; print UserLib::EllipticF(1.5,0.5,10.0)."\n";'
	perl -e 'use lib "./"; use UserLib; print UserLib::iT1inISpara(1e6,300,1e-12,1e-12,1e-10,19)."\n";'

install: lib 
	install -d $(ROOT)$(PREFIX)/lib $(ROOT)$(PREFIX)/include
	install -m 0644 *.dat *.a *.h $(ROOT)$(PREFIX)/lib
	install -m 0644 *.h $(ROOT)$(PREFIX)/include

clean:
	rm -f *.o *~
