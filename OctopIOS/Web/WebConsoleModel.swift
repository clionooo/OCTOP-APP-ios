import Foundation
import WebKit

/// 控制台 WebView 的状态与命令。
final class WebConsoleModel: NSObject, ObservableObject {
    @Published var progress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var loadError: String?
    /// 网页层登出 / token 被清掉时置 true，界面提示重新登录。
    @Published var sessionEnded: Bool = false
    /// 下载完成后要分享的文件。
    @Published var shareFileURL: URL?

    private(set) var homeURL: URL?
    weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    /// 网页层续期了 JWT 时回调，原生这边把它存起来。
    var onTokenRefreshed: ((String) -> Void)?

    func attach(_ webView: WKWebView, homeAddress: String) {
        self.webView = webView
        self.homeURL = URL(string: homeAddress + "/")
        observations.removeAll()

        observations.append(webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] obj, _ in
            let value = obj.estimatedProgress
            DispatchQueue.main.async { self?.progress = value }
        })
        observations.append(webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] obj, _ in
            let value = obj.canGoBack
            DispatchQueue.main.async { self?.canGoBack = value }
        })
        observations.append(webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] obj, _ in
            let value = obj.canGoForward
            DispatchQueue.main.async { self?.canGoForward = value }
        })
        observations.append(webView.observe(\.title, options: [.initial, .new]) { [weak self] obj, _ in
            let value = obj.title ?? ""
            DispatchQueue.main.async { self?.pageTitle = value }
        })
        observations.append(webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] obj, _ in
            let value = obj.isLoading
            DispatchQueue.main.async { self?.isLoading = value }
        })
    }

    // MARK: 命令

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func reload() {
        loadError = nil
        if let url = webView?.url, url.scheme?.hasPrefix("http") == true {
            webView?.reload()
        } else {
            loadHome()
        }
    }

    func loadHome() {
        loadError = nil
        sessionEnded = false
        guard let url = homeURL else { return }
        webView?.load(URLRequest(url: url))
    }

    func endRefreshControl() {
        webView?.scrollView.refreshControl?.endRefreshing()
    }
}
