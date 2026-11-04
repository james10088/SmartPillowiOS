import SwiftUI

/// 热点配网：手机先在“设置 → Wi-Fi”里连上 SmartPillow- 开头的热点（密码 pillow123456），再回到这里发送。
struct SetupView: View {
    @EnvironmentObject private var client: PillowClient
    @State private var ssid = UserDefaults.standard.string(forKey: "lastSSID") ?? ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var phase: Phase = .idle
    @State private var note = ""

    enum Phase { case idle, sending, done, failed }

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("告诉枕头家里的 Wi-Fi").font(.display(28))

                    VStack(alignment: .leading, spacing: 8) {
                        step("1", "打开手机“设置 → Wi-Fi”，连接 SmartPillow- 开头的热点，密码 pillow123456。提示“无互联网连接”时选择继续使用。")
                        step("2", "回到这里，填写家里 2.4G Wi-Fi 的名称和密码，点发送。")
                        step("3", "看到“已连上”后，手机切回家里的 Wi-Fi。")
                    }
                    .padding(16)
                    .glass(24)

                    VStack(spacing: 0) {
                        HStack {
                            Text("网络").foregroundStyle(Theme.secondary).frame(width: 52, alignment: .leading)
                            TextField("例如 2701主卧（不要选 5G）", text: $ssid)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        .frame(minHeight: 54)
                        Divider().overlay(.white.opacity(0.1))
                        HStack {
                            Text("密码").foregroundStyle(Theme.secondary).frame(width: 52, alignment: .leading)
                            Group {
                                if showPassword { TextField("没有密码就留空", text: $password) }
                                else { SecureField("没有密码就留空", text: $password) }
                            }
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button { showPassword.toggle() } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.secondary)
                            }
                            .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
                        }
                        .frame(minHeight: 54)
                    }
                    .padding(.horizontal, 16)
                    .glass(24)

                    switch phase {
                    case .idle, .failed:
                        Button("发送给枕头") { Task { await send() } }
                            .buttonStyle(PillButtonStyle())
                    case .sending:
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("枕头正在连接 \(ssid)…")
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .glass(27)
                    case .done:
                        Label("已连上！把手机切回 \(ssid)", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.05, green: 0.17, blue: 0.13))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.mint, in: Capsule())
                    }

                    if !note.isEmpty {
                        Text(note).font(.footnote).foregroundStyle(phase == .failed ? Theme.amber : Theme.secondary)
                    }
                    Text("枕头只支持 2.4GHz 网络。").font(.caption).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 30)
            }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.numeral(20)).frame(width: 18)
            Text(text).font(.footnote).foregroundStyle(.white.opacity(0.85))
        }
    }

    private func validate() -> String? {
        let name = ssid.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "请输入 Wi-Fi 名称" }
        if name.utf8.count > 32 { return "Wi-Fi 名称不能超过 32 字节（中文占多个字节）" }
        if !password.isEmpty && !(8...63).contains(password.count) { return "密码需为 8～63 位；开放网络请留空" }
        if password.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) { return "密码请使用英文、数字或符号" }
        return nil
    }

    private func send() async {
        if let err = validate() { note = err; phase = .failed; return }
        let name = ssid.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(name, forKey: "lastSSID")
        phase = .sending
        note = ""
        let requestId = UUID().uuidString.lowercased()
        let deadline = Date().addingTimeInterval(60)
        var sentOnce = false
        while Date() < deadline {
            do {
                let reply = try await client.sendWiFi(ssid: name, password: password, requestId: requestId)
                sentOnce = true
                switch reply.state {
                case "CONNECTED":
                    phase = .done
                    note = reply.ip.isEmpty ? "切回家里 Wi-Fi 后，到设备页点“自动查找”。" : "枕头地址 \(reply.ip)"
                    if !reply.ip.isEmpty { client.host = reply.ip }
                    return
                case "FAILED", "SAVE_FAILED":
                    phase = .failed
                    note = reply.error.isEmpty ? "配网失败，请检查密码后重试" : reply.error
                    return
                default:
                    break
                }
            } catch let e as PillowClient.SetupError {
                phase = .failed
                note = e.localizedDescription
                return
            } catch {
                if !sentOnce {
                    phase = .failed
                    note = "连不上枕头热点：请先在手机设置里连接 SmartPillow- 开头的热点"
                    return
                }
                // 枕头切换信道时热点会短暂断开，继续等
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        phase = .done
        note = "没等到最终结果，但枕头可能已经连上了：切回家里 Wi-Fi，到设备页点“自动查找”。"
    }
}
