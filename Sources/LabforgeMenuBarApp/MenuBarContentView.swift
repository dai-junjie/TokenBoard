import AppKit
import SwiftUI
import LabforgeCore

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            micuSection
            Divider()
            teamBuddySection
            Divider()
            footerActions
        }
        .padding()
        .frame(width: 360)
        .disclosureGroupStyle(FullRowDisclosureStyle())
    }

    // MARK: - Micu

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
                        Text("今日消耗")
                        Text("余额")
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
                            micuAmount(state.snapshot.map { $0.formatted($0.today) })
                            micuAmount(state.snapshot.map { $0.formatted($0.balance) })
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

    // MARK: - TeamBuddy

    private var teamBuddySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TeamBuddy").font(.headline)
                Text(viewModel.teamBuddyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let snapshot = viewModel.teamBuddySnapshot {
                if snapshot.quotas.teams.isEmpty {
                    Text("尚未加入团队").font(.caption)
                }
                ForEach(snapshot.quotas.teams) { team in
                    teamCard(team: team, snapshot: snapshot)
                }
            }
            HStack(spacing: 8) {
                Button {
                    TeamBuddyWindowController.shared.show()
                } label: {
                    Label(viewModel.teamBuddyNeedsLogin ? "登录 TeamBuddy" : "打开 TeamBuddy 控制台",
                          systemImage: viewModel.teamBuddyNeedsLogin ? "person.badge.key" : "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(TeamBuddyEndpoints.apiBaseURL.absoluteString, forType: .string)
                } label: {
                    Label("复制 API 地址", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help(TeamBuddyEndpoints.apiBaseURL.absoluteString)
            }
            .controlSize(.small)
        }
    }

    private func teamCard(team: TeamBuddySnapshot.Team, snapshot: TeamBuddySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(team.team_name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if team.isActive {
                personalPrimary(team: team, snapshot: snapshot)

                DisclosureGroup(isExpanded: detailBinding(for: team.id)) {
                    personalDetails(team: team, snapshot: snapshot)
                        .padding(.top, 4)
                } label: {
                    Text("周 / 月与其它")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let overview = snapshot.overviews.first(where: { $0.team_id == team.id })?.data {
                    teamRankings(team: team, overview: overview, snapshot: snapshot)
                }
            } else {
                Text("团队或成员已停用")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func personalPrimary(team: TeamBuddySnapshot.Team, snapshot: TeamBuddySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let limit = team.primaryPersonalLimit {
                HStack(alignment: .firstTextBaseline) {
                    Text("个人\(limit.periodName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(usedQuotaLabel(limit: limit, snapshot: snapshot))
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                }
                if limit.effective_mode == "limited", limit.effective_quota > 0 {
                    QuotaBar(ratio: Double(limit.shared_used) / Double(limit.effective_quota))
                }
                if let remaining = limit.displayRemaining {
                    Text("剩余 \(snapshot.formatted(remaining))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if limit.effective_mode == "unlimited" {
                    Text("不限额")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let used = team.base_used_quota, let quota = team.base_quota {
                HStack {
                    Text("个人本周期")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot.formatted(used) + " / "
                         + (team.remaining_quota == nil ? "不限额" : snapshot.formatted(quota + (team.temporary_quota ?? 0))))
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                }
            } else {
                Text("暂无个人额度数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let resetAt = team.nextResetAt {
                Text("下次重置 \(localizedResetTime(for: resetAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func personalDetails(team: TeamBuddySnapshot.Team, snapshot: TeamBuddySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let limits = team.limits {
                ForEach(limits.filter { $0.id != team.primaryPersonalLimit?.id }) { limit in
                    metricRow("个人\(limit.periodName)", usedQuotaLabel(limit: limit, snapshot: snapshot))
                }
            }
            if let temporary = team.temporaryRemaining, temporary > 0 {
                metricRow("剩余临时额度", snapshot.formatted(temporary))
            }
            if team.reserved_quota > 0 {
                metricRow("成员专用额度", snapshot.formatted(team.reserved_quota))
            }
            metricRow("本周期消耗", snapshot.formatted(team.team_borne_quota))
            Text("个人限额按共享消耗计算；专用额度单独计算。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func usedQuotaLabel(limit: TeamBuddySnapshot.PeriodLimit, snapshot: TeamBuddySnapshot) -> String {
        let used = snapshot.formatted(limit.shared_used)
        switch limit.effective_mode {
        case "unlimited": return "\(used) / 不限额"
        case "limited": return "\(used) / \(snapshot.formatted(limit.effective_quota))"
        default: return "\(used) / --"
        }
    }

    private func teamRankings(team: TeamBuddySnapshot.Team, overview: TeamBuddySnapshot.Overview, snapshot: TeamBuddySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: rankingBinding(for: team.id)) {
                if overview.rankings.isEmpty {
                    Text("暂无可见排名数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(overview.rankings) { entry in
                        let isCurrentUser = entry.member.user_id == snapshot.current_user?.id
                        rankingRow(
                            rank: "#\(entry.rank)",
                            name: entry.member.name,
                            amount: snapshot.formatted(entry.member.consumed_quota),
                            isCurrentUser: isCurrentUser
                        )
                    }
                    if let user = snapshot.current_user,
                       !overview.rankings.contains(where: { $0.member.user_id == user.id }) {
                        let currentUser = overview.rank(for: user.id)
                        rankingRow(
                            rank: currentUser.map { "#\($0.rank)" } ?? "",
                            name: currentUser?.member.name ?? user.name,
                            amount: (currentUser?.member.consumed_quota ?? team.consumed_quota ?? team.base_used_quota)
                                .map(snapshot.formatted) ?? "--",
                            isCurrentUser: true
                        )
                    }
                    Text("本周期 · 按总消耗排序 · 前 5 名")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack(spacing: 8) {
                    Label("团队消耗榜", systemImage: "trophy")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let status = overview.teamDailyStatus {
                        Text(status)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(teamStatusColor(status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(teamStatusColor(status).opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    private func teamStatusColor(_ status: String) -> Color {
        switch status {
        case "已用完": return .red
        case "接近上限": return .orange
        case "充足": return .green
        default: return .secondary
        }
    }

    private func rankingRow(rank: String, name: String, amount: String, isCurrentUser: Bool) -> some View {
        HStack(spacing: 8) {
            Text(rank)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: 28, alignment: .leading)
            memberName(name, isCurrentUser: isCurrentUser)
            Spacer()
            Text(amount)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isCurrentUser ? Color.accentColor.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCurrentUser ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func localizedResetTime(for timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func memberName(_ name: String, isCurrentUser: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .lineLimit(1)
            if isCurrentUser {
                Text("我")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailBinding(for teamID: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.expandedTeamDetails.contains(teamID) },
            set: { expanded in
                if expanded { viewModel.expandedTeamDetails.insert(teamID) }
                else { viewModel.expandedTeamDetails.remove(teamID) }
            }
        )
    }

    private func rankingBinding(for teamID: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.expandedTeamRankings.contains(teamID) },
            set: { expanded in
                if expanded { viewModel.expandedTeamRankings.insert(teamID) }
                else { viewModel.expandedTeamRankings.remove(teamID) }
            }
        )
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack {
            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                if viewModel.isRefreshingMicu || viewModel.isRefreshingTeamBuddy {
                    Label("刷新中…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("立即刷新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isRefreshingMicu || viewModel.isRefreshingTeamBuddy)

            Button("设置") {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Helpers

private struct QuotaBar: View {
    let ratio: Double

    private var clamped: Double { min(max(ratio, 0), 1) }
    private var tint: Color {
        if clamped >= 0.9 { return .red }
        if clamped >= 0.7 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(geo.size.width * clamped, clamped > 0 ? 4 : 0))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("已用 \(Int((clamped * 100).rounded()))%")
    }
}

private struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private extension TeamBuddySnapshot.Team {
    /// Prefer the limited period with the highest usage ratio; otherwise the first period.
    var primaryPersonalLimit: TeamBuddySnapshot.PeriodLimit? {
        guard let limits, !limits.isEmpty else { return nil }
        let limited = limits.filter { $0.effective_mode == "limited" && $0.effective_quota > 0 }
        if let tightest = limited.max(by: {
            Double($0.shared_used) / Double($0.effective_quota)
                < Double($1.shared_used) / Double($1.effective_quota)
        }) {
            return tightest
        }
        return limits.first
    }
}

private extension TeamBuddySnapshot.PeriodLimit {
    var displayRemaining: Int? {
        if let remaining_quota { return remaining_quota }
        guard effective_mode == "limited", effective_quota > 0 else { return nil }
        return max(0, effective_quota - shared_used)
    }
}
