import Foundation
import XCTest
@testable import LabforgeCore

final class RefreshServiceTests: XCTestCase {
    func testRefreshDeduplicatesConcurrentCallsAndCachesSnapshot() async throws {
        let quotaURL = try XCTUnwrap(Bundle.module.url(forResource: "quota-self", withExtension: "json"))
        let modelsURL = try XCTUnwrap(Bundle.module.url(forResource: "models-status", withExtension: "json"))
        let quotaData = try Data(contentsOf: quotaURL)
        let modelsData = try Data(contentsOf: modelsURL)

        let client = StubLabforgeClient(quotaData: quotaData, modelsData: modelsData)
        let cache = InMemorySnapshotStore()
        let service = RefreshService(client: client, cache: cache, parser: LabforgeParser())

        async let first = service.refresh()
        async let second = service.refresh()
        let snapshots = try await [first, second]

        XCTAssertEqual(snapshots[0].teamRemaining, 980)
        XCTAssertEqual(snapshots[1].teamRemaining, 980)
        XCTAssertEqual(await client.quotaFetchCount, 1)
        XCTAssertEqual(await client.modelsFetchCount, 1)
        XCTAssertEqual(cache.snapshot?.personalRemaining, 120)
    }
}
