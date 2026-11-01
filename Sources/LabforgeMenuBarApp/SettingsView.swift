import AppKit
import SwiftUI
import LabforgeCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var micuAccountName = ""
    @State private var micuUsername = ""
    @State private var micuPassword = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("TeamBuddy").font(.headline)
                Text("首次通过网页登录，完成后关闭窗口；额度会直接显示在菜单栏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("打开 TeamBuddy 控制台") {
                    TeamBuddyWindowController.shared.show()
                }
                Text("API Base URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(TeamBuddyEndpoints.apiBaseURL.absoluteString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button("复制 API 地址") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(TeamBuddyEndpoints.apiBaseURL.absoluteString, forType: .string)
                }

                Divider()
                Text("米醋账号").font(.headline)
                ForEach(viewModel.micuAccounts) { state in
                    MicuAccountSettingsRow(account: state.account, viewModel: viewModel)
                }
                Text("添加账号 / 重新登录").font(.subheadline.weight(.semibold))
                TextField("账号备注（可选）", text: $micuAccountName)
                Button("通过 GitHub 授权登录米醋") {
                    viewModel.loginMicuWithGitHub(name: micuAccountName)
                }
                .disabled(viewModel.isAddingMicuAccount)
                Text("在登录窗口选择 GitHub，授权返回米醋后点击“完成登录”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("米醋用户名", text: $micuUsername)
                SecureField("米醋密码", text: $micuPassword)
                Button("添加账号密码账号") {
                    viewModel.saveMicuCredentials(username: micuUsername, password: micuPassword, name: micuAccountName)
                    micuPassword = ""
                }
                .disabled(micuUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || micuPassword.isEmpty || viewModel.isAddingMicuAccount)
                Text("米醋登录信息保存在 macOS 钥匙串。今日消耗按北京时间零点起统计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.micuStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(width: 420, height: 560)
    }
}

private struct MicuAccountSettingsRow: View {
    let account: MicuAccount
    @ObservedObject var viewModel: AppViewModel
    @State private var name = ""
    @State private var confirmsRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("账号备注", text: $name)
                Button("保存备注") { viewModel.renameMicuAccount(id: account.id, name: name) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == account.name)
                Button("移除", role: .destructive) { confirmsRemoval = true }
            }
            Text(account.loginDescription).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { name = account.name }
        .onChange(of: account.name) { _, value in name = value }
        .alert("移除“\(account.name)”？", isPresented: $confirmsRemoval) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) { viewModel.removeMicuAccount(id: account.id) }
        } message: {
            Text("只移除此应用保存的账号，不会删除米醋平台上的账号。")
        }
    }
}
