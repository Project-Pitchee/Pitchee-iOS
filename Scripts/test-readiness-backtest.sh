#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-readiness-backtest.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

# Standalone pure Swift: no Core, UI, database, native dependencies or Xcode project edits.
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -default-isolation MainActor -warnings-as-errors \
    "$project_directory/PitcheeApp/Analysis/ReadinessScoring.swift" \
    "$project_directory/Tests/Readiness/ReadinessBacktest.swift" \
    -o "$test_directory/readiness-backtest"

# Optional: --report /absolute/path/report.md. Default runs do not rewrite the report.
"$test_directory/readiness-backtest" "$@"
