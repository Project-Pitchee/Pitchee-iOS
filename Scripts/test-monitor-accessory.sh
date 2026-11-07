#!/bin/sh

set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-monitor-accessory.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    "$project_directory/PitcheeApp/Monitoring/MonitorAccessoryState.swift" \
    "$project_directory/Tests/Monitoring/MonitorAccessoryStateTests.swift" \
    -o "$test_directory/monitor-accessory-tests"

"$test_directory/monitor-accessory-tests"
