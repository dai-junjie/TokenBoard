import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(viewModel: AppViewModel) {
        NSApp.setActivationPolicy(.regular)

        if let window {
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            positionNearStatusBar(window)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)

        let contentRect = NSRect(x: 0, y: 0, width: 440, height: 500)


        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Labforge 设置"

        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        positionNearStatusBar(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.window = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }

        self.window = window
    }

    private func positionNearStatusBar(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let size = window.frame.size
        let x = visibleFrame.minX + visibleFrame.width * 0.72 - size.width / 2
        let y = visibleFrame.midY - size.height / 2
        let safeX = min(max(x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
        let safeY = min(max(y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        window.setFrameOrigin(NSPoint(x: safeX, y: safeY))
    }
}
