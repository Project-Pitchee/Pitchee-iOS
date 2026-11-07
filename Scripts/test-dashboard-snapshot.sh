#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-dashboard-snapshot.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"

xcrun swiftc -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Practice/PracticeData.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingAssessment.swift" \
    "$project_directory/Tests/Fixtures/InsightsThemeSupport.swift" \
    "$project_directory/PitcheeApp/Insights/InsightsData.swift" \
    "$project_directory/PitcheeApp/Insights/DashboardSnapshot.swift" \
    "$project_directory/Tests/Insights/DashboardSnapshotTests.swift" \
    -o "$test_directory/dashboard-snapshot-tests"

"$test_directory/dashboard-snapshot-tests"
