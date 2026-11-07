#!/bin/sh
set -eu

# Usage: Scripts/test-pdf-export.sh [booted-ios-simulator-udid]
# Installs only a uniquely identified test app, then removes it. Report artifacts
# are copied out before cleanup; no Pitchee data or simulator settings are changed.
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-pdf-export.XXXXXX")
simulator_id=${1:-}
bundle_id="com.lvyzhan.Pitchee.PDFMakerTests.run$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')"
installed=false

cleanup() {
    if [ "$installed" = true ]; then
        xcrun simctl terminate "$simulator_id" "$bundle_id" >/dev/null 2>&1 || true
        xcrun simctl uninstall "$simulator_id" "$bundle_id" >/dev/null 2>&1 || true
    fi
    rm -rf "$test_directory"
}
trap cleanup EXIT HUP INT TERM

xcrun simctl list devices available -j > "$test_directory/devices.json"
simulator_id=$(python3 - "$test_directory/devices.json" "$simulator_id" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    devices = [device for runtime, group in json.load(source)["devices"].items()
               if ".iOS-" in runtime for device in group
               if device.get("isAvailable") and device["state"] == "Booted"]
requested = sys.argv[2]
matches = [device for device in devices if not requested or device["udid"] == requested]
if len(matches) != 1:
    sys.exit("Pass the UDID of one booted iOS simulator; the default requires exactly one booted iOS device.")
print(matches[0]["udid"])
PY
)

app_directory="$test_directory/PDFMakerTests.app"
mkdir -p "$app_directory"
python3 - "$app_directory/Info.plist" "$bundle_id" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as output:
    plistlib.dump({
        "CFBundleIdentifier": sys.argv[2],
        "CFBundleName": "PDFMakerTests",
        "CFBundleExecutable": "PDFMakerTests",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "MinimumOSVersion": "17.0",
        "LSRequiresIPhoneOS": True,
        "UIDeviceFamily": [1, 2],
        "UILaunchScreen": {},
        "UIApplicationSceneManifest": {
            "UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {
                "UIWindowSceneSessionRoleApplication": [{
                    "UISceneConfigurationName": "PDF export tests",
                    "UISceneDelegateClassName": "PDFMakerTestSceneDelegate",
                }],
            },
        },
    }, output)
PY

xcrun --sdk iphonesimulator swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -strict-concurrency=complete -warnings-as-errors \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -target "$(uname -m)-apple-ios17.0-simulator" \
    "$project_directory/PitcheeApp/Analysis/PDFMaker.swift" \
    "$project_directory/Tests/Export/PDFMakerTests.swift" \
    -o "$app_directory/PDFMakerTests"
codesign --force --sign - "$app_directory" >/dev/null 2>&1
xcrun simctl install "$simulator_id" "$app_directory"
installed=true
container_directory=$(xcrun simctl get_app_container "$simulator_id" "$bundle_id" data)
xcrun simctl launch "$simulator_id" "$bundle_id"

attempt=0
while [ ! -f "$container_directory/Documents/results.json" ]; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 60 ]; then
        printf '%s\n' 'PDF test app did not produce results within 60 seconds.' >&2
        exit 1
    fi
    sleep 1
done

output_directory=$(mktemp -d "${TMPDIR:-/tmp}/pitchee-pdf-export-results.XXXXXX")
cp -R "$container_directory/Documents/." "$output_directory/"
printf 'PDF test artifacts: %s\n' "$output_directory"
python3 - "$output_directory/results.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    report = json.load(source)
print(f"PDF export checks: {report['checks']}; failures: {len(report['failures'])}")
for failure in report["failures"]:
    print(f"- {failure}")
sys.exit(0 if report["passed"] else 1)
PY
