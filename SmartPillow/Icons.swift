import SwiftUI

/// 设计稿里的自绘双色图标，坐标系 24×24，与画布上的 SVG 一致。
enum IconKind {
    case moon, tide, pillow, fadeBars, phases, constellation, eclipse, share, back, chevron, close, eye, wifiPillow, check, reconnect, swapPillow, moonPlain
}

struct Icon: View {
    let kind: IconKind
    var size: CGFloat = 20
    var color: Color = .white
    /// 镂空部分（如枕头上的三个点）的颜色
    var cutout: Color = Theme.navDot

    var body: some View {
        Canvas { ctx, sz in
            ctx.scaleBy(x: sz.width / 24, y: sz.height / 24)
            draw(&ctx)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func wave(_ y: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 3, y: y))
        p.addCurve(to: CGPoint(x: 9.6, y: y), control1: CGPoint(x: 5.2, y: y - 3), control2: CGPoint(x: 7.4, y: y - 3))
        p.addCurve(to: CGPoint(x: 16.2, y: y), control1: CGPoint(x: 11.8, y: y + 3), control2: CGPoint(x: 14, y: y + 3))
        p.addCurve(to: CGPoint(x: 21, y: y - 1.2), control1: CGPoint(x: 18.4, y: y - 3), control2: CGPoint(x: 19.5, y: y - 2.4))
        return p
    }

