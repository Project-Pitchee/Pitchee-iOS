#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-dashboard.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    "$project_directory/PitcheeApp/App/DashboardSizing.swift" \
    "$project_directory/PitcheeApp/App/DashboardConfiguration.swift" \
    "$project_directory/Tests/Insights/DashboardSizingTests.swift" \
    -o "$test_directory/dashboard-tests"
"$test_directory/dashboard-tests"
xcrun swiftc -parse-as-library -swift-version 6 -strict-concurrency=complete \
    "$project_directory/PitcheeApp/App/DashboardFlipGeometry.swift" \
    "$project_directory/Tests/Insights/DashboardFlipTests.swift" \
    -o "$test_directory/dashboard-flip-tests"
"$test_directory/dashboard-flip-tests"
