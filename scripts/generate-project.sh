#!/bin/sh
set -eu

project_file=Radroots.xcodeproj/project.pbxproj
localizations_id=A11CE10CA11A710A00000001

xcodegen generate --spec project.yml

temporary_count=$(grep -Ec '"TEMP_[0-9A-F-]+" /\* Localizations \*/' "$project_file" || true)
case "$temporary_count" in
    0) ;;
    1)
        perl -0pi -e \
            's/"TEMP_[0-9A-F-]+"( \/\* Localizations \*\/)/A11CE10CA11A710A00000001$1/g' \
            "$project_file"
        ;;
    *)
        echo "error: unexpected XcodeGen Localizations group inventory" >&2
        exit 1
        ;;
esac

if grep -Eq '"TEMP_[0-9A-F-]+" /\* Localizations \*/' "$project_file"; then
    echo "error: XcodeGen temporary Localizations identifier remains" >&2
    exit 1
fi
deterministic_count=$(grep -Ec "$localizations_id /\* Localizations \*/" "$project_file" || true)
if [ "$deterministic_count" -gt 1 ]; then
    echo "error: deterministic Localizations identifier is duplicated" >&2
    exit 1
fi
