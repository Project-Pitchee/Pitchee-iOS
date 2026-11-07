# Core regression fixture metadata

**Audio stays private. No WAV, archive or PCM belongs in this repository or in CI artifacts.**
This follows the owner's 2026-11-07 instruction and replaces the original design's proposal to commit WAVs.

`manifest.json` records the original ten short fixtures, byte sizes, SHA-256 hashes and
Core-measured speech durations from the line6 experiment on 2026-11-07. Their source is
Core commit `5831e3cca1dde8416d0cf0c971c7ff0935fa2c1c`, under
`platform/android/benchmark/app/src/main/assets/test_audio` (introduced at
`8759d930821c56271bd235fd6e6c73c3449a80ac`). The upstream repository has GPL-3.0 in
`LICENSE`; it has no separate audio license notice. This metadata does not grant
permission to redistribute the recordings. No audio is copied here.

Local use points `core_regression.py --fixtures` at an authorized directory and
`--manifest` at its manifest (the example metadata here can describe the existing
Core short corpus). CI reads an authorized private ZIP through the protected
`core-regression-fixtures` GitHub environment. Configure its
`PITCHEE_CORE_FIXTURES_URL` secret with an HTTPS download URL and its
`PITCHEE_CORE_FIXTURES_SHA256` variable with the SHA-256 of that exact ZIP. The bundle
must contain only a flat `manifest.json` and its WAVs. Use an authenticated/signed
URL with access restricted to this task; rotate it when needed. No storage location
or credential is configured by this repository.

The environment should require approval of the complete PR head before releasing
the URL: regression executes that PR's Core code. Fork PRs cannot receive it and
fail with instructions for a maintainer-controlled branch. Do not use
`pull_request_target` to run the PR. The bundle downloads into `RUNNER_TEMP`, is
deleted at job end, and never enters an artifact path. Only numeric JSON, Markdown
reports and build/inference logs are retained. Never add fixtures to caches.

The fixed budget is at most 20 mono 16 kHz PCM16/IEEE Float32 WAVs and 10 MiB of uncompressed audio.
The long tier requires at least one recording with **at least 5 seconds of speech
measured by both Core checkpoints**. WAV container duration does not qualify a
sample. Each run reports old/new measured speech seconds and excludes shorter
recordings from the long tier. The ten original samples measure 0.36–4.47 seconds,
so they exercise full/HNR/readiness comparisons but cannot satisfy the long tier.
Missing audio/manifest, invalid hashes, empty sets and absent long coverage fail
explicitly. Completed short-corpus output remains available when long coverage fails.

To extend the private bundle, add authorized long recordings without publishing
them, then update its private manifest with file, SHA-256, bytes, provenance and
selection rationale. The line6 PVQD recordings are not included or redistributed.

`full` compares every native JSON field for both score profiles, including schema
and removed fields; `hnr` calls the independently compiled public HNR API using each
checkpoint's original-timeline VAD intervals; `readiness` supplies the measured
HNR/naturalness to the current production `ReadinessScoring` under identical fixed
synthetic histories and runs the HNR-presence self-check. This is regression and
rule sensitivity evidence, not a person's readiness estimate. Every numeric
comparison is exact, with no tolerance or automatic acceptability decision.
