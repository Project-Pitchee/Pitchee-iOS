#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
onnxruntime_version="1.24.2"
destination="$project_directory/Dependencies/Artifacts/ONNXRuntime"

echo "Updating PitcheeCore submodule..."
git -C "$project_directory" submodule update --init --recursive --depth 1
if [ ! -f "$project_directory/Dependencies/PitcheeCore/models/ECAPA.onnx" ] \
    && [ "$(git -C "$project_directory/Dependencies/PitcheeCore" config --bool core.sparseCheckout || true)" = "true" ]; then
    git -C "$project_directory/Dependencies/PitcheeCore" sparse-checkout disable
fi

if [ -d "$destination/onnxruntime.xcframework" ] \
    && [ -f "$destination/Headers/onnxruntime_cxx_api.h" ]; then
    echo "ONNX Runtime $onnxruntime_version is already available."
    exit 0
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-native.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

archive="$temporary_directory/onnxruntime-ios.zip"
download_url="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-$onnxruntime_version.zip"

echo "Downloading ONNX Runtime $onnxruntime_version..."
curl --fail --location --retry 3 --output "$archive" "$download_url"

echo "Installing native artifacts..."
ditto -x -k "$archive" "$temporary_directory/extracted"
mkdir -p "$destination"
ditto "$temporary_directory/extracted/Headers" "$destination/Headers"
ditto \
    "$temporary_directory/extracted/onnxruntime.xcframework" \
    "$destination/onnxruntime.xcframework"
cp "$temporary_directory/extracted/LICENSE" "$destination/LICENSE"

echo "ONNX Runtime is ready at $destination."
