#!/usr/bin/env python3
"""Read an authorized private fixture bundle into runner temporary storage only.

The signed URL is a CI secret. Neither the URL nor exception text is logged.
The job must run in the protected core-regression-fixtures environment after
review of its complete PR head. Do not expose this environment to fork PRs.
"""
import hashlib
import io
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import urllib.request
import zipfile

from core_regression import WAV_NAME, validate_fixtures

MAX_BUNDLE = 12 * 1024 * 1024


class HTTPSRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise ValueError("Private fixture redirects must remain HTTPS")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def unpack(data, destination):
    if destination.exists():
        raise ValueError("Private fixture destination already exists")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        items = archive.infolist()
        if len(items) > 21 or not items:
            raise ValueError("Expected at most 20 WAV files and one manifest")
        if len({item.filename for item in items}) != len(items):
            raise ValueError("Duplicate fixture archive entries")
        if sum(item.file_size for item in items) > MAX_BUNDLE:
            raise ValueError("Private fixture bundle is too large")
        for item in items:
            if not (item.filename == "manifest.json" or re.fullmatch(WAV_NAME, item.filename)):
                raise ValueError("Private fixture bundle must contain flat WAVs and manifest.json only")
            if stat.S_ISLNK(item.external_attr >> 16) or item.flag_bits & 1:
                raise ValueError("Links/encrypted entries are not accepted")
        destination.mkdir(mode=0o700)
        try:
            for item in items:
                with (destination / item.filename).open("xb") as output:
                    output.write(archive.read(item))
                (destination / item.filename).chmod(0o600)
            validate_fixtures(destination)
        except Exception:
            shutil.rmtree(destination)
            raise


def main():
    url = os.environ.get("PITCHEE_CORE_FIXTURES_URL", "")
    checksum = os.environ.get("PITCHEE_CORE_FIXTURES_SHA256", "")
    if not url or not re.fullmatch(r"[0-9a-f]{64}", checksum):
        print("::error::Private fixtures are unavailable. Configure the protected environment's PITCHEE_CORE_FIXTURES_URL secret and PITCHEE_CORE_FIXTURES_SHA256 variable. Audio must not be committed or uploaded as artifacts.", file=sys.stderr)
        return 2
    if not url.startswith("https://"):
        print("::error::The private fixture bundle requires HTTPS.", file=sys.stderr)
        return 2
    destination = Path(os.environ["RUNNER_TEMP"]) / "pitchee-core-fixtures"
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "pitchee-core-regression"})
        opener = urllib.request.build_opener(HTTPSRedirectHandler())
        with opener.open(request, timeout=60) as response:
            if not response.geturl().startswith("https://"):
                raise ValueError("HTTPS required after redirect")
            data = response.read(MAX_BUNDLE + 1)
        if len(data) > MAX_BUNDLE or hashlib.sha256(data).hexdigest() != checksum:
            raise ValueError("Private fixture bundle size/checksum mismatch")
        unpack(data, destination)
        with Path(os.environ["GITHUB_ENV"]).open("a") as output:
            output.write(f"CORE_REGRESSION_FIXTURES_DIR={destination}\n")
        print("Private Core fixtures are ready in runner temporary storage; no audio will enter artifacts.")
        return 0
    except Exception:
        # urllib errors may include the signed URL; never surface that string.
        print("::error::Unable to fetch or validate private Core fixtures. Check access, checksum and flat bundle manifest; no comparison was skipped as success.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
