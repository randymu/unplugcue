# Safety boundaries

**English** | [简体中文](SAFETY.zh-CN.md)

See [test coverage](TESTING.md) for the current 2.1.1 verification record.

UnplugCue only requests a normal macOS unmount. It does not force unmount, terminate other apps, format a disk, repair a filesystem, assess drive health, or control power.

Identity verification and submission to diskutil are not atomic. An extreme hot-swap race remains possible. Do not swap or unplug devices during an operation. A 60-second delay does not establish that a mechanical drive has stopped spinning.

Open-file inspection is permission-limited and may be incomplete. A timeout does not establish that the system request was cancelled. Wait and verify in Disk Utility; do not immediately retry, restart the app to retry, or power off.

Green status updates on device events and is rechecked about every 15 seconds when idle; other work can delay it. This is neither a maximum refresh interval nor continuing permission to cut power. Remounting requires a new unmount.

Historical review, 2026-11-04 / 2.0.1: 34 mock tests, dual-architecture builds, extraction, signature-integrity, and startup checks passed. The startup check showed no external devices. It did not test real unmounts, write conflicts, or device swaps. Intel was not run on hardware; macOS 14 was a deployment target, not a completed runtime test.

Before a stable release, record actual Mac/chip/macOS, drive/enclosure/interface, filesystem, and outcomes for normal unmounts, multiple volumes, busy writes, cancellation, failures, and remounting. Use only backed-up, non-critical test drives.
