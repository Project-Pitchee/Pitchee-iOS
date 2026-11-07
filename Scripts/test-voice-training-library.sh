#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Testing Voice Training Library & Matching Engine ==="

# Validate the sole generated app resources and, when installed, their Markdown source.
python3 Scripts/build-voice-training-library.py --check
python3 - <<'PYTHON'
import importlib.util
import copy
import json
import pathlib
import tempfile
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("voice_library_builder", "Scripts/build-voice-training-library.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
with open("Resources/VoiceTrainingLibrary/voice-training-library.json", encoding="utf-8") as source:
    library = json.load(source)
with open("Resources/VoiceTrainingLibrary/voice-rule-matching-matrix.json", encoding="utf-8") as source:
    matrix = json.load(source)
required_keys = {
    "pass_boost", "high_f0_stylized_cap", "high_f0_male_cap",
    "low_f0_natural_cap", "low_f0_stylized_cap", "f0_unavailable",
    "continuous_below_pass", "continuous_pass", "timbre", "naturalness", "low_pitch",
}
assert set(matrix) == required_keys
assert matrix["f0_unavailable"] == []
assert len(library["articles"]) == 20
assert len({article["id"] for article in library["articles"]}) == 10
builder.validate_resources(library, matrix)

def rejects(operation):
    try:
        operation()
    except ValueError:
        return
    raise AssertionError("Invalid article input was accepted")

# The parser keeps real headings and introductions without inventing section roles.
source_directory = builder.LIBRARY_DOCS_DIR
with tempfile.TemporaryDirectory() as directory:
    builder.LIBRARY_DOCS_DIR = pathlib.Path(directory)
    path = builder.LIBRARY_DOCS_DIR / "practice/en/01-vfp.md"
    path.parent.mkdir(parents=True)
    for headings in [[], ["Next step"], ["Comprendre", "Pratiquer"],
                     ["الفهم", "الملاحظة", "التدريب", "المراجع", "Other"]]:
        markdown = "# Test article\n\nFirst paragraph.\n\nSecond paragraph.\n" + "\n".join(
            "## " + heading + "\nBody" for heading in headings)
        path.write_text(markdown, encoding="utf-8")
        article = builder.parse_markdown(str(path))
        assert [section["heading"] for section in article["sections"]] == ["Test article"] + headings
        assert article["sections"][0]["body"] == "First paragraph.\n\nSecond paragraph."
        assert article["summary"] == "First paragraph."
        assert article["rawContent"] == markdown
        assert all("icon" not in section for section in article["sections"])
    path.write_text("# Test article\n## Next step\nBody", encoding="utf-8")
    article = builder.parse_markdown(str(path))
    assert article["sections"] == [{"heading": "Next step", "body": "Body"}]
    assert article["summary"] == "Test article"

    for article in library["articles"]:
        path = builder.LIBRARY_DOCS_DIR / article["filename"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(article["rawContent"], encoding="utf-8")
    for name in ["README.md", "README_en.md", "README_zh_cn.md"]:
        (builder.LIBRARY_DOCS_DIR / name).write_text("Not an article", encoding="utf-8")
    assert builder.build_resources() == (library, matrix)
    path.unlink()
    rejects(builder.build_resources)
    path.write_text("# Empty article\n## No body\n", encoding="utf-8")
    rejects(builder.build_resources)
builder.LIBRARY_DOCS_DIR = source_directory

invalid = copy.deepcopy(library)
invalid["articles"][1] = copy.deepcopy(invalid["articles"][0])
rejects(lambda: builder.validate_resources(invalid, matrix))
invalid = copy.deepcopy(library)
invalid["articles"][0]["language"] = "fr"
rejects(lambda: builder.validate_resources(invalid, matrix))
invalid = copy.deepcopy(library)
invalid["articles"][0]["sections"][0]["body"] = " "
rejects(lambda: builder.validate_resources(invalid, matrix))
invalid = copy.deepcopy(library)
invalid["articles"][0]["rawContent"] += "\nChanged source.\n"
rejects(lambda: builder.validate_resources(invalid, matrix))
invalid = copy.deepcopy(library)
invalid["articles"][0]["rawContent"] += "\n[Missing](missing.md)\n"
invalid["sourceSHA256"] = builder.source_digest(invalid["articles"])
rejects(lambda: builder.validate_resources(invalid, matrix))
for target in [[], ["missing"], ["practice/01-vfp"]]:
    invalid_matrix = {**matrix, "pass_boost": target}
    rejects(lambda: builder.validate_resources(library, invalid_matrix))
rejects(lambda: builder.validate_resources(library, {**matrix, "f0_unavailable": ["practice/01-vfp"]}))
print(f"✓ Validated {len(library['articles'])} bilingual articles, {len(matrix)} mappings and rejected invalid sources")
PYTHON

# 2. Compile and run Swift test for VoiceLibraryMatcher and Section Icons
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
project_directory="$REPO_ROOT"
test_directory="$TMP_DIR"
. "$REPO_ROOT/Scripts/core-scoring-test-support.sh"

CPATH="$REPO_ROOT/Dependencies/PitcheeCore/include${CPATH:+:$CPATH}" \
xcrun swiftc -parse-as-library -swift-version 5 \
    -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
    -target "$(uname -m)-apple-macosx14.0" \
    -I "$core_scoring_module_directory" "$core_scoring_object" -lc++ \
    PitcheeApp/Interop/Core/AnalysisResult.swift \
    PitcheeApp/Analysis/VoiceScoring.swift \
    PitcheeApp/Analysis/RecordingStatistics.swift \
    PitcheeApp/Practice/PracticeData.swift \
    PitcheeApp/Practice/VoiceTrainingLibrary.swift \
    Tests/Practice/VoiceTrainingLibraryTests.swift \
    -o "$TMP_DIR/matcher-test-bin"

"$TMP_DIR/matcher-test-bin" "$REPO_ROOT/Resources/VoiceTrainingLibrary"

echo "=== Voice Training Library verification 100% SUCCESS ==="