    private var pillowShape: Path {
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 9.5))
        p.addCurve(to: CGPoint(x: 20, y: 9.5), control1: CGPoint(x: 4, y: 6.4), control2: CGPoint(x: 20, y: 6.4))
        p.addLine(to: CGPoint(x: 20.8, y: 15.5))
        p.addCurve(to: CGPoint(x: 3.2, y: 15.5), control1: CGPoint(x: 20.8, y: 18.6), control2: CGPoint(x: 3.2, y: 18.6))
        p.closeSubpath()
        return p
    }

    private func crescent(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, cutX: CGFloat, cutY: CGFloat, cutR: CGFloat) {
        ctx.drawLayer { layer in
            layer.fill(circle(cx, cy, r), with: .color(color))
            layer.blendMode = .destinationOut
            layer.fill(circle(cutX, cutY, cutR), with: .color(.black))
        }
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let c = GraphicsContext.Shading.color(color)
        func dim(_ o: Double) -> GraphicsContext.Shading { .color(color.opacity(o)) }
        let round = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

        switch kind {
        case .moon:
            crescent(&ctx, cx: 11.5, cy: 12.5, r: 7.5, cutX: 15.6, cutY: 9.2, cutR: 6.2)
            ctx.fill(circle(19, 5.5, 1.1), with: c)
            var orbit = Path()
            orbit.move(to: CGPoint(x: 3, y: 20))
            orbit.addQuadCurve(to: CGPoint(x: 14, y: 20.8), control: CGPoint(x: 8.5, y: 22.4))
            ctx.stroke(orbit, with: dim(0.55), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        case .moonPlain:
            crescent(&ctx, cx: 11.5, cy: 12.5, r: 7.5, cutX: 15.6, cutY: 9.2, cutR: 6.2)
        case .tide:
            var bottom = wave(18)
            bottom.addLine(to: CGPoint(x: 21, y: 21))
            bottom.addLine(to: CGPoint(x: 3, y: 21))
            bottom.closeSubpath()
            ctx.fill(bottom, with: dim(0.9))
            ctx.stroke(wave(12.5), with: dim(0.7), style: round)
            ctx.stroke(wave(7), with: dim(0.4), style: round)
        case .pillow:
            ctx.fill(pillowShape, with: dim(0.92))
            for (x, y) in [(8.0, 13.0), (12.0, 13.3), (16.0, 13.0)] {
                ctx.fill(circle(x, y, 1.1), with: .color(cutout))
            }
        case .fadeBars:
            ctx.fill(Path(roundedRect: CGRect(x: 3, y: 5, width: 4, height: 14), cornerRadius: 2), with: c)
            ctx.fill(Path(roundedRect: CGRect(x: 10, y: 8, width: 4, height: 8), cornerRadius: 2), with: dim(0.6))
            ctx.fill(Path(roundedRect: CGRect(x: 17, y: 10.5, width: 4, height: 3), cornerRadius: 1.5), with: dim(0.3))
        case .phases:
            ctx.fill(circle(5, 12, 3), with: dim(0.35))
            ctx.stroke(circle(12, 12, 3), with: dim(0.6), lineWidth: 1.1)
            var half = Path()
            half.addArc(center: CGPoint(x: 12, y: 12), radius: 3, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            half.closeSubpath()
            ctx.fill(half, with: c)
            ctx.fill(circle(19, 12, 3), with: c)
        case .constellation:
            var lines = Path()
            lines.move(to: CGPoint(x: 5, y: 17))
            lines.addLine(to: CGPoint(x: 11, y: 7))
            lines.addLine(to: CGPoint(x: 19, y: 13))
            ctx.stroke(lines, with: dim(0.6), lineWidth: 1.1)
            ctx.fill(circle(5, 17, 2), with: c)
            ctx.fill(circle(11, 7, 2.6), with: c)
            ctx.fill(circle(19, 13, 1.6), with: c)
        case .eclipse:
            ctx.stroke(circle(12, 12, 8), with: c, lineWidth: 1.5)
            var half = Path()
            half.addArc(center: CGPoint(x: 12, y: 12), radius: 8, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            half.closeSubpath()
            ctx.fill(half, with: c)
        case .share:
            ctx.fill(circle(9, 15, 5.5), with: dim(0.35))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 10.5, y: 13.5))
            arrow.addLine(to: CGPoint(x: 19, y: 5))
            arrow.move(to: CGPoint(x: 14, y: 4.6))
            arrow.addLine(to: CGPoint(x: 19.4, y: 4.6))
            arrow.addLine(to: CGPoint(x: 19.4, y: 10))
            ctx.stroke(arrow, with: c, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
        case .back:
            var p = Path()
            p.move(to: CGPoint(x: 14.5, y: 5.5))
            p.addLine(to: CGPoint(x: 8, y: 12))
            p.addLine(to: CGPoint(x: 14.5, y: 18.5))
            ctx.stroke(p, with: c, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            ctx.fill(circle(18, 12, 1.3), with: dim(0.5))
        case .chevron:
            var p = Path()
            p.move(to: CGPoint(x: 9.5, y: 6))
            p.addLine(to: CGPoint(x: 15.5, y: 12))
            p.addLine(to: CGPoint(x: 9.5, y: 18))
            ctx.stroke(p, with: c, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        case .close:
            var p = Path()
            p.move(to: CGPoint(x: 7, y: 7)); p.addLine(to: CGPoint(x: 17, y: 17))
            p.move(to: CGPoint(x: 17, y: 7)); p.addLine(to: CGPoint(x: 7, y: 17))
            ctx.stroke(p, with: c, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        case .eye:
            var lens = Path()
            lens.move(to: CGPoint(x: 3, y: 12))
            lens.addQuadCurve(to: CGPoint(x: 21, y: 12), control: CGPoint(x: 12, y: 0))
            lens.addQuadCurve(to: CGPoint(x: 3, y: 12), control: CGPoint(x: 12, y: 24))
            ctx.fill(lens, with: dim(0.25))
            crescent(&ctx, cx: 12, cy: 12, r: 4, cutX: 14.2, cutY: 10, cutR: 3)
        case .wifiPillow:
            var base = Path()
            base.move(to: CGPoint(x: 5, y: 15.5))
            base.addCurve(to: CGPoint(x: 19, y: 15.5), control1: CGPoint(x: 5, y: 13.6), control2: CGPoint(x: 19, y: 13.6))
            base.addLine(to: CGPoint(x: 19.6, y: 19.1))
            base.addCurve(to: CGPoint(x: 4.4, y: 19.1), control1: CGPoint(x: 19.6, y: 21.1), control2: CGPoint(x: 4.4, y: 21.1))
            base.closeSubpath()
            ctx.fill(base, with: c)
            for (i, r) in [3.5, 6.2, 8.8].enumerated() {
                var arc = Path()
                arc.addArc(center: CGPoint(x: 12, y: 13.2), radius: r, startAngle: .degrees(-140), endAngle: .degrees(-40), clockwise: false)
                ctx.stroke(arc, with: dim(1 - Double(i) * 0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        case .check:
            ctx.fill(circle(12, 12, 10), with: dim(0.22))
            var p = Path()
            p.move(to: CGPoint(x: 7, y: 12.5))
            p.addLine(to: CGPoint(x: 10.2, y: 15.7))
            p.addLine(to: CGPoint(x: 17, y: 9))
            ctx.stroke(p, with: c, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        case .reconnect:
            ctx.fill(circle(12, 3.5, 2.2), with: c)
            ctx.fill(circle(19.4, 15.5, 1.7), with: dim(0.6))
            ctx.fill(circle(4.6, 15.5, 1.2), with: dim(0.3))
        case .swapPillow:
            ctx.fill(Path(roundedRect: CGRect(x: 2.5, y: 9, width: 8, height: 6), cornerRadius: 3), with: c)
            ctx.fill(Path(roundedRect: CGRect(x: 13.5, y: 9, width: 8, height: 6), cornerRadius: 3), with: dim(0.45))
            var top = Path()
            top.move(to: CGPoint(x: 6.5, y: 6.5))
            top.addQuadCurve(to: CGPoint(x: 17.5, y: 6.5), control: CGPoint(x: 12, y: 1.5))
            ctx.stroke(top, with: c, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            var bottom = Path()
            bottom.move(to: CGPoint(x: 17.5, y: 17.5))
            bottom.addQuadCurve(to: CGPoint(x: 6.5, y: 17.5), control: CGPoint(x: 12, y: 22.5))
            ctx.stroke(bottom, with: dim(0.6), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}

/// 设计稿里的悬浮玻璃胶囊导航：选中项是实心紫色圆。
enum AppTab: Hashable { case tonight, report, device }

struct FloatingNav: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.tonight, "今夜", .moon)
            Spacer(minLength: 0)
            item(.report, "报告", .tide)
            Spacer(minLength: 0)
            item(.device, "设备", .pillow)
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 64)
        .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
        .background(Color(red: 40 / 255, green: 34 / 255, blue: 64 / 255).opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
        .overlay(alignment: .top) {
            Capsule().stroke(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.7), radius: 20, y: 12)
    }

    private func item(_ t: AppTab, _ title: String, _ icon: IconKind) -> some View {
        let on = tab == t
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = t }
        } label: {
            VStack(spacing: 1) {
                Icon(kind: icon, size: on ? 18 : 20, color: on ? .white : Color.white.opacity(0.7),
                     cutout: on ? Color(red: 75 / 255, green: 51 / 255, blue: 168 / 255) : Theme.navDot)
                Text(title).font(.system(size: 10)).foregroundStyle(on ? .white : Color.white.opacity(0.7))
            }
            .frame(width: 52, height: 52)
            .background {
                if on {
                    Circle().fill(Theme.accent).shadow(color: Theme.violet.opacity(0.8), radius: 8, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
