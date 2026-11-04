import SwiftUI

/// 画板 2「记录中」和画板 10「记录中 · 连接中断」
struct RecordingView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @Environment(\.dismiss) private var dismiss
    @State private var dim = false

    private var disconnected: Bool {
        if case .unreachable = client.link { return true }
        return false
    }

    var body: some View {
        ZStack {
            if disconnected {
                ReconnectContent(onEnd: { assist.endSession() })
            } else {
                content
            }
            if dim {
                DimOverlay { withAnimation(.easeInOut(duration: 0.5)) { dim = false } }
                    .transition(.opacity)
            }
        }
        .background { NightBackground(deep: true) }
        .animation(.easeInOut(duration: 0.4), value: disconnected)
        .statusBarHidden(dim)
    }

    private var content: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                GlassCircle(label: "收起", action: { dismiss() }) {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
                }
                HStack(spacing: 8) {
                    PulseDot()
                    Text("记录中 · 可以熄屏").font(.system(size: 13))
                }
                .padding(.horizontal, 14).frame(height: 34)
                .glass(17)
                Spacer()
                GlassCircle(label: "进入暗屏模式", action: { withAnimation(.easeInOut(duration: 0.6)) { dim = true } }) {
                    Icon(kind: .eclipse, size: 20, color: Theme.pale)
                }
            }
            .rise(0)

            HeroCard(padding: 22) {
                VStack(spacing: 0) {
                    Text("已记录").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let elapsed = assist.session.map { ctx.date.timeIntervalSince($0.start) } ?? 0
                        GhostClock(main: formatDuration(elapsed), above: formatDuration(elapsed - 60),
                                   below: formatDuration(elapsed + 60), size: 92)
                    }
                    Text(startLine).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).padding(.top, 10)
                }
            }
            .padding(.top, 6)
            .rise(0.1)

            statusCard.rise(0.2)
            tiles.rise(0.3)
            Spacer(minLength: 10)
            SlideToEnd { assist.endSession() }.rise(0.4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 24)
    }

    private var startLine: String {
        guard let s = assist.session else { return "" }
        let t = s.start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Theme.zh))
        return "\(t) 开始 · \(assist.phase.label)"
    }

    private var statusCard: some View {
        let s = client.status
        let act = s.map { Activity($0) } ?? .unknown
        let pose = Pose(raw: s?.posture?.pose, reversed: assist.reverseLR)
        let rate = s?.respiration?.rateBpm
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(s == nil ? "等待枕头数据" : (act == .away ? act.label : "\(act.label) · \(pose.label)"))
                    .font(.xiaowei(20))
                Spacer()
                Text(rate.map { "约 \(Int($0.rounded())) 次/分" } ?? "呼吸积累中")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            BreathWave(active: act != .away && s != nil)
                .frame(height: 40)
        }
        .padding(16)
        .glass(26)
    }

    private var tiles: some View {
        let ss = assist.session
        return HStack(spacing: 10) {
            StatTile(value: ss.map { "\(Int(($0.quietRatio * 100).rounded()))%" } ?? "—", label: "安静")
            StatTile(value: "\(ss?.turns ?? 0)", label: "翻身")
            StatTile(value: "\(assist.levelPercent)%", label: assist.phase == .fading ? "音量渐弱中" : "助眠音量")
        }
    }
}

/// 绿色记录点：向外扩散的脉冲。
struct PulseDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Theme.mint).frame(width: 7, height: 7)
            .background(
                Circle().stroke(Theme.mint.opacity(on ? 0 : 0.7), lineWidth: 2)
                    .scaleEffect(on ? 3 : 1)
            )
            .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true } }
            .accessibilityHidden(true)
    }
}

/// 持续流动的呼吸波形，两端淡出。
struct BreathWave: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let shift = CGFloat((t.truncatingRemainder(dividingBy: 4.3)) / 4.3) * 100
                var p = Path()
                let mid = size.height / 2
                var x: CGFloat = -100
                p.move(to: CGPoint(x: x - shift, y: mid))
                while x < size.width + 100 {
                    p.addQuadCurve(to: CGPoint(x: x + 50 - shift, y: mid), control: CGPoint(x: x + 25 - shift, y: mid - (active ? 16 : 2)))
                    p.addQuadCurve(to: CGPoint(x: x + 100 - shift, y: mid), control: CGPoint(x: x + 75 - shift, y: mid + (active ? 16 : 2)))
                    x += 100
                }
                g.stroke(p, with: .color(Theme.lilac), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                     .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .accessibilityLabel(active ? "呼吸波形" : "暂无呼吸信号")
    }
}

/// 滑动结束：按住月亮向右滑过 85% 才结束；轻点只提示，防止夜里误触。
struct SlideToEnd: View {
    private let onEnd: () -> Void
    @State private var dx: CGFloat = 0
    @State private var dragging = false
    @State private var done = false
    @State private var hint = false
    @State private var nudge = false

    init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

