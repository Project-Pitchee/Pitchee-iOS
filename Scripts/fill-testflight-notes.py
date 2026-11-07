#!/usr/bin/env python3
"""Idempotently fill bilingual whatToTest; never submit a build for review.

Credentials: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (PEM), ASC_APP_ID.
Automatic invocations pin the newest uploaded build once, including PROCESSING.
Repairs can select an exact marketing version/build pair. Polling never falls
back to a different or older build. Only sanitized error codes reach CI logs.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.appstoreconnect.apple.com/v1"
LOCALES = ("zh-Hans", "en-US")


class APIError(RuntimeError):
    def __init__(self, status: int, codes: str = ""):
        super().__init__(f"App Store Connect HTTP {status} ({codes or 'no error code'})")
        self.status = status


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward a bearer token to another host through a redirect.
        return None


class Client:
    def __init__(self, key_id: str, issuer: str, private_key: str):
        self.key_id, self.issuer, self.private_key = key_id, issuer, private_key
        self.opener = urllib.request.build_opener(NoRedirect)

    def token(self) -> str:
        import jwt
        now = int(time.time())
        return jwt.encode(
            {"iss": self.issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            self.private_key, algorithm="ES256", headers={"kid": self.key_id, "typ": "JWT"},
        )

    def request(self, method: str, path: str, payload=None, params=None):
        url = path if path.startswith("https://") else BASE + path
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com":
            raise ValueError("Refusing an unexpected API pagination host.")
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, method=method, headers={
            "Authorization": "Bearer " + self.token(), "Content-Type": "application/json",
        }, data=json.dumps(payload).encode() if payload is not None else None)
        try:
            with self.opener.open(req, timeout=30) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            try:
                body = json.loads(error.read())
                codes = ",".join(
                    re.sub(r"[^A-Za-z0-9_.-]", "", str(item.get("code", "")))[:100]
                    for item in body.get("errors", [])[:5]
                )
            except (ValueError, TypeError):
                codes = ""
            raise APIError(error.code, codes) from None

    def all(self, path: str):
        values = []
        for _ in range(100):
            result = self.request("GET", path)
            values.extend(result.get("data", []))
            path = result.get("links", {}).get("next")
            if not path:
                return values
        raise ValueError("API pagination exceeded the expected limit.")


def clean_notes(text: str) -> str:
    # Preserve translated text and ordinary punctuation. Strip control/format
    # characters, angle brackets, emoji presentation selectors and emoji planes.
    text = unicodedata.normalize("NFC", text).strip()
    text = "".join(c for c in text if c not in "<>" and c not in "\ufe0e\ufe0f"
                   and not (0x1F000 <= ord(c) <= 0x1FAFF)
                   and (c in "\n\t" or not unicodedata.category(c).startswith("C")))
    if not text or len(text) > 4000:
        raise ValueError("Each localized whatToTest must contain 1–4000 characters.")
    return text


def build_identity(build, included) -> tuple[str, str]:
    relation = build.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
    versions = {item["id"]: item.get("attributes", {}).get("version", "")
                for item in included if item.get("type") == "preReleaseVersions"}
    return versions.get(relation.get("id"), ""), build.get("attributes", {}).get("version", "")


def wait_for_build(client, app_id, version, build_number, timeout, interval,
                   clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + timeout
    pinned_id = None
    while True:
        try:
            if pinned_id:
                result = client.request("GET", f"/builds/{pinned_id}", params={"include": "preReleaseVersion,app"})
                builds = [result["data"]]
            else:
                params = {"filter[app]": app_id, "filter[preReleaseVersion.platform]": "IOS",
                          "sort": "-uploadedDate", "limit": "2", "include": "preReleaseVersion,app"}
                if version:
                    params["filter[preReleaseVersion.version]"] = version
                    params["filter[version]"] = build_number
                result = client.request("GET", "/builds", params=params)
                builds = result.get("data", [])
            if builds:
                build = builds[0]
                actual_version, actual_number = build_identity(build, result.get("included", []))
                related_app = build.get("relationships", {}).get("app", {}).get("data", {})
                if related_app.get("id") != app_id:
                    raise ValueError("Build app does not match ASC_APP_ID.")
                if not actual_version or (version and (actual_version, actual_number) != (version, build_number)):
                    raise ValueError("Build identity differs from the requested version/build pair.")
                pinned_id = build["id"]
                state = build.get("attributes", {}).get("processingState")
                if state == "VALID":
                    return build, actual_version, actual_number
                if state in ("FAILED", "INVALID"):
                    raise ValueError(f"Selected build processing state is {state}; retry after correcting the upload.")
        except APIError as error:
            if error.status not in (404, 409, 429, 500, 502, 503, 504):
                raise
        if clock() >= deadline:
            raise TimeoutError("Build is not ready in App Store Connect; rerun with the same version/build pair.")
        sleep(min(interval, max(0, deadline - clock())))


def fill_localizations(client, build_id, notes):
    current = {item["attributes"]["locale"]: item for item in
               client.all(f"/builds/{build_id}/betaBuildLocalizations?limit=200")}
    for locale, text in notes.items():
        existing = current.get(locale)
        if existing and existing["attributes"].get("whatToTest") == text:
            print(f"{locale}: already current")
        elif existing:
            client.request("PATCH", f"/betaBuildLocalizations/{existing['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": existing["id"], "attributes": {"whatToTest": text},
            }})
            print(f"{locale}: updated")
        else:
            client.request("POST", "/betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatToTest": text},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }})
            print(f"{locale}: created")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes-dir", type=Path, default=Path(".github/testflight-notes"))
    parser.add_argument("--marketing-version")
    parser.add_argument("--build-number")
    parser.add_argument("--latest", action="store_true", help="Explicitly select and pin the latest uploaded iOS build.")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--poll-interval", type=int, default=30)
    parser.add_argument("--soft-fail", action="store_true", help="Report a deferred repair without failing distribution.")
    args = parser.parse_args(argv)
    try:
        if bool(args.marketing_version) != bool(args.build_number) or (args.latest == bool(args.build_number)):
            raise ValueError("Choose --latest OR both --marketing-version and --build-number.")
        if args.timeout < 0 or args.poll_interval <= 0:
            raise ValueError("Timeout must be nonnegative and poll interval positive.")
        notes = {locale: clean_notes((args.notes_dir / f"what-to-test.{locale}.txt").read_text(encoding="utf-8"))
                 for locale in LOCALES}
        required = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "ASC_APP_ID")
        missing = [key for key in required if not os.environ.get(key)]
        if missing:
            raise ValueError("Missing environment variables: " + ", ".join(missing))
        client = Client(*(os.environ[key] for key in required[:3]))
        build, version, number = wait_for_build(client, os.environ["ASC_APP_ID"],
                                                args.marketing_version, args.build_number,
                                                args.timeout, args.poll_interval)
        print(f"Selected iOS build: {version} ({number})")
        # Localization endpoints may lag VALID. Re-read before every retry so
        # a partial successful update/create remains idempotent.
        deadline = time.monotonic() + args.timeout
        while True:
            try:
                fill_localizations(client, build["id"], notes)
                break
            except APIError as error:
                if error.status not in (404, 409, 429, 500, 502, 503, 504) or time.monotonic() >= deadline:
                    raise
                time.sleep(min(args.poll_interval, max(0, deadline - time.monotonic())))
        print("TestFlight notes saved.")
        return 0
    except Exception as error:
        # Do not print arbitrary HTTP response bodies, JWTs, key parser errors,
        # local paths, or exception representations containing credentials.
        message = str(error) if isinstance(error, (ValueError, TimeoutError, APIError)) else type(error).__name__
        print(f"{'warning' if args.soft_fail else 'error'}: TestFlight notes deferred: {message}", file=sys.stderr)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as out:
                out.write("\n⚠️ TestFlight notes were not filled. Distribution is unaffected. "
                          "Check this job's warning and rerun for the intended version/build pair.\n")
        return 0 if args.soft_fail else 1


if __name__ == "__main__":
    sys.exit(main())
