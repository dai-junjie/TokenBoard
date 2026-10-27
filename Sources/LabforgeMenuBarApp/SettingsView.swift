import SwiftUI
import LabforgeCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Labforge").font(.headline)
                TextField("Labforge 用户名", text: $username)
                SecureField("密码", text: $password)
                Button("保存登录信息") {
                    viewModel.saveCredentials(username: username, password: password)
                }
                .disabled(username.isEmpty || password.isEmpty)

                Toggle("显示日排行榜", isOn: $viewModel.showsRankings)
                Toggle("默认展开模型测试详情", isOn: $viewModel.expandsModelTestsByDefault)
                Toggle("默认展开今日排行榜", isOn: $viewModel.expandsRankingsByDefault)

                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(width: 420, height: 280)
        .task {
            if let credentials = try? viewModel.storedCredentials() {
                username = credentials.username
                password = credentials.password
            }
        }
    }
}
