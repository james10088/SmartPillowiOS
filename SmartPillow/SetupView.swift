import SwiftUI

/// 画板 4「Wi-Fi 配网向导」：手机先在设置里连上 SmartPillow- 开头的热点（密码 pillow123456）。
struct SetupView: View {
    @EnvironmentObject private var client: PillowClient
    @State private var ssid = UserDefaults.standard.string(forKey: "lastSSID") ?? ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var phase: Phase = .idle
    @State private var note = ""
    @State private var onHotspot = false

    enum Phase { case idle, sending, done, failed }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                BackBar {
                    HStack(spacing: 4) {
                        Text(phase == .done ? "3" : "2").font(.italiana(17))
                        Text("/").font(.system(size: 12))
                        Text("3").font(.italiana(17))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 12).frame(height: 32)
                    .glass(16)
                }
                .rise(0)

                VStack(spacing: 8) {
                    RippleIcon().padding(.top, 26)
                    Text("告诉枕头家里的 Wi-Fi").font(.xiaowei(30)).tracking(1).padding(.top, 18)
                    HStack(spacing: 6) {
                        if onHotspot {
                            Icon(kind: .check, size: 14, color: Theme.mint)
                            Text("已连上枕头热点").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        } else {
                            Text("先在 设置 → Wi-Fi 连接 SmartPillow- 开头的热点，密码 pillow123456")
                                .font(.system(size: 13)).foregroundStyle(Theme.amber)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .rise(0.08)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("网络").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).frame(width: 56, alignment: .leading)
                        TextField("例如 2701主卧（不要选 5G）", text: $ssid)
                            .font(.system(size: 16))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .frame(minHeight: 60).padding(.horizontal, 16)
                    RowDivider()
                    HStack(spacing: 12) {
                        Text("密码").font(.system(size: 15)).foregroundStyle(.white.opacity(0.7)).frame(width: 56, alignment: .leading)
                        Group {
                            if showPassword { TextField("没有密码就留空", text: $password) }
                            else { SecureField("没有密码就留空", text: $password) }
                        }
                        .font(.system(size: 16))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button { showPassword.toggle() } label: {
                            Icon(kind: .eye, size: 22, color: .white.opacity(0.75)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
                    }
                    .frame(minHeight: 60).padding(.leading, 16).padding(.trailing, 4)
                }
                .glass(26)
                .padding(.top, 30)
                .rise(0.18)

                Text("枕头只认 2.4GHz 网络。名字里带“5G”的，请换另一个。")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12).padding(.horizontal, 4)

                Spacer(minLength: 40)
                actionArea.rise(0.3)
                if !note.isEmpty {
                    Text(note).font(.system(size: 12))
                        .foregroundStyle(phase == .failed ? Theme.amber : Theme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 30)
        }
        .background { NightBackground() }
        .task {
            while !Task.isCancelled {
                onHotspot = Network.localIPv4()?.hasPrefix("192.168.4.") == true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @ViewBuilder private var actionArea: some View {
        switch phase {
        case .idle, .failed:
            Button("发送给枕头") { Task { await send() } }
                .buttonStyle(PillButtonStyle(height: 56))
        case .sending:
            SendingBar(ssid: ssid)
        case .done:
            HStack(spacing: 8) {
                Icon(kind: .check, size: 20, color: Color(red: 0.05, green: 0.17, blue: 0.13))
                Text("已连上！切回家里 Wi-Fi，回到设备")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(red: 0.05, green: 0.17, blue: 0.13))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.mint, in: Capsule())
            .transition(.scale(scale: 0.92).combined(with: .opacity))
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
        withAnimation { phase = .sending }
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { phase = .done }
                    note = reply.ip.isEmpty ? "切回家里 Wi-Fi 后，App 会自动找到枕头。" : "枕头地址 \(reply.ip)"
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
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        withAnimation { phase = .done }
        note = "没等到最终结果，但枕头多半已经连上：切回家里 Wi-Fi，App 会自动查找。"
    }
}

/// 紫色圆形图标：枕头上方的 Wi-Fi 波纹逐层亮起，外圈涟漪扩散。
struct RippleIcon: View {
    @State private var on = false
    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle().stroke(Theme.lilac.opacity(0.7), lineWidth: 1.5)
                    .scaleEffect(on ? 1.6 : 0.6)
                    .opacity(on ? 0 : 0.7)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 1.2), value: on)
            }
            Circle()
                .fill(LinearGradient(colors: [Theme.lavender, Theme.violet, Theme.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                .shadow(color: Theme.violet.opacity(0.8), radius: 14, y: 10)
            Icon(kind: .wifiPillow, size: 44, color: .white)
                .opacity(on ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
        }
        .frame(width: 96, height: 96)
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

/// 发送中：进度条加旋转的三点。
struct SendingBar: View {
    private let ssid: String
    @State private var progress: CGFloat = 0
    @State private var spin = false

    init(ssid: String) { self.ssid = ssid }

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.2), Theme.lilac.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * progress)
            }
            HStack(spacing: 10) {
                Icon(kind: .reconnect, size: 20).rotationEffect(.degrees(spin ? 360 : 0))
                Text("枕头正在连接 \(ssid)…").font(.system(size: 15))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
        .background(Color.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 30)) { progress = 1 }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}
