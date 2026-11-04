import SwiftUI

enum Theme {
    static let ground = Color(red: 7 / 255, green: 6 / 255, blue: 13 / 255)
    static let groundDeep = Color(red: 5 / 255, green: 4 / 255, blue: 9 / 255)
    static let lavender = Color(red: 185 / 255, green: 162 / 255, blue: 255 / 255)
    static let lilac = Color(red: 201 / 255, green: 184 / 255, blue: 255 / 255)
    static let pale = Color(red: 228 / 255, green: 219 / 255, blue: 255 / 255)
    static let violet = Color(red: 124 / 255, green: 92 / 255, blue: 230 / 255)
    static let indigo = Color(red: 59 / 255, green: 42 / 255, blue: 134 / 255)
    static let accent = Color(red: 139 / 255, green: 108 / 255, blue: 240 / 255)
    static let mint = Color(red: 126 / 255, green: 224 / 255, blue: 195 / 255)
    static let amber = Color(red: 245 / 255, green: 194 / 255, blue: 122 / 255)
    static let blush = Color(red: 245 / 255, green: 181 / 255, blue: 232 / 255)
    static let coral = Color(red: 242 / 255, green: 167 / 255, blue: 160 / 255)
    static let ink = Color(red: 42 / 255, green: 30 / 255, blue: 102 / 255)
    static let navDot = Color(red: 29 / 255, green: 24 / 255, blue: 56 / 255)
    static let secondary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.62)
    static let tertiary = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.5)

    static let hero = LinearGradient(colors: [lavender, violet, indigo],
                                     startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))

    static let zh = Locale(identifier: "zh_CN")
}

extension Font {
    /// 站酷小薇：标题、问候语。
    static func xiaowei(_ size: CGFloat) -> Font { .custom("ZCOOLXiaoWei-Regular", size: size) }
    /// Italiana：所有大号数字。
    static func italiana(_ size: CGFloat) -> Font { .custom("Italiana-Regular", size: size) }
}

// MARK: 动效

/// 进场：从下往上浮现，可设置延迟做依次出现。
struct Rise: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func rise(_ delay: Double = 0) -> some View { modifier(Rise(delay: delay)) }
    func glass(_ radius: CGFloat = 26) -> some View { modifier(GlassCard(radius: radius)) }
}

/// 背景：深色底、两团缓慢漂移的紫色光晕、闪烁的星星。光晕在 overlay 里，不会撑宽页面。
struct NightBackground: View {
    private let deep: Bool
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(deep: Bool = false) { self.deep = deep }

    var body: some View {
        (deep ? Theme.groundDeep : Theme.ground)
            .overlay {
                GeometryReader { geo in
                    Circle()
                        .fill(RadialGradient(colors: [Theme.violet.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 230))
                        .frame(width: 460, height: 460)
                        .position(x: geo.size.width * (drift ? 0.22 : 0.08), y: geo.size.height * (drift ? 0.12 : 0.06))
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 80 / 255, green: 60 / 255, blue: 190 / 255).opacity(0.38), .clear], center: .center, startRadius: 0, endRadius: 210))
                        .frame(width: 420, height: 420)
                        .position(x: geo.size.width * (drift ? 0.98 : 1.08), y: geo.size.height * (drift ? 0.74 : 0.8))
                    Stars()
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
            }
    }
}

private struct Stars: View {
    @State private var on = false
    private let points: [(CGFloat, CGFloat, CGFloat, Double, Double)] = [
        (0.77, 0.11, 2, 3.2, 0), (0.64, 0.17, 2, 4.1, 1.1), (0.87, 0.2, 3, 2.7, 0.4),
        (0.5, 0.08, 2, 5.0, 2), (0.12, 0.33, 2, 3.6, 0.3), (0.3, 0.14, 1.5, 4.4, 1.6)
    ]
    var body: some View {
        GeometryReader { geo in
            ForEach(points.indices, id: \.self) { i in
                let p = points[i]
                Circle().fill(.white)
                    .frame(width: p.2, height: p.2)
                    .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
                    .opacity(on ? 1 : 0.15)
                    .animation(.easeInOut(duration: p.3).repeatForever(autoreverses: true).delay(p.4), value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

// MARK: 卡片

/// 半透明玻璃：白 6%、细边框、顶部一道高光、背景模糊。
struct GlassCard: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(.ultraThinMaterial.opacity(0.35), in: shape)
            .background(Color.white.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12)))
            .overlay(alignment: .top) {
                shape.stroke(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// 淡紫色渐变主卡片：一道缓慢扫过的光泽，四周紫色光晕。
struct HeroCard<Content: View>: View {
    var padding: CGFloat = 22
    var dimmed = false
    private let content: Content
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(padding: CGFloat = 22, dimmed: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.dimmed = dimmed
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        content
            .frame(maxWidth: .infinity)
            .padding(padding)
            .background {
                if dimmed {
                    shape.fill(LinearGradient(colors: [Color(red: 150 / 255, green: 140 / 255, blue: 190 / 255).opacity(0.45),
                                                       Color(red: 80 / 255, green: 70 / 255, blue: 130 / 255).opacity(0.45),
                                                       Color(red: 40 / 255, green: 34 / 255, blue: 70 / 255).opacity(0.55)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    shape.fill(Theme.hero)
                }
            }
            .overlay {
                if !dimmed {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.34, height: geo.size.height * 1.6)
                            .rotationEffect(.degrees(20))
                            .offset(x: sweep ? geo.size.width * 1.3 : -geo.size.width * 0.6, y: -geo.size.height * 0.3)
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(dimmed ? 0.14 : 0.22)))
            .overlay(alignment: .top) {
                shape.stroke(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Theme.violet.opacity(dimmed ? 0 : 0.6), radius: 34, y: 22)
            .onAppear {
                guard !reduceMotion, !dimmed else { return }
                withAnimation(.easeInOut(duration: 4).delay(1.4).repeatForever(autoreverses: false)) { sweep = true }
            }
    }
}

/// 小数据块：Italiana 大号数字加说明。
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .white
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.italiana(26)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glass(22)
    }
}

// MARK: 按钮与控件

/// 白色胶囊主按钮。
struct PillButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(.white, in: Capsule())
            .shadow(color: Color(red: 20 / 255, green: 10 / 255, blue: 60 / 255).opacity(0.5), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

/// 玻璃胶囊次按钮。
struct GhostButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
    }
}

/// 44pt 玻璃圆形按钮（返回、分享、历史等）。
struct GlassCircle<IconView: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder var icon: () -> IconView

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 薄荷绿开关，带回弹动画。
struct MintSwitch: View {
    @Binding var isOn: Bool
    var label: String
    var width: CGFloat = 52
    var height: CGFloat = 32

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.mint : Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.36))
                .frame(width: width, height: height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white)
                        .frame(width: height - 6, height: height - 6)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

/// 玻璃分段控件：选中项是白色胶囊。
struct GlassSegmented<T: Hashable>: View {
    private let options: [(T, String)]
    @Binding private var selection: T
    private let font: Font
    private let height: CGFloat
    @Namespace private var ns

    init(options: [(T, String)], selection: Binding<T>, font: Font = .xiaowei(17), height: CGFloat = 44) {
        self.options = options
        self._selection = selection
        self.font = font
        self.height = height
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let on = value == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = value }
                } label: {
                    Text(title)
                        .font(font)
                        .foregroundStyle(on ? Theme.ink : Color.white.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background {
                            if on {
                                Capsule().fill(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }
}

/// 分组列表里的一行。
struct ListRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 54)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

struct RowDivider: View {
    var inset: CGFloat = 16
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.leading, inset)
    }
}
