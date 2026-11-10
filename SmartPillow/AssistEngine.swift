import Combine
import Foundation

/// 主动助眠闭环：监测 → 判断 → 干预 → 动态调节 → 自动退出 → 夜醒再助眠 → 早上渐强唤醒。
/// 每次收到枕头状态（约 1.5 秒）调用一次 tick；闹钟另有独立计时器，枕头离线也会响。
@MainActor
final class AssistEngine: ObservableObject {
    enum Phase: String {
        case idle, soothing, fading, asleep, reassist, away, waking

        var label: String {
            switch self {
            case .idle: return "等待入睡"
            case .soothing: return "助眠中"
            case .fading: return "安静了，音量慢慢变轻"
            case .asleep: return "已入睡，声音已停止"
            case .reassist: return "夜间醒来，轻声陪伴"
            case .away: return "已离枕，声音暂停"
            case .waking: return "早上好，音乐正慢慢变大"
            }
        }
    }

    /// 前几晚的学习期：请手动开始，帮枕头熟悉你的睡姿和作息
    static let learningNights = 3

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var session: SleepSession?
    @Published private(set) var message: String?
    @Published var preset: AssistPreset { didSet { save() } }
    @Published var soundSource: SoundSource {
        didSet {
            save()
            sourceChanged(from: oldValue)
        }
    }
    /// 开始助眠时的音量（0.1...1），渐弱和夜间调回都按它的比例算
    @Published var startLevel: Float {
        didSet {
            save()
            if previewing { sound.ramp(to: startLevel, over: 0.3) }
        }
    }
    @Published var autoStart: Bool {
        didSet {
            save()
            refreshStandby()
        }
    }
    @Published var alarm: AlarmSettings {
        didSet {
            alarm.save()
            rescheduleAlarm(startStandby: true)
        }
    }
    /// 待命：引擎以 0 音量运行，让 App 锁屏后仍能轮询枕头、在你躺下时自动开始、早上按时叫醒。
    @Published private(set) var standby = false
    @Published private(set) var waking = false
    @Published var reverseLR: Bool { didSet { save() } }
    @Published private(set) var sessions: [SleepSession] = []
    @Published private(set) var previewing = false
    @Published private(set) var imported: [ImportedSound] = []

    let client: PillowClient
    private let sound = SoundEngine()
    private let screenshotMode = UserDefaults.standard.string(forKey: "uiScreen") != nil

    // 计时
    private var lastTick: Date?
    private var presentSince: Date?
    private var quietSince: Date?
    private var activeSince: Date?
    private var awaySince: Date?
    private var lastMotion: Date?
    private var cooldownUntil = Date.distantPast
    private var level: Float = 0
    private var fadeStart: Date?
    private var fadeFrom: Float = 0
    private var reassistStart: Date?
    private var firstTurnCount: Int?
    private var lastTurnCount: Int?
    private var previewTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var soothingSince: Date?
    /// 只有看到过一次“离枕”才允许自动开始，避免手动结束后人还躺着又被自动开启。
    private var armed = false

    /// 演示模式里显示的示例报告（只在内存里，不写进你的真实记录）
    private var demoIDs = Set<UUID>()
    private var bag = Set<AnyCancellable>()

    // 闹钟
    private var alarmTarget: Date?
    private var alarmTimer: Timer?
    private var wakeStartedAt: Date?

