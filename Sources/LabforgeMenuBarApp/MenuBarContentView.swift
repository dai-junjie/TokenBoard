import AppKit
import SwiftUI
import LabforgeCore

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            micuSection
            Divider()

            Text(appTitle)
                .font(.headline)

            if viewModel.needsLogin {
                VStack(alignment: .leading, spacing: 8) {
                    Text("需要登录")
                    Text("请打开设置并保存 Labforge 用户名和密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("打开设置") {
                        SettingsWindowController.shared.show(viewModel: viewModel)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                metricRow(
                    label: "个人团队日额度",
                    value: "\(QuotaFormatter.pointsString(viewModel.snapshot.userTeamDailyRemaining)) / \(QuotaFormatter.pointsString(viewModel.snapshot.userTeamDailyTotal))"
                )
                metricRow(
                    label: "团队今日剩余额度",
                    value: "\(QuotaFormatter.pointsString(viewModel.snapshot.teamDailyRemaining)) / \(QuotaFormatter.pointsString(viewModel.snapshot.teamDailyTotal))"
                )
                metricRow(
                    label: "今日已用 Token",
                    value: viewModel.snapshot.todayTokenUsage.formatted()
                )

                modelAvailability(snapshot: viewModel.snapshot)

                if viewModel.showsRankings {
                    dailyRankings(snapshot: viewModel.snapshot)
                }
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button("立即刷新") {
                    Task { await viewModel.refreshAll() }
                }
                .disabled(viewModel.isRefreshing || viewModel.isRefreshingMicu)

                Button("打开 Labforge") {
                    NSWorkspace.shared.open(LabforgeEndpoints.modelsDashboardURL)
                }

                Button("设置") {
                    SettingsWindowController.shared.show(viewModel: viewModel)
                }

                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var appTitle: String {
        "Labforge"

    }

    private var micuSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("米醋 API").font(.headline)
                Spacer()
                Button("打开米醋") {
                    NSWorkspace.shared.open(MicuClient.dashboardURL)
                }
            }
            if viewModel.micuAccounts.isEmpty {
                Text(viewModel.micuStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !viewModel.micuAccounts.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("账号")
                        Text("余额")
                        Text("今日消耗")
                        Color.clear.frame(width: 14, height: 1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(viewModel.micuAccounts) { state in
                        GridRow {
                            Text(state.account.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(state.account.name)
                            micuAmount(state.snapshot.map { $0.formatted($0.balance) })
                            micuAmount(state.snapshot.map { $0.formatted($0.today) })
                            Button {
                                Task { await viewModel.refreshMicuAccount(id: state.id) }
                            } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .disabled(state.isRefreshing)
                            .help("刷新此账号 · \(state.status)")
                        }
                        if state.snapshot == nil || state.refreshFailed {
                            Text(state.isRefreshing ? "正在刷新……" : state.status)
                                .font(.caption)
                                .foregroundStyle(state.refreshFailed ? Color.orange : Color.secondary)
                                .gridCellColumns(4)
                        }
                    }
                }
                DisclosureGroup("更多消耗数据", isExpanded: $viewModel.micuDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                            GridRow {
                                Text("账号")
                                Text("近 24 小时")
                                Text("累计消耗")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            ForEach(viewModel.micuAccounts) { state in
                                GridRow {
                                    Text(state.account.name).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    micuAmount(state.snapshot.map { $0.formatted($0.last24Hours) })
                                    micuAmount(state.snapshot.map { $0.formatted($0.total) })
                                }
                            }
                        }
                        ForEach(viewModel.micuAccounts) { state in
                            Text("\(state.account.name)：\(state.isRefreshing ? "正在刷新……" : state.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("今日按北京时间统计；近 24 小时为聚合数据，可能延迟约 5 分钟。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
                .font(.subheadline)
            }
        }
    }

    private func micuAmount(_ value: String?) -> some View {
        Text(value ?? "—")
            .font(.system(.subheadline, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .gridColumnAlignment(.trailing)
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func modelAvailability(snapshot: LabforgeSnapshot) -> some View {
        return VStack(alignment: .leading, spacing: 7) {
            DisclosureGroup(isExpanded: $viewModel.modelTestsExpanded) {
                if snapshot.modelGroups.isEmpty {
                    Text("刷新后加载分组详情")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.modelGroups, id: \.id) { group in
                        modelGroupRow(group)
                    }
                }
            } label: {
                HStack {
                    Label("模型测试详情", systemImage: "cpu")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(snapshot.availableModelCount) / \(snapshot.totalModelCount) 可用")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .tint(.green)
        }
        .padding(10)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.green.opacity(0.2), lineWidth: 0.5)
        }
    }

    private func dailyRankings(snapshot: LabforgeSnapshot) -> some View {
        let topThree = Array(snapshot.dailyRankings.prefix(3))
        let currentUsername = DefaultLabforgeCredentials.credentials.username
        let currentUser = snapshot.dailyRankings.first { $0.username == currentUsername }

        return VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup(isExpanded: $viewModel.rankingsExpanded) {
                if topThree.isEmpty {
                    Text("暂无排行榜数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(topThree, id: \.rank) { entry in
                        rankingRow(entry, isCurrentUser: entry.username == currentUsername)
                    }
                    if let currentUser, currentUser.rank > 3 {
                        Divider()
                        rankingRow(currentUser, isCurrentUser: true)
                    }
                }
            } label: {
                Label("今日排行榜", systemImage: "trophy")
                    .foregroundStyle(.orange)
            }
            .tint(.orange)
        }
        .padding(10)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.18), lineWidth: 0.5)
        }
    }

    private func rankingRow(_ entry: RankingEntry, isCurrentUser: Bool) -> some View {
        HStack(spacing: 8) {
            Text("#\(entry.rank)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 32, alignment: .leading)

            Text(rankingName(entry))
                .font(.body)
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(QuotaFormatter.pointsString(entry.quota))
                Text("\(tokenMillions(entry.tokenUsed))M Token")
                    .font(.caption)
            }
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isCurrentUser ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private func rankingName(_ entry: RankingEntry) -> String {
        if !entry.realName.isEmpty {
            return "\(entry.displayName)（\(entry.realName)）"
        }
        return entry.displayName.isEmpty ? entry.username : entry.displayName
    }

    private func tokenMillions(_ tokens: Int) -> String {
        let millions = Double(tokens) / 1_000_000
        return millions.formatted(.number.precision(.fractionLength(millions >= 10 ? 1 : 2)))
    }

    private func modelGroupRow(_ group: ModelGroupAvailability) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(group.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Circle()
                    .fill(modelStatusColor(group.status))
                    .frame(width: 7, height: 7)
                Text(modelStatusShortLabel(group.status))
                    .font(.caption)
                    .foregroundStyle(modelStatusColor(group.status))
            }

            HStack(spacing: 2) {
                ForEach(recentTestSlots(group.recentTests), id: \.id) { slot in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(testResultColor(slot.result))
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)
                        .help(testResultDescription(slot.result))
                }
            }

            HStack {
                Text("最近测试 \(successfulTestCount(group.recentTests))/\(group.recentTests.count)")
                Spacer()
                Text("平均 \(responseTime(group.averageResponseTimeMilliseconds))")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private struct TestSlot: Identifiable {
        let id: String
        let result: ModelTestResult?
    }

    private func recentTestSlots(_ tests: [ModelTestResult]) -> [TestSlot] {
        let recent = Array(tests.suffix(60))
        let emptyCount = max(0, 60 - recent.count)
        return (0..<emptyCount).map { TestSlot(id: "empty-\($0)", result: nil) }
            + recent.enumerated().map { TestSlot(id: "test-\($0.offset)-\($0.element.testedAt.timeIntervalSince1970)", result: $0.element) }
    }

    private func successfulTestCount(_ tests: [ModelTestResult]) -> Int {
        tests.filter(\.success).count
    }

    private func testResultColor(_ result: ModelTestResult?) -> Color {
        guard let result else { return .secondary.opacity(0.2) }
        return result.success ? .green : .red
    }

    private func testResultDescription(_ result: ModelTestResult?) -> String {
        guard let result else { return "无测试数据" }
        let state = result.success ? "可用" : "不可用"
        return "\(state) · \(responseTime(result.latencyMilliseconds)) · \(result.testedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func modelStatusColor(_ status: ModelStatus) -> Color {
        switch status {
        case .available:
            return .green
        case .degraded, .untested:
            return .orange
        case .unavailable:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func modelStatusShortLabel(_ status: ModelStatus) -> String {
        switch status {
        case .available:
            return "可用"
        case .degraded:
            return "性能下降"
        case .unavailable:
            return "不可用"
        case .untested:
            return "未测试"
        case .unknown:
            return "未知"
        }
    }

    private func responseTime(_ milliseconds: Int) -> String {
        if milliseconds >= 1_000 {
            return String(format: "%.2f s", Double(milliseconds) / 1_000)
        }
        return "\(milliseconds) ms"
    }
}
