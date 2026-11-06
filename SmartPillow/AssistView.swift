import SwiftUI
import UniformTypeIdentifiers

/// 画板 5「助眠」：起始音量、渐弱速度、助眠声音（内置音景 / 我的音频 / 外部 App）。
struct AssistView: View {
    @EnvironmentObject private var assist: AssistEngine
    @State private var draw = false
    @State private var importing = false

    private var external: Bool {
        if case .external = assist.soundSource { return true }
        return false
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                BackBar {
                    MintSwitch(isOn: $assist.autoStart, label: "躺下自动记录", width: 56, height: 34)
                }
                .rise(0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("助眠").font(.xiaowei(32)).tracking(1)
                    Text("你安静下来，声音就慢慢变轻；睡着后完全停下。翻来覆去时，再悄悄调回一些。")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.68)).lineSpacing(4)
                }
                .rise(0.06)

                if !assist.autoStart {
                    Text("躺下自动记录已关闭：睡前需要在首页手动开始")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(20)
                }

                curveCard.rise(0.12)
                levelCard.rise(0.18)

                VStack(alignment: .leading, spacing: 8) {
                    Text("变轻的速度").font(.xiaowei(20))
                    GlassSegmented(options: AssistPreset.allCases.map { ($0, $0.name) }, selection: $assist.preset)
                    Text(assist.preset.summary).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .rise(0.22)

                sourceSection.rise(0.26)

                VStack(spacing: 0) {
                    ListRow(title: "翻来覆去时调回") {
                        Text(external ? "原音量的 \(Int(assist.preset.capRatio * 100))%" : "≤ \(Int(assist.capLevel * 100))%")
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.75))
                    }
                    RowDivider()
                    ListRow(title: "两次助眠间隔") {
                        Text("\(Int(assist.preset.cooldownMinutes)) 分钟").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    }
                }
                .glass(26)
                .rise(0.3)

                Text("想用枕头里的喇叭，在手机蓝牙里连接 MH-M38 就行。")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary).lineSpacing(3)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 40)
        }
        .background { NightBackground() }
        .overlay(alignment: .bottom) { FlashBanner(text: assist.message) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mpeg4Movie, .movie], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { assist.importSound(from: url) }
        }
        .onAppear { draw = true }
        .onDisappear { assist.stopPreview() }
        .onChange(of: assist.preset) { _ in redraw() }
        .onChange(of: assist.startLevel) { _ in redraw() }
    }

    private func redraw() {
        draw = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { draw = true }
    }

    // MARK: 曲线

    private var curveCard: some View {
        let p = assist.preset
        let start: Float = external ? 1 : assist.startLevel
        return HeroCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(external ? "从你当时的手机音量开始" : "起始音量").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        Text("\(Int((start * 100).rounded()))%").font(.italiana(68))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text("最低降到 \(Int((start * p.floorRatio * 100).rounded()))%")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                VolumeCurve(start: start, preset: p, draw: draw)
                    .frame(height: 110)
                HStack {
                    Text("躺下"); Spacer(); Text("安静 \(Int(p.quietWaitMinutes)) 分钟"); Spacer(); Text("睡着后停止")
                }
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    // MARK: 起始音量

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if external {
                Text("外部 App 的声音从你开始时的手机音量算起，安静后慢慢调小手机音量；睡着后让它暂停，再把手机音量还原。")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
            } else {
                HStack {
                    Text("起始音量").font(.system(size: 15))
                    Spacer()
                    Text("\(Int((assist.startLevel * 100).rounded()))%").font(.italiana(22))
                }
                Slider(value: Binding(get: { Double(assist.startLevel) }, set: { assist.startLevel = Float($0) }),
                       in: 0.1...1, step: 0.05)
                    .tint(Theme.lilac)
                    .accessibilityLabel("起始音量")
                Text("实际响度还和手机音量有关。睡前试听一下，调到“刚好听得清”就好。")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Button {
                    assist.previewing ? assist.stopPreview() : assist.preview()
                } label: {
                    Label(assist.previewing ? "停止试听" : "试听「\(assist.soundSource.name)」",
                          systemImage: assist.previewing ? "stop.fill" : "play.fill")
                }
                .buttonStyle(GhostButtonStyle(height: 44))
                .disabled(assist.session != nil)
            }
        }
        .padding(16)
        .glass(26)
    }

    // MARK: 声音来源

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("助眠声音").font(.xiaowei(20))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Synth.Scene.sleepScenes) { sc in
                    SoundTile(title: sc.name, detail: sc.detail, selected: assist.soundSource == .scene(sc)) {
                        assist.soundSource = .scene(sc)
                        if assist.previewing { assist.preview() }
                    }
                }
                SoundTile(title: "外部 App", detail: "B 站、网易云等", selected: external) {
                    assist.stopPreview()
                    assist.soundSource = .external
                }
            }

            VStack(spacing: 0) {
                ForEach(assist.imported) { s in
                    Button {
                        assist.soundSource = .file(s.fileName)
                        if assist.previewing { assist.preview() }
                    } label: {
                        ListRow(title: s.title, subtitle: "我的音频 · 长按可删除") {
                            if assist.soundSource == .file(s.fileName) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { assist.deleteSound(s) } label: { Label("删除", systemImage: "trash") }
                    }
                    RowDivider()
                }
                Button { importing = true } label: {
                    ListRow(title: "导入音频文件", subtitle: "把 B 站 ASMR 等存成 mp3 / m4a，从「文件」里选") {
                        Image(systemName: "plus.circle").font(.system(size: 20)).foregroundStyle(Theme.lilac)
                    }
                }
                .buttonStyle(.plain)
            }
            .glass(26)

            if external { externalGuide }
        }
    }

    private var externalGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用 B 站等 App 助眠").font(.system(size: 15, weight: .semibold))
            guideLine(1, "在 B 站打开想听的 ASMR 开始播放。B 站要先打开后台播放：我的 → 设置 → 播放设置 → 后台播放。")
            guideLine(2, "回到这里，躺下就会自动开始；也可以在首页手动开始。")
            guideLine(3, "你安静下来后，手机音量会慢慢调小；睡着后让它暂停，并把手机音量还原。")
            Text("夜里醒来时没法替你让 B 站继续播，会改用「星河」轻声陪你。")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(26)
    }

    private func guideLine(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.italiana(18)).foregroundStyle(Theme.lilac).frame(width: 14)
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineSpacing(3)
        }
    }
}

