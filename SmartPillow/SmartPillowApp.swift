import SwiftUI

@main
struct SmartPillowApp: App {
    @StateObject private var client: PillowClient
    @StateObject private var assist: AssistEngine

    init() {
        let c = PillowClient()
        _client = StateObject(wrappedValue: c)
        _assist = StateObject(wrappedValue: AssistEngine(client: c))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .environmentObject(assist)
                .preferredColorScheme(.dark)
                .onAppear { client.start() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TonightView()
                .tabItem { Label("今夜", systemImage: "moon.stars.fill") }
            ReportsView()
                .tabItem { Label("报告", systemImage: "water.waves") }
            DeviceView()
                .tabItem { Label("设备", systemImage: "bed.double.fill") }
        }
        .tint(Theme.lavender)
    }
}

extension Activity {
    var label: String {
        switch self {
        case .away: return "已离枕"
        case .quiet: return "安静休息"
        case .active: return "有活动"
        case .unknown: return "识别中"
        }
    }
}
