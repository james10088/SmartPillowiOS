import SwiftUI

/// 画板 6「设备与校准」
struct DeviceView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @State private var speakerOpen = false
    @State private var advancedOpen = false
    @State private var editingHost = ""
    @State private var resetStep = 0
    @State private var resetNote: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("设备").font(.xiaowei(32)).tracking(1).rise(0)
                pillowCard.rise(0.08)
                connectionList.rise(0.18)
                systemList.rise(0.28)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 110)
            .animation(.easeInOut(duration: 0.3), value: speakerOpen)
            .animation(.easeInOut(duration: 0.3), value: advancedOpen)
        }
        .background { NightBackground() }
        .onAppear { editingHost = client.host }
        .onChange(of: client.host) { editingHost = $0 }
    }

    // MARK: 枕头主卡片

    private var pillowCard: some View {
        HeroCard(padding: 20) {
            VStack(spacing: 6) {
                PillowArt().frame(height: 128)
                Text("我的智能枕头").font(.xiaowei(22))
                HStack(spacing: 6) {
                    if client.link == .connected { PulseDot() } else { Circle().fill(Theme.amber).frame(width: 7, height: 7) }
                    Text(linkText).font(.system(size: 13)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.92))
                HStack(spacing: 10) {
                    NavigationLink(value: Route.setup) {
                        Text("更换 Wi-Fi")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(.white.opacity(0.2), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.3)))
                            .foregroundStyle(.white)
                    }
                    NavigationLink(value: Route.calibrate) {
                        Text("重新校准睡姿")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(.white, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
    }

    private var linkText: String {
        if client.demo { return "演示模式 · 模拟数据" }
        switch client.link {
        case .connected: return "在线 · \(client.host)"
        case .searching: return "正在局域网里查找…"
        case .idle: return "未连接"
        case .unreachable: return "未连上 · 展开“高级与诊断”查看原因"
        }
    }

    // MARK: 连接

    private var connectionList: some View {
        VStack(spacing: 0) {
            Button { speakerOpen.toggle() } label: {
                HStack(spacing: 12) {
                    Icon(kind: .fadeBars, size: 18, color: Theme.lilac)
                        .frame(width: 34, height: 34)
                        .background(Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255).opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("助眠音箱 MH-M38").font(.system(size: 15))
                        Text("声音从手机播放，可经蓝牙送到枕头喇叭").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Icon(kind: .chevron, size: 14, color: Theme.tertiary).rotationEffect(.degrees(speakerOpen ? 90 : 0))
                }
                .frame(minHeight: 64).padding(.horizontal, 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(speakerOpen ? "已展开" : "已收起")
            if speakerOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text("在 iPhone 的 设置 → 蓝牙 里连接 MH-M38，助眠声音就会从枕头的喇叭播放。")
                    Text("没连蓝牙时，声音从手机喇叭播放。音量随手机媒体音量变化。")
                }
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.72)).lineSpacing(3)
                .padding(.leading, 62).padding(.trailing, 16).padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            RowDivider(inset: 62)
            HStack(spacing: 12) {
                Icon(kind: .swapPillow, size: 20, color: Theme.mint)
                    .frame(width: 34, height: 34)
                    .background(Theme.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("枕头掉头放了").font(.system(size: 15))
                    Text("左右睡姿显示反了时打开").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                MintSwitch(isOn: $assist.reverseLR, label: "枕头掉头放了")
            }
            .frame(minHeight: 64).padding(.horizontal, 16)
        }
        .glass(26)
    }

    // MARK: 整夜运行 / 高级

    private var systemList: some View {
        VStack(spacing: 0) {
            ListRow(title: "躺下后自动开始") { MintSwitch(isOn: $assist.autoStart, label: "躺下后自动开始") }
            RowDivider()
            ListRow(title: "锁屏后继续工作") {
                Text(assist.standby || assist.session != nil ? "待命中" : "未待命")
                    .font(.system(size: 14))
                    .foregroundStyle(assist.standby || assist.session != nil ? Theme.mint : Theme.secondary)
            }
            RowDivider()
            Button { advancedOpen.toggle() } label: {
                ListRow(title: "高级与诊断") {
                    HStack(spacing: 6) {
                        Text("连接 · 传感器").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        Icon(kind: .chevron, size: 14, color: Theme.tertiary).rotationEffect(.degrees(advancedOpen ? 90 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(advancedOpen ? "已展开" : "已收起")
            if advancedOpen {
                advanced
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glass(26)
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 连接诊断
            VStack(alignment: .leading, spacing: 4) {
                Text("手机 IP：\(client.phoneIP)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                if let err = client.lastError {
                    Text(err).font(.system(size: 12)).foregroundStyle(Theme.amber)
                }
            }
            HStack(spacing: 8) {
                TextField("枕头 IP，例如 192.168.31.47", text: $editingHost)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit {
                        let h = PillowClient.normalizedHost(editingHost)
                        editingHost = h
                        client.host = h
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Color.white.opacity(0.08), in: Capsule())
                Button("自动查找") { Task { await client.discover() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(.white, in: Capsule())
            }

            // 传感器实时读数
            let s = client.status?.sensor
            let items: [(String, Double?)] = [("H1 左", s?.h1Mv), ("H2 中", s?.h2Mv), ("H3 右", s?.h3Mv), ("PVDF Δ", s?.pvdfDeltaMv)]
            Text("传感器实时读数（mV）").font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: 2) {
                        Text(item.1.map { String(format: "%.0f", $0) } ?? "—").font(.italiana(18))
                            .contentTransition(.numericText())
                        Text(item.0).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .animation(.easeOut(duration: 0.3), value: client.lastUpdate)

            HStack {
                Text("演示模式（模拟数据）").font(.system(size: 14))
                Spacer()
                MintSwitch(isOn: $client.demo, label: "演示模式")
            }
            .padding(.top, 4)

            Button {
                if resetStep == 0 {
                    resetStep = 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if resetStep == 1 { resetStep = 0 } }
                } else if resetStep == 1 {
                    Task {
                        let err = await client.command("BEHAVIOR_RESET")
                        resetNote = err
                        resetStep = err == nil ? 2 : 0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { resetStep = 0; resetNote = nil }
                    }
                }
            } label: {
                Text(resetNote ?? ["清零枕头上的本次统计", "再点一次确认清零（不可撤销）", "已清零"][resetStep])
                    .font(.system(size: 14)).foregroundStyle(Theme.coral)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let model = client.status?.modelId {
                Text("睡姿模型 \(model)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
}

/// 设计稿里的立体枕头：渐变、高光、四角褶皱、投影，三个传感点依次亮起。
struct PillowArt: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, 230 * geo.size.height / 128)
            let h = w * 128 / 230
            ZStack {
                // 投影用径向渐变代替 blur：观感一样，但不需要每帧重新模糊
                Ellipse()
                    .fill(RadialGradient(colors: [Color(red: 25 / 255, green: 12 / 255, blue: 70 / 255).opacity(0.6), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.4))
                    .frame(width: w * 0.85, height: h * 0.18)
                    .scaleEffect(on ? 0.88 : 1)
                    .offset(y: h * 0.4)
                ZStack {
                    PuffyPillow()
                        .fill(RadialGradient(colors: [.white, Color(red: 0.93, green: 0.91, blue: 1), Color(red: 0.76, green: 0.70, blue: 0.97),
                                                      Color(red: 0.61, green: 0.53, blue: 0.93)],
                                             center: UnitPoint(x: 0.38, y: 0.28), startRadius: 2, endRadius: w * 0.75))
                    PuffyPillow()
                        .fill(LinearGradient(colors: [.clear, Theme.indigo.opacity(0.38)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom))
                    PuffyPillow().stroke(.white.opacity(0.75), lineWidth: 1)
                    PillowCreases().stroke(Color(red: 90 / 255, green: 64 / 255, blue: 180 / 255).opacity(0.32), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.26))
                        .frame(width: w * 0.52, height: h * 0.18)
                        .offset(x: -w * 0.08, y: -h * 0.2)
                    HStack(spacing: w * 0.065) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(RadialGradient(colors: [.white, Color(red: 180 / 255, green: 156 / 255, blue: 255 / 255).opacity(0.9), Theme.violet.opacity(0)],
                                                     center: .center, startRadius: 0, endRadius: w * 0.065))
                                .frame(width: w * 0.13, height: w * 0.13)
                                .scaleEffect(on ? 1.1 : 0.75)
                                .opacity(on ? 1 : 0.35)
                                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(Double(i) * 0.4), value: on)
                        }
                    }
                    .offset(y: h * 0.06)
                }
                .frame(width: w, height: h)
                .offset(y: on ? -6 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: on)
        }
        .onAppear { if !reduceMotion { on = true } }
        .accessibilityHidden(true)
    }
}

/// 蓬松枕头轮廓（原始坐标 230×128）。
struct PuffyPillow: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 230, sy = r.height / 128
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(28, 32))
        path.addCurve(to: p(202, 32), control1: p(72, 14), control2: p(158, 14))
        path.addCurve(to: p(202, 100), control1: p(215, 54), control2: p(215, 80))
        path.addCurve(to: p(28, 100), control1: p(158, 116), control2: p(72, 116))
        path.addCurve(to: p(28, 32), control1: p(15, 80), control2: p(15, 54))
        path.closeSubpath()
        return path
    }
}

/// 四个角的褶皱线。
struct PillowCreases: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 230, sy = r.height / 128
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(28, 32)); path.addQuadCurve(to: p(40, 49), control: p(36, 38))
        path.move(to: p(202, 32)); path.addQuadCurve(to: p(190, 49), control: p(194, 38))
        path.move(to: p(28, 100)); path.addQuadCurve(to: p(40, 83), control: p(36, 94))
        path.move(to: p(202, 100)); path.addQuadCurve(to: p(190, 83), control: p(194, 94))
        return path
    }
}
