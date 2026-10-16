import XCTest
@testable import LabforgeCore

final class LabforgeParserTests: XCTestCase {
    func testParseSnapshotExtractsQuotaAndAvailability() throws {
        let quotaURL = try XCTUnwrap(Bundle.module.url(forResource: "quota-self", withExtension: "json"))
        let modelsURL = try XCTUnwrap(Bundle.module.url(forResource: "models-status", withExtension: "json"))
        let quotaData = try Data(contentsOf: quotaURL)
        let modelsData = try Data(contentsOf: modelsURL)

        let parser = LabforgeParser()
        let snapshot = try parser.makeSnapshot(quotaData: quotaData, modelsData: modelsData)

        XCTAssertEqual(snapshot.personalRemaining, 120)
        XCTAssertEqual(snapshot.teamRemaining, 980)
        XCTAssertEqual(snapshot.availableModelCount, 1)
        XCTAssertEqual(snapshot.primaryModelStatus, .available)
        XCTAssertEqual(snapshot.teamName, "OrbitOS")
    }
}
