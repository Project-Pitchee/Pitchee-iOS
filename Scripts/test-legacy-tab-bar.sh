#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-legacy-tab-bar.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/PitcheeApp/App/LegacyGlassTabBar.swift" \
    "$project_directory/Tests/Navigation/LegacyGlassTabBarTests.swift" \
    -o "$test_directory/legacy-tab-bar-tests"

"$test_directory/legacy-tab-bar-tests"
