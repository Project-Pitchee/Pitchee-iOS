#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
core_directory=${PITCHEE_CORE_SOURCE_DIRECTORY:-"$project_directory/Dependencies/PitcheeCore"}
runtime_directory="$project_directory/Dependencies/Artifacts/ONNXRuntime"
framework_directory="$runtime_directory/onnxruntime.xcframework/macos-arm64_x86_64"

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [speech-recording.wav]" >&2
    exit 1
fi
if [ ! -f "$core_directory/CMakeLists.txt" ] || [ ! -d "$core_directory/models" ]; then
    echo "PITCHEE_CORE_SOURCE_DIRECTORY must contain the Core source and models." >&2
    exit 1
fi
echo "HNR integration Core source, C module and models: $core_directory"
if [ ! -f "$framework_directory/onnxruntime.framework/onnxruntime" ]; then
    echo "Install ONNX Runtime with Scripts/bootstrap-native-dependencies.sh first." >&2
    exit 1
fi

test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-hnr-integration.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

if [ "$#" -eq 1 ]; then
    speech_source=$1
    echo "HNR integration input: supplied audio file (no microphone capture)."
else
    speech_source="$test_directory/speech.aiff"
    echo "HNR integration input: speech synthesized by macOS say (no microphone capture)."
    say -v Samantha -r 175 -o "$speech_source" \
        "The morning light falls across the quiet garden. My voice stays clear and steady while I speak."
fi
afconvert -f WAVE -d LEI16@16000 -c 1 "$speech_source" "$test_directory/speech.wav"

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

xcrun swiftc -parse-as-library -O -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    -I "$core_directory/platform/ios" \
    -I "$project_directory/PitcheeApp/Interop/Core/HNRBridge" \
    -module-cache-path "$test_directory/module-cache" \
    -enable-upcoming-feature MemberImportVisibility \
    -I "$core_directory/include" \
    -L "$test_directory/native" -l pitchee_core \
    -F "$framework_directory" -framework onnxruntime \
    -framework CoreML -framework Accelerate -framework CoreGraphics \
    -Xlinker -lc++ -Xlinker -rpath -Xlinker "$framework_directory" \
    "$project_directory"/PitcheeApp/Interop/Core/*.swift \
    "$test_directory/hnr-bridge.o" \
    "$project_directory/Tests/Recording/HNRIntegrationTests.swift" \
    -o "$test_directory/hnr-integration-tests"

"$test_directory/hnr-integration-tests" \
    "$core_directory/models" \
    "$test_directory/speech.wav" "$test_directory"
