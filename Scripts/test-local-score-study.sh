#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-local-score-study.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"

xcrun swiftc -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Diagnostics/LocalDiagnostics.swift" \
    "$project_directory/PitcheeApp/App/PrivateAppStorage.swift" \
    "$project_directory/PitcheeApp/Diagnostics/LocalDiagnosticsStore.swift" \
    "$project_directory/PitcheeApp/Diagnostics/LocalScoreStudy.swift" \
    "$project_directory/PitcheeApp/Diagnostics/LocalScoreStudyStore.swift" \
    "$project_directory/PitcheeApp/Analysis/ScoreStudyEvaluator.swift" \
    "$project_directory/Tests/Diagnostics/LocalScoreStudyTests.swift" \
    -o "$test_directory/local-score-study-tests"

"$test_directory/local-score-study-tests"
