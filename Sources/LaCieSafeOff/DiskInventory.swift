// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import Foundation

struct DiskVolume: Identifiable, Equatable, Codable, Sendable {
    let device: String
    let uuid: String?
    let name: String
    let mountPoint: String?
    var id: String { device }
}

struct PhysicalMediaIdentity: Equatable, Codable, Sendable {
    let device: String
    let parent: String?
    let registryID: UInt64?
    let size: Int64
    let model: String?
    let uuids: [String]
}

struct ExternalDisk: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let wholeDisk: String
    let model: String
    let size: Int64
    let solidState: Bool?
    let connection: String
    let identityTokens: [String]
    let volumes: [DiskVolume]
    let safetyIssue: String?
    var mediaRegistryID: UInt64? = nil
    var physicalFingerprint: [PhysicalMediaIdentity]? = nil

    var name: String {
        let names = volumes.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? model : names.joined(separator: " · ")
    }
    var mountPoints: [String] { Array(Set(volumes.compactMap(\.mountPoint))).sorted() }
    var isMounted: Bool { !mountPoints.isEmpty }
    var mediaType: String {
        switch solidState {
        case true?: "SSD"
        case false?: "机械硬盘"
        case nil: "类型未知"
        }
    }

    func matches(_ other: ExternalDisk) -> Bool {
        id == other.id && size == other.size && model == other.model
            && identityTokens == other.identityTokens && mediaRegistryID == other.mediaRegistryID
    }
}

// Parse diskutil topology separately so identity and internal-disk protection can be tested without disks.
enum DiskInventory {
    static func physicalFingerprint(entry: [String: Any], infos: [String: [String: Any]]) -> [PhysicalMediaIdentity]? {
        var result: [PhysicalMediaIdentity] = []
        for id in identifiers(in: entry).sorted() {
            guard let info = infos[id] else { return nil }
            let uuids = ["DiskUUID", "MediaUUID", "VolumeUUID", "APFSVolumeUUID", "APFSContainerUUID"]
                .compactMap { info[$0] as? String }.filter { !$0.isEmpty }.map { $0.lowercased() }.sorted()
            result.append(PhysicalMediaIdentity(device: id, parent: parent(info),
                registryID: (info["MediaRegistryID"] as? NSNumber)?.uint64Value,
                size: (info["TotalSize"] as? NSNumber)?.int64Value ?? 0,
                model: string(info, "MediaName", "DeviceModel"), uuids: uuids))
        }
        return result.isEmpty ? nil : result
    }

