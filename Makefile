FFI_ROOT := RadrootsFFI

.PHONY: all clean distclean sync-source build generate package install provenance verify print-config project xcodegen

all clean distclean sync-source build generate package install provenance verify print-config:
	cargo extbuild run -- $(MAKE) -C $(FFI_ROOT) $@

project xcodegen:
	cargo extbuild run -- xcodegen generate --spec project.yml
