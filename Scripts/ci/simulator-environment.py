#!/usr/bin/env python3
"""Explicitly report GitHub runner SDK gaps; never hide a missing shared scheme."""

import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / ".build/regression-build/environment.md"


def version(value):
    pieces = tuple(int(piece) for piece in value.split("."))
    return pieces + (0,) * max(0, 3 - len(pieces))


def report(text):
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    with REPORT.open("a") as out:
        out.write(text + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
            out.write(text + "\n")
    print(text)


def check():
    scheme = ROOT / "Pitchee.xcodeproj/xcshareddata/xcschemes/Pitchee.xcscheme"
    if not scheme.is_file():
        raise SystemExit("Missing shared Pitchee scheme; commit the shared scheme before CI can build.")
    project = (ROOT / "Pitchee.xcodeproj/project.pbxproj").read_text()
    targets = re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = "?([0-9.]+)"?;', project)
    if not targets:
        raise SystemExit("Could not determine the project's deployment target.")
    minimum = max(targets, key=version)
    result = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True, capture_output=True)
    sdk = result.stdout.strip()
    available = result.returncode == 0 and bool(re.fullmatch(r"\d+(?:\.\d+)*", sdk)) and version(sdk) >= version(minimum)
    if available:
        report(f"Simulator SDK {sdk} covers deployment target {minimum}; building arm64 + x86_64.")
    else:
        report(f"**Environment unavailable:** simulator SDK {sdk or 'missing'} cannot cover iOS {minimum}. GitHub simulator build and size measurement were not run. Xcode Cloud is authoritative.")
        print("::warning::GitHub runner simulator SDK is too old or unavailable; build was not run.")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"available={str(available).lower()}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-build")
    parser.add_argument("--available")
    args = parser.parse_args()
    if args.report_build is not None:
        if args.available != "true":
            report("Simulator build: not executed; see SDK/precondition step for the reason.")
        elif args.report_build == "success":
            report("Simulator build: arm64 + x86_64 completed without signing.")
        else:
            report(f"**Simulator build {args.report_build or 'not completed'}:** inspect xcodebuild.log. This is a best-effort report, not a PR gate.")
    else:
        check()
