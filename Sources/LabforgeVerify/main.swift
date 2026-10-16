import Foundation
import LabforgeCore

actor StubLabforgeClient: LabforgeClientProtocol {
    private(set) var quotaFetchCount = 0
    private(set) var modelsFetchCount = 0
    private let quotaData: Data
    private let modelsData: Data

    init(quotaData: Data, modelsData: Data) {
        self.quotaData = quotaData
        self.modelsData = modelsData
    }

    func login(credentials: Credentials) async throws {}

    func fetchQuotaData() async throws -> Data {
        quotaFetchCount += 1
        return quotaData
    }

    func fetchModelsData() async throws -> Data {
        modelsFetchCount += 1
        return modelsData
    }

    func validateSession() async throws -> Bool {
        true
    }

    func counts() -> (Int, Int) {
        (quotaFetchCount, modelsFetchCount)
    }
}

@main
struct LabforgeVerify {
    static func main() async {
        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let quotaURL = root.appendingPathComponent("Tests/LabforgeCoreTests/Fixtures/quota-self.json")
            let modelsURL = root.appendingPathComponent("Tests/LabforgeCoreTests/Fixtures/models-status.json")
            let quotaData = try Data(contentsOf: quotaURL)
            let modelsData = try Data(contentsOf: modelsURL)

            let parser = LabforgeParser()
            let snapshot = try parser.makeSnapshot(quotaData: quotaData, modelsData: modelsData)
            try expect(snapshot.teamPoolRemaining == 980, "teamPoolRemaining should equal 980")
            try expect(snapshot.personalGrantRemaining == 120, "personalGrantRemaining should equal 120")
            try expect(snapshot.availableModelCount == 1, "availableModelCount should equal 1")
            try expect(snapshot.primaryModelStatus == .available, "primaryModelStatus should be available")

            let credentialsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("labforge-credentials-\(UUID().uuidString).json")
            let credentialsStore = LocalCredentialsStore(fileURL: credentialsURL)
            try credentialsStore.saveCredentials(username: "njiter", password: "secret")
            let credentials = try expectNotNil(try credentialsStore.loadCredentials(), "credentials should round-trip")
            try expect(credentials.username == "njiter", "username should round-trip")
            try credentialsStore.deleteCredentials()

            let cache = InMemorySnapshotStore()
            let client = StubLabforgeClient(quotaData: quotaData, modelsData: modelsData)
            let refresh = RefreshService(client: client, cache: cache, parser: parser)
            async let first = refresh.refresh()
            async let second = refresh.refresh()
            _ = try await [first, second]

            let counts = await client.counts()
            try expect(counts.0 == 1, "concurrent refresh should deduplicate quota fetch")
            try expect(counts.1 == 1, "concurrent refresh should deduplicate models fetch")
            try expect(cache.snapshot?.teamPoolRemaining == 980, "cache should store refreshed snapshot")

            print("LabforgeVerify: PASS")
        } catch {
            fputs("LabforgeVerify: FAIL - \(error)\n", stderr)
            exit(1)
        }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw AppError.parseFailure(message)
        }
    }

    static func expectNotNil<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw AppError.parseFailure(message)
        }
        return value
    }
}
