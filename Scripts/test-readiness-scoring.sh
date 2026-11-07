#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-readiness-scoring.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -default-isolation MainActor \
    "$project_directory/PitcheeApp/Analysis/ReadinessScoring.swift" \
    "$project_directory/Tests/Readiness/ReadinessScoringTests.swift" \
    -o "$test_directory/readiness-scoring-tests"

"$test_directory/readiness-scoring-tests"
