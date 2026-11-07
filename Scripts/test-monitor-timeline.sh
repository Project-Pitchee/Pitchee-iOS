#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-monitor-timeline.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -O \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Analysis/PitchTimeline.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorTimeline.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorWaveEncoder.swift" \
    "$project_directory/Tests/Recording/MonitorTimelineTests.swift" \
    -o "$test_directory/monitor-timeline-tests"

"$test_directory/monitor-timeline-tests"
