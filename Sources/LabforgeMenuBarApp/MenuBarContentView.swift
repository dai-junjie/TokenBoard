import AppKit
import SwiftUI
import LabforgeCore

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            micuSection
            Divider()

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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(team.team_name).font(.subheadline.weight(.medium))
                            if team.isActive {
                                if let limits = team.limits {
                                    ForEach(limits) { limit in
                                        metricRow("个人\(limit.periodName)已用 / 限额", snapshot.formatted(limit.shared_used) + " / "
                                            + (limit.effective_mode == "unlimited" ? "不限额"
                                                : limit.effective_mode == "limited" ? snapshot.formatted(limit.effective_quota) : "--"))
                                    }
                                    if let temporary = team.temporaryRemaining, temporary > 0 {
                                        metricRow("剩余临时额度", snapshot.formatted(temporary))
                                    }
                                    Text("个人限额按共享消耗计算；专用额度单独计算。")
                                        .font(.caption2).foregroundStyle(.secondary)
                                } else if let used = team.base_used_quota, let quota = team.base_quota,
                                          let temporary = team.temporary_quota {
                                    metricRow("个人已用 / 上限", snapshot.formatted(used) + " / "
                                        + (team.remaining_quota == nil ? "不限额" : snapshot.formatted(quota + temporary)))
                                }
                                if team.reserved_quota > 0 {
                                    metricRow("成员专用额度", snapshot.formatted(team.reserved_quota))
                                }
                                if let overview = snapshot.overviews.first(where: { $0.team_id == team.id })?.data {
                                    metricRow("团队每日上限", overview.teamDailyStatus ?? "--")
                                }
                                if let limit = snapshot.overviews.first(where: { $0.team_id == team.id })?.data?.daily_limit {
                                    metricRow("团队已用 / 上限", snapshot.formatted(limit.spent) + " / "
                                        + (limit.limit.map(snapshot.formatted) ?? "不限额"))
                                }
                                metricRow("本周期消耗", snapshot.formatted(team.team_borne_quota))
                                if let resetAt = team.nextResetAt {
                                    Text("下次重置：\(localizedResetTime(for: resetAt))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let overview = snapshot.overviews.first(where: { $0.team_id == team.id })?.data {
                                    teamRankings(team: team, overview: overview, snapshot: snapshot)
                                }
                            } else {
                                Text("团队或成员已停用").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        TeamBuddyWindowController.shared.show()
                    }
                    label: {
                        Label(viewModel.teamBuddyNeedsLogin ? "登录 TeamBuddy" : "打开 TeamBuddy 控制台",
                              systemImage: viewModel.teamBuddyNeedsLogin ? "person.badge.key" : "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(TeamBuddyEndpoints.apiBaseURL.absoluteString, forType: .string)
                    }
                    label: {
                        Label("复制 API 地址", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help(TeamBuddyEndpoints.apiBaseURL.absoluteString)
                }
                .controlSize(.small)
            }

            Divider()

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
        .padding()
        .frame(width: 360)
        .disclosureGroupStyle(FullRowDisclosureStyle())
    }

    private func teamRankings(team: TeamBuddySnapshot.Team, overview: TeamBuddySnapshot.Overview, snapshot: TeamBuddySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: Binding(
                get: { !viewModel.collapsedTeamRankings.contains(team.id) },
                set: { expanded in
                    if expanded { viewModel.collapsedTeamRankings.remove(team.id) }
                    else { viewModel.collapsedTeamRankings.insert(team.id) }
                }
            )) {
                if overview.rankings.isEmpty {
                    Text("暂无可见排名数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(overview.rankings) { entry in
                        let isCurrentUser = entry.member.user_id == snapshot.current_user?.id
                        HStack(spacing: 8) {
                            Text("#\(entry.rank)")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .frame(width: 32, alignment: .leading)
                            memberName(entry.member.name, isCurrentUser: isCurrentUser)
                            Spacer()
                            Text(snapshot.formatted(entry.member.consumed_quota))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(isCurrentUser ? Color.accentColor.opacity(0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isCurrentUser ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
                        }
                    }
                    if let user = snapshot.current_user,
                       !overview.rankings.contains(where: { $0.member.user_id == user.id }) {
                        let currentUser = overview.rank(for: user.id)
                        HStack(spacing: 8) {
                            Text(currentUser.map { "#\($0.rank)" } ?? "")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .frame(width: 32, alignment: .leading)
                            memberName(currentUser?.member.name ?? user.name, isCurrentUser: true)
                            Spacer()
                            Text((currentUser?.member.consumed_quota ?? team.consumed_quota ?? team.base_used_quota)
                                .map(snapshot.formatted) ?? "--")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                        }
                    }
                    Text("本周期 · 按总消耗排序 · 前 5 名")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("团队消耗榜", systemImage: "trophy")
                    .foregroundStyle(.orange)
            }
            .tint(.orange)
        }
        .padding(8)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.18), lineWidth: 0.5)
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }

    private func localizedResetTime(for timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func memberName(_ name: String, isCurrentUser: Bool) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.body)
                .lineLimit(1)
            if isCurrentUser {
                Text("我")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
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
