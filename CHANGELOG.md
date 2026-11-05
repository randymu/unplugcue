# Changelog

**English** | [简体中文](CHANGELOG.zh-CN.md)

## 2.1.1 — 2026-11-05 (build 9, pre-release)

- Align the top of the U-shaped icon's left tip and right cue dot; adjust connector spacing.
- Add randymu attribution, compiled author information, and an About window.
- Add a custom license allowing free use, modification, and free sharing, including use at work; prohibit unauthorized sale, paid distribution, and inclusion in paid products.
- Include the complete license inside the app and ZIP.
- Prepare English and Chinese public documentation and download instructions; the app UI remains primarily Simplified Chinese. No executable behavior changes for this documentation update.

## 2.1.0 — internal test build (build 8)

- Rename the public app to UnplugCue.
- Replace the SF Symbols-based app icon with independent geometric cable artwork.
- Retain legacy app identifiers, executable name, and preference paths.
- Leave drive discovery and unmount logic unchanged. See [test coverage](docs/TESTING.md).

## 2.0.1 — 2026-11-04 (private sharing build 7)

- Revoke old safe-to-disconnect status and reminders when device reads fail.
- Strengthen connection identity, full physical-partition fingerprints, and APFS topology checks; stop on incomplete data.
- Preserve open-file inspection warnings and improve unusual filename parsing.
- Treat unmount timeouts as uncertain and pause further requests in that app run.

34 mock tests, dual-architecture builds, extraction, signature integrity, and startup checks passed. That review did not test real unmounts or busy writes. Intel was not tested on hardware; the app was not notarized.

A complete public history for earlier versions is unavailable; no history is invented here.
