import SwiftUI

struct TonightView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let m = assist.message {
                        Text(m)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glass(18)
                    }
                    hero
                    liveCard
                    tiles
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .confirmationDialog("结束今晚的记录？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("结束并保存报告", role: .destructive) { assist.endSession() }
            Button("继续记录", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting).font(.display(30)).lineSpacing(4)
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            LinkChip()
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 5 && h < 11 { return "早上好，\n昨夜睡得怎么样？" }
        if h >= 11 && h < 18 { return "下午好，\n今晚早点休息。" }
        return "晚上好，\n今晚好好睡。"
    }

    @ViewBuilder private var hero: some View {
        HeroCard {
            VStack(spacing: 8) {
                if let s = assist.session {
                    Text("已记录").font(.footnote).foregroundStyle(.white.opacity(0.9))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(formatDuration(Date().timeIntervalSince(s.start)))
                            .font(.numeral(84)).monospacedDigit()
                    }
                    Text(assist.phase.label).font(.subheadline).foregroundStyle(.white.opacity(0.92))
                    Text("音量 \(assist.levelPercent)% · \(assist.soundKind.name)")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                    Button("结束记录") { confirmEnd = true }
                        .buttonStyle(PillButtonStyle())
                        .padding(.top, 10)
                } else {
                    Text("现在").font(.footnote).foregroundStyle(.white.opacity(0.9))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(ctx.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.numeral(84)).monospacedDigit()
                    }
                    Text(assist.autoStart ? "躺下后会自动开始助眠" : "自动开始已关闭")
                        .font(.footnote).foregroundStyle(.white.opacity(0.9))
                    Button {
                        assist.startSession(manual: true)
                    } label: {
                        Label("开始今晚的记录", systemImage: "moon.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 10)
                }
            }
        }
    }

    private var liveCard: some View {
        let s = client.status
        let act = s.map { Activity($0) } ?? .unknown
        let pose = Pose(raw: s?.posture?.pose, reversed: assist.reverseLR)
        let rate = s?.respiration?.rateBpm
        return HStack(spacing: 14) {
            Image(systemName: act == .quiet ? "zzz" : act == .away ? "bed.double" : "waveform.path")
                .font(.title3)
                .foregroundStyle(Theme.lavender)
                .frame(width: 48, height: 48)
                .background(Theme.lavender.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(s == nil ? "等待枕头数据" : "\(act.label) · \(pose.label)").font(.headline)
                Text(rate.map { "呼吸约 \(Int($0.rounded())) 次/分" } ?? "呼吸数据积累中")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .padding(16)
        .glass()
    }

    @ViewBuilder private var tiles: some View {
        if let s = assist.session ?? assist.sessions.first {
            VStack(alignment: .leading, spacing: 8) {
                Text(assist.session == nil ? "上一晚" : "本次").font(.caption).foregroundStyle(Theme.secondary)
                HStack(spacing: 10) {
                    StatTile(value: formatDuration(s.inBedSeconds), label: "在枕")
                    StatTile(value: "\(Int((s.quietRatio * 100).rounded()))%", label: "安静占比")
                    StatTile(value: "\(s.turns)", label: "翻身", tint: Theme.mint)
                }
            }
        }
    }
}

struct LinkChip: View {
    @EnvironmentObject private var client: PillowClient

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(16)
    }

    private var color: Color {
        switch client.link {
        case .connected: return Theme.mint
        case .searching: return Theme.amber
        default: return Color.red.opacity(0.8)
        }
    }

    private var text: String {
        switch client.link {
        case .connected: return "枕头在线"
        case .searching: return "正在查找"
        case .idle: return "未连接"
        case .unreachable: return "连接中断"
        }
    }
}
