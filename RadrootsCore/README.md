# RadrootsCore

`ios/RadrootsCore` is the iOS Rust wrapper entrypoint for shared app crates.

## Shared crates
- backend runtime: `../../crates/app-core`
- swift ffi surface: `../../crates/app-ffi-swift`
- wasm surface: `../../crates/app-wasm`

## Dependency pattern
This `Cargo.toml` follows the same local workspace dependency style used in `internal/.../radrootsd/Cargo.toml`:
- local `path` dependencies during active development
- dependency declarations centralized in `[workspace.dependencies]`

When crates.io releases are ready, these paths can be switched to versioned dependencies while preserving this wrapper layout for OSS iOS consumers.

## Build flow
Use `make -C ios/RadrootsCore` (or `make` from `ios/`) to:
- build Rust libs from shared crates
- generate UniFFI Swift bindings
- package `RadrootsFFI.xcframework` into `ios/RadrootsKit/Artifacts`
