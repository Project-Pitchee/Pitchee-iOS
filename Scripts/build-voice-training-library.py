#!/usr/bin/env python3
"""Build the bilingual article resources; --check validates without writing files."""

import argparse
import hashlib
import json
import os
import posixpath
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LOCAL_DOCS_DIR = REPO_ROOT / "Docs" / "Voice-Training-Library"
LIBRARY_DOCS_DIR = Path(os.environ.get("ARTICLES_DIR") or LOCAL_DOCS_DIR).resolve()
RESOURCES_DIR = REPO_ROOT / "Resources" / "VoiceTrainingLibrary"
LANGUAGES = ("en", "zh_cn")
ARTICLE_CATEGORIES = {
    "practice/01-vfp": "timbre",
    "practice/02-naturalness": "naturalness",
    "practice/03-low-f0": "pitch",
    "rules/01-feminization-continuous-nopass": "rules",
    "rules/02-feminization-continuous-pass": "rules",
    "rules/03-pass-boost": "rules",
    "rules/04-high-f0-stylized-cap": "rules",
    "rules/05-low-f0-natural-cap": "rules",
    "rules/06-low-f0-stylized-cap": "rules",
    "rules/07-high-f0-male-cap": "rules",
}
ARTICLE_FILES = {}
for article_id in ARTICLE_CATEGORIES:
    group, name = article_id.split("/")
    for language in LANGUAGES:
        ARTICLE_FILES[f"{group}/{language}/{name}.md"] = (article_id, language)

# These are the result and practice links documented in the bilingual source.
RULE_MATRIX = {
    "pass_boost": ["rules/03-pass-boost"],
    "high_f0_stylized_cap": ["rules/04-high-f0-stylized-cap"],
    "high_f0_male_cap": ["rules/07-high-f0-male-cap"],
    "low_f0_natural_cap": ["rules/05-low-f0-natural-cap"],
    "low_f0_stylized_cap": ["rules/06-low-f0-stylized-cap"],
    "f0_unavailable": [],
    "continuous_below_pass": ["rules/01-feminization-continuous-nopass"],
    "continuous_pass": ["rules/02-feminization-continuous-pass"],
    "timbre": ["practice/01-vfp"],
    "naturalness": ["practice/02-naturalness"],
    "low_pitch": ["practice/03-low-f0"],
}


def parse_markdown(filepath):
    path = Path(filepath)
    filename = path.relative_to(LIBRARY_DOCS_DIR).as_posix()
    if filename not in ARTICLE_FILES:
        raise ValueError(f"Unknown article source: {filename}")
    article_id, language = ARTICLE_FILES[filename]
    content = path.read_bytes().decode("utf-8")
    lines = content.splitlines()
    title_index = next((i for i, line in enumerate(lines) if line.startswith("# ")), None)
    if title_index is None:
        raise ValueError(f"Missing article title: {filename}")
    title = lines[title_index][2:].strip()

    # Keep the introduction: rule conditions often precede the first H2.
    sections = [{"heading": title, "body": []}]
    for index, line in enumerate(lines):
        if index == title_index:
            continue
        if line.startswith("## "):
            sections.append({"heading": line[3:].strip(), "body": []})
        else:
            sections[-1]["body"].append(line)
    for section in sections:
        section["body"] = "\n".join(section["body"]).strip()
    introduction = sections[0]["body"]
    if not introduction:
        sections.pop(0)

    return {
        "id": article_id,
        "language": language,
        "title": title,
        "category": ARTICLE_CATEGORIES[article_id],
        "filename": filename,
        "summary": introduction.split("\n\n", 1)[0] or title,
        "userPersona": "",
        "coreGoal": "",
        "targetPreferences": ["feminine", "masculine", "undecided"]
            if article_id == "practice/02-naturalness" else ["feminine"],
        "sections": sections,
        "rawContent": content,
    }


def source_digest(articles):
    digest = hashlib.sha256()
    for article in sorted(articles, key=lambda value: value["filename"]):
        digest.update(article["filename"].encode("utf-8"))
        digest.update(b"\0")
        digest.update(article["rawContent"].encode("utf-8"))
        digest.update(b"\0")
    return digest.hexdigest()


