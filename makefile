ROOT=/home/lfx/fitteia
PREFIX=
OS=LINUX
PERLCORE=/usr/lib/$(ARCH)-linux-gnu/perl/$(PERLVERSION)/CORE

.PHONY: install clean extensions extensions-selftest

install:
	make OS=$(OS) ROOT=$(ROOT) PERLCORE=$(PERLCORE) -C core/onefit-3.1 install-fitteia
	make OS=$(OS) ROOT=$(ROOT) PERLCORE=$(PERLCORE) -C core/onefit-3.1/perl install-pcop
	make OS=$(OS) ROOT=$(ROOT) PERLCORE=$(PERLCORE) -C core/onefit-3.1/doc install
	make OS=$(OS) ROOT=$(ROOT) PERLCORE=$(PERLCORE) -C local install

clean:
	rm -f *~
	make ROOT=$(ROOT) -C core/onefit-3.1 clean
	make ROOT=$(ROOT) -C local clean

# Build and register everything in extensions/<name>/ (see extensions/README.md).
# Writes $(ROOT)/etc/extensions.mk and META-CATALOG.json; TEST=1 also runs each
# extension's own tests.
extensions:
	perl tools/extensions.pl install --c-root . --root $(ROOT)$(PREFIX) $(if $(TEST),--test)

extensions-selftest:
	perl tools/test_extensions.t
