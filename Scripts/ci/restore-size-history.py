#!/usr/bin/env python3
"""Restore history only from completed successful main push/manual regressions."""

import argparse
import io
import json
import os
from pathlib import Path
import subprocess
import zipfile


def api(route, binary=False):
    result = subprocess.run(["gh", "api", route], check=True, capture_output=True, timeout=60)
    return result.stdout if binary else json.loads(result.stdout)


def selected_history(zip_bytes):
    if len(zip_bytes) > 1024 * 1024:
        raise ValueError("History artifact exceeds 1 MiB")
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
        entries = archive.infolist()
        if len(entries) != 1 or entries[0].filename != "size-history.csv":
            raise ValueError("History artifact must contain only size-history.csv")
        if entries[0].file_size > 1024 * 1024:
            raise ValueError("Expanded size history exceeds 1 MiB")
        return archive.read(entries[0])


def tracks_main_history(event, ref):
    return ref == "refs/heads/main" and event in {"push", "workflow_dispatch"}


def eligible_run(run, current_run_id):
    return (
        str(run["id"]) != str(current_run_id)
        and run.get("head_branch") == "main"
        and run.get("event") in {"push", "workflow_dispatch"}
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
    )


def restore(repository, run_id, output):
    prefix = f"repos/{repository}/actions"
    # A failed or branch workflow must not seed main's trend. Paginate rather
    # than assuming the previous run or the first artifact happens to match.
    for page in range(1, 11):
        runs = api(f"{prefix}/workflows/regression.yml/runs?branch=main&status=success&per_page=100&page={page}")["workflow_runs"]
        for run in runs:
            if not eligible_run(run, run_id):
                continue
            artifacts = api(f"{prefix}/runs/{run['id']}/artifacts?per_page=100")["artifacts"]
            for artifact in artifacts:
                if artifact["name"] == "regression-size-history" and not artifact["expired"]:
                    content = selected_history(api(f"{prefix}/artifacts/{artifact['id']}/zip", binary=True))
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(content)
                    print(f"Restored size history from successful main run {run['id']}.")
                    return
        if len(runs) < 100:
            break
    print("No previous successful main size-history artifact exists; starting a new trend.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if tracks_main_history(os.environ.get("GITHUB_EVENT_NAME"), os.environ.get("GITHUB_REF")):
        restore(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_RUN_ID"], args.output)
    else:
        print("Size history is maintained only by main push/manual runs; no history was read.")