def build_resources():
    md_files = sorted(path for path in LIBRARY_DOCS_DIR.rglob("*.md")
                      if not path.name.lower().startswith("readme"))
    actual_files = {path.relative_to(LIBRARY_DOCS_DIR).as_posix() for path in md_files}
    expected_files = set(ARTICLE_FILES)
    if actual_files != expected_files:
        raise ValueError(f"Article source mismatch: missing {sorted(expected_files - actual_files)}, "
                         f"unexpected {sorted(actual_files - expected_files)}")
    articles = [parse_markdown(path) for path in md_files]
    library = {
        "schemaVersion": "2.0.0",
        "sourceSHA256": source_digest(articles),
        "description": "Pitchee iOS App Embedded Voice Training Text Resource Library",
        "totalArticles": len(articles),
        "articles": articles,
    }
    validate_resources(library, RULE_MATRIX)
    return library, RULE_MATRIX


def validate_resources(library=None, matrix=None):
    if library is None:
        with (RESOURCES_DIR / "voice-training-library.json").open(encoding="utf-8") as source:
            library = json.load(source)
        with (RESOURCES_DIR / "voice-rule-matching-matrix.json").open(encoding="utf-8") as source:
            matrix = json.load(source)
    articles = library["articles"]
    if (library["schemaVersion"] != "2.0.0" or library["totalArticles"] != len(articles)
            or len(articles) != len(ARTICLE_FILES)):
        raise ValueError("Invalid library schema or article count")
    identities = [(article["id"], article["language"]) for article in articles]
    if len(set(identities)) != len(identities):
        raise ValueError("Duplicate article ID within a language")
    if set(identities) != set(ARTICLE_FILES.values()):
        raise ValueError("Incomplete article manifest or translation pair")
    for article in articles:
        for field in ("id", "language", "title", "category", "filename", "summary", "rawContent"):
            if not isinstance(article.get(field), str) or not article[field].strip():
                raise ValueError(f"Missing {field} in {article['id']}")
        for field in ("userPersona", "coreGoal"):
            if not isinstance(article.get(field), str):
                raise ValueError(f"Invalid {field} in {article['id']}")
        if ARTICLE_FILES.get(article["filename"]) != (article["id"], article["language"]):
            raise ValueError(f"Invalid article source path: {article['filename']}")
        if article["category"] != ARTICLE_CATEGORIES[article["id"]]:
            raise ValueError(f"Invalid article category: {article['id']}")
        targets = (["feminine", "masculine", "undecided"]
                   if article["id"] == "practice/02-naturalness" else ["feminine"])
        if article["targetPreferences"] != targets:
            raise ValueError(f"Invalid article target preferences: {article['id']}")
        if not article["sections"] or any(
            not isinstance(section.get(field), str) or not section[field].strip()
            for section in article["sections"] for field in ("heading", "body")
        ):
            raise ValueError(f"Empty article section: {article['id']}")
        for target in re.findall(r"\[[^\]]*\]\(([^)]+\.md)\)", article["rawContent"]):
            if "://" not in target:
                destination = posixpath.normpath(posixpath.join(posixpath.dirname(article["filename"]), target))
                if ARTICLE_FILES.get(destination, (None, None))[1] != article["language"]:
                    raise ValueError(f"Broken or cross-language article link: {article['filename']} -> {target}")
    if library["sourceSHA256"] != source_digest(articles):
        raise ValueError("Article source digest mismatch")
    if matrix != RULE_MATRIX:
        raise ValueError("Matching matrix differs from the documented article mapping")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate resources without rewriting files")
    args = parser.parse_args()
    if args.check and not os.environ.get("ARTICLES_DIR") and not LIBRARY_DOCS_DIR.is_dir():
        validate_resources()
        print("Validated bundled resources; Markdown source checkout is not installed.")
        return
    library, matrix = build_resources()
    outputs = {"voice-training-library.json": library, "voice-rule-matching-matrix.json": matrix}
    if args.check:
        for name, payload in outputs.items():
            with (RESOURCES_DIR / name).open(encoding="utf-8") as source:
                if json.load(source) != payload:
                    raise ValueError(f"{name} differs from Markdown source; run Scripts/build-voice-training-library.py")
        validate_resources()
        print("Bundled JSON matches all 20 bilingual Markdown articles and the generator.")
    else:
        RESOURCES_DIR.mkdir(parents=True, exist_ok=True)
        for name, payload in outputs.items():
            path = RESOURCES_DIR / name
            with path.open("w", encoding="utf-8") as output:
                json.dump(payload, output, ensure_ascii=False, indent=2)
                output.write("\n")
            print(f"Wrote {path}")


if __name__ == "__main__":
    main()
