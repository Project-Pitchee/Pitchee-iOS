#!/usr/bin/env python3
"""Build two locked Core commits; report exact full/HNR/readiness differences.

Exit 0: every comparison ran and no fields differ; 1: exact differences exist;
2: execution/fixture coverage failure. No tolerance or acceptance policy exists.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import struct
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MISSING = object()
WAV_NAME = r"[A-Za-z0-9][A-Za-z0-9 _-]*\.wav"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_wav(path):
    """Validate RIFF metadata without decoding/converting the private audio."""
    with path.open("rb") as stream:
        header = stream.read(12)
        if len(header) != 12 or header[:4] != b"RIFF" or header[8:] != b"WAVE":
            raise ValueError(f"Expected RIFF WAV: {path.name}")
        fmt = None
        data_bytes = 0
        while chunk := stream.read(8):
            if len(chunk) != 8:
                raise ValueError("Truncated WAV chunk")
            kind, size = struct.unpack("<4sI", chunk)
            if stream.tell() + size > path.stat().st_size:
                raise ValueError("Truncated WAV data")
            if kind == b"fmt ":
                raw = stream.read(min(size, 16))
                if len(raw) != 16:
                    raise ValueError("Truncated WAV format")
                fmt = struct.unpack("<HHIIHH", raw)
                stream.seek(size - 16, 1)
            else:
                if kind == b"data":
                    data_bytes += size
                stream.seek(size, 1)
            stream.seek(size % 2, 1)
        if fmt is None or (fmt[0], fmt[5]) not in ((1, 16), (3, 32)) or fmt[1] != 1 or fmt[2] != 16000:
            raise ValueError(f"Expected mono 16 kHz PCM16 or IEEE Float32 WAV: {path.name}")
        if fmt[4] != fmt[1] * fmt[5] // 8 or fmt[3] != fmt[2] * fmt[4]:
            raise ValueError(f"Inconsistent WAV byte rate/block alignment: {path.name}")
        if data_bytes == 0 or data_bytes % fmt[4]:
            raise ValueError(f"Empty or incomplete WAV samples: {path.name}")


def validate_fixtures(directory, manifest_path=None):
    if directory is None:
        raise ValueError("Private Core fixtures are not configured; pass --fixtures or provision PITCHEE_CORE_FIXTURES_URL. No audio belongs in Git or artifacts.")
    manifest_path = manifest_path or directory / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"Missing Core regression fixture manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text())
    samples = manifest.get("samples", [])
    if manifest.get("schemaVersion") != 1 or not samples:
        raise ValueError("Core regression fixtures must have a nonempty schema-1 manifest")
    if len(samples) > 20:
        raise ValueError("Core regression fixture limit is 20 files")
    names = [item["file"] for item in samples]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate fixture filename")
    if set(names) != {path.name for path in directory.glob("*.wav")}:
        raise ValueError("Fixture WAV files and manifest differ")
    total = 0
    for item in samples:
        name = item["file"]
        if not re.fullmatch(WAV_NAME, name):
            raise ValueError(f"Unsafe fixture name: {name!r}")
        path = directory / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing regular WAV fixture: {name}")
        if digest(path) != item["sha256"] or path.stat().st_size != item["bytes"]:
            raise ValueError(f"Fixture SHA-256/size mismatch: {name}")
        validate_wav(path)
        total += path.stat().st_size
    if total > 10 * 1024 * 1024:
        raise ValueError("Core regression fixture limit is 10 MiB")
    return manifest


def differences(old, new, path="$"):
    """Preserve every changed leaf including missing fields, null and types."""
    if isinstance(old, dict) and isinstance(new, dict):
        result = []
        for key in sorted(old.keys() | new.keys()):
            result.extend(differences(old.get(key, MISSING), new.get(key, MISSING), f"{path}.{key}"))
        return result
    if isinstance(old, list) and isinstance(new, list):
        result = []
        for index in range(max(len(old), len(new))):
            result.extend(differences(old[index] if index < len(old) else MISSING,
                                      new[index] if index < len(new) else MISSING, f"{path}[{index}]"))
        return result
    if old is not MISSING and new is not MISSING and type(old) is type(new) and old == new:
        return []
    numeric = lambda value: type(value) in (int, float) and math.isfinite(value)
    return [{"field": path, "old": old if old is not MISSING else {"missing": True},
             "new": new if new is not MISSING else {"missing": True},
             "delta": new - old if numeric(old) and numeric(new) else None}]


def run(command, log, *, timeout=600, env=None):
    with log.open("ab") as output:
        output.write(("$ " + " ".join(map(str, command)) + "\n").encode())
        subprocess.run(list(map(str, command)), check=True, stdout=output, stderr=output,
                       timeout=timeout, env=env)


def snapshot(core, sha, destination, log):
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("Core checkpoints must be complete SHA-1 object IDs")
    if subprocess.run(["git", "-C", str(core), "cat-file", "-e", f"{sha}^{{commit}}"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        run(["git", "-C", core, "fetch", "--no-tags", "https://github.com/project-pitchee/Core.git", sha], log)
    destination.mkdir()
    archive = destination.parent / f"{destination.name}.tar"
    # Include historical external/hnr as well as current src/hnr, and each
    # checkpoint's own ONNX models. No mutable working-tree files enter a build.
    tracked = subprocess.check_output(["git", "-C", str(core), "ls-tree", "-r", "--name-only", sha], text=True).splitlines()
    selected = [p for p in tracked if p == "CMakeLists.txt" or p == "LICENSE"
                or p.startswith(("include/", "src/", "cmake/", "external/"))
                or p == "models/manifest.json" or p.startswith("models/") and p.endswith(".onnx")]
    with archive.open("wb") as output:
        subprocess.run(["git", "-C", str(core), "archive", sha, "--", *selected], stdout=output, check=True, timeout=180)
    with tarfile.open(archive) as source:
        for entry in source.getmembers():
            target = (destination / entry.name).resolve()
            if not target.is_relative_to(destination.resolve()) or entry.issym() or entry.islnk():
                raise ValueError("Unsupported archive member in Core source snapshot")
        source.extractall(destination, filter="data")
    archive.unlink()
    model_manifest = json.loads((destination / "models/manifest.json").read_text())
    checksums = {}
    for name, expected in model_manifest["files"].items():
        if name.endswith(".onnx"):
            if Path(name).name != name:
                raise ValueError("Unsafe model manifest path")
            actual = digest(destination / "models" / name)
            if actual != expected:
                raise ValueError(f"Model checksum mismatch at {sha}: {name}")
            checksums[name] = actual
    if not checksums:
        raise ValueError("No ONNX models found in Core manifest")
    return checksums


def build(source, output, runtime, log):
    library = runtime / "onnxruntime.xcframework/macos-arm64_x86_64/onnxruntime.framework/Versions/A/onnxruntime"
    headers = runtime / "Headers"
    if not library.is_file() or not (headers / "onnxruntime_cxx_api.h").is_file():
        raise ValueError("Missing macOS ONNX Runtime; run Scripts/bootstrap-native-dependencies.sh")
    run(["cmake", "-S", source, "-B", output, "-DCMAKE_BUILD_TYPE=Debug",
         "-DPITCHEE_BUILD_SHARED=ON", "-DPITCHEE_BUILD_CLI=OFF", "-DPITCHEE_BUILD_TESTS=OFF",
         "-DPITCHEE_ENABLE_ORT=ON", f"-DPITCHEE_ORT_INCLUDE_DIR={headers}", f"-DPITCHEE_ORT_LIBRARY={library}"], log)
    run(["cmake", "--build", output, "--target", "pitchee_core", "--parallel", "4"], log)
    probe = output / "core-regression-probe"
    run(["xcrun", "clang++", "-std=c++17", "-O0", "-I", source / "include", "-I", source / "src",
         ROOT / "Scripts/ci/core_regression_probe.cpp", source / "src/audio.cpp", source / "src/wav_reader.cpp",
         "-L", output, "-lpitchee_core",
         f"-Wl,-rpath,{output}", "-o", probe], log)
    return probe


def json_command(command, log):
    with log.open("ab") as errors:
        raw = subprocess.check_output(list(map(str, command)), stderr=errors, timeout=180)
    return json.loads(raw)


def analyze(probe, source, fixtures, manifest, output):
    output.mkdir()
    all_full, all_hnr, readiness = {}, {}, []
    for item in manifest["samples"]:
        name = item["file"]
        wav_path = fixtures / name
        if digest(wav_path) != item["sha256"]:
            raise ValueError(f"Private fixture changed before analysis: {name}")
        full = {}
        # Two profiles run all fields; score rules are native Core output.
        for profile, label in ((0, "feminization"), (1, "masculinization")):
            full[label] = json_command([probe, "full", source / "models", wav_path, profile], output / "analysis.log")
            (output / f"{name}.{label}.json").write_text(json.dumps(full[label], indent=2) + "\n")
        data = full["feminization"]
        # No PCM or converted audio is written: the native probe uses the same
        # checkpoint's read_wav/resample_mono directly in memory.
        with tempfile.TemporaryDirectory(prefix="pitchee-vad-intervals-") as private:
            segments = Path(private) / "segments.txt"
            segments.write_text("".join(f"{segment['start_seconds']!r} {segment['end_seconds']!r}\n"
                                        for segment in data["vad"]["segments"]))
            hnr = json_command([probe, "hnr", wav_path, segments], output / "analysis.log")
        (output / f"{name}.hnr.json").write_text(json.dumps(hnr, indent=2) + "\n")
        if digest(wav_path) != item["sha256"]:
            raise ValueError(f"Private fixture changed during analysis: {name}")
        all_full[name], all_hnr[name] = full, hnr
        readiness.append({"file": name, "hnr": hnr["hnr_db"],
                          "naturalness": data["naturalness"]["score"],
                          "speechSeconds": data["vad"]["speech_seconds"]})
        print(f"Analyzed {name}: speech_seconds={data['vad']['speech_seconds']}", flush=True)
    (output / "readiness-input.json").write_text(json.dumps(readiness))
    return {"full": all_full, "hnr": all_hnr}


def coverage(manifest, old, new):
    threshold = manifest.get("minimumLongSpeechSeconds", 5.0)
    if threshold < 5:
        raise ValueError("The long tier cannot lower its 5-second speech threshold")
    rows = []
    for sample in manifest["samples"]:
        name = sample["file"]
        before = old["full"][name]["feminization"]["vad"]["speech_seconds"]
        after = new["full"][name]["feminization"]["vad"]["speech_seconds"]
        rows.append({"file": name, "oldSpeechSeconds": before, "newSpeechSeconds": after,
                     "includedInLongTier": min(before, after) >= threshold})
    enough = sum(row["includedInLongTier"] for row in rows) >= max(1, manifest.get("minimumLongSamples", 1))
    return rows, enough


def cell(value):
    return json.dumps(value, ensure_ascii=False).replace("|", "&#124;").replace("\n", " ")


def validate_output_separation(fixtures, manifest, output):
    if fixtures is not None:
        fixtures = fixtures.resolve()
        if output.is_relative_to(fixtures) or fixtures.is_relative_to(output):
            raise ValueError("Private fixture and artifact output directories must not overlap")
    if manifest is not None and manifest.resolve().is_relative_to(output):
        raise ValueError("Private fixture manifest must not be inside the artifact output directory")


def main(args):
    output = args.output.resolve()
    try:
        validate_output_separation(args.fixtures, args.manifest, output)
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 2
    output.mkdir(parents=True, exist_ok=True)
    report = ["## Core checkpoint differences", "", f"`{args.old}` → `{args.new}`", "",
              "Exact field comparison; no tolerance. Nonzero differences require a reviewer decision.",
              "CPU inference, one thread, Debug libraries; this does not verify an iPhone backend.", ""]
    code = 2
    try:
        manifest = validate_fixtures(args.fixtures, args.manifest)
        (output / "fixture-provenance.json").write_text(json.dumps({
            "samples": [{key: item[key] for key in ("file", "sha256", "bytes")} for item in manifest["samples"]],
            "configuration": {"buildType": "Debug", "threads": 1, "useCoreML": False,
                              "f0Parameters": [0, 0, 0], "audioInArtifacts": False},
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
        }, indent=2) + "\n")
        with tempfile.TemporaryDirectory(prefix="pitchee-core-regression-") as tmp:
            scratch = Path(tmp)
            evidence, provenance = {}, {}
            for label, sha in (("old", args.old), ("new", args.new)):
                source, build_dir = scratch / f"source-{label}", scratch / f"build-{label}"
                log = output / f"build-{label}.log"
                models = snapshot(args.core, sha, source, log)
                probe = build(source, build_dir, args.runtime, log)
                provenance[label] = {"commit": sha, "modelSHA256": models,
                                     "librarySHA256": digest(build_dir / "libpitchee_core.dylib")}
                evidence[label] = analyze(probe, source, args.fixtures, manifest, output / label)
            readiness_probe = scratch / "readiness-probe"
            run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
                 "-warnings-as-errors", "-default-isolation", "MainActor",
                 ROOT / "PitcheeApp/Analysis/ReadinessScoring.swift", ROOT / "Scripts/ci/CoreReadinessProbe.swift",
                 "-o", readiness_probe], output / "readiness.log")
            for label in ("old", "new"):
                evidence[label]["readiness"] = json_command([readiness_probe, output / label / "readiness-input.json"],
                                                            output / "readiness.log")
                (output / label / "readiness.json").write_text(json.dumps(evidence[label]["readiness"], indent=2))
        (output / "provenance.json").write_text(json.dumps(provenance, indent=2))
        report += ["| Mode | Changed fields |", "| --- | ---: |"]
        diffsets = {}
        for mode in ("full", "hnr", "readiness"):
            diffsets[mode] = differences(evidence["old"][mode], evidence["new"][mode])
            report.append(f"| {mode} | {len(diffsets[mode])} |")
            (output / f"{mode}-differences.json").write_text(json.dumps(diffsets[mode], indent=2))
        report += ["", "| WAV | Δ feminine score | Δ masculine score | Feminine rule (old → new) | Δ HNR dB | Δ HNR std dB | Δ HNR windows | Δ readiness |",
                   "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |"]
        metrics = []
        for sample in manifest["samples"]:
            name = sample["file"]
            row = {"file": name}
            deltas = []
            for profile in ("feminization", "masculinization"):
                before = evidence["old"]["full"][name][profile]["composite"]
                after = evidence["new"]["full"][name][profile]["composite"]
                row[profile] = {"oldScore": before["final_score"], "newScore": after["final_score"],
                                "deltaScore": after["final_score"] - before["final_score"],
                                "oldRule": before["rule"], "newRule": after["rule"]}
                deltas.append(row[profile]["deltaScore"])
            for field in ("hnr_db", "hnr_std_db", "hnr_window_count"):
                before, after = evidence["old"]["hnr"][name][field], evidence["new"]["hnr"][name][field]
                row[field] = {"old": before, "new": after,
                              "delta": after - before if before is not None and after is not None else None}
                deltas.append(row[field]["delta"])
            before, after = evidence["old"]["readiness"][name]["score"], evidence["new"]["readiness"][name]["score"]
            row["readiness"] = {"old": before, "new": after, "delta": after - before}
            deltas.append(after - before)
            rule = row["feminization"]
            report.append(f"| {name} | {deltas[0]!r} | {deltas[1]!r} | {rule['oldRule']} → {rule['newRule']} | "
                          + " | ".join(map(repr, deltas[2:])) + " |")
            metrics.append(row)
        (output / "metric-differences.json").write_text(json.dumps(metrics, indent=2) + "\n")
        report += ["", "Readiness uses the current production scoring function with fixed synthetic history inputs "
                   "and each recording's measured HNR/naturalness. It is a rule sensitivity check, not a clinical estimate.", "",
                   "| WAV | Old speech seconds | New speech seconds | Long tier (≥5 s both) |",
                   "| --- | ---: | ---: | --- |"]
        rows, enough = coverage(manifest, evidence["old"], evidence["new"])
        (output / "coverage.json").write_text(json.dumps(rows, indent=2))
        for row in rows:
            report.append(f"| {row['file']} | {row['oldSpeechSeconds']!r} | {row['newSpeechSeconds']!r} | "
                          f"{'included' if row['includedInLongTier'] else 'excluded: below threshold'} |")
        for mode, rows in diffsets.items():
            report += ["", f"### {mode}", "", "| Field | Old | New | New − old |", "| --- | --- | --- | --- |"]
            if not rows:
                report.append("| All fields | Same | Same | 0 |")
            for row in rows[:60]:
                report.append(f"| {row['field']} | {cell(row['old'])[:160]} | {cell(row['new'])[:160]} | {cell(row['delta'])} |")
            if len(rows) > 60:
                report.append(f"\nShowing 60 of {len(rows)} fields; the artifact contains every unrounded value.")
        code = int(any(diffsets.values()))
        if not enough:
            report += ["", "**Fixture coverage failure:** no sufficient private long-speech set is installed. "
                       "Short-corpus comparisons above ran, but full F5 coverage remains incomplete. "
                       "Provision authorized ≥5-second Core-measured speech WAVs privately and record their SHA-256/provenance in the manifest. Do not upload audio artifacts."]
            code = 2
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, tarfile.TarError) as error:
        report += ["", f"**Execution failure:** {str(error)}", "See retained logs; no missing comparison is treated as zero."]
        print(f"::error::{error}", file=sys.stderr)
    (output / "report.md").write_text("\n".join(report) + "\n")
    (output / "outcome.json").write_text(json.dumps({"exitCode": code,
        "meaning": {0: "zero differences", 1: "nonzero differences", 2: "execution or coverage failure"}[code]}) + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
            summary.write((output / "report.md").read_text())
    return code


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", required=True)
    parser.add_argument("--new", required=True)
    parser.add_argument("--core", type=Path, default=ROOT / "Dependencies/PitcheeCore")
    parser.add_argument("--fixtures", type=Path, default=os.environ.get("CORE_REGRESSION_FIXTURES_DIR"))
    parser.add_argument("--manifest", type=Path, help="Defaults to manifest.json in the private fixture directory")
    parser.add_argument("--runtime", type=Path, default=ROOT / "Dependencies/Artifacts/ONNXRuntime")
    parser.add_argument("--output", type=Path, required=True)
    sys.exit(main(parser.parse_args()))
