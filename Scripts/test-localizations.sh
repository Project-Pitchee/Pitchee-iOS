#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
cd "$project_directory"
python3 Scripts/validate-localizations.py
python3 -m unittest discover -s Tests/Localization -p 'test_*.py'

test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-localizations.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"
test_app="$test_directory/LocalizationRuntime.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
cat > "$test_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.pitchee.localization-tests</string>
<key>CFBundleExecutable</key><string>localization-tests</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
</dict></plist>
PLIST
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$test_app/Contents/Resources"
xcrun xcstringstool compile Resources/InfoPlist.xcstrings --output-directory "$test_app/Contents/Resources"
xcrun swiftc -parse-as-library -swift-version 5 \
    -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
    PitcheeApp/Interop/Core/AnalysisResult.swift \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    PitcheeApp/Analysis/VoiceScoring.swift \
    PitcheeApp/Practice/PracticeData.swift \
    Tests/Localization/LocalizationRuntimeTests.swift \
    -o "$test_app/Contents/MacOS/localization-tests"
for locale_directory in "$test_app"/Contents/Resources/*.lproj; do
    language=$(basename "$locale_directory" .lproj)
    "$test_app/Contents/MacOS/localization-tests" -AppleLanguages "($language)"
done
