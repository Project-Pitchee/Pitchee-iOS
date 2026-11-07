#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-practice.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Practice/PracticeData.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingAssessment.swift" \
    "$project_directory/PitcheeApp/Insights/InsightsData.swift" \
    "$project_directory/PitcheeApp/App/PrivateAppStorage.swift" \
    "$project_directory/Tests/Fixtures/InsightsThemeSupport.swift" \
    "$project_directory/Tests/Practice/PracticeTests.swift" \
    -o "$test_directory/practice-tests"
"$test_directory/practice-tests"
xcrun swiftc -parse-as-library -swift-version 5 -module-name PracticeMigrationTests -D LEGACY_PRACTICE_SCHEMA \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/Tests/Fixtures/RecordingAssessmentBeforePractice.swift" \
    "$project_directory/Tests/Practice/PracticeMigrationTests.swift" \
    -o "$test_directory/create-old-store"
"$test_directory/create-old-store" "$test_directory/history.store"
xcrun swiftc -parse-as-library -swift-version 5 -module-name PracticeMigrationTests \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Practice/PracticeData.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingAssessment.swift" \
    "$project_directory/Tests/Practice/PracticeMigrationTests.swift" \
    -o "$test_directory/migrate-store"
"$test_directory/migrate-store" "$test_directory/history.store"
"$test_directory/migrate-store" "$test_directory/history.store"
xcrun swiftc -parse-as-library -swift-version 5 \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingStatistics.swift" \
    "$project_directory/Tests/Recording/RecordingQualityAudioTests.swift" \
    -o "$test_directory/audio-quality-tests"
"$test_directory/audio-quality-tests"
