import Foundation

private struct QuotaResponse: Decodable {
    let success: Bool
    let data: QuotaPayload
}

private struct QuotaPayload: Decodable {
    let teamName: String?
    let labforgeTeamName: String?
    let labGrantBalance: GrantBalance?
    let userGrantBalance: GrantBalance?
    let lab: DailyQuota?
    let teamUser: DailyQuota?
    let user: DailyQuota?

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case labforgeTeamName = "labforge_team_name"
        case labGrantBalance = "lab_grant_balance"
        case userGrantBalance = "user_grant_balance"
        case lab
        case teamUser = "team_user"
        case user
    }
}

private struct GrantBalance: Decodable {
    let remaining: Int
    let granted: Int
}

private struct DailyQuota: Decodable {
    let dailyQuota: Int
    let dailyUsed: Int

    enum CodingKeys: String, CodingKey {
        case dailyQuota = "daily_quota"
        case dailyUsed = "daily_used"
    }

    var remaining: Int? {
        guard dailyQuota >= 0 else {
            return nil
        }
        return max(dailyQuota - dailyUsed, 0)
    }
}

private struct ModelsResponse: Decodable {
    let success: Bool
    let data: ModelsPayload
}

private struct ModelsPayload: Decodable {
    let teamName: String?
    let items: [ModelItem]

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case items
    }
}

private struct ModelItem: Decodable {
    let group: String
    let label: String
    let status: ModelStatus
    let availability: Double
    let averageResponseTime: Int
    let lastTestTime: TimeInterval
    let history: [ModelHistoryItem]

    enum CodingKeys: String, CodingKey {
        case group
        case label
        case status
        case availability
        case averageResponseTime = "average_response_time"
        case lastTestTime = "last_test_time"
        case history
    }
}

private struct ModelHistoryItem: Decodable {
    let success: Bool
    let latencyMilliseconds: Int
    let testedAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case success
        case latencyMilliseconds = "latency_ms"
        case testedAt = "tested_at"
    }
}

private struct UsageResponse: Decodable {
    let success: Bool
    let data: [UsageItem]
}

private struct UsageItem: Decodable {
    let tokenUsed: Int

    enum CodingKeys: String, CodingKey {
        case tokenUsed = "token_used"
    }
}

private struct RankingsResponse: Decodable {
    let success: Bool
    let data: RankingsPayload
}

private struct RankingsPayload: Decodable {
    let items: [RankingItem]
}

private struct RankingItem: Decodable {
    let rank: Int
    let username: String
    let displayName: String
    let realName: String
    let quota: Int
    let requestCount: Int
    let tokenUsed: Int

    enum CodingKeys: String, CodingKey {
        case rank
        case username
        case displayName = "display_name"
        case realName = "labforge_real_name"
        case quota
        case requestCount = "request_count"
        case tokenUsed = "token_used"
    }
}

public struct LabforgeParser: Sendable {
    public init() {}

    public func makeSnapshot(
        quotaData: Data,
        modelsData: Data,
        usageData: Data? = nil,
        rankingsData: Data? = nil
    ) throws -> LabforgeSnapshot {
        let decoder = JSONDecoder()

        let quota = try decoder.decode(QuotaResponse.self, from: quotaData)
        let models = try decoder.decode(ModelsResponse.self, from: modelsData)
        let usage = try usageData.map { try decoder.decode(UsageResponse.self, from: $0) }
        let rankings = try rankingsData.map { try decoder.decode(RankingsResponse.self, from: $0) }

        guard quota.success, models.success else {
            throw AppError.parseFailure("success flag is false")
        }

        let teamPool = quota.data.labGrantBalance ?? GrantBalance(remaining: 0, granted: 0)
        let personalGrant = quota.data.userGrantBalance ?? GrantBalance(remaining: 0, granted: 0)
        let labDaily = quota.data.lab
        let teamUserDaily = quota.data.teamUser
        let userDaily = quota.data.user
        let statuses = models.data.items.map(\.status)
        let availableCount = statuses.filter { $0 == .available }.count
        let modelGroups = models.data.items.map { item in
            ModelGroupAvailability(
                id: item.group,
                label: item.label,
                status: item.status,
                availability: item.availability,
                averageResponseTimeMilliseconds: item.averageResponseTime,
                lastTestAt: Date(timeIntervalSince1970: item.lastTestTime),
                recentTests: item.history.suffix(60).map {
                    ModelTestResult(
                        success: $0.success,
                        latencyMilliseconds: $0.latencyMilliseconds,
                        testedAt: Date(timeIntervalSince1970: $0.testedAt)
                    )
                }
            )
        }

        return LabforgeSnapshot(
            teamName: quota.data.teamName ?? quota.data.labforgeTeamName ?? models.data.teamName ?? "--",
            personalGrantRemaining: personalGrant.remaining,
            personalGrantTotal: personalGrant.granted,
            teamPoolRemaining: teamPool.remaining,
            teamPoolTotal: teamPool.granted,
            teamDailyRemaining: labDaily?.remaining ?? 0,
            teamDailyTotal: max(labDaily?.dailyQuota ?? 0, 0),
            userTeamDailyRemaining: teamUserDaily?.remaining ?? 0,
            userTeamDailyTotal: max(teamUserDaily?.dailyQuota ?? 0, 0),
            userDailyRemaining: userDaily?.remaining,
            userDailyTotal: userDaily?.dailyQuota,
            availableModelCount: availableCount,
            totalModelCount: statuses.count,
            primaryModelStatus: summarize(statuses),
            modelGroups: modelGroups,
            todayTokenUsage: usage?.success == true
                ? usage?.data.reduce(0) { $0 + $1.tokenUsed } ?? 0
                : 0,
            dailyRankings: rankings?.success == true
                ? rankings?.data.items.map {
                    RankingEntry(
                        rank: $0.rank,
                        username: $0.username,
                        displayName: $0.displayName,
                        realName: $0.realName,
                        quota: $0.quota,
                        requestCount: $0.requestCount,
                        tokenUsed: $0.tokenUsed
                    )
                } ?? []
                : [],
            updatedAt: Date()
        )
    }

    private func summarize(_ statuses: [ModelStatus]) -> ModelStatus {
        if statuses.contains(.available) {
            return .available
        }
        if statuses.contains(.degraded) {
            return .degraded
        }
        if statuses.contains(.unavailable) {
            return .unavailable
        }
        if statuses.contains(.untested) {
            return .untested
        }
        return .unknown
    }
}
