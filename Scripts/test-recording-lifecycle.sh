#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-recording-lifecycle.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

. "$script_directory/core-scoring-test-support.sh"

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    "$project_directory/PitcheeApp/Audio/AudioSessionCoordinator.swift" \
    "$project_directory/Tests/Recording/AudioSessionCoordinatorTests.swift" \
    -o "$test_directory/session-tests"
"$test_directory/session-tests"

# Exercise the real view model and SwiftData schema with controlled microphone,
# session and inference substitutes. These checks never access real audio hardware
# or the user's diagnostics, research data or history.
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -strict-concurrency=complete -warnings-as-errors \
    -I "$project_directory/Dependencies/PitcheeCore/platform/ios" \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Interop/Core/CoreError.swift" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    "$project_directory/PitcheeApp/Analysis/VoiceScoring.swift" \
    "$project_directory/PitcheeApp/Analysis/PitchTimeline.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingStatistics.swift" \
    "$project_directory/PitcheeApp/Analysis/RecordingAssessment.swift" \
    "$project_directory/PitcheeApp/Analysis/ScoreStudyEvaluator.swift" \
    "$project_directory/PitcheeApp/Analysis/AnalysisViewModel.swift" \
    "$project_directory/PitcheeApp/Practice/PracticeData.swift" \
    "$project_directory/PitcheeApp/App/AppStorage.swift" \
    "$project_directory/PitcheeApp/Audio/AudioSessionCoordinator.swift" \
    "$project_directory/PitcheeApp/Diagnostics/LocalDiagnostics.swift" \
    "$project_directory/PitcheeApp/Diagnostics/LocalScoreStudy.swift" \
    "$project_directory/Tests/Recording/RecordingLifecycleSupport.swift" \
    "$project_directory/Tests/Recording/RecordingLifecycleTests.swift" \
    -o "$test_directory/recording-tests"
"$test_directory/recording-tests"
