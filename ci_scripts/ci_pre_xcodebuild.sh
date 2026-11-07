#!/bin/sh
set -eu
: "${CI_BUILD_NUMBER:?Xcode Cloud build number is missing}"
case "$CI_BUILD_NUMBER" in
  *[!0-9]*|0*) echo "error: CI_BUILD_NUMBER must be a positive integer" >&2; exit 1 ;;
esac
if [ "${CI_XCODEBUILD_ACTION:-}" = test-without-building ]; then
    echo "Reusing built test products; version verification runs after testing."
    exit 0
fi
cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is missing}"
python3 Scripts/ci/cloud-version.py
