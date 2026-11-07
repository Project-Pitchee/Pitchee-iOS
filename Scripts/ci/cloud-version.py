#!/usr/bin/env python3
"""Synchronize Cloud's version facts through the project's sole xcconfig."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from version_config import sync_versions, validate_build_number, version_from_tag


def main(project_root: Path | None = None) -> int:
    tag = os.environ.get('CI_TAG', '')
    workflow = os.environ.get('CI_WORKFLOW', '')
    version = version_from_tag(tag)
    if workflow == 'Release' and version is None:
        raise ValueError('Release requires a tag exactly matching vX.Y.Z.')
    build_number = validate_build_number(os.environ.get('CI_BUILD_NUMBER', ''))
    if os.environ.get('CI_XCODEBUILD_ACTION') == 'test-without-building':
        print('Reusing the built test product; no source synchronization is needed.')
        return 0
    if workflow == 'TestFlight Internal':
        if tag:
            raise ValueError('TestFlight Internal accepts an untagged main commit only.')
        subprocess.run(['git', 'fetch', '--tags', 'origin'], check=True)
        tags = subprocess.check_output(['git', 'tag', '--points-at', 'HEAD'], text=True)
        if any(version_from_tag(value) for value in tags.splitlines()):
            raise ValueError('This commit has a release tag; use the Release workflow.')
        if os.environ.get('CI_BRANCH') != 'main':
            raise ValueError('TestFlight Internal must be started on main.')
    settings = sync_versions(project_root or Path.cwd(), build_number, version)
    print(f"App version synchronized to {settings['MARKETING_VERSION']} ({settings['CURRENT_PROJECT_VERSION']}); "
          'the build number was allocated by Xcode Cloud.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(1)
