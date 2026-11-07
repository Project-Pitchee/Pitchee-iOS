#!/usr/bin/env python3
"""Verify shipping bundle metadata before Xcode Cloud distribution.

This file and Version.xcconfig travel with ci_scripts to phases without sources.
Read actual product Info.plists using PlistBuddy, never infer their values from
build settings. The Cloud build number and (when present) strict version tag are
authoritative. Non-tag builds retain the shared project's marketing version.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

VERSION_TAG = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
PLIST_BUDDY = "/usr/libexec/PlistBuddy"


class VerificationError(RuntimeError):
    pass


def expected_version(tag: str, config: Path, workflow: str = "") -> str:
    if VERSION_TAG.fullmatch(tag):
        return tag[1:]
    if workflow == "Release":
        raise VerificationError("Release requires a tag exactly matching vX.Y.Z.")
    try:
        source = config.read_text(encoding="utf-8")
    except OSError as error:
        raise VerificationError(f"Shared version configuration is missing: {config}") from error
    values = re.findall(r"^\s*MARKETING_VERSION\s*=\s*([0-9]+(?:\.[0-9]+){1,2})\s*(?://.*)?$", source, re.MULTILINE)
    if len(values) != 1:
        raise VerificationError("Shared config must contain exactly one literal MARKETING_VERSION.")
    return values[0]


def product_root(action: str, environment) -> Path:
    def required(key):
        if not environment.get(key):
            raise VerificationError(f"{key} is required for the {action} action.")
        return Path(environment[key])

    if action == "archive":
        root = required("CI_ARCHIVE_PATH") / "Products/Applications"
    elif action == "test-without-building":
        root = required("CI_TEST_PRODUCTS_PATH")
    elif action == "build-for-testing" and environment.get("CI_TEST_PRODUCTS_PATH"):
        root = required("CI_TEST_PRODUCTS_PATH")
    elif action in {"build", "build-for-testing"}:
        root = required("CI_DERIVED_DATA_PATH") / "Build/Products"
    else:
        raise VerificationError(f"Unsupported product action {action!r}; no App verification can be claimed.")
    if not root.is_dir():
        raise VerificationError(f"Declared build product directory does not exist: {root}")
    return root.resolve()


def bundle_plist(bundle: Path) -> Path:
    if bundle.is_symlink():
        raise VerificationError(f"Shipping bundle must not be a symlink: {bundle}")
    for path in (bundle / "Info.plist", bundle / "Contents/Info.plist"):
        if path.is_file():
            if path.is_symlink() or not path.resolve().is_relative_to(bundle.resolve()):
                raise VerificationError(f"Info.plist leaves its shipping bundle: {path}")
            return path
    raise VerificationError(f"Built bundle has no Info.plist: {bundle}")


def read_field(plist: Path, key: str) -> str:
    try:
        result = subprocess.run([PLIST_BUDDY, "-c", f"Print :{key}", str(plist)],
                                text=True, capture_output=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise VerificationError(f"PlistBuddy could not read {key} from {plist}") from error
    if result.returncode:
        raise VerificationError(f"Missing or unreadable {key} in {plist}")
    try:
        original = plistlib.loads(plist.read_bytes()).get(key)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise VerificationError(f"Malformed Info.plist: {plist}") from error
    if not isinstance(original, str) or not original:
        raise VerificationError(f"{key} must be a nonempty plist String in {plist}")
    # Remove only the newline printed by PlistBuddy, preserving whitespace that
    # is actually stored in the value. About uses `as? String` too: a plist
    # Number that happens to print as 45 must never masquerade as build "45".
    printed = result.stdout.removesuffix("\n")
    if printed != original:
        raise VerificationError(f"PlistBuddy and typed plist contents disagree for {key}: {plist}")
    return original


def main_apps(root: Path, bundle_id: str, reader=read_field) -> list[Path]:
    matches = []
    for directory, names, _ in os.walk(root, followlinks=False):
        keep = []
        for name in sorted(names):
            child = Path(directory) / name
            if child.is_symlink():
                continue
            if name.endswith(".app"):
                if reader(bundle_plist(child), "CFBundleIdentifier") == bundle_id:
                    matches.append(child)
                # Sibling test runners and nested apps aren't root products.
            elif not name.endswith((".framework", ".bundle", ".xctest", ".dSYM")):
                keep.append(name)
        names[:] = keep
    if not matches:
        raise VerificationError(f"No built App with bundle ID {bundle_id!r} exists under {root}")
    return matches


def shipping_bundles(app: Path) -> list[Path]:
    if not app.is_dir() or app.suffix != ".app":
        raise VerificationError(f"Expected a built .app directory: {app}")
    bundles = [app]
    for directory, names, _ in os.walk(app, followlinks=False):
        keep = []
        for name in sorted(names):
            child = Path(directory) / name
            if child.is_symlink() and name.lower() in {"plugins", "extensions", "watch", "appclips", "contents"}:
                raise VerificationError(f"Shipping bundle container is a symlink: {child}")
            if name.endswith((".app", ".appex")):
                if child.is_symlink():
                    raise VerificationError(f"Embedded shipping bundle is a symlink: {child}")
                bundles.append(child)
                keep.append(name)
            elif not child.is_symlink() and not name.endswith((".framework", ".bundle", ".xctest", ".dSYM")):
                keep.append(name)
        names[:] = keep
    return bundles


def verify(apps, bundle_id, version, build, reader=read_field):
    if not apps:
        raise VerificationError("No built Apps were supplied for verification.")
    mismatches = []
    results = []
    for app in apps:
        app_id = reader(bundle_plist(app), "CFBundleIdentifier")
        if app_id != bundle_id:
            raise VerificationError(f"Root App bundle ID {app_id!r} does not match {bundle_id!r}: {app}")
        for bundle in shipping_bundles(app):
            plist = bundle_plist(bundle)
            actual_version = reader(plist, "CFBundleShortVersionString")
            actual_build = reader(plist, "CFBundleVersion")
            results.append(f"{bundle}: {actual_version} ({actual_build})")
            for key, actual, expected in (("CFBundleShortVersionString", actual_version, version),
                                          ("CFBundleVersion", actual_build, build)):
                if actual != expected:
                    mismatches.append(f"{bundle}: {key} expected {expected!r}, found {actual!r}")
    if mismatches:
        raise VerificationError("Built App version mismatch; distribution must stop:\n" + "\n".join(mismatches))
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, action="append", help="Explicit built App for local verification; repeat for multiple products.")
    parser.add_argument("--bundle-id", default=os.environ.get("CI_BUNDLE_ID"))
    parser.add_argument("--expected-build", default=os.environ.get("CI_BUILD_NUMBER"))
    parser.add_argument("--tag", default=os.environ.get("CI_TAG", ""))
    parser.add_argument("--version-config", type=Path, default=Path(__file__).with_name("Version.xcconfig"))
    parser.add_argument("--action", default=os.environ.get("CI_XCODEBUILD_ACTION", ""))
    parser.add_argument("--xcodebuild-exit-code", default=os.environ.get("CI_XCODEBUILD_EXIT_CODE", "0"))
    args = parser.parse_args(argv)
    try:
        if args.xcodebuild_exit_code != "0":
            raise VerificationError(f"xcodebuild already failed (exit {args.xcodebuild_exit_code}); no successful product verification.")
        if not args.bundle_id:
            raise VerificationError("CI_BUNDLE_ID / --bundle-id is required.")
        if not args.expected_build or not re.fullmatch(r"[1-9][0-9]*", args.expected_build):
            raise VerificationError("CI_BUILD_NUMBER / --expected-build must be the positive Cloud integer build number.")
        version = expected_version(args.tag, args.version_config, os.environ.get("CI_WORKFLOW", ""))
        apps = args.app or main_apps(product_root(args.action, os.environ), args.bundle_id)
        results = verify(apps, args.bundle_id, version, args.expected_build)
        print(f"Verified built App metadata: expected {version} ({args.expected_build}).")
        for result in results:
            print(result)
        return 0
    except (VerificationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
