import Foundation

public enum ModelStatus: String, Codable, CaseIterable, Sendable {
    case available
    case degraded
    case unavailable
    case untested
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ModelStatus(rawValue: rawValue) ?? .unknown
    }
}

public struct ModelTestResult: Codable, Equatable, Sendable {
    public let success: Bool
    public let latencyMilliseconds: Int
    public let testedAt: Date

    public init(success: Bool, latencyMilliseconds: Int, testedAt: Date) {
        self.success = success
        self.latencyMilliseconds = latencyMilliseconds
        self.testedAt = testedAt
    }
}

public struct RankingEntry: Codable, Equatable, Sendable {
    public let rank: Int
    public let username: String
    public let displayName: String
    public let realName: String
    public let quota: Int
    public let requestCount: Int
    public let tokenUsed: Int

    public init(
        rank: Int,
        username: String,
        displayName: String,
        realName: String,
        quota: Int,
        requestCount: Int,
        tokenUsed: Int
    ) {
        self.rank = rank
        self.username = username
        self.displayName = displayName
        self.realName = realName
        self.quota = quota
        self.requestCount = requestCount
        self.tokenUsed = tokenUsed
    }
}

public struct ModelGroupAvailability: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let status: ModelStatus
    public let availability: Double
    public let averageResponseTimeMilliseconds: Int
    public let lastTestAt: Date
    public let recentTests: [ModelTestResult]

    public init(
        id: String,
        label: String,
        status: ModelStatus,
        availability: Double,
        averageResponseTimeMilliseconds: Int,
        lastTestAt: Date,
        recentTests: [ModelTestResult] = []
    ) {
        self.id = id
        self.label = label
        self.status = status
        self.availability = availability
        self.averageResponseTimeMilliseconds = averageResponseTimeMilliseconds
        self.lastTestAt = lastTestAt
        self.recentTests = recentTests
    }
}

public struct Credentials: Codable, Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct LabforgeSnapshot: Codable, Equatable, Sendable {
    public let teamName: String
    public let personalGrantRemaining: Int
    public let personalGrantTotal: Int
    public let teamPoolRemaining: Int
    public let teamPoolTotal: Int
    public let teamDailyRemaining: Int
    public let teamDailyTotal: Int
    public let userTeamDailyRemaining: Int
    public let userTeamDailyTotal: Int
    public let userDailyRemaining: Int?
    public let userDailyTotal: Int?
    public let availableModelCount: Int
    public let totalModelCount: Int
    public let primaryModelStatus: ModelStatus
    public let modelGroups: [ModelGroupAvailability]
    public let todayTokenUsage: Int
    public let dailyRankings: [RankingEntry]
    public let updatedAt: Date

    public static let empty = LabforgeSnapshot(
        teamName: "--",
        personalGrantRemaining: 0,
        personalGrantTotal: 0,
        teamPoolRemaining: 0,
        teamPoolTotal: 0,
        teamDailyRemaining: 0,
        teamDailyTotal: 0,
        userTeamDailyRemaining: 0,
        userTeamDailyTotal: 0,
        userDailyRemaining: nil,
        userDailyTotal: nil,
        availableModelCount: 0,
        totalModelCount: 0,
        primaryModelStatus: .unknown,
        modelGroups: [],
        todayTokenUsage: 0,
        dailyRankings: [],
        updatedAt: .distantPast
    )

    public init(
        teamName: String,
        personalGrantRemaining: Int,
        personalGrantTotal: Int,
        teamPoolRemaining: Int,
        teamPoolTotal: Int,
        teamDailyRemaining: Int,
        teamDailyTotal: Int,
        userTeamDailyRemaining: Int,
        userTeamDailyTotal: Int,
        userDailyRemaining: Int?,
        userDailyTotal: Int?,
        availableModelCount: Int,
        totalModelCount: Int,
        primaryModelStatus: ModelStatus,
        modelGroups: [ModelGroupAvailability] = [],
        todayTokenUsage: Int = 0,
        dailyRankings: [RankingEntry] = [],
        updatedAt: Date
    ) {
        self.teamName = teamName
        self.personalGrantRemaining = personalGrantRemaining
        self.personalGrantTotal = personalGrantTotal
        self.teamPoolRemaining = teamPoolRemaining
        self.teamPoolTotal = teamPoolTotal
        self.teamDailyRemaining = teamDailyRemaining
        self.teamDailyTotal = teamDailyTotal
        self.userTeamDailyRemaining = userTeamDailyRemaining
        self.userTeamDailyTotal = userTeamDailyTotal
        self.userDailyRemaining = userDailyRemaining
        self.userDailyTotal = userDailyTotal
        self.availableModelCount = availableModelCount
        self.totalModelCount = totalModelCount
        self.primaryModelStatus = primaryModelStatus
        self.modelGroups = modelGroups
        self.todayTokenUsage = todayTokenUsage
        self.dailyRankings = dailyRankings
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case teamName
        case personalGrantRemaining
        case personalGrantTotal
        case teamPoolRemaining
        case teamPoolTotal
        case teamDailyRemaining
        case teamDailyTotal
        case userTeamDailyRemaining
        case userTeamDailyTotal
        case userDailyRemaining
        case userDailyTotal
        case availableModelCount
        case totalModelCount
        case primaryModelStatus
        case modelGroups
        case todayTokenUsage
        case dailyRankings
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamName = try container.decode(String.self, forKey: .teamName)
        personalGrantRemaining = try container.decode(Int.self, forKey: .personalGrantRemaining)
        personalGrantTotal = try container.decode(Int.self, forKey: .personalGrantTotal)
        teamPoolRemaining = try container.decode(Int.self, forKey: .teamPoolRemaining)
        teamPoolTotal = try container.decode(Int.self, forKey: .teamPoolTotal)
        teamDailyRemaining = try container.decode(Int.self, forKey: .teamDailyRemaining)
        teamDailyTotal = try container.decode(Int.self, forKey: .teamDailyTotal)
        userTeamDailyRemaining = try container.decode(Int.self, forKey: .userTeamDailyRemaining)
        userTeamDailyTotal = try container.decode(Int.self, forKey: .userTeamDailyTotal)
        userDailyRemaining = try container.decodeIfPresent(Int.self, forKey: .userDailyRemaining)
        userDailyTotal = try container.decodeIfPresent(Int.self, forKey: .userDailyTotal)
        availableModelCount = try container.decode(Int.self, forKey: .availableModelCount)
        totalModelCount = try container.decode(Int.self, forKey: .totalModelCount)
        primaryModelStatus = try container.decode(ModelStatus.self, forKey: .primaryModelStatus)
        modelGroups = try container.decodeIfPresent([ModelGroupAvailability].self, forKey: .modelGroups) ?? []
        todayTokenUsage = try container.decodeIfPresent(Int.self, forKey: .todayTokenUsage) ?? 0
        dailyRankings = try container.decodeIfPresent([RankingEntry].self, forKey: .dailyRankings) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public enum AppError: LocalizedError, Sendable {
    case invalidCredentials
    case missingCredentials
    case invalidResponse(Int)
    case parseFailure(String)
    case credentialsStorageFailure(String)
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Login failed. Check username or password."
        case .missingCredentials:
            return "Login required."
        case .invalidResponse(let statusCode):
            return "Labforge returned status \(statusCode)."
        case .parseFailure(let detail):
            return "Labforge response format changed: \(detail)"
        case .credentialsStorageFailure(let detail):
            return "凭据保存失败：\(detail)"
        case .networkFailure(let detail):
            return "Network error: \(detail)"
        }
    }
}
