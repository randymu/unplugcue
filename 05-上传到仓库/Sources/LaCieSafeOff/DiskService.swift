// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import AppKit
import Darwin
import DiskArbitration
import Foundation
import IOKit

struct DiskIdentity: Codable, Equatable {
    let volumeUUID: String
    let mediaUUID: String?
    let model: String
    let size: Int64
    let volumeName: String
}

enum OccupantKind: String, Equatable, Sendable {
    case application
    case backgroundProcess
    case systemService

    var displayName: String {
        switch self {
        case .application: "应用"
        case .backgroundProcess: "后台进程"
        case .systemService: "系统服务"
        }
    }
}

struct DiskOccupant: Identifiable, Equatable, Sendable {
    let pid: Int32
    let command: String
    let displayName: String
    let bundleIdentifier: String?
    let kind: OccupantKind
    let openPaths: [String]
    let isExpectedSystemService: Bool
    let blocksSafeUnmount: Bool
    let note: String?

    var id: Int32 { pid }
}

struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum DiskServiceError: LocalizedError {
    case commandFailed(String)
    case invalidDiskInfo
    case identityMismatch
    case unsafeDisk(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message
        case .invalidDiskInfo: "无法读取完整的硬盘身份信息。"
        case .identityMismatch: "硬盘身份或分区已变化，已停止操作；请重新检查并确认设备。"
        case .unsafeDisk(let message): message
        case .disconnected: "目标硬盘已经断开，未执行卸载。"
        }
    }
}

protocol DiskServicing: Sendable {
    func discover() async throws -> [ExternalDisk]
    func locate(_ expected: ExternalDisk) async throws -> ExternalDisk?
    func occupyingProcesses(on disk: ExternalDisk) async -> (occupants: [DiskOccupant], warning: String?)
    func unmountWholeDisk(_ expected: ExternalDisk) async throws -> Bool
}