    init(client: PillowClient) {
        self.client = client
        let d = UserDefaults.standard
        preset = AssistPreset(rawValue: d.string(forKey: "preset") ?? "") ?? .standard
        soundSource = SoundSource(key: d.string(forKey: "soundSource") ?? "")
        startLevel = d.object(forKey: "startLevel") as? Float ?? 0.5
        autoStart = d.object(forKey: "autoStart") as? Bool ?? true
        alarm = AlarmSettings.load()
        reverseLR = d.bool(forKey: "reverseLR")
        sessions = SessionStore.load()
        imported = SoundLibrary.list()
        // 截图用：启动参数 `-seedDemo YES` 时填入 7 晚示例报告（只在内存里，不保存）
        if d.bool(forKey: "seedDemo") && sessions.isEmpty { showDemoNights(true) }
        if case .file(let name) = soundSource, SoundLibrary.url(for: name) == nil { soundSource = .scene(.ambient) }
        sound.setSource(soundSource)
        sound.onRemoteStop = { [weak self] in
            Task { @MainActor in self?.remoteStop() }
        }
        client.onStatus = { [weak self] s in self?.tick(s) }
        // 打开演示模式时，没有真实记录就放 7 晚示例报告；关掉演示就收回
        client.$demo
            .removeDuplicates()
            .sink { [weak self] on in self?.showDemoNights(on) }
            .store(in: &bag)
        rescheduleAlarm(startStandby: false)
        if !screenshotMode {
            let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkAlarm() }
            }
            RunLoop.main.add(t, forMode: .common)
            alarmTimer = t
        }
    }

    /// 演示模式开关变化时调用（重复调用无副作用）。
    func showDemoNights(_ on: Bool) {
        if on {
            guard sessions.isEmpty else { return }
            let samples = SleepSession.sampleNights()
            demoIDs = Set(samples.map(\.id))
            sessions = samples
        } else if !demoIDs.isEmpty {
            sessions.removeAll { demoIDs.contains($0.id) }
            demoIDs = []
        }
    }

    /// 保存记录时去掉示例报告
    private func persistSessions() {
        SessionStore.save(sessions.filter { !demoIDs.contains($0.id) })
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(preset.rawValue, forKey: "preset")
        d.set(soundSource.key, forKey: "soundSource")
        d.set(startLevel, forKey: "startLevel")
        d.set(autoStart, forKey: "autoStart")
        d.set(reverseLR, forKey: "reverseLR")
    }

    var levelPercent: Int { Int((level * 100).rounded()) }
    var floorLevel: Float { startLevel * preset.floorRatio }
    var capLevel: Float { startLevel * preset.capRatio }
    /// 还在学习期（记录不足 3 晚）
    var isLearning: Bool { sessions.count < AssistEngine.learningNights }

    private var needsStandby: Bool { autoStart || alarm.enabled }

    func ensureStandby() {
        // 截图模式（启动参数 -uiScreen）只为看界面，不开后台音频
        guard !screenshotMode, needsStandby, session == nil, !sound.isRunning else { return }
        do {
            try sound.start()
            standby = true
        } catch {
            standby = false
        }
    }

    private func refreshStandby() {
        if needsStandby {
            ensureStandby()
        } else if session == nil && !previewing && !waking {
            sound.stop()
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

    // MARK: 声音来源

    private func sourceChanged(from old: SoundSource) {
        guard !waking, !previewing else { return }
        if session != nil {
            if case .external = old { sound.restoreExternalVolume() }
            if case .external = soundSource { sound.beginExternal(ref: max(level, 0.05)) }
        }
        sound.setSource(soundSource)
    }

    func importSound(from url: URL) {
        do {
            let s = try SoundLibrary.importFile(url)
            imported = SoundLibrary.list()
            soundSource = .file(s.fileName)
            flash("已导入「\(s.title)」")
        } catch {
            flash("这个文件没法播放，换成 mp3、m4a 或 wav 试试")
        }
    }

    func deleteSound(_ s: ImportedSound) {
        if case .file(let name) = soundSource, name == s.fileName { soundSource = .scene(.ambient) }
        if alarm.soundKey == SoundSource.file(s.fileName).key { alarm.soundKey = SoundSource.scene(.morning).key }
        SoundLibrary.delete(s)
        imported = SoundLibrary.list()
    }

    // MARK: 开始 / 结束

    func startSession(manual: Bool) {
        guard session == nil else { return }
        if !screenshotMode {
            do {
                try sound.start()
            } catch {
                flash("无法启动声音：\(error.localizedDescription)")
                return
            }
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
        sound.setSource(soundSource)
        if case .external = soundSource {
            sound.beginExternal(ref: startLevel)
        }
        setLevel(startLevel, over: 10)
        phase = .soothing
        if case .external = soundSource {
            flash(manual ? "已开始。外部 App 的声音会随你入睡慢慢变轻" : "检测到你躺下了，已自动开始记录")
        } else {
            flash(manual ? "已开始，今晚好好睡" : "检测到你躺下了，已自动开始记录")
        }
        if client.status?.behavior?.state == "STOPPED" {
            Task { await client.command("BEHAVIOR_START") }
        }
    }

    func endSession() {
        guard var s = session else { return }
        if waking { finishWake() }
        s.end = Date()
        let saved = s.duration > 120
        if saved {
            sessions.insert(s, at: 0)
            persistSessions()
        }
        if case .external = sound.source { sound.restoreExternalVolume() }
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
        persistSessions()
    }

    // MARK: 试听

    /// 试听一种声音：默认是当前助眠声音、当前起始音量。
    func preview(_ source: SoundSource? = nil, level target: Float? = nil) {
        guard session == nil, !waking else { return }
        let src = source ?? soundSource
        if case .external = src {
            flash("外部 App 的声音请在那个 App 里试听")
            return
        }
        do { try sound.start() } catch { flash("无法启动声音"); return }
        previewing = true
        sound.setSource(src)
        sound.ramp(to: target ?? startLevel, over: 1.5)
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stopPreview()
        }
    }

    func stopPreview() {
        previewTask?.cancel()
        guard previewing else { return }
        previewing = false
        guard session == nil, !waking else { return }
        sound.ramp(to: 0, over: 1.2)
        stopSoundLater(after: 1.5)
    }

    private func stopSoundLater(after seconds: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.session == nil, !self.previewing, !self.waking else { return }
            self.sound.setSource(self.soundSource)
            if self.needsStandby {
                self.standby = true      // 保持 0 音量运行，继续待命
            } else {
                self.sound.stop()
                self.standby = false
            }
        }
    }

    // MARK: 闹钟

    private func rescheduleAlarm(startStandby: Bool) {
        alarmTarget = alarm.enabled ? alarm.next() : nil
        guard !screenshotMode else { return }
        if let t = alarmTarget {
            if UserDefaults.standard.bool(forKey: "onboarded") { AlarmNotifier.requestPermission() }
            AlarmNotifier.schedule(at: t)
        } else {
            AlarmNotifier.cancel()
        }
        if startStandby { refreshStandby() }
    }

    private func checkAlarm() {
        let now = Date()
        if waking {
            // 叫了一小时没人理，就停下
            if let w = wakeStartedAt, now.timeIntervalSince(w) > 3600 { stopWake() }
            return
        }
        guard alarm.enabled, let target = alarmTarget else { return }
        if now > target.addingTimeInterval(3600) {
            rescheduleAlarm(startStandby: false)
            return
        }
        let latestStart = target.addingTimeInterval(-Double(alarm.rampMinutes) * 60)
        let windowStart = target.addingTimeInterval(-Double(alarm.windowMinutes) * 60)
        let lightSleep = lastMotion.map { now.timeIntervalSince($0) < 90 } ?? false
        if now >= latestStart || (now >= windowStart && lightSleep && session != nil) {
            startWake()
        }
    }

    private func startWake() {
        guard !waking else { return }
        if !sound.isRunning {
            do { try sound.start() } catch { return }
        }
        stopPreview()
        previewing = false
        waking = true
        wakeStartedAt = Date()
        AlarmNotifier.cancel()
        if case .external = sound.source { sound.restoreExternalVolume() }
        sound.setExclusive(true)
        let src = SoundSource(key: alarm.soundKey)
        if case .external = src {
            sound.setSource(.scene(.morning))
        } else {
            sound.setSource(src)
        }
        // 手机音量太小会听不见，提到一个能听清的下限
        SystemVolume.shared.ensureAtLeast(0.4)
        phase = .waking
        level = 0
        setLevel(0.8, over: Double(alarm.rampMinutes) * 60)
        sound.showNowPlaying("早上好 · 正在轻轻叫醒你")
        flash("早上好，正在轻轻叫醒你")
    }

    /// “我醒了”：停止闹钟；有记录就一起结束并保存报告。
    func stopWake() {
        guard waking else { return }
        if session != nil {
            endSession()
        } else {
            finishWake()
            phase = .idle
            setLevel(0, over: 2)
            stopSoundLater(after: 2.5)
        }
    }

    private func finishWake() {
        waking = false
        wakeStartedAt = nil
        sound.showNowPlaying(nil)
        sound.setExclusive(false)
        // 下一次闹钟从这次闹钟时间之后算，避免提前叫醒后又在原时间再响
        let after = (alarmTarget ?? Date()).addingTimeInterval(60)
        alarmTarget = alarm.enabled ? alarm.next(after: max(after, Date())) : nil
        if let t = alarmTarget, !screenshotMode { AlarmNotifier.schedule(at: t) }
    }

    private func remoteStop() {
        if waking {
            stopWake()
        } else if session != nil {
            setLevel(0, over: 2)
            flash("已在锁屏上暂停声音")
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
        if act == .active { activeSince = activeSince ?? now; lastMotion = now } else { activeSince = nil }
        if act == .away { awaySince = awaySince ?? now; presentSince = nil } else { awaySince = nil; presentSince = presentSince ?? now }
        if let tc = s.behavior?.turnCount {
            if let last = lastTurnCount, tc != last { lastMotion = now }
            lastTurnCount = tc
        }

        if act == .away { armed = true }

        checkAlarm()

        // 自动开始：枕头空过之后，有人躺下并持续 20 秒（还没走完首次引导时不自动开始）
        guard session != nil else {
            if autoStart, !waking, armed, UserDefaults.standard.bool(forKey: "onboarded"), act != .away,
               let p = presentSince, now.timeIntervalSince(p) >= 20 {
                startSession(manual: false)
            }
            return
        }

        record(s, act, dt: dt)

        let quietFor = quietSince.map { now.timeIntervalSince($0) } ?? 0
        let activeFor = activeSince.map { now.timeIntervalSince($0) } ?? 0
        let awayFor = awaySince.map { now.timeIntervalSince($0) } ?? 0
        let wait = preset.quietWaitMinutes * 60

        // 叫醒中：起床离枕一分半钟，就当你已经起来了
        if phase == .waking {
            if awayFor >= 90 { stopWake() }
            return
        }

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
                beginReassist(now)
                session?.interventions += 1
            }
            return
        }

        switch phase {
        case .soothing:
            // 一直没稳定安静（例如状态识别不准）时，45 分钟后也开始渐弱，不让声音整夜响着
            let tooLong = now.timeIntervalSince(soothingSince ?? now) >= 45 * 60
            if quietFor >= wait || tooLong { beginFade(now) }
        case .reassist:
            if quietFor >= wait {
                beginFade(now)
            } else {
                // 两分钟内平滑回到上限，不再一档一档往上加
                let x = min(1, now.timeIntervalSince(reassistStart ?? now) / 120)
                setLevel(floorLevel + (capLevel - floorLevel) * Float(x), over: 3)
            }
        case .fading:
            if activeFor >= 45 {
                beginReassist(now)
                break
            }
            let x = min(1, now.timeIntervalSince(fadeStart ?? now) / (preset.fadeMinutes * 60))
            let e = Float(x * x * (3 - 2 * x))
            setLevel(fadeFrom + (floorLevel - fadeFrom) * e, over: 3)
            if x >= 1 && quietFor >= wait + 300 {
                // 降到最低后又安静了 5 分钟：判定入睡，一分半钟淡出到无声
                setLevel(0, over: 90)
                phase = .asleep
                if session?.sleepOnsetSeconds == nil, let q = quietSince, let start = session?.start {
                    session?.sleepOnsetSeconds = q.timeIntervalSince(start)
                }
                pauseExternalAfterFade()
            }
        case .asleep:
            if activeFor >= 60 && now >= cooldownUntil {
                cooldownUntil = now.addingTimeInterval(preset.cooldownMinutes * 60)
                session?.interventions += 1
                beginReassist(now)
            }
        case .idle, .away, .waking:
            break
        }
    }

    private func beginFade(_ now: Date) {
        phase = .fading
        fadeStart = now
        fadeFrom = level
    }

    private func beginReassist(_ now: Date) {
        phase = .reassist
        reassistStart = now
        setLevel(max(level, floorLevel), over: 15)
    }

    /// 外部 App 模式：淡出到无声后，让 B 站等 App 暂停，再把系统音量还回去；
    /// 夜里醒来时改用内置的「星河」陪你，因为没法替你让别的 App 继续播放。
    private func pauseExternalAfterFade() {
        guard case .external = sound.source else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 95_000_000_000)
            guard let self, self.phase == .asleep, case .external = self.sound.source else { return }
            self.sound.setSource(.scene(.ambient))
            self.sound.setExclusive(true)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.sound.restoreExternalVolume()
            self.sound.setExclusive(false)
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
