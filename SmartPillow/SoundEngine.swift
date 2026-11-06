import AVFoundation
import MediaPlayer
import SwiftUI

/// 助眠 / 唤醒的声音来源。
enum SoundSource: Hashable {
    /// App 实时合成的音景
    case scene(Synth.Scene)
    /// 自己导入的音频文件（Documents/Sounds 里的文件名）
    case file(String)
    /// 在 B 站、网易云等其他 App 里播放，这里只通过系统音量帮你渐弱
    case external

    init(key: String) {
        if key == "external" {
            self = .external
        } else if key.hasPrefix("file:") {
            self = .file(String(key.dropFirst(5)))
        } else if key.hasPrefix("scene:"), let raw = Int(key.dropFirst(6)), let s = Synth.Scene(rawValue: raw) {
            self = .scene(s)
        } else {
            self = .scene(.ambient)
        }
    }

    var key: String {
        switch self {
        case .scene(let s): return "scene:\(s.rawValue)"
        case .file(let name): return "file:\(name)"
        case .external: return "external"
        }
    }

    var name: String {
        switch self {
        case .scene(let s): return s.name
        case .file(let name): return (name as NSString).deletingPathExtension
        case .external: return "外部 App"
        }
    }
}

/// 导入的音频文件。
struct ImportedSound: Identifiable, Hashable {
    let fileName: String
    var id: String { fileName }
    var title: String { (fileName as NSString).deletingPathExtension }
}

enum SoundLibrary {
    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for name: String) -> URL? {
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func list() -> [ImportedSound] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { ImportedSound(fileName: $0) }
    }

    /// 复制到 App 里，并确认系统能解码；不能播放的文件会被删掉并报错。
    static func importFile(_ src: URL) throws -> ImportedSound {
        let access = src.startAccessingSecurityScopedResource()
        defer { if access { src.stopAccessingSecurityScopedResource() } }
        let base = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        var dest = folder.appendingPathComponent(src.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        try FileManager.default.copyItem(at: src, to: dest)
        do {
            _ = try AVAudioFile(forReading: dest)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return ImportedSound(fileName: dest.lastPathComponent)
    }

    static func delete(_ sound: ImportedSound) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(sound.fileName))
    }
}

/// 调节系统音量（用于给其他 App 的声音渐弱、早上把音量提上来）。
/// 依赖界面里一个几乎透明的 MPVolumeView，见 `SystemVolumeHost`。
final class SystemVolume {
    static let shared = SystemVolume()

    let view: MPVolumeView = {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        v.alpha = 0.01
        v.isUserInteractionEnabled = false
        return v
    }()

    private var lastSet: Float = -1

    var current: Float { AVAudioSession.sharedInstance().outputVolume }

    func set(_ value: Float) {
        let v = max(0, min(1, value))
        guard abs(v - lastSet) >= 0.006 else { return }
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        lastSet = v
        slider.setValue(v, animated: false)
    }

    func ensureAtLeast(_ value: Float) {
        if current < value { set(value) }
    }
}

struct SystemVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { SystemVolume.shared.view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// 声音引擎：合成音景和导入的音频都走同一个混音器，音量在主线程平滑过渡。
/// 只要引擎在运行（哪怕音量为 0），App 锁屏后也能继续工作、继续轮询枕头。
final class SoundEngine {
    private let engine = AVAudioEngine()
    private var synth = Synth(sampleRate: 48_000)
    private var sourceNode: AVAudioSourceNode?
    private let player = AVAudioPlayerNode()
    private var playerAttached = false
    private var playGeneration = 0
    private(set) var isRunning = false
    private(set) var source: SoundSource = .scene(.ambient)

    /// 当前音量（0...1，过渡中的实时值）
    private(set) var level: Float = 0
    private var rampFrom: Float = 0
    private var rampTo: Float = 0
    private var rampStart = Date()
    private var rampDuration: Double = 0.05
    private var timer: Timer?

    /// 外部 App 模式：开始时的系统音量，以及它对应的助眠音量
    private var externalBase: Float = 0.5
    private var externalRef: Float = 0.5

    private var observers: [NSObjectProtocol] = []
    private var remoteReady = false
    /// 锁屏界面上按了暂停
    var onRemoteStop: (() -> Void)?

    init() {
        let nc = NotificationCenter.default
        // 连接或断开蓝牙音箱时引擎会被系统停掉，这里自动重启
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restartIfNeeded()
        })
        // 来电、闹钟等打断结束后恢复
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.restartIfNeeded()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func restartIfNeeded() {
        guard isRunning, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
        if case .file = source, rampTo > 0 || level > 0 { player.play() }
    }

