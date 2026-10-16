import AppKit
import WebKit
import LabforgeCore

@MainActor
final class MicuLoginWindowController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = MicuLoginWindowController()
    private var window: NSWindow?
    private var webView: WKWebView?
    private var message: NSTextField?
    private var completion: ((MicuWebSession) async throws -> Void)?
    private var isCompleting = false

    func show(completion: @escaping (MicuWebSession) async throws -> Void) {
        self.completion = completion
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(
            source: MicuWebLogin.documentStartScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let message = NSTextField(wrappingLabelWithString: "在米醋登录页选择 GitHub，完成授权后点击“完成登录”。")
        let finish = NSButton(title: "完成登录", target: self, action: #selector(finishLogin))
        let reload = NSButton(title: "返回米醋登录页", target: self, action: #selector(loadSignIn))
        let buttons = NSStackView(views: [reload, finish])
        buttons.spacing = 12
        let footer = NSStackView(views: [message, buttons])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 8
        let content = NSView()
        for view in [webView, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 740),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "米醋 · GitHub 授权登录"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.webView = webView
        self.message = message
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadSignIn()
    }

    @objc private func loadSignIn() {
        webView?.load(URLRequest(url: URL(string: "https://www.micuapi.ai/sign-in")!))
    }

    @objc private func finishLogin() {
        guard !isCompleting, let webView, let host = webView.url?.host,
              MicuWebSession.isMicuHost(host), webView.url?.scheme == "https" else {
            message?.stringValue = "请先完成 GitHub 授权并返回米醋页面。"
            return
        }
        isCompleting = true
        message?.stringValue = "正在验证米醋登录态……"
        Task {
            defer { isCompleting = false }
            do {
                // Runs only on Micu's HTTPS origin. Verify its own session before importing it.
                let result = try await webView.callAsyncJavaScript("""
                    const uid = localStorage.getItem('uid');
                    if (!uid) return null;
                    const response = await fetch('/api/user/self', {
                        credentials: 'include', headers: { 'New-Api-User': uid }
                    });
                    if (!response.ok) return null;
                    const body = await response.json();
                    return body.success && body.data ? body.data.id : null;
                    """, arguments: [:], in: nil, contentWorld: .page)
                guard let userID = result as? Int, userID > 0,
                      let currentHost = webView.url?.host, MicuWebSession.isMicuHost(currentHost) else {
                    throw MicuError.unauthorized
                }
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let micuCookies = cookies.filter {
                    MicuWebSession.isMicuHost($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                        && ($0.expiresDate.map { $0 > Date() } ?? true)
                }
                let session = MicuWebSession(userID: userID, cookies: micuCookies)
                _ = try session.validatedCookies()
                try await completion?(session)
                window?.close()
            } catch {
                message?.stringValue = "未完成登录：\(error.localizedDescription)"
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        message?.stringValue = "网页加载失败，请返回登录页重试。"
    }

    func windowWillClose(_ notification: Notification) {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        window = nil
        webView = nil
        message = nil
        completion = nil
    }
}
