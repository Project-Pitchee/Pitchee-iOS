#!/usr/bin/env python3
"""Rebuild Articles in a temporary tree and report counts/schema, preserving checkout."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RESOURCE = "Resources/VoiceTrainingLibrary"


def stats(library, matrix):
    return {"articleEntries": len(library["articles"]),
            "distinctArticles": len({item["id"] for item in library["articles"]}),
            "languages": sorted({item["language"] for item in library["articles"]}),
            "schemaVersion": library["schemaVersion"],
            "matrixEntries": len(matrix),
            "matrixArticleLinks": sum(len(value) for value in matrix.values())}


def main(args):
    args.output.mkdir(parents=True, exist_ok=True)
    report = ["## Articles checkpoint differences", "", f"`{args.old}` → `{args.new}`", ""]
    code = 2
    try:
        source = ROOT / "Docs/Voice-Training-Library"
        if not source.is_dir() or not any(source.rglob("*.md")):
            raise ValueError("Articles source checkout is missing; bundled-resource-only checks are insufficient")
        actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
        if actual != args.new:
            raise ValueError("Articles checkout does not match the candidate gitlink")
        before = {}
        for name in ("voice-training-library.json", "voice-rule-matching-matrix.json"):
            before[name] = json.loads(subprocess.check_output(["git", "show", f"{args.base}:{RESOURCE}/{name}"], cwd=ROOT))
        with tempfile.TemporaryDirectory(prefix="pitchee-articles-regression-") as tmp:
            temp = Path(tmp)
            (temp / "Scripts").mkdir()
            shutil.copy2(ROOT / "Scripts/build-voice-training-library.py", temp / "Scripts/build-voice-training-library.py")
            shutil.copytree(ROOT / RESOURCE, temp / RESOURCE)
            command = [sys.executable, str(temp / "Scripts/build-voice-training-library.py")]
            env = {**os.environ, "ARTICLES_DIR": str(source)}
            with (args.output / "generator.log").open("wb") as log:
                subprocess.run(command, env=env, stdout=log, stderr=log, check=True, timeout=180)
                subprocess.run([*command, "--check"], env=env, stdout=log, stderr=log, check=True, timeout=180)
            after = {name: json.loads((temp / RESOURCE / name).read_text()) for name in before}
            stale = [name for name, value in after.items() if value != json.loads((ROOT / RESOURCE / name).read_text())]
            for name in after:
                shutil.copy2(temp / RESOURCE / name, args.output / name)
        counts = {"old": stats(*before.values()), "new": stats(*after.values())}
        (args.output / "counts.json").write_text(json.dumps(counts, ensure_ascii=False, indent=2) + "\n")
        report += ["Full rebuild and generator --check completed.", "", "| Metric | Baseline bundle | Candidate rebuild |",
                   "| --- | --- | --- |"]
        for field in counts["old"]:
            report.append(f"| {field} | {json.dumps(counts['old'][field], ensure_ascii=False)} | {json.dumps(counts['new'][field], ensure_ascii=False)} |")
        if stale:
            report += ["", "**Execution failure:** committed candidate JSON differs from the rebuild: " + ", ".join(stale)]
            code = 2
        else:
            code = 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report += ["", f"**Execution failure:** {error}", "The article regression did not complete."]
        print(f"::error::{error}", file=sys.stderr)
    (args.output / "report.md").write_text("\n".join(report) + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
            summary.write((args.output / "report.md").read_text())
    return code


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("old", "new", "base"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--output", type=Path, required=True)
    sys.exit(main(parser.parse_args()))
