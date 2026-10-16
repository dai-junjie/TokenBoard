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

    private let authManager: AuthManager
    private let refreshService: RefreshService
    private let autoRefreshScheduler: AutoRefreshScheduler
    private let loginItemService: LoginItemService
    @Published var micuSnapshot: MicuSnapshot?
    @Published var micuStatus = "请在设置中登录米醋"
    @Published var isRefreshingMicu = false
    private let micuClient = MicuClient()
    private let micuCredentialsStore = MicuCredentialsStore()
    private let micuWebSessionStore = MicuWebSessionStore()
    private var micuWebSessionLoaded = false

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
            async let micu: () = self.refreshMicu()
            await self.refreshFromTimer()
            await micu
        }

        Task { [weak self] in
            guard let self else { return }
            async let micu: () = self.refreshMicu()
            await self.bootstrap()
            await micu
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
            statusMessage = "已保存到钥匙串，正在登录……"
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


    func saveMicuCredentials(username: String, password: String) {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        guard !isRefreshingMicu else { return }
        do {
            try micuCredentialsStore.save(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            UserDefaults.standard.set(false, forKey: "micuUsesWebLogin")
            micuWebSessionLoaded = false
            micuSnapshot = nil
            micuStatus = "已保存到钥匙串，正在登录米醋……"
            Task {
                await micuClient.resetSession()
                await refreshMicu()
            }
        } catch {
            micuStatus = "米醋凭证保存失败：\(error.localizedDescription)"
        }
    }

    func refreshMicu() async {
        guard !isRefreshingMicu else { return }
        isRefreshingMicu = true
        defer { isRefreshingMicu = false }
        do {
            let usesWebLogin = UserDefaults.standard.bool(forKey: "micuUsesWebLogin")
            if usesWebLogin && !micuWebSessionLoaded {
                guard let session = try micuWebSessionStore.load() else { throw MicuError.missingCredentials }
                try await micuClient.useWebSession(session)
                micuWebSessionLoaded = true
            }
            let credentials = usesWebLogin ? nil : try micuCredentialsStore.load()
            let fresh = try await micuClient.refresh(credentials: credentials)
            micuSnapshot = fresh
            micuStatus = "更新于\(formatted(date: fresh.updatedAt)) · 今日按北京时间"
        } catch {
            let cached = micuSnapshot == nil ? "" : "（显示上次成功数据）"
            micuStatus = "\(error.localizedDescription)\(cached)"
        }
    }

    func loginMicuWithGitHub() {
        MicuLoginWindowController.shared.show { [weak self] session in
            guard let self else { return }
            guard !self.isRefreshingMicu else { throw MicuError.requestFailed }
            self.isRefreshingMicu = true
            defer { self.isRefreshingMicu = false }
            try await self.micuClient.useWebSession(session)
            do {
                let fresh = try await self.micuClient.refresh(credentials: nil)
                try self.micuWebSessionStore.save(session)
                UserDefaults.standard.set(true, forKey: "micuUsesWebLogin")
                self.micuWebSessionLoaded = true
                self.micuSnapshot = fresh
                self.micuStatus = "GitHub 登录成功 · 更新于\(self.formatted(date: fresh.updatedAt)) · 今日按北京时间"
            } catch {
                await self.micuClient.resetSession()
                self.micuWebSessionLoaded = false
                self.micuStatus = error.localizedDescription
                throw error
            }
        }
    }

    func refreshAll() async {
        async let micu: () = refreshMicu()
        if !needsLogin { await refresh() }
        await micu
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
                    async let micu: () = self.refreshMicu()
            await self.refreshFromTimer()
            await micu
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
