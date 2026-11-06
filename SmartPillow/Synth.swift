import Foundation

/// 实时合成的助眠音景。只在音频线程里调用 `render`；主线程只写 `requested` 和 `active`。
/// 每个音景都带随机变化（和弦走向、铃音、雨滴、浪的周期），所以不会听起来是一段固定循环。
final class Synth {
    enum Scene: Int, CaseIterable, Identifiable {
        case ambient = 0, rain, ocean, bowl, pink, morning
        var id: Int { rawValue }

        var name: String {
            switch self {
            case .ambient: return "星河"
            case .rain: return "雨夜"
            case .ocean: return "海浪"
            case .bowl: return "颂钵"
            case .pink: return "粉噪音"
            case .morning: return "晨光"
            }
        }

        var detail: String {
            switch self {
            case .ambient: return "柔和和弦与钢琴"
            case .rain: return "窗外的雨"
            case .ocean: return "远处的浪"
            case .bowl: return "缓慢的钵声"
            case .pink: return "均匀的底噪"
            case .morning: return "明亮和弦与鸟鸣"
            }
        }

        /// 助眠可选的音景（晨光只用于唤醒）
        static let sleepScenes: [Scene] = [.ambient, .rain, .ocean, .bowl, .pink]
        /// 唤醒可选的音景
        static let wakeScenes: [Scene] = [.morning, .ambient, .bowl, .ocean]
    }

    /// 主线程写：想播放的音景（rawValue）
    var requested: Int = 0
    /// 主线程写：false 时直接输出静音，不做任何计算
    var active = false

    let sampleRate: Float
    private var scene = -1
    private var sceneGain: Float = 0
    private let fadeOut: Float
    private let fadeIn: Float

    // MARK: 工具

