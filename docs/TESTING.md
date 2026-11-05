# Test coverage and known limitations

**English** | [简体中文](TESTING.zh-CN.md)

UnplugCue 2.1.1, build 9. Record date: 2026-11-05.

| Check | Result |
|---|---|
| 34 mock tests | Passed; no failures |
| Apple Silicon / Intel builds | Passed; universal binary contains arm64 and x86_64 |
| ZIP extraction and signature integrity | Passed; ad-hoc signing only, not Apple identity verification or notarization |
| Version, randymu attribution, icon, bundled license | Checked |
| New UI interactions and About button | Not manually tested |
| Real-drive unmounts, busy writes, hot-swap races | Not tested in this review |
| Preference retention after replacing an older installation | Not tested; paths and identifiers retained |
| Intel Mac hardware | Not tested |
| Each macOS version from 14 onward | Not tested; 14 is the minimum deployment target |

Mock tests cover device exclusions, APFS mapping and incomplete data, connection identity and physical fingerprints, remounts and stale-state invalidation, and open-file path parsing. A successful build does not establish compatibility with every enclosure, filesystem, or macOS version.

Drive discovery, unmounting, and status logic have not changed in this update. Attribution and documentation changes are not new real-drive tests. No spindle-stop detection or replacement for backups is provided. Read [safety notes](SAFETY.md).

## Pending manual checks

Use a backed-up, non-critical drive. Record Mac, chip, macOS, app version, drive/enclosure, interface, filesystem, and results.

- [ ] First launch, main window, About, and complete license display.
- [ ] In-window operation with notification permission denied.
- [ ] HDD/SSD and multiple volumes on one physical drive are identified correctly.
- [ ] Cancelling confirmation submits no unmount request.
- [ ] Normal unmount and reminder after all file operations have finished.
- [ ] Busy/failed operations do not falsely report success; never force-unplug a test drive.
- [ ] Remounting revokes old green status and requires another unmount.
- [ ] Preference retention, old-version upgrade, and complete removal.

These are pending checks, not passed results. After a timeout, wait and check Disk Utility instead of repeatedly retrying or cutting power.