    var body: some View {
        GeometryReader { geo in
            let maxX = max(1, geo.size.width - 66)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.15), Theme.lilac.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: dx + 60)
                ShimmerText(text: hint ? "按住月亮，向右滑到底" : "滑动结束记录，早上见")
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 66).padding(.trailing, 12)
                    .opacity(done ? 0 : Double(max(0, 1 - dx / 180)))
                Icon(kind: .moonPlain, size: 22, color: Theme.ink)
                    .frame(width: 54, height: 54)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.5), radius: 9, y: 4)
                    .padding(.leading, 6)
                    .offset(x: dx + (nudge && dx == 0 && !dragging ? 18 : 0))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard !done else { return }
                                dragging = true
                                dx = min(maxX, max(0, v.translation.width))
                            }
                            .onEnded { v in
                                dragging = false
                                if dx > maxX * 0.85 {
                                    withAnimation(.easeOut(duration: 0.2)) { dx = maxX; done = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onEnd() }
                                } else {
                                    if abs(v.translation.width) < 4 { showHint() }
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dx = 0 }
                                }
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("滑动结束记录")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onEnd() }
            }
        }
        .frame(height: 66)
        .background(Color.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
        .clipShape(Capsule())
        .task {
            // 每 3 秒把月亮往右轻推一下，提示“可以滑”
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                guard !dragging, !done else { continue }
                withAnimation(.easeOut(duration: 0.3)) { nudge = true }
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { nudge = false }
            }
        }
    }

    private func showHint() {
        hint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { hint = false }
    }
}

/// 一道流光扫过的文字。
struct ShimmerText: View {
    private let text: String
    @State private var phase: CGFloat = -1

    init(text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.5))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width)
                }
                .mask(Text(text).font(.system(size: 15)))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .onAppear { withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) { phase = 1.5 } }
    }
}

/// 暗屏：几乎全黑，只留暗淡的时长，轻触恢复。
struct DimOverlay: View {
    private let onWake: () -> Void
    @EnvironmentObject private var assist: AssistEngine

    init(onWake: @escaping () -> Void) { self.onWake = onWake }

    var body: some View {
        Button(action: onWake) {
            ZStack {
                Color.black.opacity(0.94).ignoresSafeArea()
                VStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Text(formatDuration(assist.session.map { ctx.date.timeIntervalSince($0.start) } ?? 0))
                            .font(.italiana(64)).foregroundStyle(Theme.lilac.opacity(0.35))
                    }
                    Text("暗屏中，记录照常进行 · 轻触恢复").font(.system(size: 12)).foregroundStyle(Theme.tertiary.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("轻触恢复亮度")
    }
}

/// 画板 10：枕头断开时的状态。
struct ReconnectContent: View {
    private let onEnd: () -> Void
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @State private var spin = false
    @State private var glow = false

    init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Icon(kind: .reconnect, size: 24, color: Theme.amber)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    Text("枕头暂时断开，正在重连").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 251 / 255, green: 227 / 255, blue: 190 / 255))
                    Text(client.lastError ?? "每几秒自动再试一次").font(.system(size: 12))
                        .foregroundStyle(Color(red: 251 / 255, green: 227 / 255, blue: 190 / 255).opacity(0.78))
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.amber.opacity(0.35)))
            .shadow(color: Theme.amber.opacity(glow ? 0.3 : 0), radius: 14)
            .rise(0)

            HeroCard(padding: 22, dimmed: true) {
                VStack(spacing: 6) {
                    Text("已记录 · 暂停计时").font(.system(size: 13)).foregroundStyle(.white.opacity(0.82))
                    Text(formatDuration(assist.session.map { Date().timeIntervalSince($0.start) } ?? 0))
                        .font(.italiana(92)).tracking(2)
                        .opacity(glow ? 0.45 : 0.75)
                    Text("之前的数据都已保存，连上后自动接着记").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .rise(0.1)

            VStack(alignment: .leading, spacing: 0) {
                Text("可以先看看这几项").font(.xiaowei(17)).foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
                checkRow(done: Network.localIPv4() != nil, "手机连着家里的 Wi-Fi（\(client.phoneIP)）")
                RowDivider(inset: 50)
                checkRow(done: false, "枕头电源灯是否亮着")
                RowDivider(inset: 50)
                checkRow(done: false, "手机的 VPN / 代理是否已关闭")
                    .padding(.bottom, 6)
            }
            .glass(26)
            .rise(0.2)

            Spacer(minLength: 10)
            Button("立即重试") { Task { await client.discover() } }
                .buttonStyle(PillButtonStyle(height: 56))
            Button("结束并保存已记录的部分", action: onEnd)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.78))
                .frame(height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private func checkRow(done: Bool, _ text: String) -> some View {
        HStack(spacing: 12) {
            if done {
                Icon(kind: .check, size: 22, color: Theme.mint)
            } else {
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                    .foregroundStyle(Theme.tertiary.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .padding(1)
            }
            Text(text).font(.system(size: 15))
            Spacer()
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }
}
