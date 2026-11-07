#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-readiness-provider.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -default-isolation MainActor -warnings-as-errors \
    -target "$(uname -m)-apple-macosx14.0" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Practice/PracticeData.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingAssessment.swift" \
    "$project_directory/PitcheeApp/Analysis/ReadinessScoring.swift" \
    "$project_directory/PitcheeApp/Analysis/ReadinessHistory.swift" \
    "$project_directory/PitcheeApp/Analysis/ReadinessProvider.swift" \
    "$project_directory/Tests/Readiness/ReadinessProviderTests.swift" \
    -o "$test_directory/readiness-provider-tests"

"$test_directory/readiness-provider-tests"
