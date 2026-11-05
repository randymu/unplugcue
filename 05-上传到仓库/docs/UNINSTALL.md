# Uninstall UnplugCue

**English** | [简体中文](UNINSTALL.zh-CN.md)

1. Quit from the main window or menu bar. Also quit the old LaCie Safe Off if it is running.
2. Move UnplugCue.app from its installed location to Trash. Remove an old LaCie Safe Off.app separately if you no longer need it.
3. In Finder, press Command+Shift+G and open `~/Library/Application Support/`. Remove `LaCieSafeOff` if present. This resets preferences shared with older versions too.
4. Open `~/Library/Preferences/` and remove `com.randymu.LaCieSafeOff.plist` if present.
5. Optionally disable the app's notifications in System Settings and remove diagnostics you exported manually.

There are no drivers, background services, or login items to remove. macOS-managed notification permissions, launch records, or system logs may remain. Do not remove unrelated system files or disable security protections.
