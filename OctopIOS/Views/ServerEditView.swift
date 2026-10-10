import SwiftUI

/// 新增 / 编辑服务器地址。
struct ServerEditView: View {
    @EnvironmentObject private var store: ServerStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let existing: OctopServer?

    @State private var addressText: String = ""
    @State private var nameText: String = ""
    @State private var probing = false
    @State private var probeResult: ProbeResult?
    @State private var autoFilledPort = false

    enum ProbeResult {
        case ok(message: String)
        case failure(String)
    }

    init(server: OctopServer?) {
        existing = server
        _addressText = State(initialValue: server?.address ?? "")
        _nameText = State(initialValue: server?.name ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务器地址"),
                        footer: Text("直连填 http://飞牛IP:8089（Octop 默认端口）；反代域名直接填完整地址即可，例如 https://octop.example.com，带子路径也行（https://example.com/octop）。留空端口时点「测试连接」会自动补上 8089。")) {
                    TextField("http://192.168.8.8:8089 或 https://你的域名", text: $addressText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                }

                Section(header: Text("备注（可选）")) {
                    TextField("例如：飞牛 NAS", text: $nameText)
                }

                Section {
                    Button {
                        Task { await probe() }
                    } label: {
                        HStack {
                            if probing {
                                ProgressView().padding(.trailing, 6)
                            } else {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .padding(.trailing, 6)
                            }
                            Text(probing ? "正在测试…" : "测试连接")
                        }
                    }
                    .disabled(probing || addressText.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let result = probeResult {
                        probeRow(result)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        if let existing { store.remove(existing) }
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("删除这台服务器")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加服务器" : "编辑服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(normalizedAddress() == nil)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: 逻辑

    private func normalizedAddress() -> String? {
        OctopServer.normalize(addressText)
    }

    private func save() {
        guard let address = normalizedAddress() else { return }
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if var server = existing {
            server.address = address
            server.name = name
            store.upsert(server)
        } else {
            let server = OctopServer(name: name, address: address)
            store.upsert(server)
        }
        dismiss()
    }

    /// 探测服务器是否可达，顺便看是否还没初始化管理员。
    private func probe() async {
        guard let address = normalizedAddress() else {
            probeResult = .failure("地址格式不对，例如 http://192.168.8.8:8089 或 https://octop.example.com")
            return
        }

        var target = address
        var api = OctopAPI(baseAddress: target, allowInsecureTLS: settings.allowInsecureTLS)

        // 先按用户填的地址试；连不上且没写端口时，自动补 8088 再试一次
        if let status = try? await api.setupStatus() {
            probeResult = .ok(message: status.setupRequired
                              ? "服务器在线，还没创建管理员，请先在服务端完成初始化"
                              : "服务器在线")
            autoFilledPort = false
            addressText = target
            return
        }

        if let fallback = OctopServer.withDefaultPort(address) {
            target = fallback
            api = OctopAPI(baseAddress: target, allowInsecureTLS: settings.allowInsecureTLS)
            if let status = try? await api.setupStatus() {
                probeResult = .ok(message: "已自动补上 8088 端口，" +
                                  (status.setupRequired ? "服务器还没创建管理员" : "服务器在线"))
                autoFilledPort = true
                addressText = target
                return
            }
        }

        // 两次都没通，给个明确的错误原因
        do {
            _ = try await api.setupStatus()
        } catch {
            probeResult = .failure(error.localizedDescription)
        }
        _ = autoFilledPort
    }

    @ViewBuilder
    private func probeRow(_ result: ProbeResult) -> some View {
        switch result {
        case .ok(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(message).font(.footnote)
            }
        case .failure(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message).font(.footnote)
            }
        }
    }
}