actor DiskService: DiskServicing {
    private var unmountCommandsSuspended = false
    func diagnosticData() throws -> Data {
        let list = try commandPlist(["list", "-plist"])
        let physical = try commandPlist(["list", "-plist", "physical"])
        let apfs = try commandPlist(["apfs", "list", "-plist"])
        var infos: [String: [String: Any]] = [:]
        for id in DiskInventory.identifiers(in: list).union(DiskInventory.identifiers(in: apfs)).sorted() {
            infos[id] = try? plistInfo(id)
        }
        let diagnostic: [String: Any] = ["list": list, "physical": physical, "apfs": apfs, "infos": infos]
        return try PropertyListSerialization.data(fromPropertyList: diagnostic, format: .xml, options: 0)
    }

    func discover() throws -> [ExternalDisk] {
        let list = try commandPlist(["list", "-plist"])
        let physical = try commandPlist(["list", "-plist", "physical"])
        let apfs = try commandPlist(["apfs", "list", "-plist"])
        var infos: [String: [String: Any]] = [:]
        var ids: Set<String> = []
        for entry in physical["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            guard let id = entry["DeviceIdentifier"] as? String else { continue }
            let info = try plistInfo(id)
            infos[id] = info
            if info["Internal"] as? Bool == false { ids.formUnion(DiskInventory.identifiers(in: entry)) }
        }
        let physicalChildren = ids
        for container in apfs["Containers"] as? [[String: Any]] ?? [] {
            let stores = container["PhysicalStores"] as? [[String: Any]]
                ?? container["APFSPhysicalStores"] as? [[String: Any]] ?? []
            guard stores.contains(where: { ($0["DeviceIdentifier"] as? String).map(physicalChildren.contains) == true }) else { continue }
            ids.formUnion(DiskInventory.identifiers(in: container))
            if let reference = container["ContainerReference"] as? String { ids.insert(reference) }
        }
        for entry in list["AllDisksAndPartitions"] as? [[String: Any]] ?? [] {
            if !DiskInventory.identifiers(in: entry).isDisjoint(with: ids) {
                ids.formUnion(DiskInventory.identifiers(in: entry))
            }
        }
        for id in ids.sorted() where infos[id] == nil { infos[id] = try? plistInfo(id) }
        let mounted = try mountedFilesystems()
        for (id, path) in mounted {
            guard var info = infos[id] ?? (try? plistInfo(id)) else {
                if ids.contains(id) { throw DiskServiceError.invalidDiskInfo }
                continue
            }
            guard ids.contains(id) || DiskInventory.parent(info).map(ids.contains) == true else { continue }
            ids.insert(id)
            info["MountPoint"] = path
            infos[id] = info
        }
        let disks = DiskInventory.build(list: list, physicalIDs: DiskInventory.identifiers(in: physical),
                                       apfs: apfs, infos: infos)
        return disks.map { disk in
            guard disk.mediaRegistryID == nil else { return disk }
            return ExternalDisk(id: disk.id, wholeDisk: disk.wholeDisk, model: disk.model, size: disk.size,
                                solidState: disk.solidState, connection: disk.connection,
                                identityTokens: disk.identityTokens, volumes: disk.volumes,
                                safetyIssue: "无法确认本次连接的硬件身份，请重新连接后再检查。")
        }
    }

    func locate(_ expected: ExternalDisk) throws -> ExternalDisk? {
        guard let current = try discover().first(where: { $0.id == expected.id }) else { return nil }
        guard expected.matches(current) else { throw DiskServiceError.identityMismatch }
        if let issue = current.safetyIssue { throw DiskServiceError.unsafeDisk(issue) }
        return current
    }

    func occupyingProcesses(on disk: ExternalDisk) -> (occupants: [DiskOccupant], warning: String?) {
        var occupants: [Int32: DiskOccupant] = [:]
        var warnings: [String] = []
        for mount in disk.mountPoints {
            do {
                let result = try occupyingProcesses(at: mount)
                if let warning = result.warning { warnings.append(warning) }
                for item in result.occupants {
                    if let prior = occupants[item.pid] {
                        occupants[item.pid] = DiskOccupant(pid: item.pid, command: item.command,
                            displayName: item.displayName, bundleIdentifier: item.bundleIdentifier, kind: item.kind,
                            openPaths: Array(Set(prior.openPaths + item.openPaths)).sorted(),
                            isExpectedSystemService: item.isExpectedSystemService,
                            blocksSafeUnmount: prior.blocksSafeUnmount || item.blocksSafeUnmount, note: item.note)
                    } else { occupants[item.pid] = item }
                }
            } catch { warnings.append(error.localizedDescription) }
        }
        return (occupants.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
                warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
    }

    func occupyingProcesses(at mountPoint: String) throws -> (occupants: [DiskOccupant], warning: String?) {
        let result = run("/usr/sbin/lsof", ["-nP", "-F0pcfn", "+f", "--", mountPoint])
        guard result.status == 0 || result.status == 1 else {
            throw DiskServiceError.commandFailed("无法检查正在使用硬盘的应用：\(result.stderr.trimmed)")
        }

        let records = OccupancyParser.records(result.stdout, mountPoint: mountPoint)

        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let expectedSystemCommands = Set([
            "mds", "mds_store", "mdworker", "mdworker_shared", "fseventsd",
            "diskarbitrationd", "Spotlight", "corespotlightd"
        ])

        let occupants = records.compactMap { pid, record -> DiskOccupant? in
            guard pid != ownPID else { return nil }
            let running = NSRunningApplication(processIdentifier: pid_t(pid))
            let applicationBundle = owningApplicationBundle(for: pid)
            let bundleIdentifier = applicationBundle?.bundleIdentifier ?? running?.bundleIdentifier
            let isExpectedSystemService = expectedSystemCommands.contains(record.command)
                || bundleIdentifier == "com.apple.Spotlight"
                || bundleIdentifier == "com.apple.metadata.mds"
            let kind: OccupantKind
            if isExpectedSystemService {
                kind = .systemService
            } else if applicationBundle != nil {
                kind = .application
            } else if let running,
                      running.activationPolicy != .prohibited || running.bundleURL?.pathExtension == "app" {
                kind = .application
            } else {
                kind = .backgroundProcess
            }
            let displayName = applicationDisplayName(from: applicationBundle)
                ?? running?.localizedName?.trimmed.nonEmpty
                ?? running?.bundleURL?.deletingPathExtension().lastPathComponent.nonEmpty
                ?? record.command
            let sortedPaths = Array(Set(record.paths)).sorted()
            let trashOnly = isTrashOnlyAccess(paths: sortedPaths, mountPoint: mountPoint)
            let blocksSafeUnmount = !isExpectedSystemService && !trashOnly
            let note = sortedPaths.isEmpty ? "发现进程，但文件路径无法完整读取。"
                : (trashOnly ? "只打开了废纸篓目录，是否阻碍卸载由 macOS 判断。" : nil)
            return DiskOccupant(
                pid: pid,
                command: record.command,
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                kind: kind,
                openPaths: sortedPaths,
                isExpectedSystemService: isExpectedSystemService,
                blocksSafeUnmount: blocksSafeUnmount,
                note: note
            )
        }
        let warning = result.stderr.trimmed.isEmpty ? nil
            : "占用检查有警告，结果可能不完整：\(result.stderr.trimmed)"
        return (occupants.sorted {
            if $0.blocksSafeUnmount != $1.blocksSafeUnmount { return $0.blocksSafeUnmount && !$1.blocksSafeUnmount }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }, warning)
    }

    private func isTrashOnlyAccess(paths: [String], mountPoint: String) -> Bool {
        guard !paths.isEmpty else { return false }
        let trashPrefix = mountPoint.hasSuffix("/") ? "\(mountPoint).Trashes" : "\(mountPoint)/.Trashes"
        return paths.allSatisfy { path in
            path == trashPrefix || path.hasPrefix("\(trashPrefix)/")
        }
    }

    private func owningApplicationBundle(for pid: Int32) -> Bundle? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        let executablePath = String(decoding: bytes, as: UTF8.self)
        let components = URL(fileURLWithPath: executablePath).pathComponents
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let appPath = NSString.path(withComponents: Array(components.prefix(through: appIndex)))
        return Bundle(url: URL(fileURLWithPath: appPath))
    }

    private func applicationDisplayName(from bundle: Bundle?) -> String? {
        guard let bundle else { return nil }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.trimmed.nonEmpty
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmed.nonEmpty
            ?? bundle.bundleURL.deletingPathExtension().lastPathComponent.nonEmpty
    }

    func unmountWholeDisk(_ expected: ExternalDisk) throws -> Bool {
        guard !unmountCommandsSuspended else {
            throw DiskServiceError.unsafeDisk("先前的卸载命令超时，结果尚不确定。本次运行已暂停后续卸载；请等待并在磁盘工具确认状态，不要立即拔线或关电。")
        }
        guard let current = try locate(expected) else { throw DiskServiceError.disconnected }
        guard current.isMounted else { return false }
        // Revalidate the physical device itself immediately before using its transient BSD identifier.
        let info = try plistInfo(current.wholeDisk)
        guard info["Internal"] as? Bool == false,
              (info["Whole"] as? Bool ?? info["WholeDisk"] as? Bool) == true,
              let registryID = current.mediaRegistryID,
              (info["MediaRegistryID"] as? NSNumber)?.uint64Value == registryID else {
            throw DiskServiceError.identityMismatch
        }
        if let uuid = DiskInventory.string(info, "DiskUUID", "MediaUUID"),
           !current.identityTokens.contains(uuid.lowercased()) { throw DiskServiceError.identityMismatch }
        let physical = try commandPlist(["list", "-plist", "physical"])
        guard let entry = (physical["AllDisksAndPartitions"] as? [[String: Any]])?
            .first(where: { $0["DeviceIdentifier"] as? String == current.wholeDisk }) else {
            throw DiskServiceError.identityMismatch
        }
        var verifiedInfos: [String: [String: Any]] = [:]
        for device in DiskInventory.identifiers(in: entry) {
            let child = try plistInfo(device)
            verifiedInfos[device] = child
            guard device == current.wholeDisk || DiskInventory.parent(child) == current.wholeDisk else {
                throw DiskServiceError.identityMismatch
            }
        }
        guard let expectedFingerprint = current.physicalFingerprint,
              let verifiedFingerprint = DiskInventory.physicalFingerprint(entry: entry, infos: verifiedInfos),
              expectedFingerprint == verifiedFingerprint else {
            throw DiskServiceError.identityMismatch
        }
        let result = run("/usr/sbin/diskutil", ["unmountDisk", current.wholeDisk], timeout: 90) {
            // Run after output-file setup, immediately before starting the system command.
            let finalInfo = try self.plistInfo(current.wholeDisk)
            guard finalInfo["Internal"] as? Bool == false,
                  (finalInfo["MediaRegistryID"] as? NSNumber)?.uint64Value == registryID else {
                throw DiskServiceError.identityMismatch
            }
        }
        if result.status == -2 {
            unmountCommandsSuspended = true
            throw DiskServiceError.unsafeDisk("卸载命令超时，系统请求可能仍在处理。本次运行已暂停后续卸载；请在磁盘工具确认状态，不能依据此次结果关电。")
        }
        guard result.status == 0 else {
            let detail = result.stderr.trimmed.isEmpty ? result.stdout.trimmed : result.stderr.trimmed
            throw DiskServiceError.commandFailed(detail.isEmpty ? "macOS 未能卸载硬盘。" : detail)
        }
        guard let after = try locate(current), !after.isMounted else {
            throw DiskServiceError.unsafeDisk("卸载命令已返回，但无法确认所有卷均已卸载；不会启动倒计时。")
        }
        return true
    }

    private func plistInfo(_ target: String) throws -> [String: Any] {
        // Disk Arbitration reads identity without diskutil info's potentially slow SMART query.
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, target),
              let raw = DADiskCopyDescription(disk) else { throw DiskServiceError.invalidDiskInfo }
        let description = raw as NSDictionary
        var info: [String: Any] = ["DeviceIdentifier": target]
        let mappings: [(CFString, String)] = [
            (kDADiskDescriptionDeviceInternalKey, "Internal"),
            (kDADiskDescriptionMediaWholeKey, "WholeDisk"),
            (kDADiskDescriptionMediaSizeKey, "TotalSize"),
            (kDADiskDescriptionDeviceModelKey, "DeviceModel"),
            (kDADiskDescriptionMediaNameKey, "MediaName"),
            (kDADiskDescriptionDeviceProtocolKey, "BusProtocol"),
            (kDADiskDescriptionMediaContentKey, "Content"),
            (kDADiskDescriptionVolumeNameKey, "VolumeName")
        ]
        for (key, name) in mappings { if let value = description[key] { info[name] = value } }
        for (key, name) in [(kDADiskDescriptionMediaUUIDKey, "DiskUUID"),
                            (kDADiskDescriptionVolumeUUIDKey, "VolumeUUID")] {
            if let value = description[key], CFGetTypeID(value as CFTypeRef) == CFUUIDGetTypeID() {
                info[name] = CFUUIDCreateString(kCFAllocatorDefault, (value as! CFUUID)) as String
            }
        }
        if let url = description[kDADiskDescriptionVolumePathKey] as? URL { info["MountPoint"] = url.path }
        if let whole = DADiskCopyWholeDisk(disk), let bsd = DADiskGetBSDName(whole) {
            info["ParentWholeDisk"] = String(cString: bsd)
        }
        let media = DADiskCopyIOMedia(disk)
        if media != 0 {
            defer { IOObjectRelease(media) }
            var registryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(media, &registryID) == KERN_SUCCESS {
                info["MediaRegistryID"] = NSNumber(value: registryID)
            }
            let options = IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
            if let property = IORegistryEntrySearchCFProperty(media, kIOServicePlane, "Solid State" as CFString, kCFAllocatorDefault, options),
               let solid = property as? Bool { info["SolidState"] = solid }
            if info["SolidState"] == nil,
               let property = IORegistryEntrySearchCFProperty(media, kIOServicePlane, "Device Characteristics" as CFString, kCFAllocatorDefault, options),
               let characteristics = property as? [String: Any], let medium = characteristics["Medium Type"] as? String {
                if medium == "Solid State" { info["SolidState"] = true }
                else if medium == "Rotational" { info["SolidState"] = false }
            }
        }
        return info
    }

    private func mountedFilesystems() throws -> [String: String] {
        var table: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&table, MNT_NOWAIT)
        guard count > 0, let table else { throw DiskServiceError.invalidDiskInfo }
        var result: [String: String] = [:]
        for index in 0..<Int(count) {
            var mount = table[index]
            let source = withUnsafeBytes(of: &mount.f_mntfromname) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let path = withUnsafeBytes(of: &mount.f_mntonname) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            guard let range = source.range(of: "/dev/", options: .backwards) else { continue }
            let device = String(source[range.upperBound...])
            if device.hasPrefix("disk"), !device.contains("/") { result[device] = path }
        }
        return result
    }

    private func commandPlist(_ arguments: [String]) throws -> [String: Any] {
        let result = run("/usr/sbin/diskutil", arguments)
        guard result.status == 0, let data = result.stdout.data(using: .utf8) else {
            throw DiskServiceError.commandFailed(result.stderr.trimmed.nonEmpty ?? result.stdout.trimmed)
        }
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any] else { throw DiskServiceError.invalidDiskInfo }
        return dictionary
    }

    private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 12,
                     prelaunch: (() throws -> Void)? = nil) -> CommandResult {
        let process = Process()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaCieSafeOff-\(UUID().uuidString)", isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: outputURL)
            let error = try FileHandle(forWritingTo: errorURL)
            process.standardOutput = output
            process.standardError = error
            try prelaunch?()
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(timeout * 1_000)))
            while process.isRunning && ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                let stopDeadline = ContinuousClock.now.advanced(by: .seconds(1))
                while process.isRunning && ContinuousClock.now < stopDeadline { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                let killDeadline = ContinuousClock.now.advanced(by: .seconds(1))
                while process.isRunning && ContinuousClock.now < killDeadline { Thread.sleep(forTimeInterval: 0.05) }
                try output.close()
                try error.close()
                try? FileManager.default.removeItem(at: temporaryDirectory)
                let command = ([executable] + arguments).joined(separator: " ")
                return CommandResult(status: -2, stdout: "", stderr: "系统磁盘命令超时，结果不确定：\(command)")
            }
            try output.close()
            try error.close()
            let stdout = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            let stderr = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: temporaryDirectory)
            return CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

}

enum OccupancyParser {
    struct Record {
        var command = "未知进程"
        var paths: [String] = []
    }

    static func records(_ output: String, mountPoint: String) -> [Int32: Record] {
        var records: [Int32: Record] = [:]
        var currentPID: Int32?
        // lsof -F0 uses NUL fields; newline characters inside filenames are not record separators.
        for raw in output.split(separator: "\0", omittingEmptySubsequences: true) {
            let field = raw.drop(while: { $0 == "\n" })
            guard let kind = field.first else { continue }
            let value = String(field.dropFirst())
            switch kind {
            case "p":
                currentPID = Int32(value)
                if let currentPID { records[currentPID] = Record() }
            case "c":
                if let currentPID { records[currentPID]?.command = value }
            case "n":
                if let currentPID, value == mountPoint || value.hasPrefix(mountPoint + "/") {
                    records[currentPID]?.paths.append(value)
                }
            default: break
            }
        }
        return records
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
