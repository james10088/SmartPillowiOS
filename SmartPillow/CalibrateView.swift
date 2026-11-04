import SwiftUI

/// 画板 8「睡姿校准引导」：每一步倒计时 10 秒，结束时记下这一姿势的三路压力参考值（保存在手机上）。
struct CalibrateView: View {
    @EnvironmentObject private var client: PillowClient
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var stepStart = Date()
    @State private var captured: Set<Int> = []
    @State private var samples: [[Double]] = []

    private struct StepDef { let name, title, hint: String }
    private let steps = [
        StepDef(name: "空枕", title: "先把枕头空出来", hint: "头离开枕头，让它记住“没人”的样子"),
        StepDef(name: "仰卧", title: "平躺，脸朝上", hint: "后脑放在枕头正中间"),
        StepDef(name: "左侧卧", title: "向左侧躺好", hint: "像平时睡觉那样，肩膀放松"),
        StepDef(name: "右侧卧", title: "再向右侧躺好", hint: "最后一步，完成后会自动保存")
    ]
    private let duration: Double = 10
    private var done: Bool { step >= steps.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    GlassCircle(label: "退出校准", action: { dismiss() }) { Icon(kind: .close, size: 18) }
                    Spacer()
                    Text("睡姿校准").font(.xiaowei(19))
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .rise(0)
                chips.rise(0.06)
                if done { doneCard.transition(.scale(scale: 0.95).combined(with: .opacity)) } else { countdownCard.rise(0.12) }
                pressureCard.rise(0.22)
                buttons.padding(.top, 20)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 30)
        }
        .background { NightBackground() }
        .onChange(of: client.lastUpdate) { _ in collect() }
    }

    // MARK: 步骤

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(steps.indices, id: \.self) { i in
                let current = i == step
                let passed = captured.contains(i) || i < step
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(passed ? Theme.mint : current ? Color.white : Color.white.opacity(0.1))
                        if passed {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.ink)
                        } else {
                            Text("\(i + 1)").font(.italiana(14)).foregroundStyle(current ? Theme.ink : Theme.secondary)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(steps[i].name).font(.system(size: 12)).foregroundStyle(i <= step ? .white : Theme.tertiary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(current ? Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255).opacity(0.2) : Color.white.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(current ? Theme.lilac.opacity(0.5) : Color.white.opacity(0.08)))
                .animation(.easeInOut(duration: 0.4), value: step)
            }
        }
    }

    private var countdownCard: some View {
        HeroCard(padding: 22) {
            VStack(spacing: 0) {
                Text("第 \(step + 1) 步 · 保持不动").font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                TimelineView(.periodic(from: stepStart, by: 0.1)) { ctx in
                    let remaining = max(0, duration - ctx.date.timeIntervalSince(stepStart))
                    ZStack {
                        Circle().stroke(.white.opacity(0.22), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: remaining / duration)
                            .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(captured.contains(step) ? "✓" : "\(Int(remaining.rounded(.up)))")
                                .font(.italiana(76))
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.25), value: Int(remaining.rounded(.up)))
                            Text(captured.contains(step) ? "已记录" : "秒").font(.system(size: 12)).foregroundStyle(.white.opacity(0.88))
                        }
                    }
                    .frame(width: 168, height: 168)
                    .padding(.top, 12)
                    .onChange(of: remaining <= 0) { finished in if finished { capture() } }
                }
                Text(steps[min(step, steps.count - 1)].title).font(.xiaowei(26)).tracking(1).padding(.top, 16)
                Text(steps[min(step, steps.count - 1)].hint).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).padding(.top, 4)
            }
        }
    }

    private var doneCard: some View {
        HeroCard(padding: 26) {
            VStack(spacing: 0) {
                DoneCheck().frame(width: 168, height: 168)
                Text("校准完成").font(.xiaowei(26)).tracking(1).padding(.top, 16)
                Text("四种姿势的压力参考值已保存在手机上").font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).padding(.top, 4)
            }
        }
    }

    // MARK: 实时压力

    private var pressureCard: some View {
        let s = client.status?.sensor
        let values: [Double] = [s?.h1Mv ?? 0, s?.h2Mv ?? 0, s?.h3Mv ?? 0]
        let names = ["左侧", "中间", "右侧"]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("枕头感受到的压力").font(.system(size: 13))
                Spacer()
                Text(feel(values)).font(.system(size: 13)).foregroundStyle(Theme.mint)
            }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(LinearGradient(colors: [Theme.lilac, Theme.violet], startPoint: .top, endPoint: .bottom))
                                    .frame(height: max(3, geo.size.height * min(1, values[i] / 2800)))
                            }
                        }
                        .frame(height: 44)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: values[i])
                        Text(names[i]).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .padding(16)
        .glass(26)
    }

    private func feel(_ v: [Double]) -> String {
        guard client.status != nil else { return client.demo ? "演示数据" : "等待枕头数据" }
        let total = v.reduce(0, +)
        if total < 150 { return "几乎没有压力" }
        let i = v.firstIndex(of: v.max() ?? 0) ?? 1
        return ["左侧受力", "中间受力", "右侧受力"][i]
    }

    // MARK: 按钮

    @ViewBuilder private var buttons: some View {
        if done {
            HStack(spacing: 10) {
                Button("重新校准") { restart(at: 0) }.buttonStyle(GhostButtonStyle())
                Button("回到设备") { dismiss() }.buttonStyle(PillButtonStyle(height: 52))
            }
        } else {
            HStack(spacing: 10) {
                Button("重做这一步") { restart(at: step) }.buttonStyle(GhostButtonStyle())
                Button(step == steps.count - 1 ? "完成校准" : "下一步") { next() }
                    .buttonStyle(PillButtonStyle(height: 52))
                    .opacity(captured.contains(step) ? 1 : 0.55)
                    .disabled(!captured.contains(step))
            }
        }
    }

    // MARK: 逻辑

    private func collect() {
        guard !done, let s = client.status?.sensor else { return }
        let elapsed = Date().timeIntervalSince(stepStart)
        // 只取倒计时后半段（人已经躺稳）的数据
        if elapsed >= duration / 2 && elapsed <= duration {
            samples.append([s.h1Mv ?? 0, s.h2Mv ?? 0, s.h3Mv ?? 0])
        }
    }

    private func capture() {
        guard !done, !captured.contains(step) else { return }
        let n = Double(max(1, samples.count))
        let avg = (0..<3).map { k in samples.map { $0[k] }.reduce(0, +) / n }
        var refs = UserDefaults.standard.dictionary(forKey: "calibrationRefs") as? [String: [Double]] ?? [:]
        refs[["EMPTY", "SUPINE", "LEFT", "RIGHT"][step]] = avg
        UserDefaults.standard.set(refs, forKey: "calibrationRefs")
        withAnimation { _ = captured.insert(step) }
    }

    private func next() {
        withAnimation(.easeInOut(duration: 0.35)) { step += 1 }
        stepStart = Date()
        samples = []
    }

    private func restart(at i: Int) {
        withAnimation(.easeInOut(duration: 0.35)) {
            if i == 0 { captured = [] } else { captured.remove(i) }
            step = i
        }
        stepStart = Date()
        samples = []
    }
}

/// 完成：绿色圆环画满，对勾弹出。
struct DoneCheck: View {
    @State private var ring = false
    @State private var pop = false
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: ring ? 1 : 0)
                .stroke(Theme.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark").font(.system(size: 56, weight: .semibold))
                .scaleEffect(pop ? 1 : 0.6).opacity(pop ? 1 : 0)
        }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.9)) { ring = true }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.6)) { pop = true }
        }
    }
}
