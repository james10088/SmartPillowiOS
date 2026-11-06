import SwiftUI

/// 起床闹钟设置：时间、智能唤醒窗口、渐强时长、唤醒声音。
struct AlarmSheet: View {
    @EnvironmentObject private var assist: AssistEngine
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    private var a: AlarmSettings { assist.alarm }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("起床闹钟").font(.xiaowei(30))
                        Text(a.enabled ? "明早 \(a.timeText) 前，用音乐慢慢叫醒你" : "已关闭")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    MintSwitch(isOn: $assist.alarm.enabled, label: "闹钟开关", width: 56, height: 34)
                }

                DatePicker("起床时间", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Theme.zh)
                    .frame(maxWidth: .infinity)
                    .frame(height: 170)
                    .clipped()
                    .glass(26)
                    .opacity(a.enabled ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("智能唤醒").font(.xiaowei(20))
                    GlassSegmented(options: [(0, "准时"), (15, "提前 15 分"), (30, "提前 30 分")],
                                   selection: $assist.alarm.windowMinutes, font: .system(size: 14, weight: .medium), height: 40)
                    Text(windowText).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(3)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("音乐渐强").font(.xiaowei(20))
                    GlassSegmented(options: [(5, "5 分钟"), (10, "10 分钟"), (15, "15 分钟")],
                                   selection: $assist.alarm.rampMinutes, font: .system(size: 14, weight: .medium), height: 40)
                    Text("从无声慢慢变大，到点时是正常音量。手机静音时也会响。")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("唤醒声音").font(.xiaowei(20))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Synth.Scene.wakeScenes) { sc in
                            tile(.scene(sc), detail: sc.detail)
                        }
                        ForEach(assist.imported) { s in
                            tile(.file(s.fileName), detail: "我的音频")
                        }
                    }
                    Button {
                        assist.previewing ? assist.stopPreview() : assist.preview(SoundSource(key: a.soundKey), level: 0.6)
                    } label: {
                        Label(assist.previewing ? "停止试听" : "试听唤醒声音", systemImage: assist.previewing ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(GhostButtonStyle(height: 44))
                    .disabled(assist.session != nil)
                }

                Text("闹钟需要智能枕头留在后台：睡前不要把它从后台划掉。万一被系统关掉，到点会弹系统通知提醒你，请允许通知。")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary).lineSpacing(3)

                Button("完成") { dismiss() }
                    .buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .background { NightBackground() }
        .overlay(alignment: .bottom) { FlashBanner(text: assist.message) }
        .preferredColorScheme(.dark)
        .onAppear {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            c.hour = a.hour
            c.minute = a.minute
            time = Calendar.current.date(from: c) ?? Date()
        }
        .onChange(of: time) { t in
            let c = Calendar.current.dateComponents([.hour, .minute], from: t)
            let h = c.hour ?? a.hour
            let m = c.minute ?? a.minute
            guard h != a.hour || m != a.minute else { return }
            var next = assist.alarm
            next.hour = h
            next.minute = m
            next.enabled = true
            assist.alarm = next
        }
        .onDisappear { assist.stopPreview() }
    }

    private var windowText: String {
        if a.windowMinutes == 0 { return "到 \(a.timeText) 时音乐刚好变到正常音量。" }
        return "\(a.text(minutesBefore: a.windowMinutes))–\(a.timeText) 之间，检测到你翻身或动了（浅睡）就开始叫醒；最晚 \(a.timeText) 叫醒。"
    }

    private func tile(_ src: SoundSource, detail: String) -> some View {
        SoundTile(title: src.name, detail: detail, selected: a.soundKey == src.key) {
            assist.alarm.soundKey = src.key
            if assist.previewing { assist.preview(src, level: 0.6) }
        }
    }
}
