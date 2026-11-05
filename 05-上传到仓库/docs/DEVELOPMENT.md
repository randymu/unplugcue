# Development and builds

**English** | [简体中文](DEVELOPMENT.zh-CN.md)

App users should download the ZIP from Releases; Xcode is not required to run it.

Development requires macOS, a Swift 6 toolchain, and Command Line Tools. Scripts currently use `/Library/Developer/CommandLineTools`; mock tests load XCTest from `/Applications/Xcode.app/Contents/Developer`. Set XCODE_ROOT for a different Xcode path. Complete Apple's installation and license requirements for your tools first.

From the repository root:

```sh
zsh scripts/test.command
zsh scripts/package-share.command
```

Packaging creates `Distribution/UnplugCue-<version>-macOS-universal.zip`. Existing output for the same version causes the script to stop. Preserve past releases and build in a fresh working copy. Signing is ad-hoc; Apple notarization is not performed.

The app icon is drawn from geometric paths in `scripts/generate-app-icon.swift`. Regenerate it with:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools zsh scripts/generate-app-icon.command
```

Internal target, executable, bundle ID, and preference paths retain LaCieSafeOff. The public name is UnplugCue. Do not run new and old versions simultaneously.

## Release provenance

Fix the source commit, build and test from it, and tag that same commit with the release version. Attach the app ZIP, SHA256SUMS, and build records to one Release. Checksums establish file consistency, not developer identity.

The app interface remains primarily Simplified Chinese. Bilingual documentation is not an English UI implementation. Keep English and Chinese documentation synchronized; English LICENSE remains authoritative.

No automatic updates, CI, or automatic publishing are configured. Releases are distributed manually. See LICENSE for restrictions on sale and paid integration.