/// 声音选择卡片（助眠页和闹钟页共用）。
struct SoundTile: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.xiaowei(19))
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint) }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(selected ? Theme.violet.opacity(0.35) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(selected ? Theme.lilac.opacity(0.7) : Color.white.opacity(0.1)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 页面底部的短暂提示。
struct FlashBanner: View {
    let text: String?

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glass(18)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: text)
    }
}

/// 音量变化曲线：躺下后保持起始音量，安静后平滑降到最低，睡着后淡出到无声。
/// 线条像笔一样画出来，再有一颗光点沿曲线走一遍。
struct VolumeCurve: View {
    private let start: Float
    private let preset: AssistPreset
    private let draw: Bool
    @State private var travel: CGFloat = 0

    init(start: Float, preset: AssistPreset, draw: Bool) {
        self.start = start
        self.preset = preset
        self.draw = draw
    }

    private var totalMinutes: Double { preset.quietWaitMinutes + preset.fadeMinutes + 10 }

    private func points(in size: CGSize) -> [CGPoint] {
        let total = totalMinutes
        func x(_ m: Double) -> CGFloat { size.width * CGFloat(m / total) }
        func y(_ v: Double) -> CGFloat { size.height - size.height * CGFloat(v / 1.05) }
        let s = Double(start)
        let floor = s * Double(preset.floorRatio)
        var pts = [CGPoint(x: 0, y: y(s)), CGPoint(x: x(preset.quietWaitMinutes), y: y(s))]
        for i in 1...24 {
            let t = Double(i) / 24
            let e = t * t * (3 - 2 * t)
            pts.append(CGPoint(x: x(preset.quietWaitMinutes + preset.fadeMinutes * t), y: y(s + (floor - s) * e)))
        }
        let hold = preset.quietWaitMinutes + preset.fadeMinutes + 5
        pts.append(CGPoint(x: x(hold), y: y(floor)))
        for i in 1...8 {
            let t = Double(i) / 8
            let e = t * t * (3 - 2 * t)
            pts.append(CGPoint(x: x(hold + 1.5 * t), y: y(floor * (1 - e))))
        }
        pts.append(CGPoint(x: size.width, y: y(0)))
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
            let waitX = geo.size.width * CGFloat(preset.quietWaitMinutes / totalMinutes)
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
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.6).delay(0.3), value: draw)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .white.opacity(0.8), radius: 8)
                    .modifier(FollowPath(t: travel, path: line))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("躺下后保持 \(Int(start * 100))%，安静 \(Int(preset.quietWaitMinutes)) 分钟后用 \(Int(preset.fadeMinutes)) 分钟慢慢降到 \(Int(start * preset.floorRatio * 100))%，睡着后停止")
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
