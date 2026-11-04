import SwiftUI

/// 报告页签：显示最近一晚；没有记录时显示空状态。
struct ReportTab: View {
    @EnvironmentObject private var assist: AssistEngine

    var body: some View {
        if let s = assist.sessions.first {
            ReportView(session: s, showsBack: false)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("睡眠报告").font(.xiaowei(32)).tracking(1).rise(0)
                    VStack(alignment: .leading, spacing: 10) {
                        Icon(kind: .tide, size: 34, color: Theme.lilac)
                        Text("还没有报告").font(.xiaowei(20))
                        Text("开始一次记录，结束后这里会自动生成一份睡眠报告：在枕时长、安静占比、翻身、整夜节律和睡姿。")
                            .font(.system(size: 14)).foregroundStyle(Theme.secondary).lineSpacing(4)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(28)
                    .rise(0.1)
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 110)
            }
            .background { NightBackground() }
        }
    }
}

/// 画板 3「睡眠报告」
struct ReportView: View {
    private let session: SleepSession
    private let showsBack: Bool
    @EnvironmentObject private var assist: AssistEngine
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false
    @State private var confirmDelete = false

    init(session: SleepSession, showsBack: Bool) {
        self.session = session
        self.showsBack = showsBack
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if showsBack { BackBar().rise(0) }
                header.rise(0)
                hero.rise(0.1)
                HStack(spacing: 10) {
                    StatTile(value: "\(session.turns)", label: "翻身")
                    StatTile(value: "\(session.awayCount)", label: "离枕")
                    StatTile(value: session.respAverage.map { "~\(Int($0.rounded()))" } ?? "—", label: "呼吸 次/分")
                }
                .rise(0.2)
                timeline.rise(0.3)
                poses.rise(0.4)
                insight.rise(0.5)
                Text("可能清醒的时间根据持续活动推算。结果仅供参考，不是医学诊断。")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineSpacing(3)
                Button("删除这份报告") { confirmDelete = true }
                    .font(.system(size: 13)).foregroundStyle(Theme.coral.opacity(0.9))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 110)
        }
        .background { NightBackground() }
        .onAppear { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.8).delay(0.4)) { appear = true } }
        .confirmationDialog("删除这份报告？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                assist.deleteSession(session.id)
                if showsBack { dismiss() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.xiaowei(32)).lineSpacing(6).tracking(1)
                Text(range).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                NavigationLink(value: Route.history) {
                    Icon(kind: .phases, size: 22, color: Theme.pale)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("历史报告")
                ShareLink(item: shareText) {
                    Icon(kind: .share, size: 22, color: Theme.pale)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
                }
                .accessibilityLabel("分享报告")
            }
        }
    }

    private var title: String {
        let h = Calendar.current.component(.hour, from: Date())
        let lead = (h >= 5 && h < 12) ? "早上好，" : "这一晚，"
        return lead + "\n" + (session.quietRatio >= 0.7 ? "睡得不错。" : "有点不安稳。")
    }

    private var range: String {
        let f = Date.FormatStyle.dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Theme.zh)
        return "\(session.start.formatted(f)) – \((session.end ?? Date()).formatted(f))"
    }

    private var shareText: String {
        var t = "我的睡眠报告（\(range)）\n在枕 \(formatHM(session.inBedSeconds))，安静 \(Int((session.quietRatio * 100).rounded()))%，翻身 \(session.turns) 次"
        if let onset = session.sleepOnsetSeconds { t += "，助眠后约 \(Int(onset / 60)) 分钟入睡" }
        return t + "。——智能枕头"
    }

    // MARK: 主卡片

    private var hero: some View {
        HeroCard(padding: 22) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("在枕时长").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                    Text(formatDuration(session.inBedSeconds)).font(.italiana(76)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(compareLine).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92))
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: appear ? session.quietRatio : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((session.quietRatio * 100).rounded()))%").font(.italiana(26))
                        Text("安静").font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("安静占比 \(Int((session.quietRatio * 100).rounded()))%")
            }
        }
    }

    private var compareLine: String {
        if let onset = session.sleepOnsetSeconds { return "助眠后约 \(max(1, Int(onset / 60))) 分钟入睡" }
        let others = assist.sessions.filter { $0.id != session.id }.prefix(7)
        guard !others.isEmpty else { return "第一份报告，继续记录就能对比" }
        let avg = others.map(\.inBedSeconds).reduce(0, +) / Double(others.count)
        let diff = Int((session.inBedSeconds - avg) / 60)
        if abs(diff) < 5 { return "和近 \(others.count) 晚平均差不多" }
        return diff > 0 ? "比近 \(others.count) 晚平均多 \(diff) 分钟" : "比近 \(others.count) 晚平均少 \(-diff) 分钟"
    }

    // MARK: 整夜节律

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("整夜节律").font(.xiaowei(19))
                Spacer()
                Text(rhythmNote).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            GeometryReader { geo in
                let labelW: CGFloat = 36
                let w = geo.size.width - labelW
                let total = max(1, session.duration)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(["离枕", "活动", "安静"].enumerated()), id: \.offset) { i, name in
                        Rectangle().fill(Color.white.opacity(0.07)).frame(width: w, height: 1)
                            .offset(x: labelW, y: CGFloat(i) * 40 + 16)
                        Text(name).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .offset(y: CGFloat(i) * 40 + 8)
                    }
                    ForEach(Array(session.segments.enumerated()), id: \.offset) { i, seg in
                        let lane: CGFloat = seg.kind == .away ? 0 : seg.kind == .active ? 1 : 2
                        let color: Color = seg.kind == .away ? Theme.tertiary.opacity(0.7) : seg.kind == .active ? Theme.blush : Theme.lavender
                        Capsule()
                            .fill(color)
                            .shadow(color: seg.kind == .away ? .clear : color.opacity(0.6), radius: 6)
                            .frame(width: max(5, w * (seg.end - seg.start) / total - 2), height: 20)
                            .scaleEffect(x: appear ? 1 : 0, anchor: .leading)
                            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7).delay(0.5 + Double(min(i, 30)) * 0.05), value: appear)
                            .offset(x: labelW + w * seg.start / total, y: lane * 40 + 6)
                    }
                }
            }
            .frame(height: 112)
            HStack {
                Text(timeLabel(0)); Spacer(); Text(timeLabel(0.5)); Spacer(); Text(timeLabel(1))
            }
            .font(.italiana(13)).foregroundStyle(Theme.secondary)
            .padding(.leading, 36)
        }
        .padding(18)
        .glass(28)
    }

    private var rhythmNote: String {
        guard let peak = session.segments.filter({ $0.kind == .active }).max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) else {
            return "整夜比较平稳"
        }
        let t = session.start.addingTimeInterval(peak.start)
        let h = Calendar.current.component(.hour, from: t)
        return "\(h) 点前后较活跃"
    }

    private func timeLabel(_ f: Double) -> String {
        session.start.addingTimeInterval(session.duration * f)
            .formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Theme.zh))
    }

    // MARK: 睡姿

    private var poses: some View {
        let total = max(1, session.poseSeconds.values.reduce(0, +))
        let rows: [(Pose, Color)] = [(.supine, Theme.pale), (.left, Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255)),
                                     (.right, Color(red: 110 / 255, green: 79 / 255, blue: 214 / 255)), (.unknown, Theme.tertiary.opacity(0.7))]
        return VStack(alignment: .leading, spacing: 12) {
            Text("睡姿").font(.xiaowei(19))
            ForEach(rows.indices, id: \.self) { i in
                let (pose, color) = rows[i]
                let sec = session.poseSeconds[pose.rawValue] ?? 0
                HStack(spacing: 10) {
                    Text(pose == .unknown ? "未识别" : pose.label).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(color)
                                .frame(width: geo.size.width * sec / total)
                                .scaleEffect(x: appear ? 1 : 0, anchor: .leading)
                                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1).delay(0.7 + Double(i) * 0.12), value: appear)
                        }
                    }
                    .frame(height: 8)
                    Text(formatDuration(sec)).font(.italiana(16)).frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .glass(28)
    }

    // MARK: 建议

    private var insight: some View {
        HStack(alignment: .top, spacing: 12) {
            InsightStar()
            VStack(alignment: .leading, spacing: 4) {
                Text("今晚试试").font(.xiaowei(18))
                Text(advice).font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).lineSpacing(4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255).opacity(0.12), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.lilac.opacity(0.24)))
    }

    private var advice: String {
        let inBed = max(1, session.inBedSeconds)
        if let onset = session.sleepOnsetSeconds, onset > 30 * 60 {
            return "这次入睡用了约 \(Int(onset / 60)) 分钟。今晚可以早一点开始助眠，或者换成更低沉的棕噪音。"
        }
        if session.activeSeconds / inBed > 0.25 {
            return "夜里活动偏多，可以检查枕头高度和睡前环境，保持相近的入睡时间。"
        }
        if session.interventions >= 2 {
            return "夜里醒来了 \(session.interventions) 次。睡前少看手机、调暗灯光，会更容易一觉到天亮。"
        }
        return "整夜大多安静。保持和昨晚相近的入睡时间，对比会更准。"
    }
}

