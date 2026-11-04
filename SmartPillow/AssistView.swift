import SwiftUI

/// 画板 5「助眠音量」
struct AssistView: View {
    @EnvironmentObject private var assist: AssistEngine
    @State private var draw = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                BackBar {
                    MintSwitch(isOn: $assist.autoStart, label: "助眠总开关", width: 56, height: 34)
                }
                .rise(0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("助眠音量").font(.xiaowei(32)).tracking(1)
                    Text("你安静下来，音乐就一点点变轻；翻来覆去时，再悄悄调回一些。")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.68)).lineSpacing(4)
                }
                .rise(0.06)

                if !assist.autoStart {
                    Text("已关闭：不会自动开始，也不会自动调节音量")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(20)
                }

                Group {
                    curveCard.rise(0.12)
                    GlassSegmented(options: AssistPreset.allCases.map { ($0, $0.name) }, selection: $assist.preset)
                        .rise(0.22)
                    GlassSegmented(options: SoundEngine.Kind.allCases.map { ($0, $0.name) }, selection: $assist.soundKind,
                                   font: .system(size: 14, weight: .medium), height: 38)
                        .rise(0.26)
                    VStack(spacing: 0) {
                        ListRow(title: "翻来覆去时调回") {
                            Text("≤ \(Int(assist.preset.capLevel * 100))%").font(.italiana(18)).foregroundStyle(.white.opacity(0.75))
                        }
                        RowDivider()
                        ListRow(title: "两次助眠间隔") {
                            Text("\(Int(assist.preset.cooldownMinutes)) 分钟").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                        RowDivider()
                        Button {
                            assist.previewing ? assist.stopPreview() : assist.preview()
                        } label: {
                            ListRow(title: assist.previewing ? "停止试听" : "试听 8 秒") {
                                Image(systemName: assist.previewing ? "stop.fill" : "play.fill").foregroundStyle(Theme.lilac)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(assist.session != nil)
                    }
                    .glass(26)
                    .rise(0.3)
                }
                .opacity(assist.autoStart ? 1 : 0.35)
                .saturation(assist.autoStart ? 1 : 0.2)
                .allowsHitTesting(assist.autoStart)
                .animation(.easeInOut(duration: 0.4), value: assist.autoStart)

                Text("你自己按音量键时，助眠会先停下，不和你抢。想用枕头的喇叭，就在手机蓝牙里连接 MH-M38。")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary).lineSpacing(3)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 40)
        }
        .background { NightBackground() }
        .onAppear { draw = true }
        .onChange(of: assist.preset) { _ in
            draw = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { draw = true }
        }
    }

    private var curveCard: some View {
        let p = assist.preset
        return HeroCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("最低降到").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        Text("\(Int(p.minLevel * 100))%").font(.italiana(68))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text("安静 \(Int(p.quietWaitMinutes)) 分钟后开始")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                VolumeCurve(preset: p, draw: draw)
                    .frame(height: 110)
                HStack {
                    Text("安静开始 · 60%"); Spacer(); Text("一小时后")
                }
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.88))
            }
        }
    }
}

/// 音量变化曲线：线条像笔一样画出来，再有一颗光点沿曲线走一遍。
struct VolumeCurve: View {
    private let preset: AssistPreset
    private let draw: Bool
    @State private var travel: CGFloat = 0

    init(preset: AssistPreset, draw: Bool) {
        self.preset = preset
        self.draw = draw
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let minutes = 60.0
        let step = preset == .gentle ? 2.5 : preset == .standard ? 2 : 1.5
        func x(_ m: Double) -> CGFloat { size.width * m / minutes }
        func y(_ v: Double) -> CGFloat { size.height - size.height * v / 64 }
        var pts = [CGPoint(x: 0, y: y(60)), CGPoint(x: x(preset.quietWaitMinutes), y: y(60))]
        var v = 60.0, t = preset.quietWaitMinutes
        let floor = Double(preset.minLevel * 100)
        while v > floor && t < minutes {
            t += step
            pts.append(CGPoint(x: x(t), y: y(v)))
            v = max(floor, v - 5)
            pts.append(CGPoint(x: x(t), y: y(v)))
        }
        pts.append(CGPoint(x: size.width, y: y(v)))
        return pts
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            let line = Path { p in p.addLines(pts) }
            let area = Path { p in
                p.addLines(pts)
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                p.closeSubpath()
            }
            let waitX = geo.size.width * preset.quietWaitMinutes / 60
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: waitX, y: 0))
                    p.addLine(to: CGPoint(x: waitX, y: geo.size.height))
                }
                .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                area.fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .opacity(draw ? 1 : 0)
                    .animation(.easeOut(duration: 1.2).delay(0.9), value: draw)
                line.trim(from: 0, to: draw ? 1 : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.6).delay(0.3), value: draw)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .white.opacity(0.8), radius: 8)
                    .modifier(FollowPath(t: travel, path: line))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音量从 60% 在安静 \(Int(preset.quietWaitMinutes)) 分钟后逐步降到 \(Int(preset.minLevel * 100))%")
        .task(id: preset) {
            // 光点每 6 秒沿曲线走一遍
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while !Task.isCancelled {
                travel = 0
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.easeInOut(duration: 6)) { travel = 1 }
                try? await Task.sleep(nanoseconds: 6_500_000_000)
            }
        }
    }
}

/// 让视图沿路径移动：t 从 0 到 1 时逐帧计算路径上的位置，而不是直线插值。
struct FollowPath: ViewModifier, Animatable {
    var t: CGFloat
    let path: Path

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        content
            .position(path.trimmedPath(from: 0, to: max(0.001, t)).currentPoint ?? .zero)
            .opacity(t > 0.02 && t < 0.98 ? 1 : 0)
    }
}
