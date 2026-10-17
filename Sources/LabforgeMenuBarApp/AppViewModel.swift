import Foundation
import LabforgeCore

struct MicuAccountState: Identifiable {
    var account: MicuAccount
    var snapshot: MicuSnapshot?
    var status = "等待刷新"
    var isRefreshing = false
    var refreshFailed = false
    var id: UUID { account.id }
}

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
    @Published var micuDetailsExpanded = false
    @Published var rankingsExpanded = false

    func resetMenuDisclosureState() {
        modelTestsExpanded = expandsModelTestsByDefault
        micuDetailsExpanded = false
        rankingsExpanded = false
    }

    private let authManager: AuthManager
    private let refreshService: RefreshService
    private let autoRefreshScheduler: AutoRefreshScheduler
    private let loginItemService: LoginItemService
    @Published var micuAccounts: [MicuAccountState] = []
    @Published var micuStatus = "请添加米醋账号"
    @Published var isAddingMicuAccount = false
    var isRefreshingMicu: Bool { isAddingMicuAccount || micuAccounts.contains { $0.isRefreshing } }
    private let micuAccountStore = MicuAccountStore()
    private var micuClients: [UUID: MicuClient] = [:]
    private var micuAccountsLoaded = false

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


    private func loadMicuAccounts() throws {
        guard !micuAccountsLoaded else { return }
        micuAccounts = try micuAccountStore.loadOrMigrateLegacy().map { MicuAccountState(account: $0) }
        micuAccountsLoaded = true
        micuStatus = micuAccounts.isEmpty ? "请添加米醋账号" : "账号已保存在钥匙串"
    }

    func saveMicuCredentials(username: String, password: String, name: String) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !password.isEmpty, !isAddingMicuAccount else { return }
        isAddingMicuAccount = true
        micuStatus = "正在验证新账号……"
        Task {
            defer { isAddingMicuAccount = false }
            do {
                try loadMicuAccounts()
                let client = MicuClient()
                let credentials = Credentials(username: username, password: password)
                let fresh = try await client.refresh(credentials: credentials)
                let existing = micuAccounts.first {
                    if case .password(let saved) = $0.account.login { return saved.username == username }
                    return false
                }
                let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let account = MicuAccount(id: existing?.id ?? UUID(),
                    name: label.isEmpty ? (existing?.account.name ?? username) : label,
                    login: .password(credentials))
                try saveMicuAccount(account, client: client, snapshot: fresh)
            } catch {
                micuStatus = "添加失败：\(error.localizedDescription)"
            }
        }
    }

    private func saveMicuAccount(_ account: MicuAccount, client: MicuClient, snapshot: MicuSnapshot) throws {
        var updated = micuAccounts
        let state = MicuAccountState(account: account, snapshot: snapshot,
            status: "更新于\(formatted(date: snapshot.updatedAt)) · 今日按北京时间")
        if let index = updated.firstIndex(where: { $0.id == account.id }) { updated[index] = state }
        else { updated.append(state) }
        try micuAccountStore.save(updated.map(\.account))
        micuClients[account.id] = client
        micuAccounts = updated
        micuStatus = "已保存账号：\(account.name)"
    }

    func renameMicuAccount(id: UUID, name: String) {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, let index = micuAccounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = micuAccounts
        updated[index].account.name = label
        do {
            try micuAccountStore.save(updated.map(\.account))
            micuAccounts = updated
        } catch { micuStatus = "保存备注失败：\(error.localizedDescription)" }
    }

    func removeMicuAccount(id: UUID) {
        let updated = micuAccounts.filter { $0.id != id }
        do {
            try micuAccountStore.save(updated.map(\.account))
            micuAccounts = updated
            micuClients.removeValue(forKey: id)
            micuStatus = updated.isEmpty ? "请添加米醋账号" : "账号已移除"
        } catch { micuStatus = "移除失败：\(error.localizedDescription)" }
    }

    func refreshMicu() async {
        do { try loadMicuAccounts() }
        catch { micuStatus = "读取账号失败：\(error.localizedDescription)"; return }
        let ids = micuAccounts.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { await self.refreshMicuAccount(id: id) } }
        }
    }

    func refreshMicuAccount(id: UUID) async {
        guard let index = micuAccounts.firstIndex(where: { $0.id == id }),
              !micuAccounts[index].isRefreshing else { return }
        let account = micuAccounts[index].account
        micuAccounts[index].isRefreshing = true
        do {
            let client: MicuClient
            if let existing = micuClients[id] { client = existing }
            else {
                client = MicuClient()
                if case .web(let session) = account.login { try await client.useWebSession(session) }
                guard micuAccounts.contains(where: { $0.id == id }) else { return }
                micuClients[id] = client
            }
            let credentials: Credentials?
            if case .password(let saved) = account.login { credentials = saved } else { credentials = nil }
            let fresh = try await client.refresh(credentials: credentials)
            guard let current = micuAccounts.firstIndex(where: { $0.id == id }) else { return }
            micuAccounts[current].snapshot = fresh
            micuAccounts[current].refreshFailed = false
            micuAccounts[current].status = "更新于\(formatted(date: fresh.updatedAt)) · 今日按北京时间"
        } catch {
            if let current = micuAccounts.firstIndex(where: { $0.id == id }) {
                let cached = micuAccounts[current].snapshot == nil ? "" : "（显示上次成功数据）"
                micuAccounts[current].status = "\(error.localizedDescription)\(cached)"
                micuAccounts[current].refreshFailed = true
            }
        }
        if let current = micuAccounts.firstIndex(where: { $0.id == id }) {
            micuAccounts[current].isRefreshing = false
        }
    }

    func loginMicuWithGitHub(name: String) {
        MicuLoginWindowController.shared.show { [weak self] session in
            guard let self else { return }
            guard !self.isAddingMicuAccount else { throw MicuError.requestFailed }
            self.isAddingMicuAccount = true
            defer { self.isAddingMicuAccount = false }
            try self.loadMicuAccounts()
            let client = MicuClient()
            try await client.useWebSession(session)
            let fresh = try await client.refresh(credentials: nil)
            let existing = self.micuAccounts.first {
                if case .web(let saved) = $0.account.login { return saved.userID == session.userID }
                return false
            }
            let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = MicuAccount(id: existing?.id ?? UUID(),
                name: label.isEmpty ? (existing?.account.name ?? "GitHub 账号") : label,
                login: .web(session))
            try self.saveMicuAccount(account, client: client, snapshot: fresh)
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
