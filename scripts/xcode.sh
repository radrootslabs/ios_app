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
    remote-ui-test)
        destination=${2:?remote-ui-test requires a simulator destination}
        test_selector=${3:?remote-ui-test requires a RadrootsUITests selector}
        result_name=${4:?remote-ui-test requires a result name}
        qualification_run_id=${RADROOTS_IOS_UI_TEST_RUN_ID:?RADROOTS_IOS_UI_TEST_RUN_ID is required}
        blossom_origins=${RADROOTS_IOS_UI_TEST_BLOSSOM_ORIGINS:?RADROOTS_IOS_UI_TEST_BLOSSOM_ORIGINS is required}
        relay_urls=${RADROOTS_IOS_UI_TEST_NOSTR_RELAY_URLS:-}
        if [[ ! "$destination" =~ ^platform=iOS\ Simulator,id=[A-Fa-f0-9-]+$ ]]; then
            echo "error: remote-ui-test destination must be one exact simulator id" >&2
            exit 64
        fi
        if [[ ! "$test_selector" =~ ^RadrootsUITests(/[-A-Za-z0-9_]+){0,2}$ ]]; then
            echo "error: remote-ui-test selector is invalid" >&2
            exit 64
        fi
        if [[ ! "$result_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
            echo "error: remote-ui-test result name is invalid" >&2
            exit 64
        fi
        if [[ ! "$qualification_run_id" =~ ^[a-z0-9][a-z0-9-]{6,62}[a-z0-9]$ ]]; then
            echo "error: remote-ui-test run id is invalid" >&2
            exit 64
        fi
        result_bundle="$XCODE_RESULTS/$result_name.xcresult"
        if [[ -e "$result_bundle" ]]; then
            echo "error: remote-ui-test result already exists: $result_bundle" >&2
            exit 1
        fi
        mkdir -p "$XCODE_RESULTS"
        exec xcodebuild \
            -project Radroots.xcodeproj \
            -scheme Radroots \
            -configuration Debug \
            -destination "$destination" \
            "${output_args[@]}" \
            "${offline_args[@]}" \
            -resultBundlePath "$result_bundle" \
            "-only-testing:$test_selector" \
            "RADROOTS_IOS_UI_TEST_RUN_ID=$qualification_run_id" \
            "RADROOTS_IOS_UI_TEST_NOSTR_RELAY_URLS=$relay_urls" \
            "RADROOTS_IOS_UI_TEST_BLOSSOM_ORIGINS=$blossom_origins" \
            test
        ;;
    physical-ui-build|physical-ui-test)
        destination=${2:?physical UI qualification requires a device destination}
        test_selector=${3:?physical UI qualification requires a RadrootsUITests selector}
        result_name=${4:-}
        development_team=${RADROOTS_IOS_DEVELOPMENT_TEAM:?RADROOTS_IOS_DEVELOPMENT_TEAM is required}
        qualification_run_id=${RADROOTS_IOS_UI_TEST_RUN_ID:?RADROOTS_IOS_UI_TEST_RUN_ID is required}
        blossom_origins=${RADROOTS_IOS_UI_TEST_BLOSSOM_ORIGINS:?RADROOTS_IOS_UI_TEST_BLOSSOM_ORIGINS is required}
        relay_urls=${RADROOTS_IOS_UI_TEST_NOSTR_RELAY_URLS:-}
        if [[ ! "$destination" =~ ^id=[A-Fa-f0-9-]+$ ]]; then
            echo "error: physical-ui-test destination must be one exact device id" >&2
            exit 64
        fi
        if [[ ! "$test_selector" =~ ^RadrootsUITests(/[-A-Za-z0-9_]+){0,2}$ ]]; then
            echo "error: physical-ui-test selector is invalid" >&2
            exit 64
        fi
        if [[ ! "$development_team" =~ ^[A-Z0-9]{10}$ ]]; then
            echo "error: physical-ui-test development team is invalid" >&2
            exit 64
        fi
        if [[ ! "$qualification_run_id" =~ ^[a-z0-9][a-z0-9-]{6,62}[a-z0-9]$ ]]; then
            echo "error: physical-ui-test run id is invalid" >&2
            exit 64
        fi
        physical_args=(
            -project Radroots.xcodeproj \
            -scheme Radroots \
            -configuration Debug \
            -destination "$destination" \
            "${output_args[@]}" \
            "${offline_args[@]}" \
            "-only-testing:$test_selector" \
            "DEVELOPMENT_TEAM=$development_team" \
            CODE_SIGN_STYLE=Automatic \
            "CODE_SIGN_IDENTITY=Apple Development" \
            "RADROOTS_IOS_UI_TEST_RUN_ID=$qualification_run_id" \
            "RADROOTS_IOS_UI_TEST_NOSTR_RELAY_URLS=$relay_urls" \
            "RADROOTS_IOS_UI_TEST_BLOSSOM_ORIGINS=$blossom_origins"
        )
        if [[ "$operation" == "physical-ui-build" ]]; then
            exec xcodebuild "${physical_args[@]}" build-for-testing
        fi
        if [[ ! "$result_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
            echo "error: physical-ui-test result name is invalid" >&2
            exit 64
        fi
        result_bundle="$XCODE_RESULTS/$result_name.xcresult"
        if [[ -e "$result_bundle" ]]; then
            echo "error: physical-ui-test result already exists: $result_bundle" >&2
            exit 1
        fi
        mkdir -p "$XCODE_RESULTS"
        exec xcodebuild \
            "${physical_args[@]}" \
            -resultBundlePath "$result_bundle" \
            test-without-building
        ;;
    *)
        echo "usage: $0 {resolve|package-build|package-test|project-build|project-test|remote-ui-test|physical-ui-build|physical-ui-test}" >&2
        exit 64
        ;;
esac
