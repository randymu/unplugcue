import XCTest
@testable import LaCieSafeOff

private actor FakeDiskService: DiskServicing {
    var disk: ExternalDisk?
    var occupants: [DiskOccupant] = []
    var failUnmount = false
    var unmountCalls = 0
    var checks = 0
    var failDiscovery = false
    var leavesMounted = false

    init(disk: ExternalDisk?) { self.disk = disk }
    func setOccupants(_ value: [DiskOccupant]) { occupants = value }
    func setFailure(_ value: Bool) { failUnmount = value }
    func setDisk(_ value: ExternalDisk?) { disk = value }
    func setDiscoveryFailure(_ value: Bool) { failDiscovery = value }
    func setLeavesMounted(_ value: Bool) { leavesMounted = value }
    func discover() throws -> [ExternalDisk] {
        if failDiscovery { throw DiskServiceError.invalidDiskInfo }
        return disk.map { [$0] } ?? []
    }
    func locate(_ expected: ExternalDisk) throws -> ExternalDisk? {
        if failDiscovery { throw DiskServiceError.invalidDiskInfo }
        if let disk, !expected.matches(disk) { throw DiskServiceError.identityMismatch }
        if let issue = disk?.safetyIssue { throw DiskServiceError.unsafeDisk(issue) }
        return disk
    }
    func occupyingProcesses(on disk: ExternalDisk) -> (occupants: [DiskOccupant], warning: String?) {
        checks += 1
        return (occupants, nil)
    }
    func unmountWholeDisk(_ expected: ExternalDisk) throws -> Bool {
        unmountCalls += 1
        if failUnmount { throw DiskServiceError.commandFailed("disk is busy") }
        if let disk, !leavesMounted {
            self.disk = ExternalDisk(id: disk.id, wholeDisk: disk.wholeDisk, model: disk.model, size: disk.size,
                solidState: disk.solidState, connection: disk.connection, identityTokens: disk.identityTokens,
                volumes: disk.volumes.map { DiskVolume(device: $0.device, uuid: $0.uuid, name: $0.name, mountPoint: nil) },
                safetyIssue: disk.safetyIssue, mediaRegistryID: disk.mediaRegistryID)
        }
        return true
    }
}

final class AppModelTests: XCTestCase {
    private func disk(mounted: Bool = true, solidState: Bool = true) -> ExternalDisk {
        ExternalDisk(id: "test-ssd", wholeDisk: "disk20", model: "Test SSD", size: 2_000_000_000_000,
                     solidState: solidState, connection: "USB", identityTokens: ["test-ssd"],
                     volumes: [DiskVolume(device: "disk20s1", uuid: "test-volume", name: "Test",
                                          mountPoint: mounted ? "/Volumes/Test" : nil)], safetyIssue: nil)
    }

    @MainActor func testCheckDoesNotUnmount() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.checkOccupants(d)
        let calls = await fake.unmountCalls
        XCTAssertEqual(calls, 0)
        guard case .busy(let occupants, _, let failure) = model.state(for: d) else { return XCTFail("Expected check results") }
        XCTAssertTrue(occupants.isEmpty)
        XCTAssertNil(failure)
    }
    @MainActor func testOpenFilesDoNotAutomaticallyBlockNormalUnmount() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        await fake.setOccupants([DiskOccupant(pid: 123, command: "Test", displayName: "Test App", bundleIdentifier: nil,
            kind: .application, openPaths: ["/Volumes/Test/image.raw"], isExpectedSystemService: false,
            blocksSafeUnmount: true, note: nil)])
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        let calls = await fake.unmountCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.state(for: d), .safeToDisconnect)
    }
    @MainActor func testFailureRechecksOccupantsWithoutCountdown() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        await fake.setFailure(true)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        let checks = await fake.checks
        XCTAssertEqual(checks, 2)
        guard case .busy(_, _, let failure) = model.state(for: d) else { return XCTFail("Expected failure results") }
        XCTAssertEqual(failure, "disk is busy")
    }
    @MainActor func testAlreadyUnmountedDoesNotStartOperation() async {
        let d = disk(mounted: false)
        let fake = FakeDiskService(disk: d)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        let calls = await fake.unmountCalls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.state(for: d), .alreadyUnmounted)
    }
    @MainActor func testDisconnectedDoesNotStartUnmount() async {
        let d = disk()
        let fake = FakeDiskService(disk: nil)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.beginSafeUnmount(d)
        let calls = await fake.unmountCalls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(model.state(for: d), .notConnected)
    }
    @MainActor func testRecheckReplacesOldOccupants() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        await fake.setOccupants([DiskOccupant(pid: 123, command: "App", displayName: "App", bundleIdentifier: nil,
            kind: .application, openPaths: ["/Volumes/Test/test.raw"], isExpectedSystemService: false,
            blocksSafeUnmount: true, note: nil)])
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.checkOccupants(d)
        await fake.setOccupants([])
        await model.checkOccupants(d)
        guard case .busy(let latest, _, _) = model.state(for: d) else { return XCTFail("Expected new results") }
        XCTAssertTrue(latest.isEmpty)
        let calls = await fake.unmountCalls
        XCTAssertEqual(calls, 0)
    }
    @MainActor func testRemountCancelsHDDReminder() async {
        let d = disk(solidState: false)
        let fake = FakeDiskService(disk: d)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        guard case .countdown = model.state(for: d) else { return XCTFail("Expected HDD countdown") }
        await fake.setDisk(d)
        await model.refreshAll()
        XCTAssertEqual(model.state(for: d), .ready)
    }

    @MainActor func testDiscoveryFailureRevokesSafeStatus() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        XCTAssertEqual(model.state(for: d), .safeToDisconnect)
        await fake.setDiscoveryFailure(true)
        await model.refreshAll()
        guard case .failed = model.state(for: d) else { return XCTFail("Stale safety status must be revoked") }
    }

    @MainActor func testDiscoveryFailureStopsCountdown() async {
        let d = disk(solidState: false)
        let fake = FakeDiskService(disk: d)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        guard case .countdown = model.state(for: d) else { return XCTFail("Expected countdown") }
        await fake.setDiscoveryFailure(true)
        await model.refreshAll()
        guard case .failed = model.state(for: d) else { return XCTFail("Countdown must stop on read failure") }
    }

    @MainActor func testMountedDiskNeverGetsSafeStatusEvenAfterReportedSuccess() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        await fake.setLeavesMounted(true)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        XCTAssertEqual(model.state(for: d), .ready)
    }

    @MainActor func testUnsafeTopologyRevokesGreenStatus() async {
        let d = disk()
        let fake = FakeDiskService(disk: d)
        let model = AppModel(service: fake, monitoring: false, notificationsEnabled: false)
        await model.refreshAll()
        await model.beginSafeUnmount(d)
        let unsafe = ExternalDisk(id: d.id, wholeDisk: d.wholeDisk, model: d.model, size: d.size,
            solidState: true, connection: d.connection, identityTokens: d.identityTokens, volumes: [],
            safetyIssue: "APFS topology missing")
        await fake.setDisk(unsafe)
        await model.refreshAll()
        guard case .failed = model.state(for: d) else { return XCTFail("Unsafe topology must not remain green") }
    }
}
