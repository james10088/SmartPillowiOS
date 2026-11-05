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
    @Published var autoStart: Bool {
        didSet {
            save()
            if autoStart { ensureStandby() } else if session == nil && !previewing { sound.stop(); standby = false }
        }
    }
    /// 待命：引擎以 0 音量运行，让 App 锁屏后仍能轮询枕头、在你躺下时自动开始。
    @Published private(set) var standby = false
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
    private var messageTask: Task<Void, Never>?
    private var soothingSince: Date?
    /// 只有看到过一次“离枕”才允许自动开始，避免手动结束后人还躺着又被自动开启。
    private var armed = false

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
        // 截图用：启动参数 `-seedDemo YES` 时填入 7 晚示例报告（只在内存里，不保存）
        if d.bool(forKey: "seedDemo") && sessions.isEmpty { sessions = SleepSession.sampleNights() }
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

    func ensureStandby() {
        // 截图模式（启动参数 -uiScreen）只为看界面，不开后台音频
        guard UserDefaults.standard.string(forKey: "uiScreen") == nil else { return }
        guard autoStart, session == nil, !sound.isRunning else { return }
        do {
            try sound.start()
            standby = true
        } catch {
            standby = false
        }
    }

    private func flash(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, self?.message == text else { return }
            self?.message = nil
        }
    }

    // MARK: 开始 / 结束

    func startSession(manual: Bool) {
        guard session == nil else { return }
        do {
            try sound.start()
        } catch {
            flash("无法启动声音：\(error.localizedDescription)")
            return
        }
        stopPreview()
        standby = false
        armed = false
        soothingSince = Date()
        session = SleepSession(start: Date())
        firstTurnCount = client.status?.behavior?.turnCount
        quietSince = nil
        activeSince = nil
        awaySince = nil
        cooldownUntil = .distantPast
        setLevel(preset.startLevel, over: 10)
        phase = .soothing
        flash(manual ? "已开始，今晚好好睡" : "检测到你躺下了，已自动开始助眠")
        if client.status?.behavior?.state == "STOPPED" {
            Task { await client.command("BEHAVIOR_START") }
        }
    }

    func endSession() {
        guard var s = session else { return }
        s.end = Date()
        let saved = s.duration > 120
        if saved {
            sessions.insert(s, at: 0)
            SessionStore.save(sessions)
        }
        session = nil
        phase = .idle
        presentSince = nil
        armed = false
        setLevel(0, over: 3)
        stopSoundLater(after: 3.5)
        flash(saved ? "已结束，报告已保存" : "记录不到 2 分钟，没有生成报告")
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        SessionStore.save(sessions)
    }

    // MARK: 试听

    func preview() {
        guard session == nil else { return }
        do { try sound.start() } catch { flash("无法启动声音"); return }
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
            if self.autoStart {
                self.standby = true      // 保持 0 音量运行，继续待命
            } else {
                self.sound.stop()
                self.standby = false
            }
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

        if act == .away { armed = true }

        // 自动开始：枕头空过之后，有人躺下并持续 20 秒（还没走完首次引导时不自动开始）
        guard session != nil else {
            if autoStart, armed, UserDefaults.standard.bool(forKey: "onboarded"), act != .away, let p = presentSince, now.timeIntervalSince(p) >= 20 {
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
            // 一直没稳定安静（例如状态识别不准）时，45 分钟后也开始渐弱，不让声音整夜响着
            let tooLong = phase == .soothing && now.timeIntervalSince(soothingSince ?? now) >= 45 * 60
            if quietFor >= wait || tooLong {
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

extension AssistEngine {
    /// 最近 7 晚的平均开始时间，例如 "23:15"；不足 2 晚时返回 nil。
    var usualBedtime: String? {
        let recent = sessions.prefix(7)
        guard recent.count >= 2 else { return nil }
        let cal = Calendar.current
        // 以中午 12 点为界，把凌晨的时间算到前一天之后，避免 23:50 和 00:10 平均成中午
        let minutes = recent.map { s -> Int in
            let c = cal.dateComponents([.hour, .minute], from: s.start)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            return m < 12 * 60 ? m + 24 * 60 : m
        }
        let avg = (minutes.reduce(0, +) / minutes.count) % (24 * 60)
        let rounded = (avg + 2) / 5 * 5 % (24 * 60)
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }

    /// 连续有记录的晚数（以入睡那天算，允许今晚还没开始）。
    var streak: Int {
        let cal = Calendar.current
        func nightOf(_ d: Date) -> Date { cal.startOfDay(for: d.addingTimeInterval(-12 * 3600)) }
        let nights = Set(sessions.map { nightOf($0.start) })
        var day = nightOf(Date())
        if !nights.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while nights.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
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
