import SwiftUI
import UIKit
import WebKit
import PhotosUI
import UniformTypeIdentifiers

/// Octop 控制台的 WebView 承载。
/// 登录 token 在文档开头注入 localStorage（Octop 前端认的就是 auth_token 这个键），
/// 页面里跑一个轮询桥，把网页侧续期/清空的 token 回传给原生，两边保持一致。
struct WebConsoleView: UIViewRepresentable {
    let server: OctopServer
    let token: String
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: WebConsoleModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let content = WKUserContentController()
        content.add(context.coordinator, name: "octopBridge")
        configuration.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground

        model.attach(webView, homeAddress: server.address)
        context.coordinator.model = model

        context.coordinator.appliedDesktopMode = settings.desktopMode
        webView.customUserAgent = settings.desktopMode ? AppSettings.desktopUserAgent : nil
        webView.pageZoom = CGFloat(settings.pageZoom)
        webView.overrideUserInterfaceStyle = settings.appearance.uiStyle
        context.coordinator.applyRefreshControl(in: webView, enabled: settings.pullToRefresh)
        context.coordinator.installScripts(in: webView, token: token)

        if let url = model.homeURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.model = model

        webView.pageZoom = CGFloat(settings.pageZoom)
        webView.overrideUserInterfaceStyle = settings.appearance.uiStyle
        context.coordinator.applyRefreshControl(in: webView, enabled: settings.pullToRefresh)

        if context.coordinator.appliedDesktopMode != settings.desktopMode {
            context.coordinator.appliedDesktopMode = settings.desktopMode
            webView.customUserAgent = settings.desktopMode ? AppSettings.desktopUserAgent : nil
            webView.reload()
        }

