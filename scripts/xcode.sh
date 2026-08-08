#!/bin/bash
set -euo pipefail

for variable in XCODE_DERIVED_DATA XCODE_SOURCE_PACKAGES XCODE_PACKAGE_CACHE; do
    if [[ -z "${!variable:-}" ]]; then
        echo "error: $variable is required; run this command through cargo extbuild" >&2
        exit 1
    fi
done

output_args=(
    -quiet
    -derivedDataPath "$XCODE_DERIVED_DATA"
    -clonedSourcePackagesDirPath "$XCODE_SOURCE_PACKAGES"
    -packageCachePath "$XCODE_PACKAGE_CACHE"
)
offline_args=(
    -disableAutomaticPackageResolution
    -onlyUsePackageVersionsFromResolvedFile
    -skipPackagePluginValidation
)

operation=${1:-}
case "$operation" in
    resolve)
        exec xcodebuild \
            -resolvePackageDependencies \
            -project Radroots.xcodeproj \
            -scheme Radroots \
            "${output_args[@]}"
        ;;
    package-build)
        exec xcodebuild \
            -scheme RadrootsApp \
            -destination 'generic/platform=iOS Simulator' \
            "${output_args[@]}" \
            "${offline_args[@]}" \
            ARCHS=arm64 \
            build
        ;;
    package-test)
        destination=${2:?package-test requires a simulator destination}
        exec xcodebuild \
            -scheme RadrootsAppPublicAPITests \
            -destination "$destination" \
            "${output_args[@]}" \
            "${offline_args[@]}" \
            test
        ;;
    project-build)
        configuration=${2:?project-build requires a configuration}
        case "$configuration" in
            Debug|Release) ;;
            *) echo "error: unsupported configuration: $configuration" >&2; exit 1 ;;
        esac
        exec xcodebuild \
            -project Radroots.xcodeproj \
            -scheme Radroots \
            -configuration "$configuration" \
            -destination 'generic/platform=iOS Simulator' \
            "${output_args[@]}" \
            "${offline_args[@]}" \
            build
        ;;
    project-test)
        destination=${2:?project-test requires a simulator destination}
        test_target=${3:?project-test requires a test target}
        case "$test_target" in
            RadrootsTests|RadrootsUITests) ;;
            *) echo "error: unsupported test target: $test_target" >&2; exit 1 ;;
        esac
        exec xcodebuild \
            -project Radroots.xcodeproj \
            -scheme Radroots \
            -destination "$destination" \
            "${output_args[@]}" \
            "${offline_args[@]}" \
            "-only-testing:$test_target" \
            test
        ;;
    *)
        echo "usage: $0 {resolve|package-build|package-test|project-build|project-test}" >&2
        exit 64
        ;;
esac
