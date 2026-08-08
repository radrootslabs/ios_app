#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ios_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
lock_file="$ios_root/RadrootsFFI/source.lock"

lock_value() {
    key=$1
    awk -v key="$key" '$2 == key && $3 == ":=" { print $4 }' "$lock_file"
}

require_sha256() {
    path=$1
    expected=$2
    label=$3
    if [ ! -f "$path" ]; then
        echo "error: missing $label; run 'make bootstrap' from $ios_root" >&2
        exit 1
    fi
    actual=$(shasum -a 256 "$path" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        echo "error: stale $label; run 'make bootstrap' from $ios_root" >&2
        exit 1
    fi
}

framework="$ios_root/Radroots/Frameworks/RadrootsFFI.xcframework"
if [ ! -d "$framework" ]; then
    echo "error: missing RadrootsFFI.xcframework; run 'make bootstrap' from $ios_root" >&2
    exit 1
fi

require_sha256 \
    "$framework/ios-arm64/libradroots_mobile_ffi.a" \
    "$(lock_value RADROOTS_FIELD_FFI_DEVICE_SHA256)" \
    "device FFI library"
require_sha256 \
    "$framework/ios-arm64-simulator/libradroots_mobile_ffi.a" \
    "$(lock_value RADROOTS_FIELD_FFI_SIMULATOR_SHA256)" \
    "simulator FFI library"
require_sha256 \
    "$ios_root/Radroots/Generated/RadrootsKitBindings.swift" \
    "$(lock_value RADROOTS_FIELD_FFI_SWIFT_SHA256)" \
    "generated Swift bindings"
require_sha256 \
    "$framework/ios-arm64-simulator/Headers/RadrootsFFI.h" \
    "$(lock_value RADROOTS_FIELD_FFI_HEADER_SHA256)" \
    "FFI header"
require_sha256 \
    "$framework/ios-arm64-simulator/Headers/module.modulemap" \
    "$(lock_value RADROOTS_FIELD_FFI_MODULEMAP_SHA256)" \
    "FFI module map"
require_sha256 \
    "$ios_root/RadrootsFFI/api/RadrootsKitBindings.symbols.json" \
    "$(lock_value RADROOTS_FIELD_FFI_API_SHA256)" \
    "generated bindings API snapshot"

framework_sha256=$(
    cd "$ios_root/Radroots/Frameworks"
    find RadrootsFFI.xcframework -type f -print | LC_ALL=C sort | while IFS= read -r file; do
        shasum -a 256 "$file"
    done | shasum -a 256 | awk '{print $1}'
)
if [ "$framework_sha256" != "$(lock_value RADROOTS_FIELD_FFI_XCFRAMEWORK_SHA256)" ]; then
    echo "error: stale XCFramework aggregate; run 'make bootstrap' from $ios_root" >&2
    exit 1
fi

expected_revision=$(lock_value RADROOTS_FIELD_LIB_GIT_REV)
expected_version=$(lock_value RADROOTS_FIELD_FFI_CRATE_VERSION)
if ! grep -Fq "\"revision\": \"$expected_revision\"" "$ios_root/RadrootsFFI/provenance.json"; then
    echo "error: stale FFI provenance revision; run 'make bootstrap' from $ios_root" >&2
    exit 1
fi
if ! grep -Fq "version = \"$expected_version\"" "$ios_root/radroots.lib.source-lock.v1.toml"; then
    echo "error: source-lock version differs from FFI source.lock" >&2
    exit 1
fi

echo "installed FFI artifacts match source.lock"
