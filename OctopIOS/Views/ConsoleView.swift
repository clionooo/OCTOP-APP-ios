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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
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

    // MARK: 底部工具条

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                barButton("chevron.backward", enabled: model.canGoBack) { model.goBack() }
                barButton("chevron.forward", enabled: model.canGoForward) { model.goForward() }
                barButton("arrow.clockwise", enabled: !model.isLoading) { model.reload() }
                barButton("house", enabled: true) { model.loadHome() }
                Menu {
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
                        .font(.system(size: 21, weight: .regular))
                        .frame(width: 52, height: 42)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel("更多操作")
            }
            .padding(.vertical, 4)
            .background(Color(uiColor: .systemBackground))
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
            Toggle(isOn: $settings.desktopMode) {
                Label("桌面模式", systemImage: "menubar.dock.rectangle")
            }
            Button {
                model.loadHome()
            } label: {
                Label("回到首页", systemImage: "house")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func barButton(_ icon: String,
                           enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .regular))
                .frame(width: 52, height: 42)
        }
        .foregroundColor(enabled ? .accentColor : Color(uiColor: .tertiaryLabel))
        .disabled(!enabled)
        .accessibilityLabel(icon)
    }

    // MARK: 覆盖层

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
