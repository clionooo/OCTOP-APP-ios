import SwiftUI
import UIKit

/// 外观偏好。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "gearshape"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 全局设置，全部落 UserDefaults。
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let appearance = "octop.settings.appearance"
        static let allowInsecureTLS = "octop.settings.allowInsecureTLS"
        static let desktopMode = "octop.settings.desktopMode"
        static let pageZoom = "octop.settings.pageZoom"
        static let pullToRefresh = "octop.settings.pullToRefresh"
        static let keepScreenAwake = "octop.settings.keepScreenAwake"
    }

    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// 允许自签名证书（局域网 HTTPS 常见）。
    @Published var allowInsecureTLS: Bool {
        didSet { defaults.set(allowInsecureTLS, forKey: Key.allowInsecureTLS) }
    }

    /// 桌面模式：用桌面 UA + 固定 1280pt 视口，控制台在小屏上排版难受时用。
    @Published var desktopMode: Bool {
        didSet { defaults.set(desktopMode, forKey: Key.desktopMode) }
    }

    /// 0.8 ~ 1.5
    @Published var pageZoom: Double {
        didSet { defaults.set(pageZoom, forKey: Key.pageZoom) }
    }

    @Published var pullToRefresh: Bool {
        didSet { defaults.set(pullToRefresh, forKey: Key.pullToRefresh) }
    }

    /// 直播/挂机时防止锁屏。
    @Published var keepScreenAwake: Bool {
        didSet {
            defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake)
            applyIdleTimer()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        allowInsecureTLS = defaults.bool(forKey: Key.allowInsecureTLS)
        desktopMode = defaults.bool(forKey: Key.desktopMode)
        let zoom = defaults.double(forKey: Key.pageZoom)
        pageZoom = zoom == 0 ? 1.0 : zoom
        pullToRefresh = defaults.object(forKey: Key.pullToRefresh) == nil
            ? true
            : defaults.bool(forKey: Key.pullToRefresh)
        keepScreenAwake = defaults.bool(forKey: Key.keepScreenAwake)
    }

    func applyIdleTimer() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = self.keepScreenAwake
        }
    }

    /// 桌面模式的 UA，伪装成 Mac 上的 Safari。
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.4 Safari/605.1.15"
}
