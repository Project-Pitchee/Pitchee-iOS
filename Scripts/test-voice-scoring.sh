#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-voice-scoring.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/Tests/Voice/VoiceScoringTests.swift" \
    -o "$test_directory/voice-scoring-tests"

"$test_directory/voice-scoring-tests"