    // MARK: 启停

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers：不打断你在 B 站等 App 里放的声音；后台播放依然有效
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let out = engine.outputNode.inputFormat(forBus: 0)
        let sr = out.sampleRate > 0 ? out.sampleRate : 48_000
        if synth.sampleRate != Float(sr) { synth = Synth(sampleRate: Float(sr)) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return }

        let s = synth
        let node = AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            s.render(left, right, Int(frameCount))
            if !s.active { isSilence.pointee = true }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        if !playerAttached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playerAttached = true
        }
        engine.mainMixerNode.outputVolume = 0
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.detach(node)
            throw error
        }
        sourceNode = node
        isRunning = true
        level = 0
        rampTo = 0
        applySource()
    }

    func stop() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        playGeneration += 1
        player.stop()
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        isRunning = false
        level = 0
        rampTo = 0
        synth.active = false
        showNowPlaying(nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 早上叫醒时独占音频：成为“正在播放”的 App，锁屏能看到并能按暂停；也会让别的 App 停下来。
    func setExclusive(_ on: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: on ? [] : [.mixWithOthers])
        if isRunning { try? session.setActive(true) }
    }

    // MARK: 来源

    func setSource(_ s: SoundSource) {
        guard s != source else { return }
        source = s
        if isRunning { applySource() }
    }

    /// 外部 App 模式开始：记下此刻的系统音量，作为 `ref` 这个助眠音量对应的“原音量”。
    func beginExternal(ref: Float) {
        externalBase = max(0.05, SystemVolume.shared.current)
        externalRef = max(0.05, ref)
    }

    /// 外部 App 模式结束：把系统音量还给你。
    func restoreExternalVolume() {
        SystemVolume.shared.set(externalBase)
    }

    var externalOriginalVolume: Float { externalBase }

    private func applySource() {
        playGeneration += 1
        switch source {
        case .scene(let sc):
            player.stop()
            synth.requested = sc.rawValue
        case .file(let name):
            player.stop()
            if let url = SoundLibrary.url(for: name) { playFile(url) }
        case .external:
            player.stop()
        }
        updateActivity()
        apply(level)
    }

    private func playFile(_ url: URL) {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        let gen = playGeneration
        scheduleLoop(file, gen)
        if level > 0 || rampTo > 0 { player.play() }
    }

    private func scheduleLoop(_ file: AVAudioFile, _ gen: Int) {
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.playGeneration == gen, self.isRunning else { return }
                file.framePosition = 0
                self.scheduleLoop(file, gen)
            }
        }
    }

    // MARK: 音量

    /// 在 seconds 秒内把音量平滑过渡到 target（0...1）。
    func ramp(to target: Float, over seconds: Double) {
        rampFrom = level
        rampTo = max(0, min(1, target))
        rampStart = Date()
        rampDuration = max(0.05, seconds)
        updateActivity()
        if timer == nil {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.stepRamp() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    var target: Float { rampTo }

    private func stepRamp() {
        let x = min(1, Date().timeIntervalSince(rampStart) / rampDuration)
        let e = Float(x * x * (3 - 2 * x))
        apply(rampFrom + (rampTo - rampFrom) * e)
        if x >= 1 {
            timer?.invalidate()
            timer = nil
            updateActivity()
        }
    }

    private func apply(_ v: Float) {
        level = v
        guard isRunning else { return }
        switch source {
        case .external:
            engine.mainMixerNode.outputVolume = 0
            SystemVolume.shared.set(externalBase * min(1, v / externalRef))
        default:
            // 人耳对音量的感受接近对数，这里用幂曲线，让“降 10%”听起来也是均匀的一小步
            engine.mainMixerNode.outputVolume = pow(v, 1.7)
        }
    }

    private func updateActivity() {
        let audible = level > 0.0005 || rampTo > 0
        if case .scene = source {
            synth.active = audible
        } else {
            synth.active = false
        }
        if case .file = source, isRunning {
            if audible {
                if !player.isPlaying { player.play() }
            } else {
                player.pause()
            }
        }
    }

    // MARK: 锁屏信息

    func showNowPlaying(_ title: String?) {
        let center = MPRemoteCommandCenter.shared()
        guard let title else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        if !remoteReady {
            remoteReady = true
            let handler: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
                DispatchQueue.main.async { self?.onRemoteStop?() }
                return .success
            }
            center.pauseCommand.addTarget(handler: handler)
            center.stopCommand.addTarget(handler: handler)
            center.togglePlayPauseCommand.addTarget(handler: handler)
        }
        center.pauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "智能枕头",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }
}
