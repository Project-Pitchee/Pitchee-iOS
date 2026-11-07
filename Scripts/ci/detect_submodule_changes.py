#!/usr/bin/env python3
"""Resolve PR gitlinks at the merge base, rather than a moving target branch."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

PATHS = {"core": "Dependencies/PitcheeCore", "articles": "Docs/Voice-Training-Library"}


def git(*args, cwd=None):
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()


def gitlink(ref, path, cwd=None):
    value = git("ls-tree", ref, "--", path, cwd=cwd)
    pieces = value.split()
    if len(pieces) != 4 or pieces[0:2] != ["160000", "commit"] or pieces[3] != path:
        raise ValueError(f"Required gitlink {path} is missing or has changed type at {ref}")
    if not re.fullmatch(r"[0-9a-f]{40}", pieces[2]):
        raise ValueError("Invalid gitlink object ID")
    return pieces[2]


def detect(base, head, cwd=None):
    for value in (base, head):
        if not re.fullmatch(r"[0-9a-f]{40}", value):
            raise ValueError("Expected complete base and head commit SHA")
    merge_base = git("merge-base", base, head, cwd=cwd)
    result = {"base": merge_base, "head": head}
    for name, path in PATHS.items():
        old, new = gitlink(merge_base, path, cwd), gitlink(head, path, cwd)
        result.update({f"{name}_old": old, f"{name}_new": new,
                       f"{name}_changed": "true" if old != new else "false"})
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    args = parser.parse_args()
    result = detect(args.base, args.head)
    print(json.dumps(result, indent=2))
    if os.environ.get("GITHUB_OUTPUT"):
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as stream:
            stream.writelines(f"{key}={value}\n" for key, value in result.items())
