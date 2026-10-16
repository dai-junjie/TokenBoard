import SwiftUI
import LabforgeCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var username = ""
    @State private var password = ""

    @State private var micuUsername = ""
    @State private var micuPassword = ""

    var body: some View {
        Form {
            TextField("用户名", text: $username)
            SecureField("密码", text: $password)
            Button("保存登录信息") {
                viewModel.saveCredentials(username: username, password: password)
            }
            .disabled(username.isEmpty || password.isEmpty)

            Toggle("显示日排行榜", isOn: $viewModel.showsRankings)

        
            Divider()
            Text("米醋 API").font(.headline)
            Button("通过 GitHub 授权登录米醋") {
                viewModel.loginMicuWithGitHub()
            }
            .disabled(viewModel.isRefreshingMicu)
            Text("在登录窗口选择 GitHub，授权返回米醋后点击“完成登录”。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("米醋用户名", text: $micuUsername)
            SecureField("米醋密码", text: $micuPassword)
            Button("保存并登录米醋") {
                viewModel.saveMicuCredentials(username: micuUsername, password: micuPassword)
                micuPassword = ""
            }
            .disabled(micuUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || micuPassword.isEmpty || viewModel.isRefreshingMicu)
            Text("米醋登录信息保存在 macOS 钥匙串。今日消耗按北京时间零点起统计。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.micuStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, height: 480)
        .task {
            if let credentials = try? viewModel.storedCredentials() {
                username = credentials.username
                password = credentials.password
            }
        }
    }
}
