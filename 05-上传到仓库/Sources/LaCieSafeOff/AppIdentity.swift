// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import AppKit

@MainActor
enum AppIdentity {
    static let author = "randymu"
    static let copyright = "Copyright © 2026 randymu. All rights reserved."
    static let licenseName = "UnplugCue Free Use and Non-Sale License 1.0"
    static let licenseSummary = "允许免费使用、修改和免费分享，包含工作中使用。未经另行授权，不得售卖、收费分发或嵌入收费产品。分享时须保留 randymu 署名和许可。"

    static func showAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info["CFBundleVersion"] as? String ?? "—"
        let alert = NSAlert()
        alert.messageText = "UnplugCue \(version) (\(build))"
        alert.informativeText = "作者与维护：\(author)\n\(copyright)\n\n\(licenseName)\n\(licenseSummary)"
        alert.addButton(withTitle: "关闭")
        if Bundle.main.url(forResource: "LICENSE", withExtension: "txt") != nil {
            alert.addButton(withTitle: "查看完整许可")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }
}
