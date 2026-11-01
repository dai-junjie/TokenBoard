import AppKit
import SwiftUI
import LabforgeCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
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

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(width: 420, height: 260)
    }
}
