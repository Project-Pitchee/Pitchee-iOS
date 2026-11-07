import importlib.util
import os
from pathlib import Path
import plistlib
import re
import subprocess
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cloud = load('cloud_version', 'Scripts/ci/cloud-version.py')
notes = load('testflight_notes', 'Scripts/fill-testflight-notes.py')


def build(identifier, state='VALID', number='15'):
    return {'id': identifier, 'attributes': {'version': number, 'processingState': state},
            'relationships': {'preReleaseVersion': {'data': {'id': 'release'}},
                              'app': {'data': {'id': 'app'}}}}


INCLUDED = [{'id': 'release', 'type': 'preReleaseVersions', 'attributes': {'version': '1.2.0'}}]


class FakeClient:
    def __init__(self, responses=(), localizations=()):
        self.responses = iter(responses)
        self.localizations = localizations
        self.calls = []

    def request(self, method, path, payload=None, params=None):
        self.calls.append((method, path, payload, params))
        if method == 'GET':
            return next(self.responses)
        return {}

    def all(self, path):
        return self.localizations


class CloudVersionTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory)
        for relative in ('Config/Version.xcconfig', 'Pitchee.xcodeproj/project.pbxproj'):
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        return root

    def test_tag_and_cloud_build_update_the_single_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            project = root / 'Pitchee.xcodeproj/project.pbxproj'
            before = project.read_bytes()
            with patch.dict(os.environ, {'CI_WORKFLOW': 'Release', 'CI_TAG': 'v0.0.1',
                                         'CI_BUILD_NUMBER': '45', 'CI_XCODEBUILD_ACTION': 'archive'}, clear=True):
                self.assertEqual(cloud.main(root), 0)
            from version_config import validate_project
            settings = validate_project(root)
            self.assertEqual(settings['MARKETING_VERSION'], '0.0.1')
            self.assertEqual(settings['CURRENT_PROJECT_VERSION'], '45')
            self.assertEqual(project.read_bytes(), before)

    def test_strict_tags(self):
        self.assertEqual(cloud.version_from_tag('v12.4.0'), '12.4.0')
        for tag in ('v1.2', 'v1.2.3-beta', 'v01.2.3', 'v1.2.3\n', 'v1.2.3;echo bad', 'docs'):
            self.assertIsNone(cloud.version_from_tag(tag), tag)

    def test_invalid_release_fails_before_mutation(self):
        with patch.dict(os.environ, {'CI_WORKFLOW': 'Release', 'CI_TAG': 'v1.2-beta'}, clear=True), \
                patch.object(cloud, 'sync_versions') as sync:
            with self.assertRaises(ValueError):
                cloud.main()
            sync.assert_not_called()

    def test_source_update_failure_is_fatal(self):
        with patch.dict(os.environ, {'CI_WORKFLOW': 'Release', 'CI_TAG': 'v1.2.0',
                                     'CI_BUILD_NUMBER': '45'}, clear=True), \
                patch.object(cloud, 'sync_versions', side_effect=OSError('read-only config')):
            with self.assertRaises(OSError):
                cloud.main()

    def test_main_build_only_copies_cloud_counter(self):
        from version_config import read_settings, validate_project
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            before = read_settings((root / 'Config/Version.xcconfig').read_text())
            with patch.dict(os.environ, {'CI_WORKFLOW': 'Build & Test', 'CI_TAG': '',
                                         'CI_BUILD_NUMBER': '45'}, clear=True):
                self.assertEqual(cloud.main(root), 0)
            after = validate_project(root)
            self.assertEqual(after['MARKETING_VERSION'], before['MARKETING_VERSION'])
            self.assertEqual(after['CURRENT_PROJECT_VERSION'], '45')

    def test_internal_archive_rejects_tagged_commit(self):
        with patch.dict(os.environ, {'CI_WORKFLOW': 'TestFlight Internal', 'CI_TAG': '', 'CI_BRANCH': 'main',
                                     'CI_BUILD_NUMBER': '45'}, clear=True), \
                patch.object(cloud.subprocess, 'run'), \
                patch.object(cloud.subprocess, 'check_output', return_value='v1.2.0\n'):
            with self.assertRaisesRegex(ValueError, 'release tag'):
                cloud.main()

    def test_target_override_is_rejected_without_changing_version_source(self):
        from version_config import validate_project
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            config = root / 'Config/Version.xcconfig'
            before = config.read_bytes()
            project = root / 'Pitchee.xcodeproj/project.pbxproj'
            text = project.read_text()
            offset = text.index('B76D28D52FDC49E5009E536B /* Debug */ = {')
            offset = text.index('buildSettings = {', offset) + len('buildSettings = {')
            project.write_text(text[:offset] + '\nMARKETING_VERSION = 9.9;' + text[offset:])
            with self.assertRaisesRegex(ValueError, 'Independent version overrides'):
                validate_project(root)
            with self.assertRaisesRegex(ValueError, 'Independent version overrides'):
                cloud.sync_versions(root, '45', '0.0.1')
            self.assertEqual(config.read_bytes(), before)

    def test_literal_generated_plist_field_is_rejected(self):
        from version_config import validate_project
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            config = root / 'Config/Version.xcconfig'
            config.write_text(config.read_text().replace('$(CURRENT_PROJECT_VERSION)', '1'))
            with self.assertRaisesRegex(ValueError, 'Info.plist version keys'):
                validate_project(root)

    def test_conditional_target_overrides_are_rejected(self):
        from version_config import validate_project
        for key in ('MARKETING_VERSION[sdk=iphoneos*]', 'INFOPLIST_KEY_CFBundleVersion[config=Release]'):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                root = self.fixture(directory)
                project = root / 'Pitchee.xcodeproj/project.pbxproj'
                text = project.read_text()
                offset = text.index('B76D28D52FDC49E5009E536B /* Debug */ = {')
                offset = text.index('buildSettings = {', offset) + len('buildSettings = {')
                project.write_text(text[:offset] + f'\n"{key}" = 99;' + text[offset:])
                with self.assertRaisesRegex(ValueError, 'Independent version overrides'):
                    validate_project(root)

    def test_conditional_literal_info_plist_is_rejected(self):
        from version_config import validate_project
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            project = root / 'Pitchee.xcodeproj/project.pbxproj'
            text = project.read_text()
            offset = text.index('B76D28D52FDC49E5009E536B /* Debug */ = {')
            offset = text.index('buildSettings = {', offset) + len('buildSettings = {')
            project.write_text(text[:offset] + '\n"INFOPLIST_FILE[sdk=iphoneos*]" = Fixture-Info.plist;' + text[offset:])
            (root / 'Fixture-Info.plist').write_bytes(plistlib.dumps({
                'CFBundleShortVersionString': '9.9', 'CFBundleVersion': '1'}))
            with self.assertRaisesRegex(ValueError, 'Literal or missing Info.plist version'):
                validate_project(root)

    def test_configuration_cannot_disconnect_from_shared_source(self):
        from version_config import validate_project
        with tempfile.TemporaryDirectory() as directory:
            root = self.fixture(directory)
            project = root / 'Pitchee.xcodeproj/project.pbxproj'
            project.write_text(re.sub(r'\s*baseConfigurationReference = [^;]+;', '', project.read_text(), count=1))
            with self.assertRaisesRegex(ValueError, 'must inherit'):
                validate_project(root)

    def test_repository_has_one_inherited_version_source(self):
        from version_config import validate_project
        self.assertTrue(validate_project(ROOT)['MARKETING_VERSION'])

    def test_test_without_building_needs_no_checkout(self):
        environment = {'CI_BUILD_NUMBER': '45', 'CI_XCODEBUILD_ACTION': 'test-without-building'}
        with patch.dict(os.environ, environment, clear=True), patch.object(cloud, 'sync_versions') as sync:
            self.assertEqual(cloud.main(Path('/does-not-exist')), 0)
            sync.assert_not_called()
        completed = subprocess.run(['/bin/sh', str(ROOT / 'ci_scripts/ci_pre_xcodebuild.sh')],
                                   env=environment, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        for number in ('', '0', '01', '-1', '1;bad'):
            completed = subprocess.run(['/bin/sh', str(ROOT / 'ci_scripts/ci_pre_xcodebuild.sh')],
                                       env={**environment, 'CI_BUILD_NUMBER': number}, capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0, number)


class TestFlightTests(unittest.TestCase):
    def test_latest_processing_build_is_pinned_not_older_valid(self):
        client = FakeClient([
            {'data': [build('new', 'PROCESSING'), build('old')], 'included': INCLUDED},
            {'data': build('new'), 'included': INCLUDED},
        ])
        result = notes.wait_for_build(client, 'app', None, None, 10, 1, clock=lambda: 0, sleep=lambda _: None)
        self.assertEqual(result[0]['id'], 'new')
        self.assertEqual(client.calls[1][1], '/builds/new')

    def test_exact_selection_checks_response_identity(self):
        client = FakeClient([{'data': [build('wrong', number='16')], 'included': INCLUDED}])
        with self.assertRaisesRegex(ValueError, 'identity'):
            notes.wait_for_build(client, 'app', '1.2.0', '15', 0, 1)
        self.assertEqual(client.calls[0][3]['filter[version]'], '15')

    def test_missing_build_times_out_loudly(self):
        client = FakeClient([{'data': []}])
        with self.assertRaises(TimeoutError):
            notes.wait_for_build(client, 'app', '1.2.0', '15', 0, 1)

    def test_existing_locale_patch_missing_locale_create(self):
        client = FakeClient(localizations=[{'id': 'zh', 'attributes': {'locale': 'zh-Hans', 'whatToTest': 'old'}}])
        notes.fill_localizations(client, 'build-id', {'zh-Hans': '中文', 'en-US': 'English'})
        self.assertEqual([(c[0], c[1]) for c in client.calls], [
            ('PATCH', '/betaBuildLocalizations/zh'), ('POST', '/betaBuildLocalizations')])
        payload = client.calls[1][2]['data']
        self.assertEqual(payload['relationships']['build']['data']['id'], 'build-id')
        self.assertEqual(payload['attributes']['whatToTest'], 'English')

    def test_identical_notes_cause_no_write(self):
        client = FakeClient(localizations=[{'id': 'en', 'attributes': {'locale': 'en-US', 'whatToTest': 'same'}}])
        notes.fill_localizations(client, 'id', {'en-US': 'same'})
        self.assertEqual(client.calls, [])

    def test_clean_notes_preserves_languages_and_normalizes(self):
        self.assertEqual(notes.clean_notes('  中\u200b文 <e\u0301> 🎤\nEnglish  '), '中文 é \nEnglish')
        for text in ('', 'x' * 4001):
            with self.assertRaises(ValueError):
                notes.clean_notes(text)

    def test_missing_credentials_report_soft_failure_without_network(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(notes.Client, 'request') as request:
            self.assertEqual(notes.main(['--latest', '--notes-dir', str(ROOT / '.github/testflight-notes'), '--soft-fail']), 0)
            self.assertEqual(notes.main(['--latest', '--notes-dir', str(ROOT / '.github/testflight-notes')]), 1)
            request.assert_not_called()


if __name__ == '__main__':
    unittest.main()
