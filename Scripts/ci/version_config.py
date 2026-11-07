"""Single-source app version reading, validation and temporary Cloud updates."""
from __future__ import annotations

import json
from pathlib import Path
import plistlib
import re

CONFIG_PATH = Path('Config/Version.xcconfig')
PROJECT_PATH = Path('Pitchee.xcodeproj/project.pbxproj')
VERSION_KEYS = {
    'MARKETING_VERSION', 'CURRENT_PROJECT_VERSION', 'VERSIONING_SYSTEM',
    'INFOPLIST_KEY_CFBundleShortVersionString', 'INFOPLIST_KEY_CFBundleVersion',
}
VERSION_TAG = re.compile(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')
ASSIGNMENT = re.compile(r'^\s*([A-Za-z_][A-Za-z_0-9]*)\s*=\s*([^\n]+?)\s*$', re.MULTILINE)


def version_from_tag(tag: str) -> str | None:
    return tag[1:] if VERSION_TAG.fullmatch(tag) else None


def validate_build_number(number: str) -> str:
    if not re.fullmatch(r'[1-9][0-9]*', number):
        raise ValueError('CI_BUILD_NUMBER must be the positive integer allocated by Xcode Cloud.')
    return number


def read_settings(text: str) -> dict[str, str]:
    settings = {}
    for line in text.splitlines():
        line = line.split('//', 1)[0].strip()
        if not line:
            continue
        match = ASSIGNMENT.fullmatch(line)
        if not match or match[1] in settings:
            raise ValueError('Version.xcconfig must contain unique, unconditional assignments only.')
        settings[match[1]] = match[2]
    if set(settings) != VERSION_KEYS:
        raise ValueError('Version.xcconfig must contain exactly the five shared version settings.')
    if not re.fullmatch(r'(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){1,2}', settings['MARKETING_VERSION']):
        raise ValueError('Invalid project marketing version.')
    validate_build_number(settings['CURRENT_PROJECT_VERSION'])
    required = {
        'VERSIONING_SYSTEM': 'apple-generic',
        'INFOPLIST_KEY_CFBundleShortVersionString': '$(MARKETING_VERSION)',
        'INFOPLIST_KEY_CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
    }
    if any(settings[key] != value for key, value in required.items()):
        raise ValueError('Generated Info.plist version keys must reference shared build settings.')
    return settings


def parse_project(source: str) -> dict:
    """Parse OpenStep plist containers without requiring macOS plutil on Linux CI."""
    pattern = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,"]+', re.DOTALL)
    tokens = [token for token in pattern.findall(source)
              if not token.isspace() and not token.startswith(('//', '/*'))]
    cursor = 0

    def take(expected=None):
        nonlocal cursor
        if cursor >= len(tokens):
            raise ValueError('Unexpected end of Xcode project')
        token = tokens[cursor]
        cursor += 1
        if expected is not None and token != expected:
            raise ValueError(f'Expected {expected!r} in Xcode project, got {token!r}')
        return token

    def value():
        token = take()
        if token == '{':
            result = {}
            while tokens[cursor] != '}':
                key = value()
                take('=')
                if key in result:
                    raise ValueError(f'Duplicate Xcode project key: {key}')
                result[key] = value()
                take(';')
            take('}')
            return result
        if token == '(':
            result = []
            while tokens[cursor] != ')':
                result.append(value())
                if tokens[cursor] != ')':
                    take(',')
            take(')')
            return result
        return json.loads(token) if token.startswith('"') else token

    try:
        result = value()
        if cursor != len(tokens) or not isinstance(result, dict):
            raise ValueError('Malformed Xcode project')
        return result
    except (IndexError, TypeError, json.JSONDecodeError) as error:
        raise ValueError('Malformed Xcode project') from error


def validate_project(root: Path) -> dict[str, str]:
    settings = read_settings((root / CONFIG_PATH).read_text(encoding='utf-8'))
    project = parse_project((root / PROJECT_PATH).read_text(encoding='utf-8'))
    objects = project['objects']
    main = objects[project['rootObject']]
    version_files = [identifier for identifier, obj in objects.items()
                     if obj.get('isa') == 'PBXFileReference'
                     and obj.get('path') == CONFIG_PATH.as_posix()
                     and obj.get('sourceTree') == 'SOURCE_ROOT']
    if len(version_files) != 1:
        raise ValueError('Project must reference Config/Version.xcconfig exactly once from SOURCE_ROOT.')
    shared_reference = version_files[0]
    project_configs = objects[main['buildConfigurationList']]['buildConfigurations']
    project_defaults = {}
    for identifier in project_configs:
        config = objects[identifier]
        if config.get('baseConfigurationReference') != shared_reference:
            raise ValueError(f"Project {config['name']} must inherit Config/Version.xcconfig.")
        project_defaults[config['name']] = config.get('buildSettings', {})
    for identifier, obj in objects.items():
        if obj.get('isa') != 'XCBuildConfiguration':
            continue
        overrides = {key for key in obj.get('buildSettings', {})
                     if key.split('[', 1)[0] in VERSION_KEYS}
        if overrides:
            raise ValueError(f"Independent version overrides in {identifier} ({obj['name']}): {sorted(overrides)}")
        if identifier not in project_configs and obj.get('baseConfigurationReference'):
            raise ValueError('Target-specific xcconfig requires an inheritance audit before CI can use it.')
    for target_id in main['targets']:
        target = objects[target_id]
        for config_id in objects[target['buildConfigurationList']]['buildConfigurations']:
            config = objects[config_id]
            target_settings = {**project_defaults[config['name']], **config.get('buildSettings', {})}
            info_paths = [value for key, value in target_settings.items()
                          if key.split('[', 1)[0] == 'INFOPLIST_FILE']
            for info_path in info_paths:
                for prefix in ('$(SRCROOT)/', '$(PROJECT_DIR)/'):
                    info_path = info_path.removeprefix(prefix)
                if '$' in info_path or Path(info_path).is_absolute() or '..' in Path(info_path).parts:
                    raise ValueError(f"Cannot safely resolve Info.plist for {target['name']}")
                info = plistlib.loads((root / info_path).read_bytes())
                if (info.get('CFBundleShortVersionString') != '$(MARKETING_VERSION)'
                        or info.get('CFBundleVersion') != '$(CURRENT_PROJECT_VERSION)'):
                    raise ValueError(f"Literal or missing Info.plist version in {target['name']}")
            if not info_paths and target_settings.get('GENERATE_INFOPLIST_FILE') != 'YES':
                raise ValueError(f"{target['name']} must generate Info.plist with shared version fields.")
    return settings


def sync_versions(root: Path, build_number: str, marketing_version: str | None) -> dict[str, str]:
    """Copy external facts into the disposable checkout; never allocate a number."""
    validate_build_number(build_number)
    before = validate_project(root)
    updates = {'CURRENT_PROJECT_VERSION': build_number}
    if marketing_version is not None:
        if version_from_tag('v' + marketing_version) is None:
            raise ValueError('Tag marketing version must use X.Y.Z format.')
        updates['MARKETING_VERSION'] = marketing_version
    path = root / CONFIG_PATH
    source = path.read_text(encoding='utf-8')
    for key, value in updates.items():
        source, count = re.subn(rf'(?m)^([ \t]*{key}[ \t]*=[ \t]*)[^\n]+$', lambda match: match[1] + value, source)
        if count != 1:
            raise ValueError(f'Expected exactly one {key} assignment.')
    expected = read_settings(source)
    temporary = path.with_suffix('.xcconfig.tmp')
    temporary.write_text(source, encoding='utf-8')
    temporary.replace(path)
    after = validate_project(root)
    if after != expected or (marketing_version is None and after['MARKETING_VERSION'] != before['MARKETING_VERSION']):
        raise ValueError('Version synchronization verification failed.')
    return after
