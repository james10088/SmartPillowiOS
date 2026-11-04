import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @State private var editingHost = ""
    @State private var resetNote: String?

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("设备").font(.display(30))
                        pillowCard
                        assistCard
                        sensorsCard
                        moreCard
                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { editingHost = client.host }
        .onChange(of: client.host) { editingHost = $0 }
    }

    // MARK: 枕头连接

    private var pillowCard: some View {
        HeroCard {
            VStack(spacing: 10) {
                PillowArt().frame(height: 110)
                Text("我的智能枕头").font(.display(22))
                HStack(spacing: 6) {
                    Circle().fill(client.link == .connected ? Theme.mint : Theme.amber).frame(width: 7, height: 7)
                    Text(linkText).font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.92))
                VStack(spacing: 2) {
                    Text("手机 IP：\(client.phoneIP)")
                    if let err = client.lastError { Text(err).multilineTextAlignment(.center) }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 8) {
                    TextField("枕头 IP，例如 192.168.31.47", text: $editingHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(.white.opacity(0.18), in: Capsule())
                        .submitLabel(.go)
                        .onSubmit {
                            let h = PillowClient.normalizedHost(editingHost)
                            editingHost = h
                            client.host = h
                        }
                    Button("自动查找") {
                        Task {
                            await client.discover()
                            editingHost = client.host
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(.white, in: Capsule())
                }
                .padding(.top, 6)
            }
        }
    }

    private var linkText: String {
        switch client.link {
        case .connected: return "在线 · \(client.host)"
        case .searching: return "正在局域网里查找…"
        case .idle: return "未连接"
        case .unreachable(let why): return why
        }
    }

    // MARK: 助眠设置

    private var assistCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("助眠").font(.display(18))
            Picker("强度", selection: $assist.preset) {
                ForEach(AssistPreset.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(assist.preset.summary).font(.footnote).foregroundStyle(Theme.secondary)

            Picker("声音", selection: $assist.soundKind) {
                ForEach(SoundEngine.Kind.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("躺下后自动开始", isOn: $assist.autoStart).tint(Theme.mint)

            Button {
                assist.previewing ? assist.stopPreview() : assist.preview()
            } label: {
                Label(assist.previewing ? "停止试听" : "试听 8 秒", systemImage: assist.previewing ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(assist.session != nil)
            .glass(22)

            Text("声音从手机播放。想用枕头的喇叭，就在手机蓝牙里连接 MH-M38。")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .padding(18)
        .glass(28)
    }

    // MARK: 传感器

    private var sensorsCard: some View {
        let s = client.status?.sensor
        let items: [(String, Double?)] = [("H1", s?.h1Mv), ("H2", s?.h2Mv), ("H3", s?.h3Mv), ("PVDF Δ", s?.pvdfDeltaMv)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("传感器实时读数").font(.display(18))
                Spacer()
                Text("mV").font(.caption).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 6) {
                        Text(item.1.map { String(format: "%.0f", $0) } ?? "—")
                            .font(.numeral(22)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(item.0).font(.caption2).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .animation(.easeOut(duration: 0.3), value: client.lastUpdate)
            if let model = client.status?.modelId {
                Text("睡姿模型 \(model)").font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(18)
        .glass(28)
    }

    // MARK: 更多

    private var moreCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $assist.reverseLR) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("枕头掉头放了")
                    Text("左右睡姿显示反了时打开").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            .tint(Theme.mint)
            .padding(.vertical, 12)
            Divider().overlay(.white.opacity(0.1))
            NavigationLink {
                SetupView()
            } label: {
                HStack {
                    Text("给枕头配 Wi-Fi")
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            Divider().overlay(.white.opacity(0.1))
            Button {
                Task {
                    let err = await client.command("BEHAVIOR_RESET")
                    resetNote = err ?? "已清零枕头上的本次统计"
                }
            } label: {
                HStack {
                    Text("清零枕头上的本次统计").foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.62))
                    Spacer()
                    if let resetNote { Text(resetNote).font(.caption).foregroundStyle(Theme.secondary) }
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .glass(28)
    }
}

/// 立体的枕头插画，三个传感点依次呼吸亮起。
struct PillowArt: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Theme.indigo.opacity(0.6))
                .frame(width: 170, height: 12)
                .blur(radius: 6)
                .offset(y: 50)
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(RadialGradient(colors: [.white, Color(red: 0.93, green: 0.91, blue: 1), Color(red: 0.76, green: 0.70, blue: 0.97)],
                                         center: UnitPoint(x: 0.38, y: 0.25), startRadius: 4, endRadius: 140))
                    .frame(width: 190, height: 84)
                    .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(.white.opacity(0.7)))
                Ellipse().fill(.white.opacity(0.8)).frame(width: 100, height: 14).blur(radius: 4).offset(x: -18, y: -24)
                HStack(spacing: 34) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(RadialGradient(colors: [.white, Theme.accent.opacity(0.8), .clear], center: .center, startRadius: 0, endRadius: 14))
                            .frame(width: 28, height: 28)
                            .scaleEffect(pulse ? 1.1 : 0.75)
                            .opacity(pulse ? 1 : 0.4)
                            .animation(.easeInOut(duration: 1.2).repeatForever().delay(Double(i) * 0.4), value: pulse)
                    }
                }
                .offset(y: 8)
            }
            .offset(y: pulse ? -4 : 2)
            .animation(.easeInOut(duration: 2.5).repeatForever(), value: pulse)
        }
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}
