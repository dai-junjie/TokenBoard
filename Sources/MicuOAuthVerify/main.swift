import AppKit
import WebKit
import LabforgeCore

// Exercise WebKit itself: a same-window OAuth redirect must not look like binding.
@MainActor
final class OAuthProbe: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var stage = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: MicuWebLogin.documentStartScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                let hasOpener = try await webView.evaluateJavaScript("!!window.opener") as! Bool
                if stage == 0 {
                    precondition(!hasOpener)
                    stage = 1
                    // This creates the real WebKit self-opener bug on an unrelated page.
                    _ = try await webView.evaluateJavaScript("window.open('about:blank', '_self'); undefined")
                } else if stage == 1 {
                    precondition(hasOpener, "Probe must reproduce WebKit's self-opener")
                    stage = 2
                    webView.loadHTMLString("<html>OAuth callback</html>",
                        baseURL: URL(string: "https://www.micuapi.ai/oauth/github"))
                } else {
                    precondition(!hasOpener, "Micu callback must be treated as sign-in")
                    print("MicuOAuthVerify: PASS (reproduced self-opener and cleared it on callback)")
                    exit(0)
                }
            } catch {
                fatalError("WebKit probe failed: \(error)")
            }
        }
    }
}

let app = NSApplication.shared
let probe = OAuthProbe()
probe.webView.loadHTMLString("<html>Sign in</html>", baseURL: nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
    fatalError("WebKit probe timed out")
}
app.run()
