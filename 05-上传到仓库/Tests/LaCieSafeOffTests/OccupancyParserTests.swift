import XCTest
@testable import LaCieSafeOff

final class OccupancyParserTests: XCTestCase {
    func testNullSeparatedProcessAndFileRecords() {
        let output = "p123\0cLightroom\0\nf4\0n/Volumes/Photos/catalog.lrcat\0\nf7\0n/Volumes/Photos/image.raw\0\np456\0cFinder\0\nf8\0n/Volumes/Other/file\0\n"
        let records = OccupancyParser.records(output, mountPoint: "/Volumes/Photos")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[123]?.command, "Lightroom")
        XCTAssertEqual(records[123]?.paths.count, 2)
    }

    func testFilenameCannotInjectProcessRecord() {
        let path = "/Volumes/Photos/image\np999\ncFake.raw"
        let records = OccupancyParser.records("p123\0cFinder\0\nf4\0n\(path)\0\n", mountPoint: "/Volumes/Photos")
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records[999])
        XCTAssertEqual(records[123]?.paths, [path])
    }

    func testSimilarVolumeNameIsNotIncluded() {
        let records = OccupancyParser.records("p123\0cFinder\0\nf4\0n/Volumes/Photos-old/file\0\n", mountPoint: "/Volumes/Photos")
        XCTAssertEqual(records[123]?.paths, [])
    }
}
