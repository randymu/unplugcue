// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.orange.gradient).frame(width: 52, height: 52)
                    Image(systemName: model.menuBarSymbol).font(.system(size: 25, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("UnplugCue").font(.title2.weight(.semibold))
                    Text("外置硬盘 · 安全卸载与占用检查").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
            }
            if let error = model.discoveryError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.disks.isEmpty {
                        ContentUnavailableView(model.isRefreshing ? "正在读取硬盘信息" : "未发现外置物理硬盘",
                                               systemImage: "externaldrive",
                                               description: Text("不显示内置磁盘、网络磁盘或磁盘映像。"))
                            .padding(.top, 70)
                    }
                    ForEach(model.disks) { disk in DriveCard(disk: disk, model: model) }
                }
            }
            .scrollIndicators(.automatic)
            Divider()
            HStack {
                Button("刷新硬盘列表") { Task { await model.refreshAll() } }
                    .disabled(model.isRefreshing || model.isPerformingOperation)
                Button { model.exportDiagnostics() } label: { Image(systemName: "stethoscope") }
                    .help("导出只读设备诊断")
                    .accessibilityLabel("导出只读设备诊断")
                    .disabled(model.isRefreshing || model.isPerformingOperation)
                Button("关于") { AppIdentity.showAbout() }
                Spacer()
                Text("仅正常卸载，不强制结束应用").font(.caption).foregroundStyle(.secondary)
                Button("退出") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DriveCard: View {
    let disk: ExternalDisk
    @ObservedObject var model: AppModel
    @State private var confirmUnmount = false
    private var state: AppModel.State { model.state(for: disk) }
    private var active: Bool {
        switch state { case .checking, .unmounting, .countdown: true; default: false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusSymbol).font(.system(size: 30)).foregroundStyle(statusColor).frame(width: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(disk.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(statusTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if case .countdown(let seconds) = state {
                    Text("\(seconds)s").font(.title2.monospacedDigit()).foregroundStyle(.orange)
                } else if active { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 10) {
                Text(ByteCountFormatter.string(fromByteCount: disk.size, countStyle: .decimal))
                Text(disk.mediaType)
                Text(disk.connection)
                Spacer()
                Text(disk.wholeDisk).monospaced().textSelection(.enabled)
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(statusDetail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let issue = disk.safetyIssue {
                Label(issue, systemImage: "lock.shield").font(.callout).foregroundStyle(.red)
            }
            if case .busy(let occupants, let warning, _) = state {
                occupancyPanel(occupants: occupants, warning: warning)
            }
            DisclosureGroup("整盘包含 \(disk.volumes.count) 个卷") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(disk.volumes) { volume in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(volume.name)
                                Spacer()
                                Text(volume.device).monospaced().foregroundStyle(.secondary)
                            }
                            Text(volume.mountPoint ?? "未挂载").foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }.font(.caption).padding(.top, 8)
            }
            .font(.caption)
            Divider()
            Toggle("卸载成功后等待 60 秒再提醒关电", isOn: Binding(
                get: { model.waitsBeforeReminder(for: disk) },
                set: { model.setWaitsBeforeReminder($0, for: disk) }
            ))
            .toggleStyle(.checkbox).font(.caption)
            .disabled(active || model.isPerformingOperation)
            HStack(spacing: 10) {
                if case .busy = state {
                    Button("关闭相关应用后重新检查") { Task { await model.checkOccupants(disk) } }
                        .disabled(!canOperate)
                } else {
                    Button("检查占用") { Task { await model.checkOccupants(disk) } }
                        .disabled(!canOperate)
                }
                Spacer(minLength: 8)
                Button("安全卸载整盘") { confirmUnmount = true }
                    .buttonStyle(.borderedProminent).tint(.orange).disabled(!canOperate)
            }
            .controlSize(.large)
        }
        .padding(20)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .alert("安全卸载「\(disk.name)」？", isPresented: $confirmUnmount) {
            Button("取消", role: .cancel) {}
            Button("卸载整盘") { Task { await model.beginSafeUnmount(disk) } }
        } message: {
            Text("将正常卸载这块物理硬盘上的所有已挂载卷：\n\(disk.volumes.filter { $0.mountPoint != nil }.map(\.name).joined(separator: "\n"))\n\n如果 macOS 拒绝卸载，会停止并重新检查占用者，不使用强制模式。")
        }
    }

    private var canOperate: Bool {
        guard !model.isRefreshing, !model.isPerformingOperation, disk.safetyIssue == nil, !active else { return false }
        return switch state { case .ready, .busy, .failed: disk.isMounted; default: false }
    }
    private var statusTitle: String {
        switch state {
        case .ready: "已挂载"
        case .checking: "正在检查设备与占用者"
        case .busy(_, _, let failure): failure == nil ? "占用检查结果" : "macOS 未完成卸载"
        case .unmounting: "正在正常卸载整盘"
        case .countdown: "已卸载，关电提醒倒计时"
        case .safeToDisconnect: "已安全卸载"
        case .notConnected: "硬盘已断开"
        case .alreadyUnmounted: "硬盘已经卸载"
        case .failed: "检查未完成"
        }
    }
    private var statusDetail: String {
        switch state {
        case .ready: "操作前会重新核对 UUID 和整盘范围。打开的文件仅供参考，是否允许卸载由 macOS 判断。"
        case .checking, .unmounting: "请暂时不要拔线或关闭电源。"
        case .busy(_, _, let failure): failure.map { "卸载失败后已自动复查：\($0)" }
            ?? "这是检查时的打开文件列表，不代表这些进程一定阻止卸载。"
        case .countdown: "所有相关卷已确认卸载。60 秒是提醒缓冲时间，不代表已经检测到机械盘停转。"
        case .safeToDisconnect: model.waitsBeforeReminder(for: disk) ? "可以关闭硬盘电源或拔掉连接线。" : "可以拔掉连接线。"
        case .notConnected: "保留本次运行的设备记录；连接后会自动重新发现。"
        case .alreadyUnmounted: "本次操作前已经卸载，不启动倒计时。"
        case .failed(let message): message
        }
    }
    private var statusSymbol: String {
        switch state {
        case .checking, .unmounting: "arrow.triangle.2.circlepath"
        case .countdown: "timer"
        case .safeToDisconnect, .alreadyUnmounted: "checkmark.circle.fill"
        case .notConnected: "externaldrive.badge.xmark"
        case .busy(_, _, let failure): failure == nil ? "info.circle" : "exclamationmark.triangle"
        case .failed: "exclamationmark.triangle"
        case .ready: "externaldrive.fill"
        }
    }
    private var statusColor: Color {
        switch state {
        case .safeToDisconnect, .alreadyUnmounted: .green
        case .busy(_, _, let failure): failure == nil ? .secondary : .orange
        case .failed, .countdown: .orange
        default: .secondary
        }
    }

    private func occupancyPanel(occupants: [DiskOccupant], warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let warning { Text(warning).font(.caption).foregroundStyle(.red) }
            if occupants.isEmpty {
                Text("本次检查未发现打开文件的进程；不保证没有瞬时占用或权限不可见的进程。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                occupantSection(title: "应用与后台进程", occupants: occupants.filter { !$0.isExpectedSystemService })
                occupantSection(title: "macOS 系统后台服务", occupants: occupants.filter(\.isExpectedSystemService))
            }
            Text("无需强制结束进程。可关闭相关应用后重新检查，或尝试正常卸载。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func occupantSection(title: String, occupants: [DiskOccupant]) -> some View {
        if !occupants.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(occupants) { occupant in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(occupant.displayName).font(.subheadline.weight(.semibold))
                            Text(occupant.kind.displayName).font(.caption2).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(verbatim: "PID \(occupant.pid)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if occupant.command != occupant.displayName {
                            Text("进程：\(occupant.command)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let note = occupant.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(occupant.openPaths.prefix(4)), id: \.self) { path in pathText(path) }
                        if occupant.openPaths.count > 4 {
                            DisclosureGroup("另外 \(occupant.openPaths.count - 4) 个路径") {
                                ForEach(Array(occupant.openPaths.dropFirst(4)), id: \.self) { path in pathText(path) }
                            }.font(.caption)
                        }
                    }
                }
            }
        }
    }
    private func pathText(_ path: String) -> some View {
        Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UnplugCue").font(.headline)
            if model.disks.isEmpty { Text("未发现外置硬盘").font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.disks) { disk in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(disk.name).font(.subheadline.weight(.medium))
                            Text(compactStatus(model.state(for: disk))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 240)
            Divider()
            Button("关于 UnplugCue") { AppIdentity.showAbout() }
            Button("打开主窗口") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("刷新硬盘列表") { Task { await model.refreshAll() } }
                .disabled(model.isRefreshing || model.isPerformingOperation)
            Button("导出只读设备诊断") { model.exportDiagnostics() }
                .disabled(model.isRefreshing || model.isPerformingOperation)
            Divider()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(14).frame(width: 300)
    }
    private func compactStatus(_ state: AppModel.State) -> String {
        switch state {
        case .ready: "已挂载"
        case .checking, .unmounting: "正在检查或卸载"
        case .busy: "查看占用检查结果"
        case .countdown(let seconds): "已卸载，\(seconds) 秒后提醒"
        case .safeToDisconnect: "可以拔线或关电"
        case .notConnected: "已断开"
        case .alreadyUnmounted: "已经卸载"
        case .failed: "上次检查未完成"
        }
    }
}
