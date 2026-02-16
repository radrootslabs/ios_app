# RadrootsFFI

`ios/RadrootsFFI` is the source resolver and build workspace for the Rust FFI
artifact consumed by `ios/RadrootsKit`.

## Goals
- keep the iOS project openable and buildable in Xcode for OSS developers
- keep `radroots-app-ffi-swift` reusable for other Apple clients
- support three source modes from one Makefile: `git`, `crates`, and `local`

## Quick start
- build everything: `make -C ios all`
- print current config: `make -C ios print-config`
- rebuild from scratch: `make -C ios distclean all`

## Source modes
- `SOURCE_MODE=git` (default)
  - clones `RADROOTS_CRATES_GIT_URL` at `RADROOTS_CRATES_GIT_REV`
  - builds `app-ffi-swift` from the checked out workspace
- `SOURCE_MODE=crates`
  - downloads `radroots-app-ffi-swift` from crates.io by version
- `SOURCE_MODE=local`
  - requires `LOCAL_FFI_MANIFEST=/absolute/path/to/app-ffi-swift/Cargo.toml`

## Configuration
Configuration is read from:
- `RadrootsFFI/source.lock` for pinned defaults
- `RadrootsFFI/Config/ffi-build.env` for optional local overrides

## Outputs
- xcframework: `ios/RadrootsKit/Artifacts/RadrootsFFI.xcframework`
- generated swift bindings: `ios/RadrootsKit/Sources/RadrootsKit/Generated`
