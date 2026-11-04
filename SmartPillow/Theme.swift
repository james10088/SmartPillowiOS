import SwiftUI

enum Theme {
    static let ground = Color(red: 7 / 255, green: 6 / 255, blue: 13 / 255)
    static let lavender = Color(red: 185 / 255, green: 162 / 255, blue: 255 / 255)
    static let violet = Color(red: 124 / 255, green: 92 / 255, blue: 230 / 255)
    static let indigo = Color(red: 59 / 255, green: 42 / 255, blue: 134 / 255)
    static let accent = Color(red: 139 / 255, green: 108 / 255, blue: 240 / 255)
    static let mint = Color(red: 126 / 255, green: 224 / 255, blue: 195 / 255)
    static let amber = Color(red: 245 / 255, green: 194 / 255, blue: 122 / 255)
    static let ink = Color(red: 42 / 255, green: 30 / 255, blue: 102 / 255)
    static let secondary = Color.white.opacity(0.62)

    static let hero = LinearGradient(colors: [lavender, violet, indigo],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Font {
    /// 大号数字：系统字体的极细字重，接近 Apple 锁屏时钟。
    static func numeral(_ size: CGFloat) -> Font { .system(size: size, weight: .ultraLight, design: .default) }
    /// 标题：New York 衬线体。
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

/// 背景：深色底加两团缓慢漂移的紫色光晕和闪烁的星星。
struct NightBackground: View {
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.ground
            Circle()
                .fill(RadialGradient(colors: [Theme.violet.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 240))
                .frame(width: 480, height: 480)
                .offset(x: drift ? -60 : -110, y: drift ? -230 : -280)
            Circle()
                .fill(RadialGradient(colors: [Theme.indigo.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 440)
                .offset(x: drift ? 150 : 110, y: drift ? 260 : 300)
            Stars()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

private struct Stars: View {
    @State private var on = false
    private let points: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.78, 0.10, 2, 3.2), (0.64, 0.16, 1.5, 4.1), (0.88, 0.21, 2.5, 2.7),
        (0.50, 0.07, 1.5, 5.0), (0.15, 0.30, 1.5, 3.6), (0.30, 0.13, 2, 4.4)
    ]
    var body: some View {
        GeometryReader { geo in
            ForEach(points.indices, id: \.self) { i in
                let p = points[i]
                Circle().fill(.white)
                    .frame(width: p.2, height: p.2)
                    .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
                    .opacity(on ? 1 : 0.15)
                    .animation(.easeInOut(duration: p.3).repeatForever(autoreverses: true), value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

/// 半透明玻璃卡片。
struct Glass: ViewModifier {
    var radius: CGFloat = 26
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

/// 淡紫色渐变主卡片，带一道缓慢扫过的光泽。
struct HeroCard<Content: View>: View {
    private let content: Content
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(Theme.hero, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.35)
                        .rotationEffect(.degrees(20))
                        .offset(x: sweep ? geo.size.width * 1.4 : -geo.size.width * 0.6)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .accessibilityHidden(true)
            )
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.22)))
            .shadow(color: Theme.violet.opacity(0.6), radius: 30, y: 18)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.5).delay(1.5).repeatForever(autoreverses: false)) { sweep = true }
            }
    }
}

extension View {
    func glass(_ radius: CGFloat = 26) -> some View { modifier(Glass(radius: radius)) }
}

/// 小数据块：大号细数字加说明。
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .white
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.numeral(26)).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glass(22)
    }
}

/// 白色胶囊主按钮。
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}
