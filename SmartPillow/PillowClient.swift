import Foundation

/// 与枕头 ESP32 的局域网通信：轮询状态、发送命令、在局域网里查找枕头、热点配网。
@MainActor
final class PillowClient: ObservableObject {
    enum Link: Equatable {
        case idle, searching, connected, unreachable(String)
    }

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "pillowHost") }
    }
    @Published private(set) var status: PillowStatus?
    @Published private(set) var link: Link = .idle
    @Published private(set) var lastUpdate: Date?

    var onStatus: (@MainActor (PillowStatus) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var failures = 0
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 2.5
        c.timeoutIntervalForResource = 4
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init() {
        host = UserDefaults.standard.string(forKey: "pillowHost") ?? ""
    }

    // MARK: 轮询

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if self.host.isEmpty { await self.discover() }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        guard !host.isEmpty else { return }
        do {
            let s = try await fetchStatus(host: host)
            status = s
            lastUpdate = Date()
            failures = 0
            link = .connected
            onStatus?(s)
        } catch {
            failures += 1
            if failures >= 3 { link = .unreachable("连不上枕头（\(host)）") }
            if failures == 10 { await discover() }
        }
    }

    private func fetchStatus(host: String) async throws -> PillowStatus {
        let url = URL(string: "http://\(host)/api/status")!
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try PillowStatus.decode(data)
    }

    // MARK: 命令

    /// BEHAVIOR_START / BEHAVIOR_STOP / BEHAVIOR_RESET
    @discardableResult
    func command(_ name: String) async -> String? {
        guard !host.isEmpty, let url = URL(string: "http://\(host)/api/command") else { return "设备尚未连接" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": name])
        do {
            let (data, _) = try await session.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if obj?["ok"] as? Bool == true { return nil }
            let err = obj?["error"] as? String ?? "设备拒绝操作"
            return err == "ESP_ERR_INVALID_STATE" ? "当前记录状态不允许此操作" : err
        } catch {
            return "命令未送达：\(error.localizedDescription)"
        }
    }

    // MARK: 查找枕头

    /// iOS 发 UDP 广播需要苹果特批权限，这里改为扫描当前 Wi-Fi 网段的 /api/status。
    func discover() async {
        link = .searching
        guard let ip = Network.localIPv4(), let prefix = Network.prefix24(ip) else {
            link = .unreachable("请先连接家里的 Wi-Fi")
            return
        }
        let probe = URLSessionConfiguration.ephemeral
        probe.timeoutIntervalForRequest = 1.2
        let probeSession = URLSession(configuration: probe)

        let found: String? = await withTaskGroup(of: String?.self, returning: String?.self) { group in
            var next = 1
            var running = 0
            func add() {
                let candidate = "\(prefix).\(next)"
                next += 1
                running += 1
                group.addTask {
                    guard let url = URL(string: "http://\(candidate)/api/status"),
                          let result = try? await probeSession.data(from: url) else { return nil }
                    let (data, resp) = result
                    guard (resp as? HTTPURLResponse)?.statusCode == 200,
                          let s = try? PillowStatus.decode(data),
                          s.sensor != nil || s.modelId != nil else { return nil }
                    return candidate
                }
            }
            while next <= 254 && running < 40 { add() }
            while let result = await group.next() {
                running -= 1
                if let r = result {
                    group.cancelAll()
                    return r
                }
                if next <= 254 { add() }
            }
            return nil
        }

        if let found {
            host = found
            link = .connected
        } else {
            link = .unreachable("没找到枕头：确认它已开机、和手机在同一个 Wi-Fi")
        }
    }

    // MARK: 热点配网（手机先连上 SmartPillow- 热点）

    struct SetupReply {
        let state: String
        let error: String
        let ip: String
    }

    func sendWiFi(ssid: String, password: String, requestId: String) async throws -> SetupReply {
        var req = URLRequest(url: URL(string: "http://192.168.4.1/api/wifi")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "ssid": ssid, "password": password, "request_id": requestId
        ])
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw SetupError.message("当前固件不支持配网，需要烧录新版 ESP32 程序") }
        if code == 409 { throw SetupError.message("枕头正在配网，请稍等 30 秒再试") }
        guard code == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SetupError.message("枕头拒绝配网（HTTP \(code)），请检查输入")
        }
        guard obj["device"] as? String == "SMART_PILLOW" else {
            throw SetupError.message("当前连接的不是智能枕头热点")
        }
        return SetupReply(state: obj["state"] as? String ?? "",
                          error: obj["error"] as? String ?? "",
                          ip: obj["ip"] as? String ?? "")
    }

    enum SetupError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let m) = self { return m }
            return nil
        }
    }
}

enum Network {
    /// 当前 Wi-Fi（en0）的 IPv4 地址。
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name) == "en0" else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buf, socklen_t(buf.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: buf)
            }
        }
        return nil
    }

    static func prefix24(_ ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts[0...2].joined(separator: ".")
    }
}
