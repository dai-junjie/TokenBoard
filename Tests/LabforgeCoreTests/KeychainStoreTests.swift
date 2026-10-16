import XCTest
@testable import LabforgeCore

final class LocalCredentialsStoreTests: XCTestCase {
    func testCredentialsRoundTripThroughStore() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("labforge-credentials-\(UUID().uuidString).json")
        let store = LocalCredentialsStore(fileURL: fileURL)
        try store.deleteCredentials()
        try store.saveCredentials(username: "njiter", password: "secret")

        let credentials = try XCTUnwrap(try store.loadCredentials())
        XCTAssertEqual(credentials.username, "njiter")
        XCTAssertEqual(credentials.password, "secret")
    }
}
