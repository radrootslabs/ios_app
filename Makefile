FFI_ROOT := RadrootsFFI

.PHONY: all clean distclean sync-source build generate package install print-config

all clean distclean sync-source build generate package install print-config:
	$(MAKE) -C $(FFI_ROOT) $@