        if context.coordinator.injectedToken != token {
            context.coordinator.installScripts(in: webView, token: token)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject,
                             WKNavigationDelegate,
                             WKUIDelegate,
                             WKScriptMessageHandler,
                             WKDownloadDelegate,
                             UIDocumentPickerDelegate,
                             PHPickerViewControllerDelegate {

        var parent: WebConsoleView
        weak var model: WebConsoleModel?

        var injectedToken: String = ""
        var appliedDesktopMode: Bool = false

        private var hasSeenToken = false
        private var uploadCompletion: (([URL]?) -> Void)?
        private var uploadAllowsMultiple = false
        private var pendingDownloadName: String?
        private var pendingDownloadURL: URL?
        private var refreshControl: UIRefreshControl?

        init(_ parent: WebConsoleView) {
            self.parent = parent
        }

        // MARK: 注入脚本

        func installScripts(in webView: WKWebView, token: String) {
            injectedToken = token
            let content = webView.configuration.userContentController
            content.removeAllUserScripts()
            content.removeAllScriptMessageHandlers()
            content.add(self, name: "octopBridge")

            if !token.isEmpty {
                let source = "(function(){try{localStorage.setItem('auth_token',\(Self.jsString(token)));}catch(e){}})();"
                content.addUserScript(WKUserScript(source: source,
                                                   injectionTime: .atDocumentStart,
                                                   forMainFrameOnly: true))
            }
            content.addUserScript(WKUserScript(source: Self.bridgeScript,
                                               injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true))
            if appliedDesktopMode {
                content.addUserScript(WKUserScript(source: Self.desktopViewportScript,
                                                   injectionTime: .atDocumentEnd,
                                                   forMainFrameOnly: true))
            }
        }

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
          setInterval(report, 800);
          report();
        })();
        """

        static let desktopViewportScript = """
        (function(){
          function apply(){
            try {
              var m = document.querySelector('meta[name="viewport"]');
              if (!m) { m = document.createElement('meta'); m.setAttribute('name','viewport');
                        (document.head || document.documentElement).appendChild(m); }
              m.setAttribute('content','width=1280, initial-scale=1, minimum-scale=0.1, maximum-scale=5, shrink-to-fit=no');
            } catch(e) {}
          }
          apply();
          document.addEventListener('DOMContentLoaded', apply);
        })();
        """

        /// JWT 是 base64url + 点号，这里还是老老实实转义一遍，稳妥。
        static func jsString(_ value: String) -> String {
            var escaped = ""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\"": escaped += "\\\""
                case "\\": escaped += "\\\\"
                case "\n": escaped += "\\n"
                case "\r": escaped += "\\r"
                case "\t": escaped += "\\t"
                default:
                    if scalar.value < 0x20 {
                        escaped += String(format: "\\u%04x", scalar.value)
                    } else {
                        escaped += String(scalar)
                    }
                }
            }
            return "\"" + escaped + "\""
        }

        // MARK: 下拉刷新

        func applyRefreshControl(in webView: WKWebView, enabled: Bool) {
            if enabled {
                if refreshControl != nil { return }
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
                webView.scrollView.refreshControl = control
                refreshControl = control
            } else {
                refreshControl?.endRefreshing()
                webView.scrollView.refreshControl = nil
                refreshControl = nil
            }
        }

        @objc private func refreshPulled() {
            Haptics.light()
            model?.reload()
        }

        // MARK: JS 桥

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "octopBridge",
                  let body = message.body as? [String: Any] else { return }
            let token = (body["token"] as? String) ?? ""
            let origin = (body["origin"] as? String) ?? ""
            DispatchQueue.main.async { self.handleAuth(token: token, origin: origin) }
        }

        private func handleAuth(token: String, origin: String) {
            guard let model = model else { return }
            guard let expected = parent.server.origin, origin == expected else { return }

            if !token.isEmpty {
                hasSeenToken = true
                if token != injectedToken {
                    model.onTokenRefreshed?(token)
                }
            } else if hasSeenToken {
                hasSeenToken = false
                model.sessionEnded = true
            }
        }

        // MARK: 导航

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if let scheme = url.scheme?.lowercased() {
                let external = ["tel", "mailto", "sms", "facetime", "itms-apps"]
                if external.contains(scheme) {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
                let allowed = ["http", "https", "about", "file", "blob", "data"]
                if !allowed.contains(scheme) {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model?.endRefreshControl()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportError(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            reportError(error)
        }

        private func reportError(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            let message = (error as? URLError).map { OctopAPIError.describe($0) }
                ?? error.localizedDescription
            DispatchQueue.main.async {
                self.model?.loadError = message
                self.model?.endRefreshControl()
            }
        }

        /// 局域网自签名证书放行（需要在设置里打开）。
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               parent.settings.allowInsecureTLS,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            completionHandler(.performDefaultHandling, nil)
        }

        /// target=_blank 的链接直接在当前 WebView 里打开。
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: 下载

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
            pendingDownloadName = navigationResponse.response.suggestedFilename
        }

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
            pendingDownloadName = navigationAction.request.url?.lastPathComponent
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let raw = suggestedFilename.isEmpty ? (pendingDownloadName ?? "download") : suggestedFilename
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OctopDownloads", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var target = directory.appendingPathComponent(Self.safeFilename(raw))
            if FileManager.default.fileExists(atPath: target.path) {
                let stem = target.deletingPathExtension().lastPathComponent
                let ext = target.pathExtension
                let suffix = Int(Date().timeIntervalSince1970)
                target = directory.appendingPathComponent(
                    ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)")
            }
            pendingDownloadURL = target
            completionHandler(target)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let url = pendingDownloadURL
            pendingDownloadURL = nil
            DispatchQueue.main.async {
                if let url { self.model?.shareFileURL = url }
                self.model?.endRefreshControl()
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            pendingDownloadURL = nil
            DispatchQueue.main.async {
                self.model?.loadError = "下载失败：\(error.localizedDescription)"
            }
        }

        static func safeFilename(_ name: String) -> String {
            let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "download" : cleaned
        }

        // MARK: 文件上传（input type=file）

        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            uploadCompletion = completionHandler
            uploadAllowsMultiple = parameters.allowsMultipleSelection

            let host = topMostViewController()
            let alert = UIAlertController(title: nil, message: "选择要上传的内容", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "从相册选择", style: .default) { [weak self] _ in
                self?.presentPhotoPicker(from: host)
            })
            alert.addAction(UIAlertAction(title: "从文件选择", style: .default) { [weak self] _ in
                self?.presentDocumentPicker(from: host)
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
                self?.uploadCompletion = nil
                completionHandler(nil)
            })

            if let popover = alert.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = CGRect(x: webView.bounds.midX,
                                            y: webView.bounds.midY,
                                            width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            host?.present(alert, animated: true)
        }

        private func presentPhotoPicker(from host: UIViewController?) {
            guard let host else {
                uploadCompletion?(nil)
                uploadCompletion = nil
                return
            }
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = uploadAllowsMultiple ? 0 : 1
            configuration.filter = .any(of: [.images, .videos, .livePhotos])

            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            host.present(picker, animated: true)
        }

        private func presentDocumentPicker(from host: UIViewController?) {
            guard let host else {
                uploadCompletion?(nil)
                uploadCompletion = nil
                return
            }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = uploadAllowsMultiple
            host.present(picker, animated: true)
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let completion = uploadCompletion else { return }
            uploadCompletion = nil

            let providers = results.map { $0.itemProvider }
            copyProviders(providers) { urls in
                DispatchQueue.main.async { completion(urls) }
            }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let completion = uploadCompletion else { return }
            uploadCompletion = nil
            completion(urls.isEmpty ? nil : urls)
        }

        private func copyProviders(_ providers: [NSItemProvider],
                                   completion: @escaping ([URL]?) -> Void) {
            guard !providers.isEmpty else {
                completion(nil)
                return
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OctopUpload-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let group = DispatchGroup()
            let lock = NSLock()
            var collected: [URL] = []

            for (index, provider) in providers.enumerated() {
                let identifiers = provider.registeredTypeIdentifiers
                guard let identifier = identifiers.first(where: {
                    $0.contains("image") || $0.contains("movie") || $0.contains("video")
                }) ?? identifiers.first else { continue }

                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: identifier) { source, _ in
                    defer { group.leave() }
                    guard let source else { return }

                    var stem = provider.suggestedName ?? "upload-\(index)"
                    stem = (stem as NSString).deletingPathExtension
                    if stem.isEmpty { stem = "upload-\(index)" }
                    let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension

                    let destination = directory.appendingPathComponent("\(stem).\(ext)")
                    try? FileManager.default.removeItem(at: destination)
                    do {
                        try FileManager.default.copyItem(at: source, to: destination)
                        lock.lock()
                        collected.append(destination)
                        lock.unlock()
                    } catch { }
                }
            }

            group.notify(queue: .main) {
                completion(collected.isEmpty ? nil : collected)
            }
        }
    }
}
