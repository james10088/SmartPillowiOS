import Foundation

/// 主动助眠闭环：监测 → 判断 → 干预 → 动态调节 → 自动退出 → 夜醒再助眠。
/// 每次收到枕头状态（约 1.5 秒）调用一次 tick。
@MainActor
final class AssistEngine: ObservableObject {
    enum Phase: String {
        case idle, soothing, fading, asleep, reassist, away

        var label: String {
            switch self {
            case .idle: return "等待入睡"
            case .soothing: return "助眠中"
            case .fading: return "安静了，音量逐步变轻"
            case .asleep: return "已入睡，声音已停止"
            case .reassist: return "夜间醒来，轻声陪伴"
            case .away: return "已离枕，声音暂停"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var session: SleepSession?
    @Published private(set) var message: String?
    @Published var preset: AssistPreset { didSet { save() } }
    @Published var soundKind: SoundEngine.Kind { didSet { sound.kind = soundKind; save() } }
    @Published var autoStart: Bool { didSet { save() } }
    @Published var reverseLR: Bool { didSet { save() } }
    @Published private(set) var sessions: [SleepSession] = []
    @Published private(set) var previewing = false

    let client: PillowClient
    private let sound = SoundEngine()

    // 计时
    private var lastTick: Date?
    private var presentSince: Date?
    private var quietSince: Date?
    private var activeSince: Date?
    private var awaySince: Date?
    private var lastStep = Date.distantPast
    private var cooldownUntil = Date.distantPast
    private var level: Float = 0
    private var firstTurnCount: Int?
    private var previewTask: Task<Void, Never>?

    private let stepInterval: TimeInterval = 30
    private let stepSize: Float = 0.05

    init(client: PillowClient) {
        self.client = client
        let d = UserDefaults.standard
        preset = AssistPreset(rawValue: d.string(forKey: "preset") ?? "") ?? .standard
        soundKind = SoundEngine.Kind(rawValue: d.string(forKey: "soundKind") ?? "") ?? .pink
        autoStart = d.object(forKey: "autoStart") as? Bool ?? true
        reverseLR = d.bool(forKey: "reverseLR")
        sound.kind = soundKind
        sessions = SessionStore.load()
        client.onStatus = { [weak self] s in self?.tick(s) }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(preset.rawValue, forKey: "preset")
        d.set(soundKind.rawValue, forKey: "soundKind")
        d.set(autoStart, forKey: "autoStart")
        d.set(reverseLR, forKey: "reverseLR")
    }

    var levelPercent: Int { Int((level * 100).rounded()) }

    // MARK: 开始 / 结束

    func startSession(manual: Bool) {
        guard session == nil else { return }
        do {
            try sound.start()
        } catch {
            message = "无法启动声音：\(error.localizedDescription)"
            return
        }
        stopPreview()
        session = SleepSession(start: Date())
        firstTurnCount = client.status?.behavior?.turnCount
        quietSince = nil
        activeSince = nil
        awaySince = nil
        cooldownUntil = .distantPast
        setLevel(preset.startLevel, over: 10)
        phase = .soothing
        message = manual ? "已开始，今晚好好睡" : "检测到你躺下了，已自动开始助眠"
        if client.status?.behavior?.state == "STOPPED" {
            Task { await client.command("BEHAVIOR_START") }
        }
    }

    func endSession() {
        guard var s = session else { return }
        s.end = Date()
        if s.duration > 120 {
            sessions.insert(s, at: 0)
            SessionStore.save(sessions)
        }
        session = nil
        phase = .idle
        presentSince = nil
        setLevel(0, over: 3)
        stopSoundLater(after: 3.5)
        message = "已结束，报告已保存"
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        SessionStore.save(sessions)
    }

    // MARK: 试听

    func preview() {
        guard session == nil else { return }
        do { try sound.start() } catch { message = "无法启动声音"; return }
        previewing = true
        sound.ramp(to: preset.startLevel, over: 2)
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.stopPreview()
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        guard previewing else { return }
        previewing = false
        guard session == nil else { return }
        sound.ramp(to: 0, over: 1.5)
        stopSoundLater(after: 2)
    }

    private func stopSoundLater(after seconds: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.session == nil, !self.previewing else { return }
            self.sound.stop()
        }
    }

    // MARK: 闭环

    private func setLevel(_ value: Float, over seconds: Double) {
        level = max(0, min(1, value))
        sound.ramp(to: level, over: seconds)
    }

    private func tick(_ s: PillowStatus) {
        let now = Date()
        let dt = min(5, now.timeIntervalSince(lastTick ?? now))
        lastTick = now
        let act = Activity(s)

        // 连续状态计时
        if act == .quiet { quietSince = quietSince ?? now } else { quietSince = nil }
        if act == .active { activeSince = activeSince ?? now } else { activeSince = nil }
        if act == .away { awaySince = awaySince ?? now; presentSince = nil } else { awaySince = nil; presentSince = presentSince ?? now }

        // 自动开始：有人躺下并持续 20 秒
        guard session != nil else {
            if autoStart, act != .away, let p = presentSince, now.timeIntervalSince(p) >= 20 {
                startSession(manual: false)
            }
            return
        }

        record(s, act, dt: dt)

        let quietFor = quietSince.map { now.timeIntervalSince($0) } ?? 0
        let activeFor = activeSince.map { now.timeIntervalSince($0) } ?? 0
        let awayFor = awaySince.map { now.timeIntervalSince($0) } ?? 0
        let wait = preset.quietWaitMinutes * 60

        // 离枕两分钟：暂停；离枕 30 分钟且之前睡着过：自动结束
        if awayFor >= 120 && phase != .away {
            phase = .away
            session?.awayCount += 1
            setLevel(0, over: 5)
            return
        }
        if phase == .away {
            if awayFor >= 1800 && session?.sleepOnsetSeconds != nil { endSession(); return }
            if act != .away {
                phase = .reassist
                setLevel(preset.minLevel, over: 8)
                lastStep = now
                session?.interventions += 1
            }
            return
        }

        switch phase {
        case .soothing, .reassist:
            if quietFor >= wait {
                phase = .fading
                lastStep = now
            } else if phase == .reassist, now.timeIntervalSince(lastStep) >= stepInterval, level < preset.capLevel {
                setLevel(min(preset.capLevel, level + stepSize), over: 8)
                lastStep = now
            }
        case .fading:
            if activeFor >= 45 {
                phase = .reassist
                lastStep = now
            } else if now.timeIntervalSince(lastStep) >= stepInterval {
                lastStep = now
                if level > preset.minLevel + 0.001 {
                    setLevel(max(preset.minLevel, level - stepSize), over: 8)
                } else if quietFor >= wait + 300 {
                    // 在最低音量又安静了 5 分钟：判定入睡，淡出停止
                    setLevel(0, over: 60)
                    phase = .asleep
                    if session?.sleepOnsetSeconds == nil, let q = quietSince, let start = session?.start {
                        session?.sleepOnsetSeconds = q.timeIntervalSince(start)
                    }
                }
            }
        case .asleep:
            if activeFor >= 60 && now >= cooldownUntil {
                phase = .reassist
                cooldownUntil = now.addingTimeInterval(preset.cooldownMinutes * 60)
                session?.interventions += 1
                setLevel(preset.minLevel, over: 15)
                lastStep = now
            }
        case .idle, .away:
            break
        }
    }

    private func record(_ s: PillowStatus, _ act: Activity, dt: Double) {
        guard var ss = session else { return }
        let t1 = Date().timeIntervalSince(ss.start)
        if act != .away { ss.inBedSeconds += dt }
        if act == .quiet { ss.quietSeconds += dt }
        if act == .active { ss.activeSeconds += dt }
        if act != .unknown { ss.add(act, from: max(0, t1 - dt), to: t1) }
        let pose = Pose(raw: s.posture?.pose, reversed: reverseLR)
        if pose != .empty { ss.poseSeconds[pose.rawValue, default: 0] += dt }
        if let rate = s.respiration?.rateBpm, rate > 4, rate < 40 {
            ss.respSum += rate
            ss.respCount += 1
        }
        if let tc = s.behavior?.turnCount {
            if firstTurnCount == nil { firstTurnCount = tc }
            ss.turns = max(0, tc - (firstTurnCount ?? tc))
        }
        session = ss
    }
}

enum SessionStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sessions.json")
    }

    static func load() -> [SleepSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([SleepSession].self, from: data)) ?? []
    }

    static func save(_ sessions: [SleepSession]) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(sessions) { try? data.write(to: url, options: .atomic) }
    }
}
