#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-launch-animation.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/PitcheeApp/App/LaunchAnimation.swift" \
    "$project_directory/Tests/App/LaunchAnimationTests.swift" \
    -o "$test_directory/launch-animation-tests"

"$test_directory/launch-animation-tests"
