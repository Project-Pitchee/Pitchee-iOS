import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('built_version', ROOT / 'ci_scripts/verify-built-version.py')
version = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(version)


def reader(path, key):
    with path.open('rb') as stream:
        values = plistlib.load(stream)
    if key not in values:
        raise version.VerificationError(f'Missing {key}')
    return str(values[key])


def app_at(path, identifier='example.app', short='0.0.1', build='45'):
    path.mkdir(parents=True)
    with (path / 'Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleShortVersionString': short,
                      'CFBundleVersion': build}, stream)
    return path


class BuiltVersionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='pitchee-version-check-')
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        self.config = self.root / 'Version.xcconfig'
        self.config.write_text('MARKETING_VERSION = 1.0\nCURRENT_PROJECT_VERSION = 1\n')

    def test_tag_is_product_marketing_source(self):
        self.assertEqual(version.expected_version('v0.0.1', self.config, 'Release'), '0.0.1')

    def test_branch_and_nonversion_tag_keep_project_version(self):
        for tag in ('', 'notes-2026', 'v0.0.1-test'):
            self.assertEqual(version.expected_version(tag, self.config), '1.0')

    def test_invalid_release_tag_cannot_use_old_project_version(self):
        with self.assertRaises(version.VerificationError):
            version.expected_version('v0.0.1-test', self.config, 'Release')

    def test_missing_and_duplicate_shared_version_fail(self):
        self.config.write_text('CURRENT_PROJECT_VERSION = 1\n')
        with self.assertRaises(version.VerificationError):
            version.expected_version('', self.config)
        self.config.write_text('MARKETING_VERSION = 1.0\nMARKETING_VERSION = 2.0\n')
        with self.assertRaises(version.VerificationError):
            version.expected_version('', self.config)

    def test_archive_never_falls_back_to_derived_products(self):
        derived = self.root / 'derived'
        (derived / 'Build/Products').mkdir(parents=True)
        with self.assertRaisesRegex(version.VerificationError, 'CI_ARCHIVE_PATH'):
            version.product_root('archive', {'CI_DERIVED_DATA_PATH': str(derived)})
        with self.assertRaisesRegex(version.VerificationError, 'does not exist'):
            version.product_root('archive', {'CI_ARCHIVE_PATH': str(self.root / 'missing.xcarchive'),
                                              'CI_DERIVED_DATA_PATH': str(derived)})

    def test_test_without_building_uses_declared_test_products(self):
        products = self.root / 'Pitchee.xctestproducts'
        products.mkdir()
        self.assertEqual(version.product_root('test-without-building', {'CI_TEST_PRODUCTS_PATH': str(products)}), products.resolve())
        with self.assertRaisesRegex(version.VerificationError, 'CI_TEST_PRODUCTS_PATH'):
            version.product_root('test-without-building', {'CI_DERIVED_DATA_PATH': str(self.root)})

    def test_declared_test_products_missing_does_not_use_stale_derived(self):
        (self.root / 'Build/Products').mkdir(parents=True)
        with self.assertRaisesRegex(version.VerificationError, 'does not exist'):
            version.product_root('build-for-testing', {'CI_TEST_PRODUCTS_PATH': str(self.root / 'absent'),
                                                       'CI_DERIVED_DATA_PATH': str(self.root)})

    def test_discovery_matches_bundle_id_and_excludes_runners(self):
        app = app_at(self.root / 'Debug-iphonesimulator/Pitchee.app')
        app_at(self.root / 'Debug-iphonesimulator/PitcheeUITests-Runner.app', 'example.tests.xctrunner', build='1')
        app_at(app / 'AppClips/Clip.app', 'example.app.Clip')
        self.assertEqual(version.main_apps(self.root, 'example.app', reader), [app])
        with self.assertRaisesRegex(version.VerificationError, 'No built App'):
            version.main_apps(self.root, 'unrelated', reader)

    def test_all_cached_matching_apps_are_checked(self):
        app_at(self.root / 'Debug/Pitchee.app')
        app_at(self.root / 'Release/Pitchee.app', build='44')
        apps = version.main_apps(self.root, 'example.app', reader)
        with self.assertRaisesRegex(version.VerificationError, "CFBundleVersion expected '45', found '44'"):
            version.verify(apps, 'example.app', '0.0.1', '45', reader)

    def test_actual_app_and_embedded_products_match(self):
        app = app_at(self.root / 'Pitchee.app')
        app_at(app / 'PlugIns/Widget.appex', 'example.app.Widget')
        app_at(app / 'AppClips/Clip.app', 'example.app.Clip')
        app_at(app / 'Frameworks/Foo.framework/Nested.app', 'vendor.framework', build='999')
        self.assertEqual(len(version.verify([app], 'example.app', '0.0.1', '45', reader)), 3)

    def test_embedded_target_with_literal_old_version_is_fatal(self):
        app = app_at(self.root / 'Pitchee.app')
        app_at(app / 'PlugIns/Widget.appex', 'example.app.Widget', short='0.0.0')
        with self.assertRaisesRegex(version.VerificationError, "CFBundleShortVersionString expected '0.0.1', found '0.0.0'"):
            version.verify([app], 'example.app', '0.0.1', '45', reader)

    def test_empty_apps_and_wrong_root_id_fail(self):
        with self.assertRaises(version.VerificationError):
            version.verify([], 'example.app', '0.0.1', '45', reader)
        with self.assertRaisesRegex(version.VerificationError, 'bundle ID'):
            version.verify([app_at(self.root / 'Wrong.app', 'wrong')], 'example.app', '0.0.1', '45', reader)

    def test_symlinked_shipping_bundle_cannot_escape_artifact(self):
        app = app_at(self.root / 'Pitchee.app')
        other = app_at(self.root / 'Other.appex', 'example.app.Other')
        (app / 'PlugIns').mkdir()
        (app / 'PlugIns/Other.appex').symlink_to(other, target_is_directory=True)
        with self.assertRaisesRegex(version.VerificationError, 'symlink'):
            version.verify([app], 'example.app', '0.0.1', '45', reader)

    def test_failed_xcodebuild_does_not_accept_stale_app(self):
        with patch.object(version, 'verify') as verify:
            self.assertEqual(version.main(['--xcodebuild-exit-code', '65']), 1)
            verify.assert_not_called()

    def test_linked_plugin_container_cannot_hide_old_extension(self):
        app = app_at(self.root / 'Pitchee.app')
        outside = self.root / 'outside'
        app_at(outside / 'Widget.appex', 'example.app.Widget', short='0.0.0', build='44')
        (app / 'PlugIns').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(version.VerificationError, 'container is a symlink'):
            version.verify([app], 'example.app', '0.0.1', '45', reader)

    @unittest.skipUnless(Path(version.PLIST_BUDDY).is_file(), 'Apple PlistBuddy integration requires macOS')
    def test_real_plist_reader_does_not_normalize_whitespace_or_number_type(self):
        app = app_at(self.root / 'Pitchee.app', short=' 0.0.1 ', build=' 45 ')
        with self.assertRaisesRegex(version.VerificationError, "found ' 45 '"):
            version.verify([app], 'example.app', '0.0.1', '45')
        with (app / 'Info.plist').open('rb') as stream:
            data = plistlib.load(stream)
        data['CFBundleShortVersionString'] = '0.0.1'
        data['CFBundleVersion'] = 45
        with (app / 'Info.plist').open('wb') as stream:
            plistlib.dump(data, stream)
        with self.assertRaisesRegex(version.VerificationError, 'must be a nonempty plist String'):
            version.verify([app], 'example.app', '0.0.1', '45')

    @unittest.skipUnless(Path(version.PLIST_BUDDY).is_file(), 'Apple PlistBuddy integration requires macOS')
    def test_actual_post_hook_runs_without_checkout_and_blocks_mismatch(self):
        scripts = self.root / 'ci_scripts'
        scripts.mkdir()
        for name in ('ci_post_xcodebuild.sh', 'verify-built-version.py'):
            shutil.copy2(ROOT / 'ci_scripts' / name, scripts / name)
        shutil.copy2(self.config, scripts / 'Version.xcconfig')
        products = self.root / 'Pitchee.xctestproducts'
        app = app_at(products / 'Products/Debug-iphonesimulator/Pitchee.app', short='1.0')
        environment = {key: value for key, value in os.environ.items() if not key.startswith('CI_')}
        environment.update(CI_XCODEBUILD_ACTION='test-without-building', CI_XCODEBUILD_EXIT_CODE='0',
                           CI_TEST_PRODUCTS_PATH=str(products), CI_BUNDLE_ID='example.app', CI_BUILD_NUMBER='45',
                           CI_PRIMARY_REPOSITORY_PATH=str(self.root / 'no-checkout'))
        result = subprocess.run(['sh', str(scripts / 'ci_post_xcodebuild.sh')], env=environment,
                                cwd=scripts, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with (app / 'Info.plist').open('rb') as stream:
            data = plistlib.load(stream)
        data['CFBundleVersion'] = '44'
        with (app / 'Info.plist').open('wb') as stream:
            plistlib.dump(data, stream)
        failed = subprocess.run(['sh', str(scripts / 'ci_post_xcodebuild.sh')], env=environment,
                                cwd=scripts, text=True, capture_output=True)
        self.assertEqual(failed.returncode, 1)
        self.assertIn("CFBundleVersion expected '45', found '44'", failed.stderr)


if __name__ == '__main__':
    unittest.main()
