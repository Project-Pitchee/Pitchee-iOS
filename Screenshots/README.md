# App Store screenshot capture

Run the **Screenshots** workflow manually. It defaults to both 6.9-inch and 6.5-inch slots, Simplified Chinese and English, in light appearance. Set languages to `all` for every language currently present in the string catalog and choose `light dark` for both appearances. Two combinations run at a time to bound macOS runner usage.

The pipeline uses XCUITest attachments and `xcresulttool`; there is no Ruby or fastlane dependency. It produces raw app interfaces. Marketing composition and App Store Connect screenshot upload remain separate workflows.

Local example after restoring native dependencies:

```sh
bash Scripts/bootstrap-native-dependencies.sh
python3 Screenshots/capture.py --device 6.9 --language en --appearance light
```

Outputs are in `.build/screenshots-output/<language>/<size>/<appearance>/`. Each combination must export all five named PNGs in order: practice home, pitch monitor, recording results, pitch articles, and recording history. The exporter checks the PNG dimensions against the requested App Store slot. It fails if a named image is missing, duplicated, or has the wrong dimensions; incidental failure screenshots do not count.

The capture script creates and deletes its own simulator. It does not modify an existing review device. Runtime and device support are checked before building. A missing compatible iOS 26.5+ runtime or device exits with environment status 78 and an explicit diagnostic; it never claims to have produced screenshots. Xcode Cloud remains the authority for app builds when GitHub's hosted image lags behind the SDK.

The shared `Pitchee` scheme includes `PitcheeTests` and `PitcheeUITests` in a Debug Test action. Archive uses Release. The screenshot launch interface is available **only in Debug**:

```text
-UITestMode -ScreenshotScreen home|monitor|insights|articles|history
```

This mode creates an in-memory SwiftData store with fourteen deterministic sample assessments across seven days, a separate resettable defaults suite, fixed dates and IDs, disabled animations, bundled articles, and blocked outbound URL loading. It does not initialize diagnostics storage, read existing recordings, or request the microphone. Monitor and result screens use the app's existing preview models and production views. No random generator is used. The status bar, language, text size, and appearance are set by the test harness. Article content is bilingual; other interface languages follow the app's existing English article fallback.

Validation helpers:

```sh
python3 -m unittest discover -s Screenshots -p 'test_*.py'
xcodebuild test -project Pitchee.xcodeproj -scheme Pitchee \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' CODE_SIGNING_ALLOWED=NO
```

The UI test waits for loaded bundle content and asserts screen-specific controls before attaching each image. Unit tests cover fixture isolation, determinism, short-speech rejection, and both article languages. These checks do not replace a visual review of the exported PNGs or real-device acceptance.
