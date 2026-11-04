import SwiftUI

@main
struct SmartPillowApp: App {
    @StateObject private var client: PillowClient
    @StateObject private var assist: AssistEngine
    @Environment(\.scenePhase) private var scenePhase

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
                .environment(\.locale, Theme.zh)
                .onAppear {
                    client.start()
                    assist.ensureStandby()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { assist.ensureStandby() }
                }
        }
    }
}

/// 页面内的跳转目标。
enum Route: Hashable {
    case assist, setup, calibrate, history, report(UUID)
}

struct RootView: View {
    @EnvironmentObject private var client: PillowClient
    @EnvironmentObject private var assist: AssistEngine
    @AppStorage("onboarded") private var onboarded = false
    @State private var tab: AppTab = .tonight
    @State private var tonightPath: [Route] = []
    @State private var reportPath: [Route] = []
    @State private var devicePath: [Route] = []
    @State private var showRecording = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .tonight:
                    NavigationStack(path: $tonightPath) {
                        TonightView(showRecording: $showRecording).withRoutes()
                    }
                case .report:
                    NavigationStack(path: $reportPath) {
                        ReportTab().withRoutes()
                    }
                case .device:
                    NavigationStack(path: $devicePath) {
                        DeviceView().withRoutes()
                    }
                }
            }
            if currentPathEmpty {
                FloatingNav(tab: $tab)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentPathEmpty)
        .fullScreenCover(isPresented: $showRecording) {
            RecordingView()
                .environmentObject(client)
                .environmentObject(assist)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView { goSetup in
                onboarded = true
                if goSetup {
                    tab = .device
                    devicePath = [.setup]
                }
            }
            .environmentObject(client)
            .environmentObject(assist)
            .preferredColorScheme(.dark)
        }
        .onAppear {
            for name in ["ZCOOLXiaoWei-Regular", "Italiana-Regular"] where UIFont(name: name, size: 12) == nil {
                print("⚠️ 字体未加载：\(name)")
            }
        }
        .onChange(of: assist.session?.id) { id in
            // 开始记录（手动或自动）就进入“记录中”全屏页，结束后退出
            showRecording = id != nil
        }
    }

    private var currentPathEmpty: Bool {
        switch tab {
        case .tonight: return tonightPath.isEmpty
        case .report: return reportPath.isEmpty
        case .device: return devicePath.isEmpty
        }
    }
}

private struct RouteDestinations: ViewModifier {
    @EnvironmentObject private var assist: AssistEngine
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case .assist: AssistView()
                    case .setup: SetupView()
                    case .calibrate: CalibrateView()
                    case .history: HistoryView()
                    case .report(let id):
                        if let s = assist.sessions.first(where: { $0.id == id }) {
                            ReportView(session: s, showsBack: true)
                        } else {
                            Text("报告已删除").foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }
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

/// 页面顶部的返回按钮 + 右侧可选内容。
struct BackBar<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    private let trailing: () -> Trailing

    init(@ViewBuilder trailing: @escaping () -> Trailing) {
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            GlassCircle(label: "返回", action: { dismiss() }) { Icon(kind: .back, size: 20) }
            Spacer()
            trailing()
        }
    }
}

extension BackBar where Trailing == EmptyView {
    init() { self.trailing = { EmptyView() } }
}
