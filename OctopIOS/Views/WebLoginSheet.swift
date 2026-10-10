import SwiftUI
import WebKit

/// 网页方式登录：加载 Octop 自带的登录页（支持滑动验证码 / LDAP / OIDC），
/// 通过轮询 localStorage 拿到登录后的 JWT 再回传给原生。
struct WebLoginSheet: View {
    let server: OctopServer
    var onToken: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var progress: Double = 0

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                WebLoginWebView(server: server, progress: $progress) { token in
                    onToken(token)
                    dismiss()
                }
                if progress < 1.0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Octop 登录").font(.headline)
                        Text(server.hostLabel).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - WebView

private struct WebLoginWebView: UIViewRepresentable {
    let server: OctopServer
    @Binding var progress: Double
    var onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let content = WKUserContentController()
        content.add(context.coordinator, name: "octopBridge")
        content.addUserScript(WKUserScript(source: Coordinator.bridgeScript,
                                           injectionTime: .atDocumentStart,
                                           forMainFrameOnly: true))
        configuration.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground

        context.coordinator.attach(webView)

        var request = URLRequest(url: URL(string: server.address + "/login") ?? server.baseURL ?? URL(string: "about:blank")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebLoginWebView
        private var observations: [NSKeyValueObservation] = []
        private var finished = false

        init(_ parent: WebLoginWebView) {
            self.parent = parent
        }

        func attach(_ webView: WKWebView) {
            observations.append(webView.observe(\.estimatedProgress) { [weak self] obj, _ in
                let value = obj.estimatedProgress
                DispatchQueue.main.async { self?.parent.progress = value }
            })
        }

        /// 轮询 localStorage 里的 token 和当前路径。
        static let bridgeScript = """
        (function(){
          if (window.__octopBridgeInstalled) return;
          window.__octopBridgeInstalled = true;
          function report(){
            try {
              var t = localStorage.getItem('auth_token') || '';
              window.webkit.messageHandlers.octopBridge.postMessage({
                type: 'auth', token: t, path: location.pathname, origin: location.origin
              });
            } catch(e) {}
          }
          setInterval(report, 700);
          report();
        })();
        """

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "octopBridge",
                  let body = message.body as? [String: Any] else { return }
            let token = (body["token"] as? String) ?? ""
            let path = (body["path"] as? String) ?? ""
            let origin = (body["origin"] as? String) ?? ""
            DispatchQueue.main.async { self.handle(token: token, path: path, origin: origin) }
        }

        private func handle(token: String, path: String, origin: String) {
            guard !finished, !token.isEmpty else { return }
            guard let expected = parent.server.origin, origin == expected else { return }
            let lower = path.lowercased()
            let onAuthPage = lower.hasPrefix("/login") || lower.hasPrefix("/setup") || lower.hasPrefix("/invite")
            guard !onAuthPage else { return }
            finished = true
            parent.onToken(token)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let scheme = navigationAction.request.url?.scheme {
                let special = ["tel", "mailto", "sms", "facetime"]
                if special.contains(scheme.lowercased()) {
                    UIApplication.shared.open(navigationAction.request.url!)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
