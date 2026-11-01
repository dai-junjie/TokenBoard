import AppKit
import SwiftUI

private struct MenuContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private let viewModel: AppViewModel
    private var outsideClickMonitor: Any?
    private var contentHeight: CGFloat = 394

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 394),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "TokenBoard")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .popover
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        backgroundView.layer?.borderWidth = 0.5
        backgroundView.layer?.borderColor = NSColor.separatorColor.cgColor

        let hostingView = NSHostingView(rootView: ScrollView {
            MenuBarContentView(viewModel: viewModel)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: MenuContentHeightKey.self, value: geometry.size.height)
                })
        }
        .scrollIndicators(.visible)
        .onPreferenceChange(MenuContentHeightKey.self) { [weak self] height in
            DispatchQueue.main.async { [weak self] in
                guard height > 0 else { return }
                self?.contentHeight = height
                self?.updatePanelHeight(height)
            }
        })
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])
        panel.contentView = backgroundView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.sharingType = .readOnly
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return }
            let location = NSEvent.mouseLocation
            if !self.panel.frame.contains(location) {
                self.panel.orderOut(nil)
            }
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        viewModel.resetMenuDisclosureState()
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        updatePanelHeight(contentHeight)
        let size = panel.frame.size
        let origin = NSPoint(
            x: screenRect.midX - size.width / 2,
            y: screenRect.minY - size.height - 6
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func updatePanelHeight(_ height: CGFloat) {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let availableHeight = (screen?.visibleFrame.height ?? 900) - 40
        let fittedHeight = min(ceil(height), availableHeight)
        guard panel.frame.height != fittedHeight else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = fittedHeight
        frame.origin.y = top - fittedHeight
        panel.setFrame(frame, display: panel.isVisible, animate: panel.isVisible)
    }
}
