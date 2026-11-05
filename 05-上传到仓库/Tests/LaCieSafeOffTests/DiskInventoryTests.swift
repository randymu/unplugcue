import XCTest
@testable import LaCieSafeOff

final class DiskInventoryTests: XCTestCase {
    private func fixture(internalDisk: Bool = false, virtual: Bool = false) -> (list: [String: Any], infos: [String: [String: Any]]) {
        let list: [String: Any] = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk5", "Partitions": [
            ["DeviceIdentifier": "disk5s1"], ["DeviceIdentifier": "disk5s2"]
        ]]]]
        let infos: [String: [String: Any]] = [
            "disk5": ["Whole": true, "Internal": internalDisk, "DiskUUID": "PHYSICAL-UUID", "MediaName": "Test SSD",
                      "VirtualOrPhysical": virtual ? "Virtual" : "Physical", "BusProtocol": "USB",
                      "TotalSize": Int64(2_000_000_000_000), "SolidState": true],
            "disk5s1": ["PartOfWhole": "disk5", "VolumeName": "Pictures", "VolumeUUID": "A",
                        "MountPoint": "/Volumes/Pictures", "DiskUUID": "P1"],
            "disk5s2": ["PartOfWhole": "disk5", "VolumeName": "Projects", "VolumeUUID": "B", "DiskUUID": "P2"]
        ]
        return (list, infos)
    }
    private func build(_ value: (list: [String: Any], infos: [String: [String: Any]]), apfs: [String: Any] = [:]) -> [ExternalDisk] {
        DiskInventory.build(list: value.list, physicalIDs: ["disk5"], apfs: apfs, infos: value.infos)
    }

    func testGroupsMountedAndUnmountedPartitions() throws {
        let disk = try XCTUnwrap(build(fixture()).first)
        XCTAssertEqual(disk.volumes.count, 2)
        XCTAssertEqual(disk.mountPoints, ["/Volumes/Pictures"])
        XCTAssertEqual(disk.size, 2_000_000_000_000)
        XCTAssertEqual(disk.solidState, true)
        XCTAssertNil(disk.safetyIssue)
    }
    func testExcludesInternalVirtualAndNonphysicalDisks() {
        XCTAssertTrue(build(fixture(internalDisk: true)).isEmpty)
        XCTAssertTrue(build(fixture(virtual: true)).isEmpty)
        let f = fixture()
        XCTAssertTrue(DiskInventory.build(list: f.list, physicalIDs: [], apfs: [:], infos: f.infos).isEmpty)
    }
    func testMissingExternalClassificationIsExcluded() {
        var f = fixture()
        f.infos["disk5"]?.removeValue(forKey: "Internal")
        XCTAssertTrue(build(f).isEmpty)
    }
    func testUUIDRequiredAndIncompleteInfoBlocksAction() throws {
        var f = fixture()
        for id in Array(f.infos.keys) {
            f.infos[id]?.removeValue(forKey: "VolumeUUID")
            f.infos[id]?.removeValue(forKey: "DiskUUID")
        }
        XCTAssertNotNil(try XCTUnwrap(build(f).first).safetyIssue)
        f = fixture()
        f.infos.removeValue(forKey: "disk5s2")
        XCTAssertNotNil(try XCTUnwrap(build(f).first).safetyIssue)
    }
    func testCurrentSystemVolumeIsProtected() throws {
        var f = fixture()
        f.infos["disk5s1"]?["MountPoint"] = "/System/Volumes/Data"
        XCTAssertNotNil(try XCTUnwrap(build(f).first).safetyIssue)
    }
    func testIdentitySurvivesUnmountButNotReformat() throws {
        var f = fixture()
        let before = try XCTUnwrap(build(f).first)
        f.infos["disk5s1"]?.removeValue(forKey: "MountPoint")
        let after = try XCTUnwrap(build(f).first)
        XCTAssertTrue(before.matches(after))
        XCTAssertFalse(after.isMounted)
        f.infos["disk5s1"]?["VolumeUUID"] = "NEW-UUID"
        XCTAssertFalse(before.matches(try XCTUnwrap(build(f).first)))
    }
    func testReusedBSDNumberDoesNotMatch() throws {
        var f = fixture()
        let original = try XCTUnwrap(build(f).first)
        f.infos["disk5"]?["DiskUUID"] = "OTHER-PHYSICAL"
        XCTAssertFalse(original.matches(try XCTUnwrap(build(f).first)))
    }
    func testAPFSMapsAllVolumesToPhysicalStore() throws {
        var f = fixture()
        f.infos["disk5s2"] = ["PartOfWhole": "disk5", "DiskUUID": "STORE", "Content": "Apple_APFS"]
        f.infos["disk9"] = ["Whole": true, "VirtualOrPhysical": "Virtual"]
        f.infos["disk9s1"] = ["PartOfWhole": "disk9", "VolumeName": "APFS Photo", "VolumeUUID": "C", "MountPoint": "/Volumes/APFS Photo"]
        f.infos["disk9s2"] = ["PartOfWhole": "disk9", "VolumeName": "APFS Backup", "VolumeUUID": "D"]
        let apfs: [String: Any] = ["Containers": [["ContainerReference": "disk9", "APFSContainerUUID": "CONTAINER",
            "PhysicalStores": [["DeviceIdentifier": "disk5s2"]],
            "Volumes": [["DeviceIdentifier": "disk9s1"], ["DeviceIdentifier": "disk9s2"]]]]]
        let disk = try XCTUnwrap(build(f, apfs: apfs).first)
        XCTAssertEqual(disk.wholeDisk, "disk5")
        XCTAssertEqual(disk.volumes.count, 3)
        XCTAssertEqual(disk.mountPoints, ["/Volumes/APFS Photo", "/Volumes/Pictures"])
        XCTAssertNil(disk.safetyIssue)
    }
    func testMultiStoreAPFSIsBlocked() throws {
        var f = fixture()
        f.infos["disk9"] = ["Whole": true]
        f.infos["disk7s2"] = ["PartOfWhole": "disk7"]
        let apfs: [String: Any] = ["Containers": [["ContainerReference": "disk9",
            "PhysicalStores": [["DeviceIdentifier": "disk5s2"], ["DeviceIdentifier": "disk7s2"]]]]]
        XCTAssertNotNil(try XCTUnwrap(build(f, apfs: apfs).first).safetyIssue)
    }
    func testDuplicateUUIDsAreBlocked() {
        var f = fixture()
        var entries = f.list["AllDisksAndPartitions"] as! [[String: Any]]
        entries.append(["DeviceIdentifier": "disk6"])
        f.list["AllDisksAndPartitions"] = entries
        f.infos["disk6"] = f.infos["disk5"]
        let disks = DiskInventory.build(list: f.list, physicalIDs: ["disk5", "disk6"], apfs: [:], infos: f.infos)
        XCTAssertEqual(disks.count, 2)
        XCTAssertEqual(Set(disks.map(\.id)).count, 2)
        XCTAssertTrue(disks.allSatisfy { $0.safetyIssue != nil })
    }
    func testUnpartitionedExternalFilesystemIsIncluded() throws {
        let list: [String: Any] = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk5"]]]
        let infos: [String: [String: Any]] = ["disk5": ["Whole": true, "Internal": false,
            "VolumeUUID": "RAW-VOLUME", "VolumeName": "Portable", "MountPoint": "/Volumes/Portable",
            "VirtualOrPhysical": "Physical", "BusProtocol": "USB"]]
        let disk = try XCTUnwrap(build((list, infos)).first)
        XCTAssertTrue(disk.isMounted)
        XCTAssertEqual(disk.volumes.count, 1)
        XCTAssertNil(disk.safetyIssue)
    }
    func testDeviceRenumberingDoesNotChangeIdentity() throws {
        let disk = try XCTUnwrap(build(fixture()).first)
        let renumbered = ExternalDisk(id: disk.id, wholeDisk: "disk12", model: disk.model, size: disk.size,
            solidState: disk.solidState, connection: disk.connection, identityTokens: disk.identityTokens,
            volumes: [DiskVolume(device: "disk12s1", uuid: "A", name: "Pictures", mountPoint: "/Volumes/Pictures")], safetyIssue: nil)
        XCTAssertTrue(disk.matches(renumbered))
    }
    func testMountedEFIIsIncludedInWholeDiskScope() throws {
        var f = fixture()
        f.infos["disk5s2"]?["VolumeName"] = "EFI"
        f.infos["disk5s2"]?["Content"] = "EFI"
        f.infos["disk5s2"]?["MountPoint"] = "/Volumes/EFI"
        let disk = try XCTUnwrap(build(f).first)
        XCTAssertTrue(disk.mountPoints.contains("/Volumes/EFI"))
    }
    func testMountedSnapshotIdentifiersAreCollected() {
        let ids = DiskInventory.identifiers(in: ["MountedSnapshots": [["SnapshotBSD": "disk9s1s1"]]])
        XCTAssertTrue(ids.contains("disk9s1s1"))
    }

    func testMissingAPFSContainerBlocksSafetyClaim() throws {
        var f = fixture()
        f.infos["disk5s2"] = ["PartOfWhole": "disk5", "DiskUUID": "STORE", "Content": "Apple_APFS"]
        XCTAssertNotNil(try XCTUnwrap(build(f).first).safetyIssue)
    }

    func testSoftwareRAIDIsBlocked() throws {
        var f = fixture()
        f.infos["disk5s2"]?["Content"] = "Apple_RAID"
        XCTAssertNotNil(try XCTUnwrap(build(f).first).safetyIssue)
    }

    func testHotSwapOfCloneWithSameUUIDsDoesNotMatch() throws {
        var f = fixture()
        f.infos["disk5"]?["MediaRegistryID"] = NSNumber(value: UInt64(100))
        let first = try XCTUnwrap(build(f).first)
        f.infos["disk5"]?["MediaRegistryID"] = NSNumber(value: UInt64(200))
        XCTAssertFalse(first.matches(try XCTUnwrap(build(f).first)))
    }

    func testFingerprintRejectsDroppedPhysicalPartition() throws {
        let f = fixture()
        let entry = try XCTUnwrap((f.list["AllDisksAndPartitions"] as? [[String: Any]])?.first)
        let before = try XCTUnwrap(DiskInventory.physicalFingerprint(entry: entry, infos: f.infos))
        let reduced: [String: Any] = ["DeviceIdentifier": "disk5", "Partitions": [["DeviceIdentifier": "disk5s1"]]]
        XCTAssertNotEqual(before, DiskInventory.physicalFingerprint(entry: reduced, infos: f.infos))
        var missing = f.infos
        missing.removeValue(forKey: "disk5s2")
        XCTAssertNil(DiskInventory.physicalFingerprint(entry: entry, infos: missing))
    }

    func testListOnlyAPFSSnapshotProtectsSystemDisk() throws {
        var f = fixture()
        f.infos["disk5s2"] = ["PartOfWhole": "disk5", "DiskUUID": "STORE", "Content": "Apple_APFS"]
        f.infos["disk9"] = ["Whole": true]
        f.infos["disk9s1"] = ["PartOfWhole": "disk9", "VolumeUUID": "C"]
        f.infos["disk9s1s1"] = ["PartOfWhole": "disk9", "MountPoint": "/"]
        var entries = f.list["AllDisksAndPartitions"] as! [[String: Any]]
        entries.append(["DeviceIdentifier": "disk9", "Volumes": [["DeviceIdentifier": "disk9s1"]],
                        "MountedSnapshots": [["SnapshotBSD": "disk9s1s1"]]])
        f.list["AllDisksAndPartitions"] = entries
        let apfs: [String: Any] = ["Containers": [["ContainerReference": "disk9", "PhysicalStores": [["DeviceIdentifier": "disk5s2"]],
                                                 "Volumes": [["DeviceIdentifier": "disk9s1"]]]]]
        let disk = try XCTUnwrap(build(f, apfs: apfs).first)
        XCTAssertTrue(disk.mountPoints.contains("/"))
        XCTAssertNotNil(disk.safetyIssue)
    }

    func testMissingAPFSParentMappingIsBlocked() throws {
        var f = fixture()
        f.infos["disk5s2"] = ["DiskUUID": "STORE", "Content": "Apple_APFS"]
        let apfs: [String: Any] = ["Containers": [["ContainerReference": "disk9", "PhysicalStores": [["DeviceIdentifier": "disk5s2"]],
                                                 "Volumes": []]]]
        XCTAssertNotNil(try XCTUnwrap(build(f, apfs: apfs).first).safetyIssue)
    }
}
