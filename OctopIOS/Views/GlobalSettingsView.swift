import SwiftUI
import WebKit

/// 全局设置。
struct GlobalSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ServerStore
    @Environment(\.dismiss) private var dismiss

    @State private var showClearDataConfirm = false
    @State private var clearedNotice: String?

    var body: some View {
        Form {
            Section(header: Text("外观")) {
                Picker("主题", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
            }

            Section(header: Text("控制台"),
                    footer: Text("桌面模式会切换成桌面版 UA 并固定 1280pt 视口，控制台排版在手机上挤成一团时试试它。")) {
                Toggle(isOn: $settings.desktopMode) {
                    Text("桌面模式")
                }
                HStack {
                    Text("页面缩放")
                    Spacer()
                    Button {
                        settings.pageZoom = max(0.8, settings.pageZoom - 0.1)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)

                    Text("\(Int((settings.pageZoom * 100).rounded()))%")
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 48)
                        .foregroundColor(.secondary)

                    Button {
                        settings.pageZoom = min(1.5, settings.pageZoom + 0.1)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                Toggle(isOn: $settings.pullToRefresh) {
                    Text("下拉刷新")
                }
                Toggle(isOn: $settings.keepScreenAwake) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保持屏幕常亮")
                        Text("直播时盯弹幕不用总戳屏幕")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("网络"),
                    footer: Text("局域网里用自签名 HTTPS 时需要打开。明文 http 不受影响。")) {
                Toggle(isOn: $settings.allowInsecureTLS) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许自签名证书")
                        Text("跳过 HTTPS 证书校验")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("数据")) {
                Button {
                    showClearDataConfirm = true
                } label: {
                    HStack {
                        Text("清除网站数据与缓存")
                            .foregroundColor(.red)
                        Spacer()
                        if clearedNotice != nil {
                            ProgressView()
                        }
                    }
                }
            }

            Section(header: Text("关于")) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(Self.versionText)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("目标平台")
                    Spacer()
                    Text("Octop Web 控制台")
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .top) {
                    Text("服务器数量")
                    Spacer()
                    Text("\(store.servers.count)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("清除所有网站数据？", isPresented: $showClearDataConfirm) {
            Button("清除", role: .destructive) {
                clearWebsiteData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除所有 Octop 服务器在 App 里留下的 Cookie、localStorage 和缓存。")
        }
    }

    private static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                         modifiedSince: Date.distantPast) {
            DispatchQueue.main.async {
                clearedNotice = nil
            }
        }
    }
}
