# UnplugCue

**English** | [简体中文](README.zh-CN.md)

<img src="Resources/AppIcon-1024.png" width="112" alt="UnplugCue app icon">

Check open files before unmounting an external drive, then get a reminder to unplug it or turn off its enclosure. Formerly LaCie Safe Off; not limited to LaCie drives.

**[Download 2.1.1 pre-release](https://github.com/randymu/unplugcue/releases/tag/v2.1.1)** · [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/randymu/unplugcue/issues)

macOS 14+ · Apple Silicon / Intel universal build · No Xcode needed to run.

**App language: the current interface is primarily Simplified Chinese. Documentation is available in English and Chinese; an English app interface has not been implemented.**

This is a pre-release. Mock tests and packaging checks have passed. Intel hardware and every supported macOS version have not been tested.

## Features

- Discover external physical HDDs and SSDs connected over USB, Thunderbolt, and other interfaces.
- Show applications and processes with open files to help investigate unmount failures.
- After confirmation, request a normal unmount of all volumes on the selected physical drive. No forced unmounts or termination of other apps.
- Remind immediately for SSDs by default; wait 60 seconds for HDDs or unknown types, with per-drive settings.

The delay is a reminder buffer, not a spindle-stop detector. UnplugCue does not control drive power.

## Install

Download the macOS universal ZIP under **Assets** on the release page. Extract it and drag UnplugCue.app into Applications. The automatically generated **Source code** archives are not app installers.

The app is ad-hoc signed, without an Apple Developer identity signature or notarization. macOS may block the first launch. After checking the source of your download, review the prompt for this app in System Settings → Privacy & Security. Do not disable system-wide protections. If macOS reports damage or malware, stop and report it rather than blindly bypassing the warning.

Notifications are optional. Denying them still allows in-window operation. Normal use does not require an administrator password, Full Disk Access, or Accessibility permission.

## Use

Save your work and wait for copying or backup jobs to finish. Select a drive, optionally inspect open files, then confirm unmounting the entire drive and wait for the current operation and reminder.

Current Chinese controls: **检查占用** = check open files; **安全卸载整盘** = safely unmount the whole drive; **关于** = About; **退出** = Quit. These are explanatory translations, not English UI labels.

A whole-drive operation includes all volumes on that physical device. Do not unplug, swap, or remount it during the operation. If you remount a volume, unmount it again; do not rely on an old notification to power down. Quit when finished; the app need not stay running.

## Scope and limitations

Internal drives, disk images, and network volumes are excluded. An external drive hosting the running system cannot be unmounted. Multi-physical-store APFS containers and Apple software RAID are not supported; incomplete device information blocks the operation.

Open-file results may be incomplete because of macOS permissions. An open file does not necessarily prevent unmounting; macOS decides the final result. A timeout means the outcome is uncertain. Wait and check Disk Utility; do not immediately retry or power off.

Read the [safety notes](docs/SAFETY.md), [privacy notice](docs/PRIVACY.md), [test coverage](docs/TESTING.md), and [uninstall instructions](docs/UNINSTALL.md). Start with a backed-up, non-critical drive. This tool does not replace backups.

## Feedback and maintenance

English and Chinese reports are welcome in [Issues](https://github.com/randymu/unplugcue/issues). Include app and macOS versions, chip, drive/enclosure details, steps, and actual errors. Remove private paths, UUIDs, serial numbers, and sensitive filenames before sharing screenshots or diagnostics.

Maintained by **randymu** in spare time. Prompt replies and feature delivery are not guaranteed. See [contribution guidance](CONTRIBUTING.md).

## Development and license

See [build instructions](docs/DEVELOPMENT.md). No third-party Swift Package dependencies are currently declared. Some internal identifiers retain LaCieSafeOff to preserve settings. This independent project is not affiliated with drive manufacturers.

Licensed under the [UnplugCue Free Use and Non-Sale License 1.0](LICENSE): free use, modification, and free sharing, including use at work; no sale, paid distribution, or inclusion in paid products without separate written permission. Retain attribution and license notices and identify modified distributions.

This is source-available software with restrictions, not OSI-defined open source. The English LICENSE is authoritative; a [Chinese explanation](LICENSE.zh-CN.md) is available.
