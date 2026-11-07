#!/usr/bin/env python3
"""Validate every shipped locale without requiring a simulator or network access."""

import collections
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
FORMAT = re.compile(
    r"%(?:(\d+)\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(hh|ll|[hlLjztq])?([@diuoxXfFeEgGaAcCsSp])"
)
PLURALS = {"zero", "one", "two", "few", "many", "other"}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def signature(value):
    matches = list(FORMAT.finditer(value.replace("%%", "")))
    arguments = collections.Counter(
        (int(match[1]) if match[1] else index, (match[2] or "") + match[3])
        for index, match in enumerate(matches, 1)
    )
    mixed = any(match[1] for match in matches) and any(not match[1] for match in matches)
    return arguments, mixed


def string_units(node):
    if isinstance(node, dict):
        if "stringUnit" in node:
            yield node["stringUnit"]
        for key, value in node.items():
            if key != "stringUnit":
                yield from string_units(value)


def plural_errors(node):
    if not isinstance(node, dict):
        return
    for key, value in node.items():
        if key == "plural":
            if "other" not in value:
                yield "Plural variation has no other form"
            if set(value) - PLURALS:
                yield "Unknown plural category"
        yield from plural_errors(value)


def validate():
    project = (ROOT / "Pitchee.xcodeproj/project.pbxproj").read_text()
    regions = re.search(r"knownRegions = \((.*?)\);", project, re.S)
    if not regions:
        raise ValueError("Could not read the project's supported languages")
    languages = {
        value.strip().strip('"') for value in regions[1].split(",") if value.strip()
    } - {"Base"}
    errors = []
    total_units = formatted_units = total_keys = 0
    for path in sorted((ROOT / "Resources").glob("*.xcstrings")):
        catalog = json.loads(path.read_text(), object_pairs_hook=unique_object)
        source_language = catalog["sourceLanguage"]
        if source_language not in languages:
            errors.append(f"{path.name}: source language is absent from knownRegions")
        missing = collections.defaultdict(list)
        for key, entry in catalog["strings"].items():
            total_keys += 1
            context = f"{path.name}: {key}"
            if "%" in key.split(" ", 1)[0]:
                errors.append(f"{context}: interpolated key name, not an actual localization key")
            localizations = entry.get("localizations", {})
            unexpected = set(localizations) - languages
            if unexpected:
                errors.append(f"{context}: unsupported languages {sorted(unexpected)}")
            source_units = list(string_units(localizations.get(source_language, {})))
            source_values = {unit.get("value") for unit in source_units}
            expected, _ = signature(key)
            # Explicit semantic keys can carry arguments in defaultValue instead
            # of in the key (for example the library reading-time label).
            if not expected and source_units:
                expected, _ = signature(source_units[0].get("value", ""))
            for language in sorted(languages):
                localization = localizations.get(language, {})
                units = list(string_units(localization))
                if not units:
                    missing[language].append(key)
                for error in plural_errors(localization):
                    errors.append(f"{context} [{language}]: {error}")
                for unit in units:
                    total_units += 1
                    value = unit.get("value")
                    if not isinstance(value, str) or not value.strip():
                        errors.append(f"{context} [{language}]: empty value")
                        continue
                    if value == key and re.fullmatch(r"[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+", key):
                        errors.append(f"{context} [{language}]: localization key is displayed as text")
                    # A literal percentage (e.g. "75% or more") is not a printf argument.
                    if expected:
                        formatted_units += 1
                        actual, mixed = signature(value)
                        if actual != expected:
                            errors.append(f"{context} [{language}]: format arguments differ from key")
                        if mixed:
                            errors.append(f"{context} [{language}]: mixed positional and sequential arguments")
                    elif re.search(r"%\d+\$", value):
                        errors.append(f"{context} [{language}]: unexpected positional argument")
                    if entry.get("shouldTranslate") is False and value not in source_values:
                        errors.append(f"{context} [{language}]: non-translatable value was changed")
                    if re.search(r"[\u202a-\u202e\u2066-\u2069]", value):
                        errors.append(f"{context} [{language}]: embedded bidi formatting control")
        for language, keys in sorted(missing.items()):
            preview = ", ".join(keys[:3]) + (", …" if len(keys) > 3 else "")
            errors.append(f"{path.name} [{language}]: {len(keys)} missing translations ({preview})")
        print(f"{path.name}: {len(catalog['strings'])} keys, {len(languages)} languages")
    print(f"Checked {total_keys} keys, {total_units} string units, {formatted_units} formatted units.")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        print(f"FAILED: {len(errors)} issues.", file=sys.stderr)
        return 1
    print("PASS: all supported languages are complete; formats, plurals and protected values are valid.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(validate())
    except (OSError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
