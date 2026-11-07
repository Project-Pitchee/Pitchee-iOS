#!/bin/sh
# Cloud distribution post-actions follow this hook. A version mismatch is fatal.
# Test-without-building may have no checkout, so all verifier resources travel
# under ci_scripts; never require the repository or a prior hook's temp files.
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${CI_XCODEBUILD_EXIT_CODE:?Xcode Cloud build exit code is missing}"
: "${CI_XCODEBUILD_ACTION:?Xcode Cloud action is missing}"
printf 'workflow: %s\nbuild: %s\naction: %s\nxcodebuild exit: %s\n' \
    "${CI_WORKFLOW:-unknown}" "${CI_BUILD_NUMBER:-unknown}" \
    "${CI_XCODEBUILD_ACTION:-unknown}" "${CI_XCODEBUILD_EXIT_CODE:-unknown}"
python3 "$script_directory/verify-built-version.py"
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] && [ -d "$CI_PRIMARY_REPOSITORY_PATH/.git" ]; then
    git -C "$CI_PRIMARY_REPOSITORY_PATH" rev-parse HEAD
    git -C "$CI_PRIMARY_REPOSITORY_PATH" submodule status --recursive
fi
# Keep provenance in Cloud's retained log. Custom files are not automatically
# retained as Cloud downloadable artifacts. Notes run independently after upload.
