import Foundation
import UserNotifications

/// 起床闹钟：在设定时间之前的一段窗口里，检测到你在浅睡（翻身、动）就开始叫醒；
/// 最晚在“闹钟时间减去渐强时长”开始，保证到点时音乐已经是正常音量。
struct AlarmSettings: Codable, Equatable {
    var enabled = false
    var hour = 7
    var minute = 30
    /// 提前多少分钟内遇到浅睡就叫醒（0 = 准时）
    var windowMinutes = 30
    /// 音乐从无声渐强到正常音量用多久
    var rampMinutes = 10
    /// 唤醒声音（SoundSource.key）
    var soundKey = SoundSource.scene(.morning).key

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    func text(minutesBefore m: Int) -> String {
        let total = ((hour * 60 + minute - m) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// date 之后最近的一次闹钟时间。
    func next(after date: Date = Date()) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = hour
        c.minute = minute
        c.second = 0
        var d = cal.date(from: c) ?? date
        if d <= date { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }

    static func load() -> AlarmSettings {
        guard let data = UserDefaults.standard.data(forKey: "alarm"),
              let a = try? JSONDecoder().decode(AlarmSettings.self, from: data) else { return AlarmSettings() }
        return a
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "alarm") }
    }
}

/// 后备提醒：万一 App 被系统关掉、没法播放音乐，到点由系统通知提醒。
/// App 正常叫醒你时会先把这些通知取消。
enum AlarmNotifier {
    private static let ids = ["smartpillow.alarm.0", "smartpillow.alarm.1", "smartpillow.alarm.2"]

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func schedule(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        for (i, offset) in [0.0, 120, 300].enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "早上好"
            content.body = i == 0 ? "到起床时间了。" : "该起床了，打开智能枕头可以关掉提醒。"
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                        from: date.addingTimeInterval(offset))
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: ids[i], content: content, trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
