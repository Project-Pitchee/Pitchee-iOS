#!/usr/bin/env python3
"""Measure uncompressed simulator .app contents and maintain a 14-run CSV."""

import argparse
import csv
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import subprocess

FIELDS = ["timestamp", "commit", "run_id", "sdk", "xcode", "total_bytes", "executable_bytes", "resources_bytes"]
SCOPE = "Simulator build; uncompressed directory bytes before App Thinning. Use only for trends, never as a download/App Store size claim. Resources include all bundled files other than the main executable (including embedded libraries)."


def measure(app):
    if not app.is_dir():
        raise ValueError(f"App bundle is missing: {app}")
    with (app / "Info.plist").open("rb") as source:
        executable_name = plistlib.load(source)["CFBundleExecutable"]
    if not isinstance(executable_name, str) or Path(executable_name).name != executable_name:
        raise ValueError("CFBundleExecutable must name a file at the bundle root")
    executable = app / executable_name
    if not executable.is_file() or executable.is_symlink():
        raise ValueError("Main executable is missing or is a symlink")
    # Do not follow symlinks outside the app or count their targets twice.
    total = sum(p.lstat().st_size for p in app.rglob("*") if p.is_symlink() or p.is_file())
    main = executable.stat().st_size
    return total, main, total - main


def history_rows(path):
    if not path.exists():
        return []
    with path.open(newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != FIELDS:
            raise ValueError("Size history has an unexpected schema")
        rows = list(reader)
    for row in rows:
        for key in FIELDS[-3:]:
            if int(row[key]) < 0:
                raise ValueError("Size history contains negative bytes")
        if int(row["total_bytes"]) != int(row["executable_bytes"]) + int(row["resources_bytes"]):
            raise ValueError("Size history components do not sum to total")
    return rows[-14:]


def command_value(command):
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=15)
        return result.stdout.strip().replace("\n", " ") if result.returncode == 0 else "unknown"
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def append_measurement(history, row):
    # A retry replaces its own row, avoiding fabricated growth between attempts.
    rows = [old for old in history if not row["run_id"] or old["run_id"] != row["run_id"]]
    previous = rows[-1] if rows else None
    return (rows + [row])[-14:], previous


def render(rows, previous, threshold):
    latest = rows[-1]
    delta = int(latest["total_bytes"]) - int(previous["total_bytes"]) if previous else None
    report = []
    if delta is not None and delta > threshold * 1024 * 1024:
        report += [f"**Size warning: +{delta / 1024 / 1024:.2f} MiB since the previous measurement** (threshold {threshold:g} MiB).", ""]
    report += ["## Simulator app size trend", "", SCOPE, "", "| UTC | Commit | Total MiB | Main MiB | Resources MiB | SDK |", "|---|---|---:|---:|---:|---|"]
    for row in rows:
        report.append(f"| {row['timestamp']} | {row['commit'][:12]} | {int(row['total_bytes']) / 1048576:.2f} | {int(row['executable_bytes']) / 1048576:.2f} | {int(row['resources_bytes']) / 1048576:.2f} | {row['sdk']} |")
    if previous and (latest["sdk"], latest["xcode"]) != (previous["sdk"], previous["xcode"]):
        report += ["", "Toolchain changed since the previous sample; investigate that change before attributing size growth to code."]
    report += ["", f"Latest toolchain: {latest['xcode']}; architecture arm64 + x86_64; Release configuration."]
    return "\n".join(report) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--history", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--threshold-mb", type=float, default=2)
    args = parser.parse_args()
    total, executable, resources = measure(args.app)
    row = dict(zip(FIELDS, [
        datetime.now(timezone.utc).isoformat(timespec="seconds"), os.getenv("GITHUB_SHA", "local"),
        os.getenv("GITHUB_RUN_ID", ""), command_value(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
        command_value(["xcodebuild", "-version"]), str(total), str(executable), str(resources),
    ]))
    rows, previous = append_measurement(history_rows(args.history), row)
    args.history.parent.mkdir(parents=True, exist_ok=True)
    with args.history.open("w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    text = render(rows, previous, args.threshold_mb)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text)
    # Put the growth warning at the top of the job summary, not below build logs.
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        summary = Path(os.environ["GITHUB_STEP_SUMMARY"])
        existing = summary.read_text() if summary.exists() else ""
        summary.write_text(text + "\n" + existing)
    print(text)


if __name__ == "__main__":
    main()
