"""Regression cases for semantic keys and formatted localization values."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validator", ROOT / "Scripts/validate-localizations.py"
)
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class LocalizationValidationTests(unittest.TestCase):
    def validate_entry(self, key, chinese, english):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Pitchee.xcodeproj").mkdir()
            (root / "Pitchee.xcodeproj/project.pbxproj").write_text(
                'knownRegions = ("zh-Hans", en, Base);'
            )
            (root / "Resources").mkdir()
            entry = {
                "localizations": {
                    locale: {"stringUnit": {"state": "translated", "value": value}}
                    for locale, value in [("zh-Hans", chinese), ("en", english)]
                }
            }
            (root / "Resources/Localizable.xcstrings").write_text(json.dumps({
                "sourceLanguage": "zh-Hans", "strings": {key: entry}, "version": "1.0"
            }))
            output = io.StringIO()
            with patch.object(validator, "ROOT", root), \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                status = validator.validate()
            return status, output.getvalue()

    def test_semantic_key_preserves_default_value_arguments(self):
        status, _ = self.validate_entry(
            "voiceLibrary.article.readingTime", "约 %lld 分钟阅读", "About %1$lld min read"
        )
        self.assertEqual(status, 0)

    def test_dropped_default_value_argument_is_rejected(self):
        status, output = self.validate_entry(
            "voiceLibrary.article.readingTime", "约 %lld 分钟阅读", "About one minute"
        )
        self.assertEqual(status, 1)
        self.assertIn("format arguments differ", output)

    def test_displaying_a_key_is_rejected(self):
        status, output = self.validate_entry(
            "recording.timeline.pitchAxis", "音高", "recording.timeline.pitchAxis"
        )
        self.assertEqual(status, 1)
        self.assertIn("localization key is displayed as text", output)

    def test_dynamic_key_template_is_rejected(self):
        status, output = self.validate_entry(
            "practice.metric.%@", "practice.metric.%@", "practice.metric.%@"
        )
        self.assertEqual(status, 1)
        self.assertIn("interpolated key name", output)


if __name__ == "__main__":
    unittest.main()
