import Foundation

// 在 macOS 上离线渲染每个音景，生成 WAV 试听样本，并打印峰值 / 响度，检查有没有削波。
let sr: Float = 44_100
let seconds = 40
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "samples"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func writeWav(_ path: String, _ l: [Float], _ r: [Float]) {
    var data = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
    let n = l.count
    data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4))
    data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr) * 4); u16(4); u16(16)
    data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
    for i in 0..<n {
        u16(UInt16(bitPattern: Int16(max(-1, min(1, l[i])) * 32_767)))
        u16(UInt16(bitPattern: Int16(max(-1, min(1, r[i])) * 32_767)))
    }
    try? data.write(to: URL(fileURLWithPath: path))
}

for scene in Synth.Scene.allCases {
    let synth = Synth(sampleRate: sr)
    synth.requested = scene.rawValue
    synth.active = true
    let total = Int(sr) * seconds
    var l = [Float](repeating: 0, count: total)
    var r = [Float](repeating: 0, count: total)
    let block = 512
    let bl = UnsafeMutablePointer<Float>.allocate(capacity: block)
    let br = UnsafeMutablePointer<Float>.allocate(capacity: block)
    var pos = 0
    let t0 = Date()
    while pos < total {
        let n = min(block, total - pos)
        synth.render(bl, br, n)
        for i in 0..<n { l[pos + i] = bl[i]; r[pos + i] = br[i] }
        pos += n
    }
    let cpu = Date().timeIntervalSince(t0) / Double(seconds) * 100
    var peak: Float = 0, sum: Double = 0, clipped = 0
    for i in Int(sr) * 3..<total {
        let m = max(abs(l[i]), abs(r[i]))
        peak = max(peak, m)
        sum += Double(l[i] * l[i] + r[i] * r[i]) / 2
        if m >= 0.999 { clipped += 1 }
    }
    let rms = sqrt(sum / Double(total - Int(sr) * 3))
    print(String(format: "%@  peak %.3f  rms %.4f (%.1f dBFS)  clipped %d  cpu %.2f%%",
                 scene.name, peak, rms, 20 * log10(rms), clipped, cpu))
    writeWav("\(outDir)/\(scene.rawValue)_\(scene.name).wav", l, r)
}
