import AppKit
import WebKit
import LabforgeCore

@MainActor
final class TeamBuddyWindowController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = TeamBuddyWindowController()
    private var window: NSWindow?
    private var webView: WKWebView?
    private var message: NSTextField?
    private var pageReady = false
    private var pageWaiters: [CheckedContinuation<Void, Error>] = []
    var onClose: (() -> Void)?

    private func prepareWebView() -> WKWebView {
        if let webView {
            if !pageReady && !webView.isLoading {
                webView.load(URLRequest(url: TeamBuddyEndpoints.consoleURL))
            }
            return webView
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: TeamBuddyEndpoints.consoleURL))
        return webView
    }

    func fetchAccountData() async throws -> String {
        let webView = prepareWebView()
        if !pageReady {
            try await withCheckedThrowingContinuation { pageWaiters.append($0) }
        }
        guard webView.url?.scheme == "https", webView.url?.host == TeamBuddyEndpoints.websiteURL.host else {
            throw AppError.invalidCredentials
        }
        let result = try await webView.callAsyncJavaScript("""
            async function readAccount() {
                const response = await fetch('/api/user/auth/refresh', {
                    method: 'POST', credentials: 'include', signal: AbortSignal.timeout(20000)
                });
                const auth = await response.json();
                if (response.status === 401) return JSON.stringify({ error: 'login_required' });
                if (!response.ok || !auth.success || !auth.data?.access_token)
                    throw new Error('TeamBuddy 登录态刷新失败，请稍后重试');
                const headers = { Authorization: 'Bearer ' + auth.data.access_token };
                async function get(path) {
                    const r = await fetch(path, { credentials: 'include', headers, signal: AbortSignal.timeout(20000) });
                    const body = await r.json();
                    if (!r.ok || !body.success) throw new Error(body.message || 'TeamBuddy 数据读取失败');
                    return body.data;
                }
                const [quotas, status] = await Promise.all([
                    get('/api/team/my-quotas?page_size=100'), get('/api/status')
                ]);
                const teams = quotas.teams || [];
                for (let page = 2; teams.length < (quotas.team_pagination?.total || 0); page++) {
                    const next = await get('/api/team/my-quotas?page_size=100&p=' + page);
                    if (!next.teams?.length) throw new Error('TeamBuddy 团队列表不完整');
                    teams.push(...next.teams);
                }
                const overviews = await Promise.all(teams.map(async team => ({
                    team_id: team.team_id,
                    data: team.team_status === 'active' && team.member_status === 'active'
                        ? await get('/api/team/overview?team_id=' + encodeURIComponent(team.team_id)) : null
                })));
                return JSON.stringify({ quotas, overviews, current_user: {
                    id: auth.data.user.id,
                    username: auth.data.user.username,
                    display_name: auth.data.user.display_name
                }, currency: {
                    quota_per_unit: status.quota_per_unit,
                    quota_display_type: status.quota_display_type,
                    usd_exchange_rate: status.usd_exchange_rate,
                    custom_currency_symbol: status.custom_currency_symbol,
                    custom_currency_exchange_rate: status.custom_currency_exchange_rate
                }});
            }
            try {
                return navigator.locks
                    ? await navigator.locks.request('new-api:auth-refresh', readAccount)
                    : await readAccount();
            } catch (error) {
                return JSON.stringify({ error: 'request_failed', message: error.message || 'TeamBuddy 网络请求失败' });
            }
            """, arguments: [:], in: nil, contentWorld: .page)
        guard let json = result as? String else { throw AppError.parseFailure("TeamBuddy 数据为空") }
        return json
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let webView = prepareWebView()
        let message = NSTextField(wrappingLabelWithString: "使用原账号登录 TeamBuddy；首次登录请完成网页验证。")
        let reload = NSButton(title: "重新加载", target: self, action: #selector(reloadConsole))
        let browser = NSButton(title: "在浏览器打开", target: self, action: #selector(openInBrowser))
        let buttons = NSStackView(views: [reload, browser])
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "TeamBuddy · TokenBoard"
        window.minSize = NSSize(width: 760, height: 560)
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.webView = webView
        self.message = message
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadConsole() {
        if webView?.url == nil {
            webView?.load(URLRequest(url: TeamBuddyEndpoints.consoleURL))
        } else {
            webView?.reload()
        }
    }

    @objc private func openInBrowser() {
        NSWorkspace.shared.open(TeamBuddyEndpoints.consoleURL)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // Verification widgets run in subframes; only restrict top-level navigation.
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
        } else if url.scheme == "https", url.host == TeamBuddyEndpoints.websiteURL.host {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if url.scheme == "https" { NSWorkspace.shared.open(url) }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        let waiters = pageWaiters
        pageWaiters.removeAll()
        waiters.forEach { $0.resume() }
        message?.stringValue = "使用原账号登录；登录态由应用保存。若网页验证无法完成，可在浏览器打开。"
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pageReady = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    private func showLoadError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        pageReady = false
        let waiters = pageWaiters
        pageWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
        message?.stringValue = "网页加载失败，请重新加载或在浏览器打开。"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showLoadError(URLError(.networkConnectionLost))
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        message = nil
        onClose?()
    }
}
