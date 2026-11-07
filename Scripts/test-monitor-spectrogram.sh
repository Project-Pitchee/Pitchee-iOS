#!/bin/sh

set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-monitor-spectrogram.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -O -swift-version 6 -strict-concurrency=complete \
    "$project_directory/PitcheeApp/Interop/Core/AnalysisResult.swift" \
    "$project_directory/PitcheeApp/Analysis/PitchTimeline.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorTimeline.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorSpectrumAnalyzer.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorSpectrogramRasterizer.swift" \
    "$project_directory/Tests/Monitoring/MonitorSpectrogramTests.swift" \
    -framework Accelerate -framework CoreGraphics \
    -o "$test_directory/monitor-spectrogram-tests"

"$test_directory/monitor-spectrogram-tests"
