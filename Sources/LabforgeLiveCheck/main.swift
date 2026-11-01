import Foundation
import LabforgeCore

@main
struct LabforgeLiveCheck {
    static func main() async {
        do {
            let client = LiveLabforgeClient()
            print("Login...")
            guard let credentials = try LocalCredentialsStore().loadCredentials() else {
                throw AppError.missingCredentials
            }
            try await client.login(credentials: credentials)
            print("Login: OK")

            print("Fetch quota...")
            let quotaData = try await client.fetchQuotaData()
            print("Fetch quota: OK")

            print("Fetch models...")
            let modelsData = try await client.fetchModelsData()
            print("Fetch models: OK")

            print("Fetch today's usage...")
            let usageData = try await client.fetchTodayUsageData()
            print("Fetch today's usage: OK")

            print("Fetch daily rankings...")
            let rankingsData = try await client.fetchDailyRankingsData()
            print("Fetch daily rankings: OK")

            let snapshot = try LabforgeParser().makeSnapshot(
                quotaData: quotaData,
                modelsData: modelsData,
                usageData: usageData,
                rankingsData: rankingsData
            )

            print("LabforgeLiveCheck: PASS")
            print("Team: \(snapshot.teamName)")
            print("Team daily remaining: \(QuotaFormatter.pointsString(snapshot.teamDailyRemaining)) raw=\(snapshot.teamDailyRemaining)")
            print("Your team daily: \(QuotaFormatter.pointsString(snapshot.userTeamDailyRemaining)) raw=\(snapshot.userTeamDailyRemaining)")
            if let userDailyRemaining = snapshot.userDailyRemaining {
                print("Personal daily: \(QuotaFormatter.pointsString(userDailyRemaining)) raw=\(userDailyRemaining)")
            } else {
                print("Personal daily: Unlimited")
            }
            print("Team pool total: \(QuotaFormatter.pointsString(snapshot.teamPoolRemaining)) raw=\(snapshot.teamPoolRemaining)")
            print("Personal grant: \(QuotaFormatter.pointsString(snapshot.personalGrantRemaining)) raw=\(snapshot.personalGrantRemaining)")
            print("Models: \(snapshot.availableModelCount)/\(snapshot.totalModelCount) \(snapshot.primaryModelStatus.rawValue)")
            print("Tokens used today: \(snapshot.todayTokenUsage)")
            print("Daily rankings: \(snapshot.dailyRankings.count) entries")
        } catch {
            fputs("LabforgeLiveCheck: FAIL - \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
