# 开发与构建

[English](DEVELOPMENT.md) | **简体中文**

普通使用者应从 Releases 下载 ZIP，无需 Xcode。

开发需要 macOS、Swift 6 工具链与 Command Line Tools。当前脚本使用 `/Library/Developer/CommandLineTools`；模拟测试还从 `/Applications/Xcode.app/Contents/Developer` 加载 XCTest。不同安装位置可用 XCODE_ROOT 配置测试。请先按 Apple 要求完成相应工具的安装与许可。

在仓库根目录：

```sh
zsh scripts/test.command
zsh scripts/package-share.command
```

打包生成 `Distribution/UnplugCue-<版本>-macOS-universal.zip`。同版本输出已存在时会停止，请保留历史包并在新工作副本构建。输出为本地临时签名，不执行 Apple 公证。

图标由 `scripts/generate-app-icon.swift` 的几何路径绘制；如需重新生成：

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools zsh scripts/generate-app-icon.command
```

现有内部 target、可执行文件名、bundle ID 和偏好路径保留 LaCieSafeOff。对外名称为 UnplugCue。不要同时运行新旧应用。

## 发布对应关系

先固定源码提交，从该提交构建并测试，再将同一提交标记为对应版本 tag。安装包、SHA256SUMS 和构建信息放同一个 Release。校验和只证明文件一致性，不提供开发者身份认证。

目前没有自动更新、持续集成或自动发布；更新通过 Releases 手动分发。许可限制售卖及收费集成，详见根目录 LICENSE。
