import SwiftUI

/// 原生登录页：直接调 Octop 的 /api/auth/login。
struct LoginView: View {
    let server: OctopServer
    var onSuccess: (String) -> Void

    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings

    private enum Field { case username, password }
    @FocusState private var focused: Field?

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var remember: Bool = true
    @State private var busy: Bool = false
    @State private var errorText: String?
    @State private var notice: String?
    @State private var showWebLogin: Bool = false
    @State private var probed: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                VStack(spacing: 18) {
                    if let notice { noticeCard(notice) }

                    VStack(spacing: 0) {
                        fieldRow(icon: "person.fill",
                                 placeholder: "用户名或邮箱",
                                 text: $username,
                                 secure: false) {
                            focused = .password
                        }
                        .focused($focused, equals: .username)

                        Divider().padding(.leading, 46)

                        fieldRow(icon: "lock.fill",
                                 placeholder: "密码",
                                 text: $password,
                                 secure: true) {
                            Task { await submit() }
                        }
                        .focused($focused, equals: .password)
                    }
                    .cardStyle()

                    Toggle(isOn: $remember) {
                        Text("记住用户名")
                            .font(.subheadline)
                    }
                    .tint(.accentColor)

                    if let errorText {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorText)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.10)))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if busy {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 8)
                            }
                            Text(busy ? "登录中…" : "登录")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
                    .disabled(!canSubmit)

                    Button {
                        showWebLogin = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "safari")
                            Text("用网页方式登录")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 2)

                    Text("如果服务端开了滑动验证码、LDAP 或 OIDC 单点登录，请用网页方式登录。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 32)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if username.isEmpty { username = server.username }
            if !probed {
                probed = true
                Task { await probe() }
            }
        }
        .sheet(isPresented: $showWebLogin) {
            WebLoginSheet(server: server) { token in
                store.saveToken(token, for: server)
                if remember { store.rememberUsername(username, for: server) }
                Haptics.success()
                onSuccess(token)
            }
        }
    }

    // MARK: 视图片段

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.29),
                                                  Color(red: 0.43, green: 0.16, blue: 0.85)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)

                Circle()
                    .stroke(Color.white, lineWidth: 5)
                    .frame(width: 34, height: 34)
            }

            VStack(spacing: 4) {
                Text(server.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(server.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text(text)
                .font(.footnote)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.blue.opacity(0.10)))
    }

    private var canSubmit: Bool {
        !busy && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    // MARK: 逻辑

    private func probe() async {
        let api = OctopAPI(baseAddress: server.address, allowInsecureTLS: settings.allowInsecureTLS)
        do {
            let status = try await api.setupStatus()
            if status.setupRequired {
                notice = "这台 Octop 还没创建管理员账号，请先在服务端完成初始化。"
                return
            }
            let captcha = try? await api.captchaConfig()
            if let captcha, captcha.isEnabled {
                notice = "服务端已开启登录验证码，原生登录用不了，请点下方「用网页方式登录」。"
            }
        } catch {
            // 探测失败不阻塞登录，用户点登录时还能看到具体错误
        }
    }

    private func submit() async {
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !password.isEmpty, !busy else { return }

        busy = true
        errorText = nil
        focused = nil
        defer { busy = false }

        let api = OctopAPI(baseAddress: server.address, allowInsecureTLS: settings.allowInsecureTLS)
        do {
            let response = try await api.login(username: user, password: password)
            store.saveToken(response.accessToken, for: server)
            if remember {
                store.rememberUsername(user, for: server)
            }
            Haptics.success()
            onSuccess(response.accessToken)
        } catch {
            Haptics.warning()
            errorText = error.localizedDescription
        }
    }

    // MARK: 输入行

    @ViewBuilder
    private func fieldRow(icon: String,
                          placeholder: String,
                          text: Binding<String>,
                          secure: Bool,
                          onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundColor(.secondary)

            if secure {
                SecureField(placeholder, text: text)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(onSubmit)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .submitLabel(.next)
                    .onSubmit(onSubmit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
