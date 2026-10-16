import Foundation

public actor RefreshService {
    private let client: LabforgeClientProtocol
    private let cache: SnapshotStore
    private let parser: LabforgeParser
    private var activeRefresh: Task<LabforgeSnapshot, Error>?

    public init(client: LabforgeClientProtocol, cache: SnapshotStore, parser: LabforgeParser = LabforgeParser()) {
        self.client = client
        self.cache = cache
        self.parser = parser
    }

    public func cachedSnapshot() -> LabforgeSnapshot? {
        cache.load()
    }

    public func refresh() async throws -> LabforgeSnapshot {
        if let activeRefresh {
            return try await activeRefresh.value
        }

        let task = Task<LabforgeSnapshot, Error> {
            async let quotaData = client.fetchQuotaData()
            async let modelsData = client.fetchModelsData()
            async let usageData = client.fetchTodayUsageData()
            async let rankingsData = client.fetchDailyRankingsData()
            let snapshot = try await parser.makeSnapshot(
                quotaData: quotaData,
                modelsData: modelsData,
                usageData: usageData,
                rankingsData: rankingsData
            )
            cache.save(snapshot)
            return snapshot
        }

        activeRefresh = task
        defer { activeRefresh = nil }
        return try await task.value
    }
}
