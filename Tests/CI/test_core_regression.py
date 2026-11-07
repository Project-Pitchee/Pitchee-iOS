import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest
import urllib.request
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts/ci"))
import core_regression as regression
import detect_submodule_changes as detection
import private_core_fixtures as private


def fixture(directory):
    path = directory / "voice.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\0\0" * 160)
    sample = {"file": path.name, "bytes": path.stat().st_size,
              "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    manifest = {"schemaVersion": 1, "samples": [sample]}
    (directory / "manifest.json").write_text(json.dumps(manifest))
    return manifest


class ExactComparisonTests(unittest.TestCase):
    def test_smallest_nonzero_change_is_preserved(self):
        difference = regression.differences({"score": 1.0}, {"score": 1.0000000000000002})
        self.assertEqual(len(difference), 1)
        self.assertGreater(difference[0]["delta"], 0)

    def test_removed_hnr_cannot_disappear_in_comparison(self):
        difference = regression.differences({"voice_quality": {"hnr_db": 15.0}}, {})
        self.assertEqual(difference[0]["field"], "$.voice_quality")
        self.assertEqual(difference[0]["new"], {"missing": True})

    def test_null_and_boolean_are_not_numeric_zero(self):
        difference = regression.differences([None, False], [0, 0])
        self.assertEqual(len(difference), 2)
        self.assertTrue(all(row["delta"] is None for row in difference))

    def test_long_tier_uses_both_core_speech_durations(self):
        manifest = {"samples": [{"file": "long.wav"}], "minimumLongSpeechSeconds": 5}
        def result(seconds):
            return {"full": {"long.wav": {"feminization": {"vad": {"speech_seconds": seconds}}}}}
        rows, enough = regression.coverage(manifest, result(8), result(4.9))
        self.assertFalse(enough)
        self.assertFalse(rows[0]["includedInLongTier"])
        self.assertTrue(regression.coverage(manifest, result(5), result(5))[1])


class PrivateFixtureTests(unittest.TestCase):
    def test_private_redirect_rejects_http_before_following(self):
        request = urllib.request.Request("https://storage.example.invalid/signed")
        handler = private.HTTPSRedirectHandler()
        with self.assertRaisesRegex(ValueError, "remain HTTPS"):
            handler.redirect_request(request, None, 302, "Found", {}, "http://other.example.invalid/clip")

    def test_artifact_directory_cannot_overlap_private_fixture_tree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp).resolve()
            for fixtures, output in ((root, root / "out"), (root / "audio", root), (root, root)):
                with self.assertRaisesRegex(ValueError, "must not overlap"):
                    regression.validate_output_separation(fixtures, None, output)
            with self.assertRaisesRegex(ValueError, "manifest"):
                regression.validate_output_separation(root / "audio", root / "out/manifest.json", root / "out")
            regression.validate_output_separation(root / "audio", None, root / "out")

    def test_float_wav_is_validated_as_float_not_reinterpreted_as_pcm16(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "float.wav"
            payload = struct.pack("<ff", .25, -.25)
            fmt = struct.pack("<HHIIHH", 3, 1, 16000, 64000, 4, 32)
            path.write_bytes(b"RIFF" + struct.pack("<I", 36 + len(payload)) + b"WAVEfmt "
                             + struct.pack("<I", 16) + fmt + b"data" + struct.pack("<I", len(payload)) + payload)
            before = path.read_bytes()
            regression.validate_wav(path)
            self.assertEqual(path.read_bytes(), before)

    def test_missing_configuration_fails(self):
        with self.assertRaisesRegex(ValueError, "not configured"):
            regression.validate_fixtures(None)

    def test_missing_and_changed_audio_fail_loudly(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            fixture(directory)
            self.assertEqual(len(regression.validate_fixtures(directory)["samples"]), 1)
            with (directory / "voice.wav").open("ab") as stream:
                stream.write(b"changed")
            with self.assertRaisesRegex(ValueError, "mismatch"):
                regression.validate_fixtures(directory)
            (directory / "voice.wav").unlink()
            with self.assertRaisesRegex(ValueError, "differ"):
                regression.validate_fixtures(directory)

    def test_zip_path_traversal_cannot_escape_temp(self):
        with tempfile.TemporaryDirectory() as temp:
            data = io.BytesIO()
            with zipfile.ZipFile(data, "w") as archive:
                archive.writestr("../escape.wav", b"bad")
            with self.assertRaisesRegex(ValueError, "flat"):
                private.unpack(data.getvalue(), Path(temp) / "private")
            self.assertFalse((Path(temp) / "escape.wav").exists())

    def test_failed_bundle_removes_private_files(self):
        with tempfile.TemporaryDirectory() as temp:
            data = io.BytesIO()
            with zipfile.ZipFile(data, "w") as archive:
                archive.writestr("manifest.json", '{"schemaVersion":1,"samples":[]}')
            target = Path(temp) / "private"
            with self.assertRaises(ValueError):
                private.unpack(data.getvalue(), target)
            self.assertFalse(target.exists())


class GitlinkTests(unittest.TestCase):
    def test_target_branch_advance_does_not_invent_a_bump(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
            git("init", "-b", "main")
            git("config", "user.email", "test@example.invalid")
            git("config", "user.name", "CI fixture")
            for name, path in detection.PATHS.items():
                git("update-index", "--add", "--cacheinfo", "160000", "a" * 40, path)
            git("commit", "-m", "initial")
            git("checkout", "-b", "feature")
            (root / "app.txt").write_text("app only")
            git("add", "app.txt")
            git("commit", "-m", "app change")
            head = git("rev-parse", "HEAD")
            git("checkout", "main")
            git("update-index", "--cacheinfo", "160000", "b" * 40, detection.PATHS["core"])
            git("commit", "-m", "main bumps core")
            base = git("rev-parse", "HEAD")
            result = detection.detect(base, head, root)
            self.assertEqual(result["core_changed"], "false")
            git("checkout", "feature")
            git("update-index", "--cacheinfo", "160000", "c" * 40, detection.PATHS["core"])
            git("commit", "-m", "feature bumps core")
            result = detection.detect(base, git("rev-parse", "HEAD"), root)
            self.assertEqual(result["core_old"], "a" * 40)
            self.assertEqual(result["core_new"], "c" * 40)
            self.assertEqual(result["core_changed"], "true")


if __name__ == "__main__":
    unittest.main()
