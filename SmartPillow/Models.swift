import Foundation

/// GET /api/status 的返回。字段全部可选：固件版本不同时缺字段也不会解析失败。
struct PillowStatus: Decodable {
    struct Sensor: Decodable {
        let timestampMs: Int?
        let h1Mv: Double?
        let h2Mv: Double?
        let h3Mv: Double?
        let pvdfMv: Double?
        let pvdfDeltaMv: Double?
    }
    struct Posture: Decodable {
        let pose: String?
        let confidence: Double?
        let source: String?
    }
    struct Behavior: Decodable {
        let sessionId: Int?
        let state: String?
        let pose: String?
        let elapsedMs: Int?
        let turnCount: Int?
        let supineMs: Int?
        let leftMs: Int?
        let rightMs: Int?
        let emptyMs: Int?
        let unknownMs: Int?
    }
    struct Observation: Decodable {
        let status: String?
        let quietMs: Int?
        let motionMs: Int?
        let awayMs: Int?
        let awakeMs: Int?
        let activityCount: Int?
        let awayCount: Int?
    }
    struct Respiration: Decodable {
        let status: String?
        let quality: Double?
        let rateBpm: Double?
    }

    let version: Int?
    let timestampMs: Int?
    let modelId: String?
    let modelLevel: String?
    let sensor: Sensor?
    let posture: Posture?
    let behavior: Behavior?
    let observation: Observation?
    let respiration: Respiration?
    let calibration: String?

    static func decode(_ data: Data) throws -> PillowStatus {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(PillowStatus.self, from: data)
    }
}

/// 把固件的状态字符串归成助眠逻辑关心的几类。
enum Activity: String, Codable {
    case away, quiet, active, unknown

    init(_ s: PillowStatus) {
        let obs = s.observation?.status ?? "UNKNOWN"
        let pose = s.posture?.pose ?? "UNKNOWN"
        if obs == "AWAY" || pose == "EMPTY" {
            self = .away
        } else if obs == "QUIET" || obs == "STABLE_QUIET" {
            self = .quiet
        } else if obs == "MOTION" || obs == "AWAKE_CANDIDATE" {
            self = .active
        } else {
            self = .unknown
        }
    }
}

enum Pose: String, Codable, CaseIterable {
    case supine = "SUPINE", left = "LEFT", right = "RIGHT", empty = "EMPTY", unknown = "UNKNOWN"

    init(raw: String?, reversed: Bool) {
        var p = Pose(rawValue: raw ?? "") ?? .unknown
        if reversed {
            if p == .left { p = .right } else if p == .right { p = .left }
        }
        self = p
    }

    var label: String {
        switch self {
        case .supine: return "仰卧"
        case .left: return "左侧卧"
        case .right: return "右侧卧"
        case .empty: return "无人"
        case .unknown: return "识别中"
        }
    }
}

/// 一晚的记录，结束时存到本地。
struct SleepSession: Codable, Identifiable {
    struct Segment: Codable {
        var start: Double   // 距开始的秒数
        var end: Double
        var kind: Activity
    }

    var id = UUID()
    var start: Date
    var end: Date?
    var inBedSeconds: Double = 0
    var quietSeconds: Double = 0
    var activeSeconds: Double = 0
    var awayCount = 0
    var turns = 0
    var interventions = 0
    var sleepOnsetSeconds: Double?          // 从开始助眠到稳定安静的时间
    var poseSeconds: [String: Double] = [:]
    var respSum: Double = 0
    var respCount = 0
    var segments: [Segment] = []

    var duration: Double { (end ?? Date()).timeIntervalSince(start) }
    var quietRatio: Double { inBedSeconds > 0 ? quietSeconds / inBedSeconds : 0 }
    var respAverage: Double? { respCount > 0 ? respSum / Double(respCount) : nil }

    mutating func add(_ kind: Activity, from t0: Double, to t1: Double) {
        if var last = segments.last, last.kind == kind, abs(last.end - t0) < 5 {
            last.end = t1
            segments[segments.count - 1] = last
        } else {
            segments.append(Segment(start: t0, end: t1, kind: kind))
        }
    }
}

extension SleepSession {
    /// 7 晚示例数据，仅用于截图和演示。
    static func sampleNights() -> [SleepSession] {
        let cal = Calendar.current
        let hours: [Double] = [7.2, 6.7, 7.5, 6.9, 5.8, 7.1, 6.4]
        let quiet: [Double] = [0.84, 0.79, 0.86, 0.80, 0.71, 0.83, 0.78]
        return hours.indices.map { i -> SleepSession in
            let day = cal.date(byAdding: .day, value: -(i + 1), to: cal.startOfDay(for: Date()))!
            let start = cal.date(bySettingHour: 23, minute: 10 + i * 3, second: 0, of: day)!
            let dur = hours[i] * 3600 + 20 * 60
            var s = SleepSession(start: start)
            s.end = start.addingTimeInterval(dur)
            s.inBedSeconds = hours[i] * 3600
            s.quietSeconds = s.inBedSeconds * quiet[i]
            s.activeSeconds = s.inBedSeconds - s.quietSeconds
            s.awayCount = i % 3
            s.turns = 10 + (i * 3) % 7
            s.interventions = i % 2
            s.sleepOnsetSeconds = Double(14 + i * 4) * 60
            s.respSum = 14.1 * 100
            s.respCount = 100
            s.poseSeconds = ["SUPINE": s.inBedSeconds * 0.46, "LEFT": s.inBedSeconds * 0.32,
                             "RIGHT": s.inBedSeconds * 0.18, "UNKNOWN": s.inBedSeconds * 0.04]
            let plan: [(Double, Activity)] = [(0.08, .quiet), (0.02, .active), (0.16, .quiet), (0.015, .away), (0.18, .quiet),
                                              (0.04, .active), (0.03, .active), (0.01, .quiet), (0.025, .active), (0.2, .quiet),
                                              (0.015, .away), (0.225, .quiet)]
            var t = 0.0
            for (f, kind) in plan {
                s.segments.append(Segment(start: t * dur, end: (t + f) * dur, kind: kind))
                t += f
            }
            return s
        }
    }
}

/// 助眠强度预设，与设计稿里的“轻柔 / 标准 / 明显”一致。
enum AssistPreset: String, Codable, CaseIterable, Identifiable {
    case gentle, standard, strong
    var id: String { rawValue }

    var name: String { ["轻柔", "标准", "明显"][index] }
    /// 安静多久后开始变轻
    var quietWaitMinutes: Double { [10, 5, 2][index] }
    /// 用多久慢慢降到最低
    var fadeMinutes: Double { [30, 20, 12][index] }
    /// 最低降到起始音量的多少
    var floorRatio: Float { [0.6, 0.4, 0.25][index] }
    /// 夜里翻来覆去时，最多调回到起始音量的多少
    var capRatio: Float { [0.8, 0.7, 0.6][index] }
    var cooldownMinutes: Double { [60, 30, 20][index] }
    var summary: String { "安静 \(Int(quietWaitMinutes)) 分钟后，用 \(Int(fadeMinutes)) 分钟慢慢变轻" }

    private var index: Int { AssistPreset.allCases.firstIndex(of: self)! }
}

func formatDuration(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    return String(format: "%d:%02d", m / 60, m % 60)
}
