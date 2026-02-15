# RadrootsCore

`ios/RadrootsCore` is the iOS Rust wrapper for the shared Swift FFI crate.

## Source of truth
- `../../crates/app-ffi-swift` (built via `--manifest-path`)

## Dependency pattern
- Keep `radroots-app-ffi-swift` in `[workspace.dependencies]` with a local `path` during development.
- Switch this to a crates.io version later without changing the make/build flow.
- Do not link `radroots-app-ffi-swift` as a Rust `[dependencies]` crate in this wrapper.

## Build flow
Run `make -C ios` (or `make -C ios/RadrootsCore`) to:
- build from `../../crates/app-ffi-swift/Cargo.toml`
- write Rust build artifacts under `ios/RadrootsCore/target`
- generate UniFFI Swift bindings
- package `RadrootsFFI.xcframework` into `ios/RadrootsKit/Artifacts`
- copy generated Swift files into `ios/RadrootsKit/Sources/RadrootsKit/Generated`
