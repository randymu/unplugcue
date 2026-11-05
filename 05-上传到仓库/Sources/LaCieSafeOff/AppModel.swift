// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import AppKit
import Foundation
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    enum State: Equatable {
        case ready
        case checking
        case busy([DiskOccupant], String?, String?)
        case unmounting
        case countdown(Int)
        case safeToDisconnect
        case notConnected
        case alreadyUnmounted
        case failed(String)
    }

    @Published private(set) var disks: [ExternalDisk] = []
    @Published private(set) var states: [String: State] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPerformingOperation = false
    @Published private(set) var discoveryError: String?
    @Published private var delayPreferences: [String: Bool] = [:]

    private let service: any DiskServicing
    private let notificationsEnabled: Bool
    private var countdownTasks: [String: Task<Void, Never>] = [:]
    private var watcher: DiskWatcher?
    private var refreshTask: Task<Void, Never>?
    private var safetyMonitorTask: Task<Void, Never>?
    private var legacyIdentities: [DiskIdentity] = []
    private static var supportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LaCieSafeOff", isDirectory: true)
    }

    init(service: any DiskServicing = DiskService(), monitoring: Bool = true, notificationsEnabled: Bool = true) {
        self.service = service
        self.notificationsEnabled = notificationsEnabled
        if let data = try? Data(contentsOf: Self.supportURL.appendingPathComponent("preferences.json")),
           let values = try? JSONDecoder().decode([String: Bool].self, from: data) { delayPreferences = values }
        for filename in ["target.json", "target-8t.json"] {
            if let data = try? Data(contentsOf: Self.supportURL.appendingPathComponent(filename)),
               let identity = try? JSONDecoder().decode(DiskIdentity.self, from: data) { legacyIdentities.append(identity) }
        }
        guard monitoring, !ProcessInfo.processInfo.arguments.contains("--diagnostics") else { return }
        watcher = DiskWatcher { [weak self] in self?.scheduleRefresh() }
        Task { await refreshAll() }
        safetyMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                if self.states.values.contains(.safeToDisconnect) { await self.refreshAll() }
            }
        }
    }

    func state(for disk: ExternalDisk) -> State { states[disk.id] ?? .ready }

    func waitsBeforeReminder(for disk: ExternalDisk) -> Bool {
        if let preference = delayPreferences[disk.id] { return preference }
        let wasLaCie = legacyIdentities.contains { identity in
            disk.volumes.contains { $0.uuid?.caseInsensitiveCompare(identity.volumeUUID) == .orderedSame }
        }
        return wasLaCie || disk.solidState != true
    }

    func setWaitsBeforeReminder(_ enabled: Bool, for disk: ExternalDisk) {
        delayPreferences[disk.id] = enabled
        do {
            try FileManager.default.createDirectory(at: Self.supportURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(delayPreferences).write(to: Self.supportURL.appendingPathComponent("preferences.json"), options: .atomic)
        } catch { states[disk.id] = .failed("无法保存提醒设置：\(error.localizedDescription)") }
    }

    var menuBarSymbol: String {
        if states.values.contains(where: { if case .countdown = $0 { true } else { false } }) { return "timer" }
        if states.values.contains(where: {
            if case .busy(_, _, let failure) = $0 { return failure != nil }
            if case .failed = $0 { return true }
            return false
        }) { return "exclamationmark.triangle" }
        return "externaldrive.badge.checkmark"
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SafeOff-diagnostics.plist"
        panel.allowedContentTypes = [UTType(filenameExtension: "plist") ?? .data]
        panel.message = "只读取设备信息，不卸载磁盘。文件包含磁盘名称与 UUID，仅保存在你选择的位置。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await DiskService().diagnosticData().write(to: url, options: .atomic) }
            catch { discoveryError = "导出诊断失败：\(error.localizedDescription)" }
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.refreshAll()
        }
    }

    func refreshAll() async {
        guard !isRefreshing, !isPerformingOperation else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let found = try await service.discover()
            let present = Set(found.map(\.id))
            for disk in found {
                let priorDisk = disks.first { $0.id == disk.id }
                if let issue = disk.safetyIssue {
                    invalidateSafety(for: disk.id, message: issue)
                } else if let priorDisk, !priorDisk.matches(disk) {
                    countdownTasks[disk.id]?.cancel()
                    clearReadyNotification(for: disk.id)
                    states[disk.id] = .failed("设备身份或分区已变化，请核对新设备后重新检查。")
                } else if !disk.isMounted {
                    switch states[disk.id] {
                    case .countdown?, .safeToDisconnect?: break
                    default: states[disk.id] = .alreadyUnmounted
                    }
                } else {
                    switch states[disk.id] {
                    case .busy?, .failed?: break
                    default:
                        countdownTasks[disk.id]?.cancel()
                        clearReadyNotification(for: disk.id)
                        states[disk.id] = .ready
                    }
                }
            }
            let missing = disks.filter { !present.contains($0.id) }
            for disk in missing {
                countdownTasks[disk.id]?.cancel()
                clearReadyNotification(for: disk.id)
                states[disk.id] = .notConnected
            }
            disks = found + missing
            discoveryError = nil
        } catch {
            discoveryError = error.localizedDescription
            for id in Array(states.keys) {
                switch states[id] {
                case .countdown?, .safeToDisconnect?, .alreadyUnmounted?:
                    invalidateSafety(for: id, message: "无法确认当前卸载状态，请重新检查：\(error.localizedDescription)")
                default: break
                }
            }
        }
    }

    func checkOccupants(_ expected: ExternalDisk) async {
        guard !isPerformingOperation, !isRefreshing else { return }
        isPerformingOperation = true
        states[expected.id] = .checking
        defer { isPerformingOperation = false; scheduleRefresh() }
        do {
            guard let current = try await service.locate(expected) else {
                states[expected.id] = .notConnected
                return
            }
            replace(current)
            guard current.isMounted else { states[expected.id] = .alreadyUnmounted; return }
            let result = await service.occupyingProcesses(on: current)
            states[expected.id] = .busy(result.occupants, result.warning, nil)
        } catch { states[expected.id] = .failed(error.localizedDescription) }
    }

    func beginSafeUnmount(_ expected: ExternalDisk) async {
        guard !isPerformingOperation, !isRefreshing else { return }
        switch state(for: expected) {
        case .ready, .busy, .failed: break
        default: return
        }
        isPerformingOperation = true
        states[expected.id] = .checking
        defer { isPerformingOperation = false; scheduleRefresh() }
        do {
            guard let current = try await service.locate(expected) else {
                states[expected.id] = .notConnected
                return
            }
            replace(current)
            guard current.isMounted else { states[expected.id] = .alreadyUnmounted; return }
            // Open files are advisory; only macOS decides whether a normal unmount is allowed.
            _ = await service.occupyingProcesses(on: current)
            states[expected.id] = .unmounting
            do {
                guard try await service.unmountWholeDisk(current) else {
                    states[expected.id] = .alreadyUnmounted
                    return
                }
                guard await verifyStillUnmounted(current) else { return }
                if waitsBeforeReminder(for: current) { startCountdown(for: current) }
                else { states[expected.id] = .safeToDisconnect; notifyReady(for: current, delayed: false) }
            } catch {
                let failure = error.localizedDescription
                do {
                    guard let latest = try await service.locate(current) else {
                        states[expected.id] = .notConnected
                        return
                    }
                    replace(latest)
                    let result = await service.occupyingProcesses(on: latest)
                    states[expected.id] = .busy(result.occupants, result.warning, failure)
                } catch { states[expected.id] = .failed("\(failure)\n复查失败：\(error.localizedDescription)") }
            }
        } catch { states[expected.id] = .failed(error.localizedDescription) }
    }

    private func replace(_ disk: ExternalDisk) {
        if let index = disks.firstIndex(where: { $0.id == disk.id }) { disks[index] = disk }
    }

    private func invalidateSafety(for id: String, message: String) {
        countdownTasks[id]?.cancel()
        countdownTasks[id] = nil
        clearReadyNotification(for: id)
        states[id] = .failed(message)
    }

    private func clearReadyNotification(for id: String) {
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["safeoff-\(id)"])
        center.removeDeliveredNotifications(withIdentifiers: ["safeoff-\(id)"])
    }

    private func startCountdown(for disk: ExternalDisk) {
        countdownTasks[disk.id]?.cancel()
        states[disk.id] = .countdown(60)
        countdownTasks[disk.id] = Task { [weak self] in
            guard let self else { return }
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            var ticks = 0
            while ContinuousClock.now < deadline {
                guard !Task.isCancelled else { return }
                let remaining = ContinuousClock.now.duration(to: deadline).components.seconds
                states[disk.id] = .countdown(max(1, Int(remaining) + 1))
                try? await Task.sleep(for: .seconds(1))
                ticks += 1
                guard !Task.isCancelled else { return }
                if ticks % 10 == 0, !(await verifyStillUnmounted(disk)) { return }
            }
            guard !Task.isCancelled, await verifyStillUnmounted(disk), !Task.isCancelled else { return }
            states[disk.id] = .safeToDisconnect
            notifyReady(for: disk, delayed: true)
        }
    }

    private func verifyStillUnmounted(_ disk: ExternalDisk) async -> Bool {
        do {
            let current = try await service.locate(disk)
            guard !Task.isCancelled else { return false }
            guard let current else {
                clearReadyNotification(for: disk.id)
                states[disk.id] = .notConnected
                return false
            }
            replace(current)
            guard !current.isMounted else {
                clearReadyNotification(for: disk.id)
                states[disk.id] = .ready
                return false
            }
            return true
        } catch {
            if !Task.isCancelled { invalidateSafety(for: disk.id, message: "提醒已停止，无法确认卸载状态：\(error.localizedDescription)") }
            return false
        }
    }

    private func notifyReady(for disk: ExternalDisk, delayed: Bool) {
        guard notificationsEnabled else { return }
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = "\(disk.name) 已安全卸载"
        content.body = delayed ? "可以关闭硬盘电源或拔掉连接线。" : "可以拔掉连接线。"
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor in
                guard let self, self.states[disk.id] == .safeToDisconnect,
                      await self.verifyStillUnmounted(disk), self.states[disk.id] == .safeToDisconnect else { return }
                try? await center.add(UNNotificationRequest(identifier: "safeoff-\(disk.id)", content: content, trigger: nil))
            }
        }
    }
}
