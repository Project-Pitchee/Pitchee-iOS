#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
core_directory=${PITCHEE_CORE_SOURCE_DIRECTORY:-"$project_directory/Dependencies/PitcheeCore"}
runtime_directory="$project_directory/Dependencies/Artifacts/ONNXRuntime"
framework_directory="$runtime_directory/onnxruntime.xcframework/macos-arm64_x86_64"

if [ ! -f "$framework_directory/onnxruntime.framework/onnxruntime" ]; then
    echo "Install ONNX Runtime with Scripts/bootstrap-native-dependencies.sh first." >&2
    exit 1
fi

test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-live-f0.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

cmake -S "$core_directory" -B "$test_directory/native" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPITCHEE_BUILD_SHARED=OFF \
    -DPITCHEE_BUILD_CLI=OFF \
    -DPITCHEE_BUILD_TESTS=OFF \
    -DPITCHEE_ORT_INCLUDE_DIR="$runtime_directory/Headers" \
    -DPITCHEE_ORT_LIBRARY="$framework_directory/onnxruntime.framework/onnxruntime"
cmake --build "$test_directory/native" --parallel 4

xcrun clang++ -std=c++20 -O2 -Wall -Wextra -Werror \
    -I "$core_directory/include" -I "$core_directory/src" \
    -c "$project_directory/PitcheeApp/Interop/Core/HNRBridge/HNRBridge.cpp" \
    -o "$test_directory/hnr-bridge.o"

xcrun clang -std=c11 -O2 -Wall -Wextra -Werror \
    -c "$project_directory/PitcheeApp/Audio/RealtimeAtomics/RealtimeAtomics.c" \
    -o "$test_directory/realtime-atomics.o"

xcrun swiftc -parse-as-library -O \
    -I "$project_directory/PitcheeApp/Audio/RealtimeAtomics" \
    -I "$core_directory/platform/ios" \
    -I "$project_directory/PitcheeApp/Interop/Core/HNRBridge" \
    -module-cache-path "$test_directory/module-cache" \
    -I "$core_directory/include" \
    -L "$test_directory/native" -l pitchee_core \
    -F "$framework_directory" -framework onnxruntime \
    -framework CoreML -framework Accelerate -framework CoreGraphics \
    -Xlinker -lc++ \
    "$project_directory"/PitcheeApp/Interop/Core/*.swift \
    "$test_directory/hnr-bridge.o" \
    "$project_directory/PitcheeApp/Audio/LivePitchAudioCapture.swift" \
    "$project_directory/PitcheeApp/Audio/RealtimeAudioBufferRing.swift" \
    "$project_directory/PitcheeApp/Analysis/PitchTimeline.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorTimeline.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorSpectrumAnalyzer.swift" \
    "$project_directory/PitcheeApp/Monitoring/MonitorAudioCapture.swift" \
    "$project_directory/Tests/Recording/LivePitchTests.swift" \
    "$test_directory/realtime-atomics.o" \
    -o "$test_directory/live-f0-tests"

"$test_directory/live-f0-tests" "$core_directory/models"