/// 建议卡片上的星座图标，带呼吸光。
struct InsightStar: View {
    @State private var glow = false
    var body: some View {
        Icon(kind: .constellation, size: 22, color: Theme.pale)
            .frame(width: 38, height: 38)
            .background(Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255).opacity(0.25), in: Circle())
            .opacity(glow ? 1 : 0.75)
            .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glow = true } }
    }
}

/// 画板 9「历史报告」
struct HistoryView: View {
    @EnvironmentObject private var assist: AssistEngine
    @State private var range = 7
    @State private var appear = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                BackBar().rise(0)
                HStack {
                    Text(range == 7 ? "最近七晚" : "最近三十晚").font(.xiaowei(32)).tracking(1)
                    Spacer()
                    GlassSegmented(options: [(7, "周"), (30, "月")], selection: $range, font: .system(size: 13, weight: .semibold), height: 34)
                        .frame(width: 112)
                }
                .rise(0)
                hero.rise(0.1)
                list.rise(0.25)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 40)
        }
        .background { NightBackground() }
        .onAppear { appear = true }
        .onChange(of: range) { _ in
            appear = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { appear = true }
        }
    }

    private var nights: [SleepSession] { Array(assist.sessions.prefix(range)) }

    private var hero: some View {
        let ns = nights
        let avgBed = ns.isEmpty ? 0 : ns.map(\.inBedSeconds).reduce(0, +) / Double(ns.count)
        let avgQuiet = ns.isEmpty ? 0 : ns.map(\.quietRatio).reduce(0, +) / Double(ns.count)
        let bars = Array(ns.reversed())
        let maxBed = max(1, bars.map(\.inBedSeconds).max() ?? 1)
        return HeroCard(padding: 20) {
            VStack(spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("平均在枕").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        Text(ns.isEmpty ? "—" : formatDuration(avgBed)).font(.italiana(60)).tracking(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("平均安静").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88))
                        Text(ns.isEmpty ? "—" : "\(Int((avgQuiet * 100).rounded()))%").font(.italiana(32))
                    }
                }
                HStack(alignment: .bottom, spacing: range == 7 ? 10 : 3) {
                    if bars.isEmpty {
                        Text("还没有记录").font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).frame(maxWidth: .infinity, minHeight: 92)
                    }
                    ForEach(bars.indices, id: \.self) { i in
                        let s = bars[i]
                        let last = i == bars.count - 1
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: range == 7 ? 10 : 3)
                                .fill(last ? Color.white : Color.white.opacity(0.35))
                                .shadow(color: last ? .white.opacity(0.7) : .clear, radius: 9)
                                .frame(height: max(6, 80 * s.inBedSeconds / maxBed))
                                .scaleEffect(y: appear ? 1 : 0, anchor: .bottom)
                                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.9).delay(0.1 + Double(i) * (range == 7 ? 0.08 : 0.02)), value: appear)
                            if range == 7 {
                                Text(s.start.formatted(.dateTime.weekday(.narrow).locale(Theme.zh)))
                                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 92, alignment: .bottom)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(nights.enumerated()), id: \.element.id) { i, s in
                if i > 0 { RowDivider() }
                NavigationLink(value: Route.report(s.id)) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.start.formatted(.dateTime.month().day().locale(Theme.zh))).font(.system(size: 15))
                            Text(s.start.formatted(.dateTime.weekday(.wide).locale(Theme.zh))).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        .frame(width: 74, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255))
                                    .frame(width: geo.size.width * s.quietRatio)
                                    .scaleEffect(x: appear ? 1 : 0, anchor: .leading)
                                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.9).delay(0.4 + Double(i) * 0.06), value: appear)
                            }
                        }
                        .frame(height: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatDuration(s.inBedSeconds)).font(.italiana(20))
                            Text("安静 \(Int((s.quietRatio * 100).rounded()))%").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        .frame(width: 60, alignment: .trailing)
                    }
                    .frame(minHeight: 64)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if nights.isEmpty {
                Text("结束一次记录后，每晚的报告会列在这里。").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glass(26)
    }
}
