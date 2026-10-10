import SwiftUI

/// 控制台主界面：WebView + 原生底部工具条。
struct ConsoleView: View {
    let server: OctopServer
    let token: String
    var onLogout: () -> Void
    var onEditServer: () -> Void

    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = WebConsoleModel()

    @State private var currentToken: String
    @State private var shareItems: [Any]?
    @State private var showLogoutConfirm = false

    init(server: OctopServer,
         token: String,
         onLogout: @escaping () -> Void,
         onEditServer: @escaping () -> Void) {
        self.server = server
        self.token = token
        self.onLogout = onLogout
        self.onEditServer = onEditServer
        _currentToken = State(initialValue: token)
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebConsoleView(server: server,
                           token: currentToken,
                           settings: settings,
                           model: model)
                // 键盘弹出时不要压缩 WebView：压缩会和 WebKit 自己的视口平移叠加，
                // 导致输入框被顶出屏幕、页面下方留一大片白。交给 WebKit 处理（和 Safari 一致）。
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .zIndex(0)

            if model.isLoading && model.progress < 1.0 {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .animation(.easeInOut(duration: 0.2), value: model.progress)
                    .zIndex(3)
            }

            if let error = model.loadError {
                overlayCard(
                    title: "页面加载失败",
                    message: error,
                    icon: "wifi.exclamationmark",
                    tint: .orange,
                    primaryTitle: "重试",
                    primaryAction: { model.reload() },
                    secondaryTitle: "回登录页",
                    secondaryAction: { onLogout() }
                ).zIndex(4)
            }

            if model.sessionEnded {
                overlayCard(
                    title: "登录状态已结束",
                    message: "网页那边已经退出登录了。要继续使用请重新登录。",
                    icon: "lock.rotation",
                    tint: .blue,
                    primaryTitle: "重新登录",
                    primaryAction: { onLogout() }
                ).zIndex(4)
            }
        }
        .navigationTitle(server.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { menu }
        }
        .onAppear {
            if model.onTokenRefreshed == nil {
                model.onTokenRefreshed = { newToken in
                    currentToken = newToken
                    store.saveToken(newToken, for: server)
                }
            }
        }
        .onChange(of: model.sessionEnded) { ended in
            if ended { store.clearToken(for: server) }
        }
        .sheet(isPresented: Binding(get: { shareItems != nil },
                                    set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems {
                ActivityShareSheet(items: items)
            }
        }
        .alert("退出登录？", isPresented: $showLogoutConfirm) {
            Button("退出登录", role: .destructive) {
                store.clearToken(for: server)
                onLogout()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会同时清除本机保存的登录 token。")
        }
    }

    private var zoomControls: some View {
        HStack {
            Label("页面缩放", systemImage: "plus.magnifyingglass")
            Spacer()
            Button {
                settings.pageZoom = max(0.8, settings.pageZoom - 0.1)
            } label: {
                Image(systemName: "minus.circle")
            }
            Text("\(Int((settings.pageZoom * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            Button {
                settings.pageZoom = min(1.5, settings.pageZoom + 0.1)
            } label: {
                Image(systemName: "plus.circle")
            }
        }
    }

    private var menu: some View {
        Menu {
            Button {
                model.loadHome()
            } label: {
                Label("回到首页", systemImage: "house")
            }
            Button {
                model.reload()
            } label: {
                Label("刷新页面", systemImage: "arrow.clockwise")
            }
            Button {
                shareItems = [server.address]
            } label: {
                Label("分享当前地址", systemImage: "square.and.arrow.up")
            }
            Button {
                if let url = URL(string: server.address) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("在 Safari 中打开", systemImage: "safari")
            }

            Divider()
            Toggle(isOn: $settings.desktopMode) {
                Label("桌面模式", systemImage: "menubar.dock.rectangle")
            }
            zoomControls

            Divider()
            Button {
                onEditServer()
            } label: {
                Label("服务器设置", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 19, weight: .medium))
        }
        .accessibilityLabel("更多操作")
    }

    // MARK: - 覆盖层

    private func overlayCard(title: String,
                             message: String,
                             icon: String,
                             tint: Color,
                             primaryTitle: String,
                             primaryAction: @escaping () -> Void,
                             secondaryTitle: String? = nil,
                             secondaryAction: (() -> Void)? = nil) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundColor(tint)

            Text(title).font(.headline)

            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                primaryAction()
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 8)

            if let secondaryTitle, let secondaryAction {
                Button {
                    secondaryAction()
                } label: {
                    Text(secondaryTitle)
                        .font(.subheadline)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: Color.black.opacity(0.25), radius: 22, y: 10)
        )
        .padding(24)
    }
}
