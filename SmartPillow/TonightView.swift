import SwiftUI

/// 画板 1「今夜 · 未开始」
struct TonightView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @Binding private var showRecording: Bool

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
                    Text("助眠音量 · \(assist.preset.name)").font(.system(size: 14, weight: .medium))
                    Text("\(assist.soundKind.name) · \(client.link == .connected ? "枕头在线" : "等待枕头连接")")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(assist.autoStart ? "已开启" : "已关闭")
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

    // MARK: 主卡片

    private var hero: some View {
        HeroCard(padding: 20) {
            ZStack {
                BreathingHalo()
                VStack(spacing: 0) {
                    if let s = assist.session {
                        Text("已记录").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
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
                    } else {
                        Text("现在").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            GhostClock(main: hm(ctx.date), above: hm(ctx.date.addingTimeInterval(-60)),
                                       below: hm(ctx.date.addingTimeInterval(60)), size: 84)
                        }
                        Text(subline).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).padding(.top, 12)
                        Button { assist.startSession(manual: true) } label: {
                            Label { Text("开始今晚的记录") } icon: { Icon(kind: .moonPlain, size: 18, color: Theme.ink) }
                        }
                        .buttonStyle(PillButtonStyle())
                        .padding(.top, 18)
                    }
                }
            }
        }
    }

    private var subline: String {
        if let t = assist.usualBedtime { return "平时 \(t) 左右入睡" }
        if !assist.autoStart { return "自动开始已关闭" }
        return assist.standby ? "待命中 · 锁屏后躺下也会自动开始" : "躺下后会自动开始助眠"
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
