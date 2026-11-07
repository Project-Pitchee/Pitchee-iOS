#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-hnr.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -target "$(uname -m)-apple-macosx14.0" \
    -I "$core_scoring_module_directory" \
    -I "$project_directory/Dependencies/PitcheeCore/include" \
    "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Practice/PracticeData.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingAssessment.swift" \
    "$project_directory/Tests/Voice/HNRTests.swift" \
    -o "$test_directory/hnr-tests"

"$test_directory/hnr-tests"
"$test_directory/hnr-tests" --write-store "$test_directory/history.store"
"$test_directory/hnr-tests" --read-store "$test_directory/history.store"