    static func identifiers(in value: Any) -> Set<String> {
        var result: Set<String> = []
        func collect(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let id = dict["DeviceIdentifier"] as? String { result.insert(id) }
                if let snapshot = dict["SnapshotBSD"] as? String { result.insert(snapshot) }
                dict.values.forEach(collect)
            } else if let values = value as? [Any] { values.forEach(collect) }
        }
        collect(value)
        return result
    }

    static func string(_ info: [String: Any], _ keys: String...) -> String? {
        keys.compactMap { info[$0] as? String }.first { !$0.isEmpty }
    }

    static func parent(_ info: [String: Any]) -> String? {
        string(info, "ParentWholeDisk", "PartOfWhole")
    }

    static func build(list: [String: Any], physicalIDs: Set<String>, apfs: [String: Any],
                      infos: [String: [String: Any]]) -> [ExternalDisk] {
        let entries = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        let containers = apfs["Containers"] as? [[String: Any]] ?? []
        var output: [ExternalDisk] = []
        for entry in entries {
            guard let device = entry["DeviceIdentifier"] as? String,
                  physicalIDs.contains(device), let info = infos[device],
                  info["Internal"] as? Bool == false,
                  (info["Whole"] as? Bool ?? info["WholeDisk"] as? Bool) == true,
                  string(info, "VirtualOrPhysical") != "Virtual",
                  string(info, "BusProtocol") != "Disk Image" else { continue }

            var devices = identifiers(in: entry)
            let physicalDevices = devices
            var tokens: Set<String> = []
            var issue: String?
            var mappedAPFSStores: Set<String> = []
            for container in containers {
                let stores = container["PhysicalStores"] as? [[String: Any]]
                    ?? container["APFSPhysicalStores"] as? [[String: Any]] ?? []
                let parents = stores.compactMap { store -> String? in
                    guard let id = store["DeviceIdentifier"] as? String, let storeInfo = infos[id] else { return nil }
                    return parent(storeInfo)
                }
                guard parents.contains(device) else { continue }
                mappedAPFSStores.formUnion(stores.compactMap { $0["DeviceIdentifier"] as? String })
                devices.formUnion(identifiers(in: container))
                if let reference = container["ContainerReference"] as? String { devices.insert(reference) }
                if let uuid = string(container, "APFSContainerUUID", "ContainerUUID") {
                    tokens.insert(uuid.lowercased())
                }
                if stores.count != 1 || parents.count != stores.count {
                    issue = "此 APFS 容器关联多个物理存储或拓扑不完整，暂不支持整盘卸载。"
                }
                if container["Volumes"] as? [[String: Any]] == nil {
                    issue = "APFS 卷清单缺失，无法确认全部挂载状态。"
                }
            }

            // diskutil list can expose snapshots/volumes omitted by a partial apfs-list response.
            for related in entries where !identifiers(in: related).isDisjoint(with: devices) {
                devices.formUnion(identifiers(in: related))
            }

            for id in physicalDevices {
                guard let child = infos[id] else { continue }
                if string(child, "Content") == "Apple_APFS", !mappedAPFSStores.contains(id) {
                    issue = "APFS 容器信息不完整，无法确认全部卷；暂不允许卸载或关电提醒。"
                }
                if string(child, "Content")?.hasPrefix("Apple_RAID") == true {
                    issue = "暂不支持 Apple 软件 RAID；请使用 macOS 磁盘工具处理。"
                }
            }

            // Include all visible children, not just the first mounted volume.
            for (id, child) in infos where parent(child).map(devices.contains) == true { devices.insert(id) }
            var volumes: [DiskVolume] = []
            for id in devices.sorted() {
                guard let child = infos[id] else {
                    issue = "部分分区信息读取失败，无法确认整盘范围；请重新检查。"
                    continue
                }
                for key in ["DiskUUID", "MediaUUID", "VolumeUUID", "APFSVolumeUUID", "APFSContainerUUID"] {
                    if let uuid = child[key] as? String, !uuid.isEmpty { tokens.insert(uuid.lowercased()) }
                }
                let mount = string(child, "MountPoint")
                if let mount, mount == "/" || mount == "/System/Volumes" || mount.hasPrefix("/System/Volumes/") {
                    issue = "这块硬盘包含当前系统正在使用的卷，禁止在此卸载。"
                }
                let name = string(child, "VolumeName")
                let content = string(child, "Content")
                if name != nil || mount != nil || string(child, "VolumeUUID", "APFSVolumeUUID") != nil {
                    if mount != nil || (content != "EFI" && name != "EFI") {
                        volumes.append(DiskVolume(device: id, uuid: string(child, "VolumeUUID", "APFSVolumeUUID"),
                                                  name: name ?? id, mountPoint: mount))
                    }
                }
            }
            let sortedTokens = tokens.sorted()
            let identity = string(info, "DiskUUID", "MediaUUID")?.lowercased() ?? sortedTokens.first
            if identity == nil { issue = "无法获取稳定的磁盘或分区 UUID，为避免误卸载暂不开放操作。" }
            output.append(ExternalDisk(
                id: identity ?? "unidentified-\(device)", wholeDisk: device,
                model: string(info, "MediaName", "DeviceModel", "IORegistryEntryName") ?? "外置硬盘",
                size: (info["TotalSize"] as? NSNumber ?? info["Size"] as? NSNumber ?? info["IOKitSize"] as? NSNumber)?.int64Value ?? 0,
                solidState: info["SolidState"] as? Bool, connection: string(info, "BusProtocol") ?? "外置连接",
                identityTokens: sortedTokens, volumes: volumes, safetyIssue: issue,
                mediaRegistryID: (info["MediaRegistryID"] as? NSNumber)?.uint64Value,
                physicalFingerprint: physicalFingerprint(entry: entry, infos: infos)
            ))
        }
        // Cloned UUIDs are not sufficient to select one of two simultaneously connected disks.
        let counts = Dictionary(grouping: output, by: \.id).mapValues(\.count)
        return output.map { disk in
            guard counts[disk.id, default: 0] > 1 else { return disk }
            return ExternalDisk(id: "duplicate-\(disk.wholeDisk)", wholeDisk: disk.wholeDisk, model: disk.model,
                                size: disk.size, solidState: disk.solidState, connection: disk.connection,
                                identityTokens: disk.identityTokens, volumes: disk.volumes,
                                safetyIssue: "检测到重复磁盘 UUID，请断开其中一块后重新检查。",
                                mediaRegistryID: disk.mediaRegistryID, physicalFingerprint: disk.physicalFingerprint)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
