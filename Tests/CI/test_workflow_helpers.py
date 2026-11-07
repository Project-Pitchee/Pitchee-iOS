import csv
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'Scripts/ci' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


suite = load('regression-suite')
size = load('app-size-trend')
restore = load('restore-size-history')
release = load('release-validation')
environment = load('simulator-environment')
simulator = load('regression-simulator')


class RegressionSuiteTests(unittest.TestCase):
    def test_narrow_failure_classification(self):
        self.assertEqual(suite.classify(0, ''), 'PASS')
        self.assertEqual(suite.classify(78, 'dependency unavailable'), 'FAIL — environment')
        self.assertEqual(suite.classify(1, 'xcrun: error: invalid active developer path'), 'FAIL — environment')
        self.assertEqual(suite.classify(1, "fatal error: 'project-header.h' file not found"), 'FAIL — code regression candidate')
        self.assertEqual(suite.classify(124, '', True), 'TIMEOUT — review required')

    def test_suite_continues_after_failure_and_discovers_every_script(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': ''}):
            root = Path(temp)
            (root / 'Scripts').mkdir()
            (root / 'Scripts/test-a.sh').write_text('exit 2\n')
            (root / 'Scripts/test-b.sh').write_text('echo later-script-ran\n')
            results = suite.run_suite(root, root / 'output', 2)
            self.assertEqual([r['exit_code'] for r in results], [2, 0])
            self.assertIn('later-script-ran', (root / 'output/test-b.sh.log').read_text())

    def test_timeout_does_not_prevent_later_scripts(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': ''}):
            root = Path(temp)
            (root / 'Scripts').mkdir()
            (root / 'Scripts/test-a.sh').write_text('sleep 20\n')
            (root / 'Scripts/test-b.sh').write_text('exit 0\n')
            results = suite.run_suite(root, root / 'output', 1)
            self.assertEqual(results[0]['exit_code'], 124)
            self.assertEqual(results[1]['result'], 'PASS')

    def test_missing_suite_is_loud(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(RuntimeError, 'No Scripts'):
                suite.run_suite(Path(temp), Path(temp) / 'output', 1)

    def test_simulator_selection_uses_available_iphone_and_latest_runtime(self):
        data = {'devices': {
            'com.apple.CoreSimulator.SimRuntime.iOS-26-5': [{'isAvailable': True, 'deviceTypeIdentifier': 'iPhone-16'}],
            'com.apple.CoreSimulator.SimRuntime.iOS-27-2': [{'isAvailable': True, 'deviceTypeIdentifier': 'iPhone-17'}, {'isAvailable': False, 'deviceTypeIdentifier': 'iPhone-99'}],
        }}
        self.assertEqual(simulator.select_device(data), ('com.apple.CoreSimulator.SimRuntime.iOS-27-2', 'iPhone-17'))
        with self.assertRaisesRegex(RuntimeError, 'CI_ENVIRONMENT_FAILURE'):
            simulator.select_device({'devices': {}})

    def test_simctl_zero_exit_does_not_hide_data_migration_failure(self):
        result = subprocess.CompletedProcess([], 0, stdout='Status=3, isTerminal=YES\nData Migration Failed', stderr='')
        with self.assertRaisesRegex(RuntimeError, 'CI_ENVIRONMENT_FAILURE'):
            simulator.verify_boot_result(result)


class SizeTests(unittest.TestCase):
    def test_bundle_measurement_does_not_follow_external_symlinks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / 'Pitchee.app'
            app.mkdir()
            with (app / 'Info.plist').open('wb') as output:
                plistlib.dump({'CFBundleExecutable': 'Pitchee'}, output)
            (app / 'Pitchee').write_bytes(b'12345')
            (app / 'asset').write_bytes(b'123')
            (root / 'outside').write_bytes(b'x' * 20000)
            (app / 'link').symlink_to(root / 'outside')
            total, main, resources = size.measure(app)
            self.assertEqual(main, 5)
            self.assertEqual(total, sum(p.lstat().st_size for p in app.iterdir()))
            self.assertEqual(total, main + resources)
            self.assertLess(total, 20000)

    def test_history_is_bounded_and_retries_replace_own_run(self):
        rows = [{'run_id': str(i)} for i in range(16)]
        actual, previous = size.append_measurement(rows, {'run_id': '15'})
        self.assertEqual(len(actual), 14)
        self.assertEqual(previous['run_id'], '14')
        self.assertEqual([row['run_id'] for row in actual].count('15'), 1)

    def test_warning_requires_strict_threshold_and_displays_measurement_scope(self):
        row = dict(zip(size.FIELDS, ['today', 'abcdef', '2', '27.2', 'Xcode 27.2', '2097153', '1', '2097152']))
        previous = {**row, 'total_bytes': '0'}
        text = size.render([row], previous, 2)
        self.assertTrue(text.startswith('**Size warning:'))
        self.assertIn('before App Thinning', text)
        self.assertIn('never as a download', text)


class RestoreTests(unittest.TestCase):
    @staticmethod
    def archive(name, data=b'timestamp,commit\n'):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as target:
            target.writestr(name, data)
        return buffer.getvalue()

    def test_artifact_is_data_only_and_rejects_paths(self):
        self.assertEqual(restore.selected_history(self.archive('size-history.csv')), b'timestamp,commit\n')
        for name in ['../size-history.csv', '/size-history.csv', 'script.py', 'nested/size-history.csv']:
            with self.assertRaises(ValueError):
                restore.selected_history(self.archive(name))

    def test_only_main_push_and_manual_events_track_history(self):
        for event in ['push', 'workflow_dispatch']:
            self.assertTrue(restore.tracks_main_history(event, 'refs/heads/main'))
            self.assertFalse(restore.tracks_main_history(event, 'refs/heads/feature'))
        for event in ['pull_request', 'pull_request_target', 'schedule', 'release', None]:
            self.assertFalse(restore.tracks_main_history(event, 'refs/heads/main'))
        self.assertFalse(restore.tracks_main_history('push', 'refs/tags/v1.2.3'))

    def test_prior_history_never_comes_from_pr_schedule_or_failed_runs(self):
        run = {'id': 8, 'head_branch': 'main', 'event': 'push', 'status': 'completed', 'conclusion': 'success'}
        self.assertTrue(restore.eligible_run(run, '9'))
        self.assertTrue(restore.eligible_run({**run, 'event': 'workflow_dispatch'}, '9'))
        for change in [
            {'event': 'pull_request'}, {'event': 'schedule'}, {'head_branch': 'feature'},
            {'status': 'in_progress'}, {'conclusion': 'failure'}, {'id': 9},
        ]:
            self.assertFalse(restore.eligible_run({**run, **change}, '9'), change)

    def test_previous_run_is_explicitly_selected_and_downloaded(self):
        with tempfile.TemporaryDirectory() as temp:
            calls = []
            def fake_api(route, binary=False):
                calls.append(route)
                if '/workflows/' in route:
                    return {'workflow_runs': [
                        {'id': 9, 'head_branch': 'main', 'event': 'workflow_dispatch', 'status': 'completed', 'conclusion': 'success'},
                        {'id': 8, 'head_branch': 'main', 'event': 'push', 'status': 'completed', 'conclusion': 'success'},
                    ]}
                if '/runs/8/artifacts' in route:
                    return {'artifacts': [{'id': 55, 'name': 'regression-size-history', 'expired': False}]}
                if '/artifacts/55/zip' in route:
                    return self.archive('size-history.csv')
                self.fail(f'Unexpected API request: {route}')
            with patch.object(restore, 'api', fake_api):
                restore.restore('owner/repo', '9', Path(temp) / 'history.csv')
            self.assertIn('/workflows/regression.yml/', calls[0])
            self.assertIn('branch=main&status=success', calls[0])
            self.assertTrue((Path(temp) / 'history.csv').is_file())


class ReleaseTests(unittest.TestCase):
    def source(self, version):
        return (f'MARKETING_VERSION = {version}\nCURRENT_PROJECT_VERSION = 1\n'
                'VERSIONING_SYSTEM = apple-generic\n'
                'INFOPLIST_KEY_CFBundleShortVersionString = $(MARKETING_VERSION)\n'
                'INFOPLIST_KEY_CFBundleVersion = $(CURRENT_PROJECT_VERSION)\n')

    def test_valid_tag_mismatch_is_warning_data_not_failure(self):
        versions, differs = release.compare('v2.0.0', self.source('1.0'))
        self.assertEqual(versions, ['1.0'])
        self.assertTrue(differs)
        self.assertFalse(release.compare('v1.2.0', self.source('1.2.0'))[1])

    def test_invalid_tag_and_missing_version_fail(self):
        for tag in ['v1.2', 'v01.2.0', 'v1.2.0;echo injected', 'release', 'v1.2.0\n']:
            with self.assertRaises(ValueError):
                release.compare(tag, self.source('1.0'))
        with self.assertRaises(ValueError):
            release.compare('v1.2.0', '')

    def test_sdk_versions_compare_numerically(self):
        self.assertGreater(environment.version('26.10'), environment.version('26.5'))
        self.assertEqual(environment.version('26.5'), environment.version('26.5.0'))


if __name__ == '__main__':
    unittest.main()
