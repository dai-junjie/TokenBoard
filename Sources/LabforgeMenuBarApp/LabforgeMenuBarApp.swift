import SwiftUI
import AppKit

@main
struct LabforgeMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appTermination) {
                    Button("退出 TokenBoard") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = AppViewModel()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(viewModel: viewModel)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        TeamBuddyWindowController.shared.show()
        return false
    }
}
