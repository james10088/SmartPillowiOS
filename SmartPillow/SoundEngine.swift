import AVFoundation

/// 实时生成助眠噪声，不依赖音频文件。音量在音频线程里逐采样平滑过渡，避免爆音。
/// 只要引擎在运行（哪怕音量为 0），App 就能在锁屏后继续工作、继续轮询枕头。
final class SoundEngine {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case pink, brown, ocean, white
        var id: String { rawValue }
        var name: String {
            switch self {
            case .pink: return "粉噪音"
            case .brown: return "棕噪音"
            case .ocean: return "海浪"
            case .white: return "白噪音"
            }
        }
    }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private(set) var isRunning = false

    // 以下字段由音频线程读取
    private var kindCode: Int = 0
    private var targetGain: Float = 0
    private var currentGain: Float = 0
    private var gainStep: Float = 0.0001
    private var sampleRate: Double = 44_100

    // 噪声发生器状态
    private var seed: UInt32 = 0x9E3779B9
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0
    private var phase: Double = 0

    var kind: Kind = .pink {
        didSet { kindCode = Kind.allCases.firstIndex(of: kind) ?? 0 }
    }

    var level: Float { targetGain }

    private var observers: [NSObjectProtocol] = []

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
    }

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers：不会打断用户正在听的音乐；后台播放依然有效
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let output = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = output.sampleRate > 0 ? output.sampleRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        let node = AVAudioSourceNode { [unowned self] isSilence, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            // 待命或已淡出（音量为 0）时直接填静音，不逐个采样计算，整夜待命几乎不占 CPU
            if self.currentGain <= 0 && self.targetGain <= 0 {
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                isSilence.pointee = true
                return noErr
            }
            for frame in 0..<Int(frameCount) {
                let s = self.nextSample()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.detach(node)
            throw error
        }
        source = node
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
        isRunning = false
        currentGain = 0
        targetGain = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 在 seconds 秒内把音量平滑过渡到 level（0...1）。
    func ramp(to level: Float, over seconds: Double) {
        let clamped = max(0, min(1, level))
        let frames = max(1, seconds * sampleRate)
        gainStep = max(0.000_001, abs(clamped - currentGain) / Float(frames))
        targetGain = clamped
    }

    // MARK: 音频线程

    private func white() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    private func nextSample() -> Float {
        if currentGain < targetGain {
            currentGain = min(targetGain, currentGain + gainStep)
        } else if currentGain > targetGain {
            currentGain = max(targetGain, currentGain - gainStep)
        }
        if currentGain <= 0 { return 0 }

        let w = white()
        var out: Float
        switch kindCode {
        case 0: // 粉噪音（Paul Kellet 滤波）
            b0 = 0.99886 * b0 + w * 0.0555179
            b1 = 0.99332 * b1 + w * 0.0750759
            b2 = 0.96900 * b2 + w * 0.1538520
            b3 = 0.86650 * b3 + w * 0.3104856
            b4 = 0.55000 * b4 + w * 0.5329522
            b5 = -0.7616 * b5 - w * 0.0168980
            out = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11
            b6 = w * 0.115926
        case 1: // 棕噪音
            brown = (brown + 0.02 * w) / 1.02
            out = brown * 3.5
        case 2: // 海浪：棕噪音加 9 秒周期的起伏
            brown = (brown + 0.02 * w) / 1.02
            phase += 2 * Double.pi / (sampleRate * 9)
            if phase > 2 * Double.pi { phase -= 2 * Double.pi }
            let swell = Float(0.25 + 0.75 * (0.5 + 0.5 * sin(phase)))
            out = brown * 3.5 * swell
        default:
            out = w * 0.5
        }
        return out * currentGain * 0.7
    }
}
