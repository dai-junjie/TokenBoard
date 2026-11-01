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
            let teamBuddyJSON = #"{"quotas":{"teams":[{"team_id":2,"team_name":"Research","member_status":"active","team_status":"active","base_quota":20000000,"temporary_quota":0,"base_used_quota":500000,"remaining_quota":19500000,"reserved_quota":0,"team_borne_quota":1000000,"period_end_at":1793577600}]},"overviews":[{"team_id":2,"data":{"daily_limit":{"quota":150000000,"spent":17500000}}}],"currency":{"quota_per_unit":500000,"quota_display_type":"CNY","usd_exchange_rate":1}}"#
            let teamBuddy = try TeamBuddySnapshot.parse(teamBuddyJSON)
            try expect(teamBuddy.quotas.teams[0].remaining_quota == 19_500_000, "TeamBuddy should preserve actual remaining quota")
            try expect(teamBuddy.formatted(19_500_000) == "¥39.00", "TeamBuddy must use the server's currency conversion")
            try expect(teamBuddy.overviews[0].data?.daily_limit.remaining == 132_500_000, "TeamBuddy team remaining must subtract spent")
            let unlimitedJSON = teamBuddyJSON.replacingOccurrences(of: #""remaining_quota":19500000"#, with: #""remaining_quota":null"#)
                .replacingOccurrences(of: #""quota":150000000"#, with: #""quota":null"#)
            let unlimited = try TeamBuddySnapshot.parse(unlimitedJSON)
            try expect(unlimited.quotas.teams[0].remaining_quota == nil, "Unlimited personal quota must not become zero")
            try expect(unlimited.overviews[0].data?.daily_limit.remaining == nil, "Unlimited team quota must not become zero")
            let negativeLimit = try TeamBuddySnapshot.parse(teamBuddyJSON.replacingOccurrences(of: #""quota":150000000"#, with: #""quota":-1"#))
            try expect(negativeLimit.overviews[0].data?.daily_limit.remaining == nil, "Negative team limit means unlimited")
            let stoppedTeam = try TeamBuddySnapshot.parse(teamBuddyJSON.replacingOccurrences(of: #""team_status":"active""#, with: #""team_status":"disabled""#))
            try expect(!stoppedTeam.quotas.teams[0].isActive, "Disabled teams must not appear available")
            let rankedJSON = teamBuddyJSON.replacingOccurrences(of: #""daily_limit":{"quota":150000000,"spent":17500000}"#,
                with: #""daily_limit":{"quota":150000000,"spent":17500000},"member_usage":[{"user_id":2,"username":"second","display_name":"","consumed_quota":500000},{"user_id":1,"username":"first","display_name":"Alice","consumed_quota":1000000},{"user_id":3,"username":"tied","display_name":"Bob","consumed_quota":1000000}]"#)
            let ranked = try TeamBuddySnapshot.parse(rankedJSON).overviews[0].data!.rankings
            try expect(ranked.map(\.rank) == [1, 1, 3], "Consumption ranking should sort descending and preserve ties")
            try expect(ranked.map(\.member.name) == ["Alice", "Bob", "second"], "Ranking names should fall back to username")
            try expect(teamBuddy.overviews[0].data?.rankings.isEmpty == true, "Missing ranking data must not break quota loading")
            let signedJSON = rankedJSON.replacingOccurrences(of: #""quotas":"#,
                with: #""current_user":{"id":3,"username":"tied","display_name":"Bob"},"quotas":"#)
            let signedSnapshot = try TeamBuddySnapshot.parse(signedJSON)
            let ownRank = signedSnapshot.overviews[0].data?.rankings.first {
                $0.member.user_id == signedSnapshot.current_user?.id
            }
            try expect(ownRank?.member.name == "Bob" && ownRank?.rank == 1, "Own row must use the signed-in user's identity")
            try expect(teamBuddy.current_user == nil, "Older snapshots without identity must remain readable")
            do {
                _ = try TeamBuddySnapshot.parse(#"{"error":"login_required"}"#)
                throw AppError.parseFailure("Expired TeamBuddy login must fail")
            } catch AppError.invalidCredentials {}
            do {
                _ = try TeamBuddySnapshot.parse(teamBuddyJSON.replacingOccurrences(of: #""quota_per_unit":500000"#, with: #""quota_per_unit":0"#))
                throw AppError.invalidCredentials
            } catch AppError.parseFailure {}

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
