#!/usr/bin/env python3
"""Validate dispatch inputs before constructing the device/language/theme matrix."""
import argparse
import json
from capture import supported_languages


def matrix(languages, appearances):
    allowed = supported_languages()
    languages = allowed if languages.strip() == "all" else languages.replace(",", " ").split()
    appearances = appearances.replace(",", " ").split()
    if not languages or len(set(languages)) != len(languages) or not set(languages) <= set(allowed):
        raise ValueError(f"Choose unique catalog languages or all: {', '.join(allowed)}")
    if not appearances or len(set(appearances)) != len(appearances) or not set(appearances) <= {"light", "dark"}:
        raise ValueError("Choose light, dark, or light dark")
    return {"device": ["6.9", "6.5"], "language": languages, "appearance": appearances}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--languages", default="zh-Hans en")
    parser.add_argument("--appearances", default="light")
    args = parser.parse_args()
    try:
        print(json.dumps(matrix(args.languages, args.appearances), separators=(",", ":")))
    except ValueError as error:
        parser.error(str(error))
