#!/usr/bin/env python3
"""Run every shell regression independently; report failures without gating PRs."""

import argparse
import html
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
# Intentionally narrow. An arbitrary missing source/header is a code regression,
# not an environment excuse. Scripts may explicitly return EX_CONFIG (78).
ENVIRONMENT_PATTERNS = (
    r"xcrun: error: (invalid active developer path|unable to find utility)",
    r"xcode-select: error:",
    r"(?:xcrun|swiftc|python3|clang\+\+|cmake|say|afconvert): command not found",
    r"SDK .* cannot be located",
    r"unable to find a destination matching",
    r"No available iOS simulator",
    r"Pass the UDID of one booted iOS simulator",
    r"Install ONNX Runtime with Scripts/bootstrap-native-dependencies.sh first",
    r"Voice .?Samantha.? (?:was )?not found",
    r"invalid value '[^']+' in '-swift-version",
    r"unknown argument: '-(?:default-isolation|strict-concurrency)",
    r"CI_ENVIRONMENT_FAILURE:",
)


def classify(returncode, output, timed_out=False):
    if timed_out:
        return "TIMEOUT — review required"
    if returncode == 0:
        return "PASS"
    if returncode == 78 or any(re.search(p, output, re.I) for p in ENVIRONMENT_PATTERNS):
        return "FAIL — environment"
    return "FAIL — code regression candidate"


def run_script(script, root, log, timeout, env):
    started = time.monotonic()
    timed_out = False
    with log.open("wb") as output:
        command = ["bash", str(script)]
        if script.name == "test-pdf-export.sh" and env.get("REGRESSION_SIMULATOR_UDID"):
            command.append(env["REGRESSION_SIMULATOR_UDID"])
        process = subprocess.Popen(
            command, cwd=root, env=env,
            stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Kill the whole process group: shell children include swiftc/simctl.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            finally:
                # The parent shell may have exited while a child ignored TERM.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            code = 124
    text = log.read_text(errors="replace")
    return {
        "script": str(script.relative_to(root)), "exit_code": code,
        "seconds": round(time.monotonic() - started, 1),
        "result": classify(code, text, timed_out), "log": log.name,
        "tail": "\n".join(text.splitlines()[-35:]),
    }


def run_suite(root, output, timeout):
    scripts = sorted((root / "Scripts").glob("test-*.sh"))
    if not scripts:
        raise RuntimeError("No Scripts/test-*.sh found; regression cannot report success.")
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    include = str(root / "Dependencies/PitcheeCore/include")
    env["CPATH"] = include + (":" + env["CPATH"] if env.get("CPATH") else "")
    results = []
    for script in scripts:
        result = run_script(script, root, output / (script.name + ".log"), timeout, env)
        results.append(result)
        print(f"{result['script']}: {result['result']} ({result['seconds']}s)", flush=True)
    failures = [item for item in results if item["result"] != "PASS"]
    report = ["## Script regression results", ""]
    if failures:
        report += [f"**{len(failures)} of {len(results)} scripts need attention.**", ""]
        print(f"::warning::{len(failures)} regression scripts need review; see the per-script report.")
    report += [
        "Environment failures use explicit exit 78 / CI_ENVIRONMENT_FAILURE or narrow known toolchain signatures.",
        "Other failures are code regression candidates; timeouts require inspection. Xcode Cloud remains the authoritative build.",
        "CPATH includes the locked Core's include directory. Every script has an independent process group and timeout.",
        "", "| Script | Result | Seconds | Exit |", "|---|---|---:|---:|",
    ]
    for item in results:
        report.append(f"| `{item['script']}` | {item['result']} | {item['seconds']} | {item['exit_code']} |")
    for item in failures:
        report += ["", f"### {item['script']}", "", "<pre>" + html.escape(item["tail"]) + "</pre>"]
    text = "\n".join(report) + "\n"
    (output / "report.md").write_text(text)
    (output / "results.json").write_text(json.dumps(results, indent=2))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write(text)
    return results


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/regression")
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("timeout must be positive")
    run_suite(ROOT, args.output.resolve(), args.timeout)
