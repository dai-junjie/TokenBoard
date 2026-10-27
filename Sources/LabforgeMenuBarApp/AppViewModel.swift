import Foundation
import LabforgeCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var snapshot: LabforgeSnapshot = .empty
    @Published var statusMessage = "需要登录"
    @Published var isRefreshing = false
    @Published var needsLogin = true
    @Published var showsRankings: Bool {
        didSet {
            UserDefaults.standard.set(showsRankings, forKey: "showsRankings")
        }
    }

    @Published var expandsModelTestsByDefault: Bool {
        didSet {
            UserDefaults.standard.set(expandsModelTestsByDefault, forKey: "expandsModelTestsByDefault")
            modelTestsExpanded = expandsModelTestsByDefault
        }
    }
    @Published var modelTestsExpanded = true
    @Published var rankingsExpanded = false

    func resetMenuDisclosureState() {
        modelTestsExpanded = expandsModelTestsByDefault
        rankingsExpanded = false
    }

    private let authManager: AuthManager
    private let refreshService: RefreshService
    private let autoRefreshScheduler: AutoRefreshScheduler
    private let loginItemService: LoginItemService
    private var hasStarted = false
    private var pendingRetryTask: Task<Void, Never>?
    private let transientRetryDelayNanoseconds: UInt64 = 30_000_000_000

    init(
        authManager: AuthManager? = nil,
        refreshService: RefreshService? = nil,
        autoRefreshScheduler: AutoRefreshScheduler = AutoRefreshScheduler(),
        loginItemService: LoginItemService = LoginItemService(),
        autoStart: Bool = true
    ) {
        let client = LiveLabforgeClient()
        self.authManager = authManager ?? AuthManager(client: client)
        self.refreshService = refreshService ?? RefreshService(
            client: client,
            cache: FileSnapshotStore()
        )
        self.autoRefreshScheduler = autoRefreshScheduler
        self.loginItemService = loginItemService
        let rankingsPreferenceVersionKey = "rankingsPreferenceVersion"
        if UserDefaults.standard.integer(forKey: rankingsPreferenceVersionKey) < 1 {
            UserDefaults.standard.set(true, forKey: "showsRankings")
            UserDefaults.standard.set(1, forKey: rankingsPreferenceVersionKey)
        }
        self.showsRankings = UserDefaults.standard.bool(forKey: "showsRankings")
        self.expandsModelTestsByDefault = UserDefaults.standard.object(forKey: "expandsModelTestsByDefault") as? Bool ?? true
        self.modelTestsExpanded = expandsModelTestsByDefault

        if autoStart {
            start()
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        loginItemService.enableIfPossible()
        autoRefreshScheduler.start { [weak self] in
            guard let self else { return }
            await self.refreshFromTimer()
        }

        Task { [weak self] in
            guard let self else { return }
            await self.bootstrap()
        }
    }

    func bootstrap() async {
        if let cached = await refreshService.cachedSnapshot() {
            snapshot = cached
            statusMessage = "正在显示缓存数据"
        }

        do {
            try await authManager.ensureAuthenticated()
            needsLogin = false
            await refresh()
        } catch {
            handle(error)
        }
    }

    func saveCredentials(username: String, password: String) {
        do {
            try authManager.saveCredentials(username: username, password: password)
            statusMessage = "已保存到本机，正在登录……"
            Task { [weak self] in
                guard let self else { return }
                await self.bootstrap()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func storedCredentials() throws -> Credentials? {
        try authManager.storedCredentials()
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fresh = try await refreshService.refresh()
            snapshot = fresh
            statusMessage = "更新于\(formatted(date: fresh.updatedAt))"
            pendingRetryTask?.cancel()
            pendingRetryTask = nil
        } catch {
            handle(error)
        }
    }

    private func refreshFromTimer() async {
        do {
            try await authManager.ensureAuthenticated()
            needsLogin = false
            await refresh()
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if isTransientNetworkError(error) {
            needsLogin = false
            statusMessage = "网络暂不可用，30 秒后重试。"
            scheduleRetryIfNeeded()
            return
        }

        needsLogin = true
        statusMessage = error.localizedDescription
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard case AppError.networkFailure = error else {
            return false
        }
        return true
    }

    private func scheduleRetryIfNeeded() {
        guard pendingRetryTask == nil else { return }
        let delay = transientRetryDelayNanoseconds

        pendingRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                guard let self else { return }
                self.pendingRetryTask = nil
                Task { [weak self] in
                    guard let self else { return }
                    await self.refreshFromTimer()
                }
            }
        }
    }

    private func formatted(date: Date) -> String {
        let elapsed = max(Date().timeIntervalSince(date), 0)
        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 3_600 {
            return " \(Int(elapsed / 60)) 分钟前"
        }
        return " \(Int(elapsed / 3_600)) 小时前"
    }
}
