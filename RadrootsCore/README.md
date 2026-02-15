# RadrootsCore

This directory is a thin iOS wrapper around shared Rust crates in `../crates`.

- shared backend crate: `../crates/app-core`
- swift ffi crate: `../crates/app-ffi-swift`
- wasm crate: `../crates/app-wasm`

Use `make -C ios/RadrootsCore` (or `make` from `ios/`) to build the Rust static libraries, generate UniFFI Swift bindings, and package `RadrootsFFI.xcframework` for `RadrootsKit`.
