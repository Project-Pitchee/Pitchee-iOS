#!/usr/bin/env python3
"""Create/clean only a dedicated CI simulator for shell scripts needing one."""

import argparse
import json
import os
import re
import subprocess


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()


def select_device(data):
    choices = []
    for runtime, devices in data["devices"].items():
        match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", runtime)
        if not match:
            continue
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device.get("deviceTypeIdentifier", ""):
                choices.append((tuple(int(i) for i in match[1].split("-")), runtime, device["deviceTypeIdentifier"]))
    if not choices:
        raise RuntimeError("CI_ENVIRONMENT_FAILURE: No available iOS simulator runtime/device pair")
    _, runtime, device_type = max(choices)
    return runtime, device_type


def verify_boot_result(result):
    output = result.stdout + result.stderr
    if result.returncode != 0 or 'Data Migration Failed' in output:
        raise RuntimeError("CI_ENVIRONMENT_FAILURE: Temporary simulator did not finish booting; inspect bootstatus output")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["create", "cleanup"])
    args = parser.parse_args()
    if args.action == "cleanup":
        identifier = os.environ.get("REGRESSION_SIMULATOR_UDID")
        if identifier:
            subprocess.run(["xcrun", "simctl", "shutdown", identifier], check=False)
            subprocess.run(["xcrun", "simctl", "delete", identifier], check=True)
        return
    if not os.environ.get("GITHUB_ENV"):
        raise RuntimeError("This helper creates simulators only in CI; local runs can supply REGRESSION_SIMULATOR_UDID.")
    runtime, device_type = select_device(json.loads(simctl("list", "devices", "available", "--json")))
    identifier = simctl("create", "Pitchee regression " + os.environ.get("GITHUB_RUN_ID", "test"), device_type, runtime)
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", identifier):
        raise RuntimeError("Unexpected simulator identifier")
    # Export before booting so always() cleanup can delete a partially booted device.
    with open(os.environ["GITHUB_ENV"], "a") as out:
        out.write(f"REGRESSION_SIMULATOR_UDID={identifier}\n")
    simctl("boot", identifier)
    result = subprocess.run(["xcrun", "simctl", "bootstatus", identifier, "-b"], text=True, capture_output=True, timeout=180)
    print(result.stdout + result.stderr)
    verify_boot_result(result)
    print(f"Dedicated regression simulator is ready: {identifier}")


if __name__ == "__main__":
    main()
