WRAPPER_ROOT := $(CURDIR)/RadrootsCore

.PHONY: all clean build generate package bindings

all:
	$(MAKE) -C $(WRAPPER_ROOT) all

clean:
	$(MAKE) -C $(WRAPPER_ROOT) clean

build:
	$(MAKE) -C $(WRAPPER_ROOT) build

generate:
	$(MAKE) -C $(WRAPPER_ROOT) generate

package:
	$(MAKE) -C $(WRAPPER_ROOT) package

bindings:
	$(MAKE) -C $(WRAPPER_ROOT) bindings
