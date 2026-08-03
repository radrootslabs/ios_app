# RadrootsFFI

`RadrootsFFI` is the source resolver and build workspace for the Rust FFI
artifact consumed by the Radroots iOS app.

## Goals
- keep the iOS project openable and buildable in Xcode for OSS developers
- keep `radroots_app_ffi` reusable for other Apple clients
- support pinned Git and explicit local source modes from one Makefile

## Quick start
- build everything: `make all`
- print current config: `make print-config`
- rebuild from scratch: `make distclean all`

## Source modes
- `SOURCE_MODE=git` (default)
  - clones `RADROOTS_FIELD_LIB_GIT_URL` at `RADROOTS_FIELD_LIB_GIT_REV`
  - builds `radroots_app_ffi` from the checked out workspace
- `SOURCE_MODE=local`
  - requires `LOCAL_FFI_MANIFEST=/absolute/path/to/radroots_app_ffi/Cargo.toml`
  - is for validating a matching local checkout before its Git ref is available

## Configuration
Configuration is read from:
- `RadrootsFFI/source.lock` for pinned defaults
- `RadrootsFFI/Config/ffi-build.env` for optional local overrides

The source lock also records the SHA-256 identities of the generated device
archive, simulator archive, and Swift source. These are release evidence for
the pinned source/toolchain/epoch tuple; generated outputs remain ignored and
must be rebuilt before the app is compiled.

Cargo output defaults to `RadrootsFFI/.build/target` for standalone use. An
inherited `CARGO_TARGET_DIR` relocates the complete device, simulator, host, and
UniFFI build graph. `TARGET_DIR=/absolute/path` is the equivalent explicit Make
override; when both are present, `TARGET_DIR` takes precedence.

## Outputs
- xcframework: `Radroots/Frameworks/RadrootsFFI.xcframework`
- generated Swift bindings: `Radroots/Generated`
