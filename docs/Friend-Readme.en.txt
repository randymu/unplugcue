UnplugCue 2.1.1 (build 9) — pre-release
Author and maintainer: randymu

LANGUAGE
The current app interface is primarily Simplified Chinese. English and Chinese project documentation is available at https://github.com/randymu/unplugcue (once published).
Controls: 检查占用 = check open files; 安全卸载整盘 = unmount the whole drive; 关于 = About; 退出 = Quit.

REQUIREMENTS AND INSTALLATION
macOS 14+. Universal Apple Silicon/Intel binary. Intel hardware and every supported macOS version have not been tested. No Xcode or extra dependencies are needed to run.
Extract and drag UnplugCue.app into Applications. The app is ad-hoc signed without Apple Developer identity verification or notarization. macOS may block launch; after checking the source, review this app in System Settings > Privacy & Security. Do not disable global protections. Stop and report damage or malware warnings instead of blindly bypassing them.
Notifications are optional. Normal use does not require an administrator password, Full Disk Access, or Accessibility permission.

USE AND SAFETY
Wait for copying/backups to finish. Inspect open files if needed, confirm a normal unmount of the entire physical drive, and wait for the current result/reminder. All volumes on that physical drive are included. No forced unmounts, termination of other apps, formatting, health checks, or power control are performed.
SSD reminders are immediate by default; HDD/unknown types wait 60 seconds, configurable per drive. The delay does not detect spindle stop.
Do not unplug, swap, or remount during an operation. Remounting requires a fresh unmount; do not rely on an old notification. Open-file results may be incomplete. macOS decides the final unmount result. A timeout is uncertain: wait and verify in Disk Utility; do not immediately retry or cut power.
Internal drives, disk images and network volumes are excluded; the running system's external drive is protected. Multi-store APFS and Apple software RAID are not supported. Start with a backed-up, non-critical drive and retain independent backups.

PRIVACY AND REMOVAL
No automatic networking, telemetry, accounts, updates, background services or login items. Reminder settings use ~/Library/Application Support/LaCieSafeOff/preferences.json; older versions may retain target.json/target-8t.json. Manually exported diagnostics may contain names, UUIDs and paths; review before sharing.
Quit and remove UnplugCue.app. If no longer needed, remove ~/Library/Application Support/LaCieSafeOff/ and ~/Library/Preferences/com.randymu.LaCieSafeOff.plist. This also resets preferences shared with old versions. macOS-managed records may remain.

LICENSE AND FEEDBACK
Free use, modification and free sharing, including use at work. No unauthorized sale, paid distribution or inclusion in paid products. Retain attribution/license and mark modified distributions. Read the complete English LICENSE.txt beside this file or from About. The license is source-available, not OSI open source.
Report issues in English or Chinese at https://github.com/randymu/unplugcue/issues once the repository is public. Redact personal data. Spare-time maintenance; prompt replies are not guaranteed.

VERIFICATION
34 mock tests passed. Universal builds, extraction, signature integrity, version, author, icon and license checks passed. New UI interactions, real-drive unmount/busy-write behavior, old-version upgrade and Intel hardware were not verified in this release review. Temporary signing is not notarization or a zero-risk guarantee.