    private var seed: UInt32 = 0x2545_F491
    @inline(__always) private func rnd() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) * (1.0 / 4_294_967_296.0)
    }
    @inline(__always) private func bip() -> Float { rnd() * 2 - 1 }

    private static let tableSize = 4096
    private let table: UnsafeMutablePointer<Float>

    /// phase 取 0..<1，返回 sin(2π·phase)
    @inline(__always) private func sine(_ phase: Float) -> Float {
        let x = phase * Float(Synth.tableSize)
        let i = Int(x)
        let f = x - Float(i)
        let a = table[i & 4095]
        let b = table[(i + 1) & 4095]
        return a + (b - a) * f
    }

    @inline(__always) private func frac(_ x: Float) -> Float { x - Float(Int(x)) }

    private func coef(_ hz: Float) -> Float { 1 - exp(-2 * Float.pi * hz / sampleRate) }

    private struct Pink {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        mutating func next(_ w: Float) -> Float {
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            return (b0 + b1 + b2 + w * 0.1848) * 0.11
        }
    }

    private struct Delay {
        let buf: UnsafeMutablePointer<Float>
        let len: Int
        var idx = 0
        var store: Float = 0

        init(_ length: Int) {
            len = max(8, length)
            buf = .allocate(capacity: len)
            buf.initialize(repeating: 0, count: len)
        }

        mutating func comb(_ x: Float, _ fb: Float, _ damp: Float) -> Float {
            let y = buf[idx]
            store = y + (store - y) * damp
            buf[idx] = x + store * fb
            idx += 1
            if idx == len { idx = 0 }
            return y
        }

        mutating func allpass(_ x: Float) -> Float {
            let b = buf[idx]
            buf[idx] = x + b * 0.5
            idx += 1
            if idx == len { idx = 0 }
            return b - x
        }
    }

    /// 简化的 Freeverb：6 个梳状滤波 + 3 个全通，左右声道错开，听起来像在一个安静的大房间里。
    private struct Reverb {
        var cl: [Delay], cr: [Delay], al: [Delay], ar: [Delay]

        init(sampleRate: Float) {
            let s = sampleRate / 44_100
            let combs = [1116, 1188, 1277, 1356, 1422, 1491]
            let aps = [556, 441, 341]
            cl = combs.map { Delay(Int(Float($0) * s)) }
            cr = combs.map { Delay(Int(Float($0 + 23) * s)) }
            al = aps.map { Delay(Int(Float($0) * s)) }
            ar = aps.map { Delay(Int(Float($0 + 23) * s)) }
        }

        mutating func process(_ x: Float, fb: Float, damp: Float) -> (Float, Float) {
            let input = x * 0.015
            var l: Float = 0
            var r: Float = 0
            for i in 0..<cl.count {
                l += cl[i].comb(input, fb, damp)
                r += cr[i].comb(input, fb, damp)
            }
            for i in 0..<al.count {
                l = al[i].allpass(l)
                r = ar[i].allpass(r)
            }
            return (l * 3, r * 3)
        }
    }

    private var reverb: Reverb

    // MARK: 星河 / 晨光

    private struct Voice {
        var freq: Float = 0
        var p1: Float = 0
        var p2: Float = 0
        var amp: Float = 0
        var target: Float = 0
        var pan: Float = 0.5
    }

    private struct Bell {
        var freq: Float = 0
        var p: Float = 0
        var amp: Float = 0
        var decay: Float = 1
        var att: Float = 0
        var pan: Float = 0.5
    }

    private struct Chirp {
        var t = 0
        var count = 0
        var len = 1
        var gap = 1
        var f0: Float = 0
        var f1: Float = 0
        var p: Float = 0
        var amp: Float = 0
        var pan: Float = 0.5
    }

    private static let chords: [[Float]] = [
        [146.83, 220.00, 293.66, 369.99], // D
        [123.47, 185.00, 246.94, 293.66], // Bm
        [98.00, 196.00, 246.94, 293.66],  // G
        [110.00, 164.81, 220.00, 277.18], // A
        [82.41, 164.81, 196.00, 246.94],  // Em
    ]
    private static let morningChords: [[Float]] = [
        [293.66, 369.99, 440.00, 587.33],
        [246.94, 329.63, 392.00, 493.88],
        [220.00, 293.66, 369.99, 440.00],
        [196.00, 293.66, 392.00, 493.88],
    ]

    private var pads = [Voice](repeating: Voice(), count: 10)
    private var bells = [Bell](repeating: Bell(), count: 8)
    private var chirp = Chirp()
    private var chordIndex = 0
    private var samplesToChord = 0
    private var samplesToBell = 0
    private var samplesToChirp = 0
    private var lfo: Float = 0
    private let padSmooth: Float
    private let attInc: Float

    // MARK: 雨

    private struct Drop {
        var amp: Float = 0
        var decay: Float = 0
        var pan: Float = 0.5
        var prev: Float = 0
    }

    private var drops = [Drop](repeating: Drop(), count: 40)
    private var rl1: Float = 0, rl2: Float = 0, rlLow: Float = 0
    private var rr1: Float = 0, rr2: Float = 0, rrLow: Float = 0
    private var dropLpL: Float = 0, dropLpR: Float = 0
    private var rainLfo: Float = 0
    private let cRain: Float, cRainLow: Float, cDrop: Float

    // MARK: 海浪 / 粉噪音

    private var wavePhase: Float = 0
    private var waveInc: Float = 0
    private var waveAmp: Float = 0.8
    private var olpL: Float = 0, olpR: Float = 0
    private var oCoef: Float = 0.05
    private var oCounter = 0
    private var pinkL = Pink(), pinkR = Pink()
    private var brownL: Float = 0, brownR: Float = 0
    private var plL: Float = 0, plR: Float = 0
    private let cPink: Float

    // MARK: 颂钵

    private struct Partial {
        var f: Float = 0
        var p1: Float = 0
        var p2: Float = 0
        var amp: Float = 0
        var decay: Float = 1
        var att: Float = 0
    }

    private static let bowlBases: [Float] = [146.83, 164.81, 196.00, 220.00]
    private static let bowlRatios: [Float] = [1, 2.76, 5.40, 8.93]
    private static let bowlAmps: [Float] = [0.16, 0.08, 0.035, 0.015]
    private static let bowlTaus: [Float] = [16, 10, 5, 2.5]
    private var partials = [Partial](repeating: Partial(), count: 12)
    private var samplesToStrike = 0
    private let bowlAtt: Float

    // MARK: 初始化

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let t = UnsafeMutablePointer<Float>.allocate(capacity: Synth.tableSize)
        for i in 0..<Synth.tableSize {
            t[i] = sin(2 * Float.pi * Float(i) / Float(Synth.tableSize))
        }
        table = t
        reverb = Reverb(sampleRate: sampleRate)
        fadeOut = 1 / (0.4 * sampleRate)
        fadeIn = 1 / (1.5 * sampleRate)
        padSmooth = 1 / (3 * sampleRate)
        attInc = 1 / (0.01 * sampleRate)
        bowlAtt = 1 / (0.03 * sampleRate)
        cRain = 1 - exp(-2 * Float.pi * 2800 / sampleRate)
        cRainLow = 1 - exp(-2 * Float.pi * 220 / sampleRate)
        cDrop = 1 - exp(-2 * Float.pi * 5000 / sampleRate)
        cPink = 1 - exp(-2 * Float.pi * 3500 / sampleRate)
        waveInc = 1 / (sampleRate * 10)
        seed = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)) | 1
    }

    // MARK: 渲染

    func render(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>?, _ n: Int) {
        guard active else {
            for i in 0..<n {
                left[i] = 0
                right?[i] = 0
            }
            return
        }
        for i in 0..<n {
            let want = requested
            if want != scene {
                sceneGain -= fadeOut
                if sceneGain <= 0 {
                    sceneGain = 0
                    enter(want)
                }
            } else if sceneGain < 1 {
                sceneGain = min(1, sceneGain + fadeIn)
            }
            var a: Float = 0
            var b: Float = 0
            switch scene {
            case Scene.ambient.rawValue: ambient(&a, &b, morning: false)
            case Scene.rain.rawValue: rain(&a, &b)
            case Scene.ocean.rawValue: ocean(&a, &b)
            case Scene.bowl.rawValue: bowl(&a, &b)
            case Scene.pink.rawValue: pinkScene(&a, &b)
            case Scene.morning.rawValue: ambient(&a, &b, morning: true)
            default: break
            }
            let g = sceneGain * levelOf(scene)
            left[i] = soften(a * g)
            right?[i] = soften(b * g)
        }
    }

    /// 各音景的响度校准：按离线测量结果把平均响度都调到约 -23 dBFS，切换声音时不会忽大忽小。
    private func levelOf(_ s: Int) -> Float {
        switch s {
        case Scene.ambient.rawValue, Scene.morning.rawValue: return 2.0
        case Scene.ocean.rawValue: return 0.5
        case Scene.bowl.rawValue: return 0.9
        case Scene.pink.rawValue: return 0.3
        default: return 1
        }
    }

    /// 柔和限幅：0.6 以下原样输出，以上平滑压到 1 以内，避免硬削波的“啪”声。
    @inline(__always) private func soften(_ x: Float) -> Float {
        let m = abs(x)
        guard m > 0.6 else { return x }
        let y = 0.6 + 0.4 * tanh((m - 0.6) / 0.4)
        return x < 0 ? -y : y
    }

    private func enter(_ s: Int) {
        scene = s
        samplesToChord = 0
        samplesToBell = Int(sampleRate * 1.5)
        samplesToChirp = Int(sampleRate * 3)
        samplesToStrike = Int(sampleRate * 0.3)
        for i in 0..<pads.count { pads[i].amp = 0; pads[i].target = 0 }
        for i in 0..<bells.count { bells[i].amp = 0 }
        for i in 0..<partials.count { partials[i].amp = 0 }
        chirp.count = 0
        wavePhase = 0
        waveInc = 1 / (sampleRate * 10)
    }

    // MARK: 星河 / 晨光

    private func ambient(_ a: inout Float, _ b: inout Float, morning: Bool) {
        if samplesToChord <= 0 {
            nextChord(morning)
            samplesToChord = Int(sampleRate * (14 + 8 * rnd()))
        }
        samplesToChord -= 1
        if samplesToBell <= 0 {
            ringBell(morning)
            samplesToBell = Int(sampleRate * (morning ? 1.2 + 1.8 * rnd() : 2.5 + 4 * rnd()))
        }
        samplesToBell -= 1

        lfo += 0.07 / sampleRate
        if lfo >= 1 { lfo -= 1 }
        let breath: Float = 0.8 + 0.2 * sine(lfo)

        var pl: Float = 0
        var pr: Float = 0
        for i in 0..<pads.count {
            var v = pads[i]
            if v.target == 0 && v.amp < 0.0003 {
                if v.amp != 0 { pads[i].amp = 0 }
                continue
            }
            v.amp += (v.target - v.amp) * padSmooth
            let inc = v.freq / sampleRate
            v.p1 += inc * 1.0012
            if v.p1 >= 1 { v.p1 -= 1 }
            v.p2 += inc * 0.9988
            if v.p2 >= 1 { v.p2 -= 1 }
            let s = (sine(v.p1) + sine(v.p2) + 0.18 * sine(frac(v.p1 * 2))) * v.amp
            pl += s * (1.15 - v.pan)
            pr += s * (0.15 + v.pan)
            pads[i] = v
        }

        var bl: Float = 0
        var br: Float = 0
        for i in 0..<bells.count where bells[i].amp > 0.0002 {
            var bell = bells[i]
            bell.p += bell.freq / sampleRate
            if bell.p >= 1 { bell.p -= 1 }
            let tone = sine(bell.p) + 0.3 * sine(frac(bell.p * 2)) + 0.1 * sine(frac(bell.p * 3))
            let s = tone * bell.amp * min(1, bell.att)
            bell.att += attInc
            bell.amp *= bell.decay
            bl += s * (1.1 - bell.pan)
            br += s * (0.1 + bell.pan)
            bells[i] = bell
        }

        var cl: Float = 0
        var cr: Float = 0
        if morning { chirpSample(&cl, &cr) }

        let dryL = pl * 0.5 * breath + bl
        let dryR = pr * 0.5 * breath + br
        let (wl, wr) = reverb.process((dryL + dryR) * 0.5, fb: 0.86, damp: 0.35)
        a = (dryL + cl) * 0.55 + wl * 0.5
        b = (dryR + cr) * 0.55 + wr * 0.5
    }

    private func nextChord(_ morning: Bool) {
        let set = morning ? Synth.morningChords : Synth.chords
        var next = Int(rnd() * Float(set.count)) % set.count
        if next == chordIndex { next = (next + 1) % set.count }
        chordIndex = next
        for i in 0..<pads.count { pads[i].target = 0 }
        for (k, f) in set[next].enumerated() {
            var slot = 0
            var low = Float.greatestFiniteMagnitude
            for i in 0..<pads.count where pads[i].target == 0 && pads[i].amp < low {
                low = pads[i].amp
                slot = i
            }
            pads[slot] = Voice(freq: f, p1: rnd(), p2: rnd(), amp: 0, target: k == 0 ? 0.13 : 0.1, pan: 0.3 + 0.4 * rnd())
        }
    }

    private func ringBell(_ morning: Bool) {
        let set = morning ? Synth.morningChords : Synth.chords
        let chord = set[chordIndex % set.count]
        var f = chord[Int(rnd() * Float(chord.count)) % chord.count]
        let floor: Float = morning ? 520 : 440
        while f < floor { f *= 2 }
        if rnd() < 0.25 { f *= 2 }
        if f > 1800 { f /= 2 }
        var slot = 0
        var low = Float.greatestFiniteMagnitude
        for i in 0..<bells.count where bells[i].amp < low {
            low = bells[i].amp
            slot = i
        }
        let tau: Float = 1.2 + 1.4 * rnd()
        bells[slot] = Bell(freq: f, p: 0, amp: 0.05 + 0.08 * rnd(), decay: exp(-1 / (sampleRate * tau)), att: 0, pan: 0.2 + 0.6 * rnd())
    }

    private func chirpSample(_ l: inout Float, _ r: inout Float) {
        if samplesToChirp <= 0 {
            chirp = Chirp(t: 0, count: 2 + Int(rnd() * 3), len: Int(sampleRate * 0.07), gap: Int(sampleRate * 0.05),
                          f0: 2600 + 900 * rnd(), f1: 3600 + 1400 * rnd(), p: 0, amp: 0.02 + 0.02 * rnd(), pan: 0.15 + 0.7 * rnd())
            samplesToChirp = Int(sampleRate * (4 + 6 * rnd()))
        }
        samplesToChirp -= 1
        guard chirp.count > 0 else { return }
        let period = chirp.len + chirp.gap
        let k = chirp.t % period
        chirp.t += 1
        if chirp.t >= period * chirp.count {
            chirp.count = 0
            return
        }
        guard k < chirp.len else { return }
        let x = Float(k) / Float(chirp.len)
        let f = chirp.f0 + (chirp.f1 - chirp.f0) * x
        chirp.p += f / sampleRate
        if chirp.p >= 1 { chirp.p -= 1 }
        let s = sine(chirp.p) * sine(x * 0.5) * chirp.amp
        l += s * (1.1 - chirp.pan)
        r += s * (0.1 + chirp.pan)
    }

    // MARK: 雨夜

    private func rain(_ a: inout Float, _ b: inout Float) {
        rainLfo += 0.025 / sampleRate
        if rainLfo >= 1 { rainLfo -= 1 }
        let intensity: Float = 0.75 + 0.25 * sine(rainLfo)

        // 底层的沙沙声：白噪 → 两次低通 → 去掉低频
        let wl = bip()
        let wr = bip()
        rl1 += cRain * (wl - rl1)
        rl2 += cRain * (rl1 - rl2)
        rlLow += cRainLow * (rl2 - rlLow)
        rr1 += cRain * (wr - rr1)
        rr2 += cRain * (rr1 - rr2)
        rrLow += cRainLow * (rr2 - rrLow)
        var l = (rl2 - rlLow) * 0.55 * intensity
        var r = (rr2 - rrLow) * 0.55 * intensity

        // 雨滴：随机出现，大多很轻，偶尔一滴清楚些
        if rnd() < (30 + 40 * intensity) / sampleRate {
            var slot = 0
            var low = Float.greatestFiniteMagnitude
            for i in 0..<drops.count where drops[i].amp < low {
                low = drops[i].amp
                slot = i
            }
            let x = rnd()
            let tau: Float = 0.002 + 0.01 * rnd()
            drops[slot] = Drop(amp: 0.05 + 0.5 * x * x * x, decay: exp(-1 / (sampleRate * tau)), pan: rnd(), prev: 0)
        }
        var dl: Float = 0
        var dr: Float = 0
        for i in 0..<drops.count where drops[i].amp > 0.0005 {
            let n = bip() * drops[i].amp
            let s = n - drops[i].prev
            drops[i].prev = n
            drops[i].amp *= drops[i].decay
            dl += s * (1 - drops[i].pan)
            dr += s * drops[i].pan
        }
        dropLpL += cDrop * (dl - dropLpL)
        dropLpR += cDrop * (dr - dropLpR)
        l += dropLpL * 0.6
        r += dropLpR * 0.6

        let (wl2, wr2) = reverb.process((l + r) * 0.5, fb: 0.8, damp: 0.5)
        a = l + wl2 * 0.15
        b = r + wr2 * 0.15
    }

    // MARK: 海浪

    private func waveEnv(_ x: Float) -> Float {
        if x < 0.3 {
            let s = sine(x / 0.3 * 0.25)
            return s * s
        }
        return exp(-(x - 0.3) * 4)
    }

    private func ocean(_ a: inout Float, _ b: inout Float) {
        wavePhase += waveInc
        if wavePhase >= 1 {
            wavePhase -= 1
            waveInc = 1 / (sampleRate * (8 + 5 * rnd()))
            waveAmp = 0.55 + 0.45 * rnd()
        }
        let e = waveEnv(wavePhase) * waveAmp
        let er = waveEnv(max(0, wavePhase - 0.025)) * waveAmp
        oCounter += 1
        if oCounter >= 32 {
            oCounter = 0
            oCoef = 1 - exp(-2 * Float.pi * (220 + 2400 * e * e) / sampleRate)
        }
        let nl = pinkL.next(bip())
        let nr = pinkR.next(bip())
        olpL += oCoef * (nl - olpL)
        olpR += oCoef * (nr - olpR)
        brownL = (brownL + 0.02 * bip()) / 1.02
        brownR = (brownR + 0.02 * bip()) / 1.02
        a = olpL * (0.15 + 1.8 * e) + brownL * 0.3
        b = olpR * (0.15 + 1.8 * er) + brownR * 0.3
    }

    // MARK: 颂钵

    private func bowl(_ a: inout Float, _ b: inout Float) {
        if samplesToStrike <= 0 {
            strike()
            samplesToStrike = Int(sampleRate * (12 + 9 * rnd()))
        }
        samplesToStrike -= 1
        var s: Float = 0
        for i in 0..<partials.count where partials[i].amp > 0.0002 {
            var p = partials[i]
            p.p1 += p.f / sampleRate
            if p.p1 >= 1 { p.p1 -= 1 }
            p.p2 += (p.f + 0.4) / sampleRate
            if p.p2 >= 1 { p.p2 -= 1 }
            s += (sine(p.p1) + sine(p.p2)) * p.amp * min(1, p.att)
            p.att += bowlAtt
            p.amp *= p.decay
            partials[i] = p
        }
        brownL = (brownL + 0.02 * bip()) / 1.02
        brownR = (brownR + 0.02 * bip()) / 1.02
        let (wl, wr) = reverb.process(s, fb: 0.88, damp: 0.3)
        a = s * 0.5 + wl * 0.45 + brownL * 0.08
        b = s * 0.5 + wr * 0.45 + brownR * 0.08
    }

    private func strike() {
        let f0 = Synth.bowlBases[Int(rnd() * Float(Synth.bowlBases.count)) % Synth.bowlBases.count]
        for k in 0..<Synth.bowlRatios.count {
            var slot = 0
            var low = Float.greatestFiniteMagnitude
            for i in 0..<partials.count where partials[i].amp < low {
                low = partials[i].amp
                slot = i
            }
            partials[slot] = Partial(f: f0 * Synth.bowlRatios[k], p1: 0, p2: rnd(),
                                     amp: Synth.bowlAmps[k] * (0.8 + 0.4 * rnd()),
                                     decay: exp(-1 / (sampleRate * Synth.bowlTaus[k])), att: 0)
        }
    }

    // MARK: 粉噪音

    private func pinkScene(_ a: inout Float, _ b: inout Float) {
        let nl = pinkL.next(bip())
        let nr = pinkR.next(bip())
        plL += cPink * (nl - plL)
        plR += cPink * (nr - plR)
        a = plL * 1.4
        b = plR * 1.4
    }
}
