import json
from pathlib import Path
import struct
import tempfile
import unittest

from capture import SCREENS, export_images
from matrix import matrix


class CaptureTests(unittest.TestCase):
    def fixture(self, directory, screens=SCREENS, dimensions=(1320, 2868)):
        entries = []
        for screen in screens:
            name = screen + ".png"
            (directory / name).write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + struct.pack(">II", *dimensions))
            entries.append({"suggestedHumanReadableName": name, "exportedFileName": name,
                            "isAssociatedWithFailure": False})
        (directory / "manifest.json").write_text(json.dumps([{"attachments": entries}]))

    def test_exports_only_complete_correct_size_set(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            self.fixture(directory)
            export_images(directory, directory / "output", "6.9")
            self.assertEqual(sorted(path.stem for path in (directory / "output").iterdir()), SCREENS)

    def test_missing_screen_cannot_pass_with_incidental_screenshot(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            self.fixture(directory, SCREENS[:-1] + ["Screenshot"])
            with self.assertRaisesRegex(ValueError, "Missing named screenshots"):
                export_images(directory, directory / "output", "6.9")

    def test_wrong_slot_dimensions_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            self.fixture(directory, dimensions=(1170, 2532))
            with self.assertRaisesRegex(ValueError, "Wrong dimensions"):
                export_images(directory, directory / "output", "6.9")

    def test_matrix_rejects_unknown_language_and_injection(self):
        for languages in ["en en", "unknown", "en; echo injected", ""]:
            with self.assertRaises(ValueError):
                matrix(languages, "light")
        self.assertEqual(matrix("zh-Hans,en", "light dark")["language"], ["zh-Hans", "en"])
        self.assertGreaterEqual(len(matrix("all", "light")["language"]), 29)


if __name__ == "__main__":
    unittest.main()
