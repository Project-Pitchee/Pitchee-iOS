#!/usr/bin/env python3
"""Version disagreement is a warning: Xcode Cloud applies the version tag."""
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from version_config import CONFIG_PATH, read_settings, validate_project, version_from_tag

ROOT = Path(__file__).resolve().parents[2]


def compare(tag, version_source):
    if version_from_tag(tag) is None:
        raise ValueError("Release requires a vX.Y.Z tag")
    versions = [read_settings(version_source)["MARKETING_VERSION"]]
    return versions, versions != [tag[1:]]


if __name__ == "__main__":
    tag = os.environ["RELEASE_TAG"]
    validate_project(ROOT)
    versions, different = compare(tag, (ROOT / CONFIG_PATH).read_text())
    report = f"Tag `{tag}`; project MARKETING_VERSION: `{', '.join(versions)}`.\n"
    if different:
        report += "**Warning:** Xcode Cloud will synchronize the marketing version from this tag before archiving.\n"
        print("::warning::Tag and project marketing versions differ; the Cloud pre-build hook applies the tag.")
    print(report)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
            out.write(report)
