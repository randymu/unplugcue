# 隐私和移除

[English](PRIVACY.md) | **简体中文**

不自动联网、收集遥测、上传数据、登录账号或自动更新。不安装后台服务或登录项。

为识别设备及检查占用，读取设备信息、挂载状态和进程打开文件的路径。偏好保存于用户 Library/Application Support/LaCieSafeOff/preferences.json。旧版本可能保留 target.json、target-8t.json。这些本机文件不应随包分发。

不自动创建持久诊断日志。手动导出的诊断可能含设备名、UUID、挂载路径，分享前请审阅和脱敏。GitHub Issue 公开可见。

退出并删除应用后，可移除上述设置目录及用户 Library/Preferences/com.randymu.LaCieSafeOff.plist。UnplugCue 2.1.1 保留了这些旧版内部路径，以继续读取偏好；旧版升级后的读取体验尚未真机验证。
