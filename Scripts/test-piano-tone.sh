#!/bin/sh

set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-piano-tone.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -O -swift-version 5 \
    -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
    "$project_directory/PitcheeApp/Audio/PianoToneRenderer.swift" \
    "$project_directory/Tests/Audio/PianoToneRendererTests.swift" \
    -o "$test_directory/piano-tone-tests"

"$test_directory/piano-tone-tests"
