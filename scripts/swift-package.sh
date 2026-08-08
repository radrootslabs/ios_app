#!/bin/sh
set -eu

for variable in SWIFTPM_SCRATCH SWIFTPM_CACHE; do
    case "$variable" in
        SWIFTPM_SCRATCH) value=${SWIFTPM_SCRATCH:-} ;;
        SWIFTPM_CACHE) value=${SWIFTPM_CACHE:-} ;;
    esac
    if [ -z "$value" ]; then
        echo "error: $variable is required; run this command through cargo extbuild" >&2
        exit 1
    fi
done

operation=${1:-}
case "$operation" in
    resolve)
        exec swift package \
            --scratch-path "$SWIFTPM_SCRATCH" \
            --cache-path "$SWIFTPM_CACHE" \
            --disable-sandbox \
            resolve
        ;;
    *)
        echo "usage: $0 resolve" >&2
        exit 64
        ;;
esac
