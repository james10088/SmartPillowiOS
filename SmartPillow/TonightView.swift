import SwiftUI

/// 画板 1「今夜 · 未开始」
struct TonightView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @Binding private var showRecording: Bool
    @State private var showAlarm = false

    init(showRecording: Binding<Bool>) {
        self._showRecording = showRecording
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header.rise(0)
                if let m = assist.message {
                    Text(m)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(18)
                        .transition(.opacity)
                }
                assistStrip.rise(0.08)
                hero.rise(0.16)
                tiles.rise(0.26)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 110)
            .animation(.easeInOut, value: assist.message)
        }
        .background { NightBackground() }
        .onAppear {
            // 截图用：启动参数 -uiScreen alarm 直接打开闹钟设置
            if UserDefaults.standard.string(forKey: "uiScreen") == "alarm" { showAlarm = true }
        }
        .sheet(isPresented: $showAlarm) {
            AlarmSheet()
                .environmentObject(client)
                .environmentObject(assist)
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting).font(.xiaowei(32)).lineSpacing(6).tracking(1)
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(Theme.zh)))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            LinkBadge()
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 5 && h < 11 { return "早上好，\n昨夜睡得怎么样？" }
        if h >= 11 && h < 18 { return "下午好，\n今晚早点休息。" }
        return "晚上好，\n今晚好好睡。"
    }

    // MARK: 助眠音量条

    private var assistStrip: some View {
        NavigationLink(value: Route.assist) {
            HStack(spacing: 12) {
                Icon(kind: .fadeBars, size: 20, color: Theme.lilac)
                    .frame(width: 40, height: 40)
                    .background(Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255).opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("助眠 · \(assist.soundSource.name)").font(.system(size: 14, weight: .medium))
                    Text("\(assist.preset.name)变轻 · \(client.link == .connected ? "枕头在线" : "等待枕头连接")")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(assist.autoStart ? "自动记录" : "手动记录")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(assist.autoStart ? Theme.mint : Theme.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((assist.autoStart ? Theme.mint : Color.white).opacity(0.16), in: Capsule())
            }
            .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, 12)
            .glass(22)
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: 主卡片：明早闹钟

    private var hero: some View {
        HeroCard(padding: 20) {
            ZStack {
                BreathingHalo()
                VStack(spacing: 0) {
                    if let s = assist.session {
                        Text(assist.waking ? "早上好" : "已记录").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            GhostClock(main: formatDuration(ctx.date.timeIntervalSince(s.start)),
                                       above: formatDuration(ctx.date.timeIntervalSince(s.start) - 60),
                                       below: formatDuration(ctx.date.timeIntervalSince(s.start) + 60),
                                       size: 80)
                        }
                        Text(assist.phase.label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).padding(.top, 12)
                        Button { showRecording = true } label: {
                            Label { Text("回到记录页") } icon: { Icon(kind: .moonPlain, size: 18, color: Theme.ink) }
                        }
                        .buttonStyle(PillButtonStyle())
                        .padding(.top, 18)
                    } else if assist.waking {
                        Text("早上好").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            GhostClock(main: hm(ctx.date), above: hm(ctx.date.addingTimeInterval(-60)),
                                       below: hm(ctx.date.addingTimeInterval(60)), size: 84)
                        }
                        Text(assist.phase.label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).padding(.top, 12)
                        Button("我醒了") { assist.stopWake() }
                            .buttonStyle(PillButtonStyle())
                            .padding(.top, 18)
                    } else {
                        Button { showAlarm = true } label: {
                            VStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Image(systemName: assist.alarm.enabled ? "alarm.fill" : "alarm")
                                        .font(.system(size: 12))
                                    Text(assist.alarm.enabled ? "明早闹钟" : "闹钟未开启")
                                }
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                                GhostClock(main: assist.alarm.timeText,
                                           above: assist.alarm.text(minutesBefore: 5),
                                           below: assist.alarm.text(minutesBefore: -5), size: 84)
                                    .opacity(assist.alarm.enabled ? 1 : 0.55)
                                Text(alarmLine).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92))
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 12)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(assist.alarm.enabled ? "明早闹钟 \(assist.alarm.timeText)，点按修改" : "设置起床闹钟")

                        if assist.isLearning {
                            Button { assist.startSession(manual: true) } label: {
                                Label { Text("开始今晚的记录") } icon: { Icon(kind: .moonPlain, size: 18, color: Theme.ink) }
                            }
                            .buttonStyle(PillButtonStyle())
                            .padding(.top, 18)
                            Text("学习期 第 \(assist.sessions.count + 1)/\(AssistEngine.learningNights) 晚 · 睡前点一下，帮枕头熟悉你")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                                .padding(.top, 10)
                        } else {
                            Text(autoLine).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                                .padding(.top, 14)
                            Button("现在开始记录") { assist.startSession(manual: true) }
                                .buttonStyle(GhostButtonStyle(height: 42))
                                .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    private var alarmLine: String {
        let a = assist.alarm
        guard a.enabled else { return "点这里设置起床时间" }
        if a.windowMinutes == 0 { return "到点前 \(a.rampMinutes) 分钟，音乐慢慢变大" }
        return "\(a.text(minutesBefore: a.windowMinutes))–\(a.timeText) 浅睡时轻轻叫醒"
    }

    private var autoLine: String {
        guard assist.autoStart else { return "自动记录已关闭，需要时点下面开始" }
        return assist.standby ? "今晚躺下就会自动记录，不用点 · 待命中" : "今晚躺下就会自动记录，不用点"
    }

    private func hm(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Theme.zh))
    }

    // MARK: 三个数据块

    private var tiles: some View {
        let last = assist.sessions.first
        return HStack(spacing: 10) {
            NavigationLink(value: last.map { Route.report($0.id) } ?? Route.history) {
                StatTile(value: last.map { formatHM($0.inBedSeconds) } ?? "—", label: "昨夜在枕")
            }
            NavigationLink(value: last.map { Route.report($0.id) } ?? Route.history) {
                StatTile(value: last.map { "\(Int(($0.quietRatio * 100).rounded()))%" } ?? "—", label: "安静占比")
            }
            NavigationLink(value: Route.history) {
                StatTile(value: "\(assist.streak)", label: "连续记录晚数", tint: Theme.mint)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

/// 大号 Italiana 数字，上下各一行淡化的“滚轮”数字，轻轻浮动。
struct GhostClock: View {
    private let main: String
    private let above: String
    private let below: String
    private let size: CGFloat
    @State private var float = false

    init(main: String, above: String, below: String, size: CGFloat = 84) {
        self.main = main
        self.above = above
        self.below = below
        self.size = size
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(spaced(above)).font(.italiana(size * 0.4)).opacity(float ? 0.42 : 0.24).offset(y: float ? -3 : 0)
            Text(main).font(.italiana(size)).tracking(2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(spaced(below)).font(.italiana(size * 0.4)).opacity(float ? 0.24 : 0.42).offset(y: float ? 0 : -3)
        }
        .foregroundStyle(.white)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.15).repeatForever(autoreverses: true)) { float = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(main)
    }

    private func spaced(_ s: String) -> String { s.replacingOccurrences(of: ":", with: " : ") }
}

/// 主卡片里按呼吸节奏（约 14 次/分）起伏的光圈和缓慢旋转的虚线环。
struct BreathingHalo: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.2), .clear], center: .center, startRadius: 0, endRadius: 130))
                .frame(width: 252, height: 252)
                .scaleEffect(on ? 1.07 : 1)
                .opacity(on ? 1 : 0.55)
                .animation(.easeInOut(duration: 2.15).repeatForever(autoreverses: true), value: on)
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: 240, height: 240)
                .rotationEffect(.degrees(on ? 360 : 0))
                .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: on)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { on = true } }
    }
}

/// 右上角的连接状态标签。
struct LinkBadge: View {
    @EnvironmentObject private var client: PillowClient

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(16)
    }

    private var color: Color {
        switch client.link {
        case .connected: return Theme.mint
        case .searching: return Theme.amber
        default: return Theme.coral
        }
    }

    private var text: String {
        if client.demo { return "演示模式" }
        switch client.link {
        case .connected: return "枕头在线"
        case .searching: return "正在查找"
        case .idle: return "未连接"
        case .unreachable: return "未连上"
        }
    }
}

func formatHM(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    return "\(m / 60)h\(String(format: "%02d", m % 60))m"
}
