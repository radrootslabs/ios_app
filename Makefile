FFI_ROOT := RadrootsFFI

.PHONY: all clean distclean sync-source build generate package install print-config project xcodegen

all clean distclean sync-source build generate package install print-config:
	$(MAKE) -C $(FFI_ROOT) $@

project xcodegen:
	xcodegen generate --spec project.yml
