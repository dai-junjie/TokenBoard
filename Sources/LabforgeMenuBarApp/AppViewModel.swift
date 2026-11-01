import Foundation
import LabforgeCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var teamBuddySnapshot: TeamBuddySnapshot?
    @Published var teamBuddyStatus = "正在读取 TeamBuddy……"
    @Published var isRefreshingTeamBuddy = false
    @Published var teamBuddyNeedsLogin = false
    @Published var collapsedTeamRankings: Set<Int> = []

    func resetMenuDisclosureState() {
        collapsedTeamRankings.removeAll()
    }

    private let autoRefreshScheduler: AutoRefreshScheduler
    private let loginItemService: LoginItemService
    private var hasStarted = false

    init(
        autoRefreshScheduler: AutoRefreshScheduler = AutoRefreshScheduler(),
        loginItemService: LoginItemService = LoginItemService(),
        autoStart: Bool = true
    ) {
        self.autoRefreshScheduler = autoRefreshScheduler
        self.loginItemService = loginItemService
        TeamBuddyWindowController.shared.onClose = { [weak self] in
            Task { await self?.refreshTeamBuddy() }
        }
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
            await self.refreshAll()
        }

        Task { [weak self] in
            await self?.refreshAll()
        }
    }

    func refreshAll() async {
        await refreshTeamBuddy()
    }

    func refreshTeamBuddy() async {
        guard !isRefreshingTeamBuddy else { return }
        isRefreshingTeamBuddy = true
        defer { isRefreshingTeamBuddy = false }
        do {
            let json = try await TeamBuddyWindowController.shared.fetchAccountData()
            teamBuddySnapshot = try TeamBuddySnapshot.parse(json)
            teamBuddyNeedsLogin = false
            teamBuddyStatus = "更新于 \(Date().formatted(date: .omitted, time: .shortened)) · 按团队周期统计"
        } catch {
            if case AppError.invalidCredentials = error {
                teamBuddyNeedsLogin = true
                teamBuddyStatus = "请登录 TeamBuddy，完成后关闭登录窗口即可刷新。"
            } else {
                teamBuddyStatus = "刷新失败：\(error.localizedDescription)"
            }
            if teamBuddySnapshot != nil { teamBuddyStatus += "（显示上次成功数据）" }
        }
    }

}
