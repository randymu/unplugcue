# 完整移除 UnplugCue

[English](UNINSTALL.md) | **简体中文**

1. 在主窗口或菜单栏点击“退出”。如旧 LaCie Safe Off 也在运行，先退出。
2. 将你安装位置中的 UnplugCue.app 移到废纸篓；若仍保留旧 LaCie Safe Off.app，可确认不再需要后分别移除。
3. Finder 按 Command+Shift+G，前往 `~/Library/Application Support/`，移除 `LaCieSafeOff` 文件夹（如存在）。此目录包含本工具与旧版本共用的提醒偏好，移除后将一并重置。
4. 同样前往 `~/Library/Preferences/`，移除 `com.randymu.LaCieSafeOff.plist`（如存在）。
5. 可在系统设置“通知”中关闭本应用通知，删除自己导出的诊断文件。

不安装驱动、后台服务或登录项。macOS 维护的通知权限、启动记录或系统日志可能保留。无需清理系统文件或关闭安全保护。
