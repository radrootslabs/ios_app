WRAPPER_ROOT := $(CURDIR)/RadrootsCore

.PHONY: all clean build generate package bindings

all clean build generate package bindings:
	$(MAKE) -C $(WRAPPER_ROOT) $@
