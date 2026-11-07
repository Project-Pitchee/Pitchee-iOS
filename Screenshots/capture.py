#!/usr/bin/env python3
"""Capture exactly five named XCUITest attachments on an isolated simulator."""
import argparse
from contextlib import nullcontext
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCREENS = ["01-home", "02-monitor", "03-insights", "04-articles", "05-history"]
DEVICES = {"6.9": ["iPhone 17 Pro Max", "iPhone 16 Pro Max", "iPhone 18 Pro Max"],
           "6.5": ["iPhone 11 Pro Max", "iPhone Xs Max"]}
DIMENSIONS = {"6.9": {(1320, 2868)}, "6.5": {(1242, 2688)}}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def output(*args):
    return run(*args, stdout=subprocess.PIPE).stdout


def version(text):
    return tuple(int(part) for part in re.findall(r"\d+", text))


def environment_unavailable(message, destination):
    diagnostic = f"ENVIRONMENT: {message} No screenshots produced.\n"
    print(diagnostic, file=sys.stderr)
    (destination / "environment.txt").write_text(diagnostic)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write(diagnostic)
    return 78


def export_images(attachments, destination, device):
    """Only our five named attachments count; incidental test screenshots cannot mask failure."""
    records = json.loads((attachments / "manifest.json").read_text())
    found = {}
    for test in records:
        for item in test["attachments"]:
            name = item["suggestedHumanReadableName"]
            matches = [screen for screen in SCREENS if re.match(re.escape(screen) + r"(?:[._ -]|$)", name)]
            if not matches or item.get("isAssociatedWithFailure"):
                continue
            screen = matches[0]
            source = (attachments / item["exportedFileName"]).resolve()
            if source.parent != attachments.resolve() or source.suffix.lower() != ".png":
                raise ValueError("Invalid screenshot attachment path")
            if screen in found:
                raise ValueError(f"Duplicate screenshot: {screen}")
            data = source.read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
                raise ValueError(f"Invalid PNG: {screen}")
            dimensions = struct.unpack(">II", data[16:24])
            if dimensions not in DIMENSIONS[device]:
                raise ValueError(f"Wrong dimensions for {device}-inch slot: {dimensions}")
            found[screen] = source
    if set(found) != set(SCREENS):
        raise ValueError(f"Missing named screenshots: {sorted(set(SCREENS) - set(found))}")
    destination.mkdir(parents=True, exist_ok=True)
    for name, source in found.items():
        shutil.copyfile(source, destination / f"{name}.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=DEVICES, required=True)
    parser.add_argument("--language", required=True)
    parser.add_argument("--appearance", choices=["light", "dark"], default="light")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/screenshots-output")
    parser.add_argument("--derived-data", type=Path, help="Optional local build cache; use a dedicated directory")
    args = parser.parse_args()
    if args.language not in supported_languages():
        parser.error("Language must be present in the string catalog")
    destination = args.output.resolve() / args.language / args.device / args.appearance
    destination.mkdir(parents=True, exist_ok=True)
    result = destination / "result.xcresult"
    if result.exists():
        raise ValueError(f"Output already exists; choose a fresh --output directory: {result}")
    os.chdir(ROOT)
    sdk = output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version").strip()
    if version(sdk) < (26, 5):
        return environment_unavailable(f"iOS simulator SDK {sdk} is older than 26.5.", destination)
    inventory = json.loads(output("xcrun", "simctl", "list", "--json"))
    runtimes = sorted([runtime for runtime in inventory["runtimes"]
                       if runtime.get("isAvailable") and runtime["name"].startswith("iOS ")
                       and version(runtime["version"]) >= (26, 5)],
                      key=lambda runtime: version(runtime["version"]), reverse=True)
    types = {device["name"]: device["identifier"] for device in inventory["devicetypes"]}
    simulator = None
    for runtime in runtimes:
        for name in DEVICES[args.device]:
            if name not in types:
                continue
            attempt = subprocess.run(["xcrun", "simctl", "create", "Pitchee CI screenshots", types[name],
                                      runtime["identifier"]], text=True, capture_output=True)
            if attempt.returncode == 0:
                simulator = attempt.stdout.strip()
                break
        if simulator:
            break
    if not simulator:
        return environment_unavailable(f"No compatible {args.device}-inch simulator and iOS >=26.5 runtime.", destination)
    try:
        run("xcrun", "simctl", "boot", simulator)
        run("xcrun", "simctl", "bootstatus", simulator, "-b")
        run("xcrun", "simctl", "ui", simulator, "appearance", args.appearance)
        run("xcrun", "simctl", "status_bar", simulator, "override", "--time", "9:41", "--dataNetwork", "wifi",
            "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
        build_directory = (nullcontext(str(args.derived_data.resolve())) if args.derived_data
                           else tempfile.TemporaryDirectory(prefix="pitchee-screenshot-build-"))
        with build_directory as derived:
            with (destination / "xcodebuild.log").open("w") as log:
                run("xcodebuild", "test", "-project", "Pitchee.xcodeproj", "-scheme", "Pitchee",
                    "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={simulator}",
                    "-derivedDataPath", derived, "-resultBundlePath", str(result),
                    "-only-testing:PitcheeUITests/PitcheeScreenshots", "-parallel-testing-enabled", "NO",
                    "-testLanguage", args.language, "-testRegion", "CN" if args.language == "zh-Hans" else "US",
                    "CODE_SIGNING_ALLOWED=NO", stdout=log, stderr=subprocess.STDOUT)
        with tempfile.TemporaryDirectory(prefix="pitchee-screenshot-attachments-") as temp:
            attachments = Path(temp)
            run("xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                "--output-path", str(attachments))
            export_images(attachments, destination, args.device)
        print(f"Exported five {args.device}-inch / {args.language} / {args.appearance} screenshots to {destination}")
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", simulator], capture_output=True)
    return 0


def supported_languages():
    catalog = json.loads((ROOT / "Resources/Localizable.xcstrings").read_text())
    return sorted({catalog["sourceLanguage"]} | {language for value in catalog["strings"].values()
                                               for language in value.get("localizations", {})})


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Screenshot capture failed: {error}", file=sys.stderr)
        sys.exit(1)
