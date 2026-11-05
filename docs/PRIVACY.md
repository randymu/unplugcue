# Privacy

**English** | [简体中文](PRIVACY.zh-CN.md)

The app does not automatically connect to the internet, collect telemetry, upload data, sign in to an account, or update itself. It installs no background service or login item.

To identify drives and inspect open files, it reads device information, mount state, and file paths opened by processes. Per-drive reminder settings are stored at `~/Library/Application Support/LaCieSafeOff/preferences.json`. Earlier versions may retain `target.json` and `target-8t.json`. These personal files must not be included in release packages.

Persistent diagnostic logs are not created automatically. Manually exported diagnostics may contain device names, UUIDs, and mount paths. Review and redact them before sharing. Public GitHub issues can be read by others.

UnplugCue 2.1.1 retains the legacy settings paths and app identifier to continue reading preferences; an actual upgrade from an older installation has not been verified. See [complete removal](UNINSTALL.md).
