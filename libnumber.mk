# The OneFit C core version, defined only here. It is part of every core
# library name (libonefit-$(LIBNUMBER).a, -modelos-, -util-), the base
# version extensions check against with "requires_base" (same major only),
# and is installed as $(ROOT)/etc/engine.mk so the per-fit makefiles of
# onefite-go and OneFit-Engine link the right names. Change it only when
# the core's API for extensions changes - see README.md, "Version".
LIBNUMBER=5.0.0
