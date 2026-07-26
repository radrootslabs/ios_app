# RadrootsFFI

`RadrootsFFI` is the source resolver and build workspace for the Rust FFI
artifact consumed by the Radroots iOS app.

## Goals
- keep the iOS project openable and buildable in Xcode for OSS developers
- keep `radroots_app_ffi` reusable for other Apple clients
- support three source modes from one Makefile: `git`, `crates`, and `local`

## Quick start
- build everything: `make all`
- print current config: `make print-config`
- rebuild from scratch: `make distclean all`

## Source modes
- `SOURCE_MODE=git` (default)
  - clones `RADROOTS_FIELD_LIB_GIT_URL` at `RADROOTS_FIELD_LIB_GIT_REV`
  - builds `radroots_app_ffi` from the checked out workspace
- `SOURCE_MODE=crates`
  - downloads `radroots_app_ffi` from crates.io by version
- `SOURCE_MODE=local`
  - requires `LOCAL_FFI_MANIFEST=/absolute/path/to/radroots_app_ffi/Cargo.toml`

## Configuration
Configuration is read from:
- `RadrootsFFI/source.lock` for pinned defaults
- `RadrootsFFI/Config/ffi-build.env` for optional local overrides

Cargo output defaults to `RadrootsFFI/.build/target` for standalone use. An
inherited `CARGO_TARGET_DIR` relocates the complete device, simulator, host, and
UniFFI build graph. `TARGET_DIR=/absolute/path` is the equivalent explicit Make
override; when both are present, `TARGET_DIR` takes precedence.

## Outputs
- xcframework: `Radroots/Frameworks/RadrootsFFI.xcframework`
- generated Swift bindings: `Radroots/Generated`
