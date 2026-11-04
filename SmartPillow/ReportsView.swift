import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var assist: AssistEngine

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("睡眠报告").font(.display(30))
                        if assist.sessions.isEmpty {
                            Text("还没有报告。结束一次记录后，报告会自动保存在这里。")
                                .font(.subheadline).foregroundStyle(Theme.secondary)
                                .padding(18).frame(maxWidth: .infinity, alignment: .leading).glass()
                        }
                        ForEach(assist.sessions) { s in
                            NavigationLink { ReportDetailView(session: s) } label: { row(s) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func row(_ s: SleepSession) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.start.formatted(.dateTime.month().day().locale(Theme.zh))).font(.headline)
                Text(s.start.formatted(.dateTime.weekday(.wide).locale(Theme.zh))).font(.caption).foregroundStyle(Theme.secondary)
            }
            .frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(Theme.lavender).frame(width: geo.size.width * s.quietRatio)
                }
            }
            .frame(height: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(s.inBedSeconds)).font(.numeral(22)).monospacedDigit()
                Text("安静 \(Int((s.quietRatio * 100).rounded()))%").font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .glass()
    }
}

struct ReportDetailView: View {
    let session: SleepSession
    @EnvironmentObject private var assist: AssistEngine
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title).font(.display(28))
                    Text(range).font(.footnote).foregroundStyle(Theme.secondary)

                    HeroCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("在枕时长").font(.footnote).foregroundStyle(.white.opacity(0.9))
                                Text(formatDuration(session.inBedSeconds)).font(.numeral(72)).monospacedDigit()
                                if let onset = session.sleepOnsetSeconds {
                                    Text("助眠后约 \(Int(onset / 60)) 分钟入睡").font(.footnote).foregroundStyle(.white.opacity(0.92))
                                }
                            }
                            Spacer()
                            ZStack {
                                Circle().stroke(.white.opacity(0.22), lineWidth: 6)
                                Circle()
                                    .trim(from: 0, to: appear ? session.quietRatio : 0)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 0) {
                                    Text("\(Int((session.quietRatio * 100).rounded()))%").font(.numeral(24))
                                    Text("安静").font(.caption2)
                                }
                            }
                            .frame(width: 96, height: 96)
                        }
                    }

                    HStack(spacing: 10) {
                        StatTile(value: "\(session.turns)", label: "翻身")
                        StatTile(value: "\(session.awayCount)", label: "离枕")
                        StatTile(value: session.respAverage.map { "~\(Int($0.rounded()))" } ?? "—", label: "呼吸 次/分")
                    }

                    timeline
                    poses

                    HStack(spacing: 10) {
                        StatTile(value: "\(session.interventions)", label: "夜间再助眠", tint: Theme.mint)
                        StatTile(value: formatDuration(session.activeSeconds), label: "活动时长")
                    }

                    Text("结果根据枕头的压力和振动信号估计，仅供参考，不是医学诊断。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.45))

                    Button(role: .destructive) {
                        assist.deleteSession(session.id)
                        dismiss()
                    } label: {
                        Text("删除这份报告").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .glass(22)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 30)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4).delay(0.3)) { appear = true } }
    }

    private var title: String {
        let h = session.duration / 3600
        return h >= 6 ? "昨夜睡得不错" : "这一晚的记录"
    }

    private var range: String {
        let f = Date.FormatStyle.dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Theme.zh)
        return "\(session.start.formatted(f)) – \((session.end ?? Date()).formatted(f))"
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("整夜节律").font(.display(18))
            GeometryReader { geo in
                let total = max(1, session.duration)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(session.segments.enumerated()), id: \.offset) { _, seg in
                        let y: CGFloat = seg.kind == .away ? 0 : seg.kind == .active ? 26 : 52
                        let color: Color = seg.kind == .away ? .white.opacity(0.35) : seg.kind == .active ? Color(red: 0.96, green: 0.71, blue: 0.91) : Theme.lavender
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(width: max(3, geo.size.width * (seg.end - seg.start) / total), height: 18)
                            .offset(x: geo.size.width * seg.start / total, y: y)
                    }
                }
            }
            .frame(height: 70)
            HStack(spacing: 14) {
                legend(.white.opacity(0.35), "离枕")
                legend(Color(red: 0.96, green: 0.71, blue: 0.91), "活动")
                legend(Theme.lavender, "安静")
            }
        }
        .padding(18)
        .glass(28)
    }

    private var poses: some View {
        let total = max(1, session.poseSeconds.values.reduce(0, +))
        let order: [Pose] = [.supine, .left, .right, .unknown]
        return VStack(alignment: .leading, spacing: 12) {
            Text("睡姿").font(.display(18))
            ForEach(order, id: \.self) { p in
                let sec = session.poseSeconds[p.rawValue] ?? 0
                HStack(spacing: 10) {
                    Text(p.label).font(.footnote).foregroundStyle(.white.opacity(0.75)).frame(width: 52, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule().fill(Theme.lavender).frame(width: appear ? geo.size.width * sec / total : 0)
                        }
                    }
                    .frame(height: 8)
                    Text(formatDuration(sec)).font(.footnote).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .glass(28)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10)
            Text(t).font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}
