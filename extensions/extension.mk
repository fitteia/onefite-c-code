# Shared build rules for ONE extension. Driven by tools/extensions.pl, run
# from inside the extension's own directory:
#
#   make -f <c-code>/extensions/extension.mk EXT_NAME=... EXT_SOURCES="a.c b.f" \
#        EXT_HEADERS="a.h" EXT_LICENSE_FILES="LICENSE NOTICE" \
#        EXT_METADATA=META-C-model.json C_ROOT=<abs> ROOT=<abs> install
#
# An extension needs no Makefile of its own. One that wants its own build sets
# "makefile" in extension.json; a Makefile that merely exists is ignored.
UNAME_S := $(shell uname -s)
OS ?= $(if $(filter Darwin,$(UNAME_S)),MacOSX,LINUX)

ifeq ($(UNAME_S),Darwin)
	# /usr/bin/gcc on macOS is Apple's clang - same reasoning and same lookup
	# as core/onefit-3.1/makefile and local/makefile: use Homebrew's real,
	# versioned gcc when present.
	GCCPATH := $(shell brew --prefix gcc 2>/dev/null)
	REAL_GCC :=
	ifneq ($(GCCPATH),)
		REAL_GCC := $(shell ls $(GCCPATH)/bin/gcc-[0-9]* 2>/dev/null | sort -t- -k2 -n | tail -1)
	endif
	ifeq ($(REAL_GCC),)
		REAL_GCC := gcc
	endif
else
	REAL_GCC := gcc
endif
ifeq ($(origin CC),default)
	CC := $(REAL_GCC)
endif
FC ?= gfortran

C_ROOT ?= ..
ROOT ?= $(C_ROOT)
CFLAGS ?= -O3 -fPIC -D$(OS)
FFLAGS ?= -O3 -fPIC -ffixed-form
INCLUDES = -I. -I$(C_ROOT)/core/onefit-3.1 -I$(ROOT)/include

BUILD := build
LIBFILE := libonefit-ext-$(EXT_NAME).a
OBJS := $(addprefix $(BUILD)/,$(addsuffix .o,$(basename $(EXT_SOURCES))))

.PHONY: all install clean
all: $(BUILD)/$(LIBFILE)

$(BUILD)/%.o: %.c $(EXT_HEADERS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) $(EXT_CFLAGS) -c $< -o $@

$(BUILD)/%.o: %.f
	@mkdir -p $(dir $@)
	$(FC) $(FFLAGS) $(EXT_FFLAGS) -c $< -o $@

$(BUILD)/$(LIBFILE): $(OBJS)
	ar rcs $@ $^

install: $(BUILD)/$(LIBFILE)
	mkdir -p $(ROOT)/lib $(ROOT)/include/ext/$(EXT_NAME) $(ROOT)/share/extensions/$(EXT_NAME)
	install -m 0644 $(BUILD)/$(LIBFILE) $(ROOT)/lib/
	for h in $(EXT_HEADERS); do install -m 0644 $$h $(ROOT)/include/ext/$(EXT_NAME)/; done
	for f in $(EXT_LICENSE_FILES) $(EXT_METADATA); do mkdir -p $(ROOT)/share/extensions/$(EXT_NAME)/$$(dirname $$f) && install -m 0644 $$f $(ROOT)/share/extensions/$(EXT_NAME)/$$f; done

clean:
	rm -rf $(BUILD)
