import SwiftUI

/// 画板 7「首次使用」
struct OnboardingView: View {
    private let onDone: (_ goSetup: Bool) -> Void
    @EnvironmentObject private var client: PillowClient
    @State private var spin = false
    @State private var bob = false
    @State private var breathe = false

    init(onDone: @escaping (_ goSetup: Bool) -> Void) { self.onDone = onDone }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            orb.rise(0)
            Text("让枕头，\n安静地陪你入睡")
                .font(.xiaowei(32)).tracking(2).lineSpacing(10)
                .multilineTextAlignment(.center)
                .padding(.top, 40)
                .rise(0.15)
            VStack(spacing: 10) {
                row(.pillowWave, "自动记录睡姿、翻身和离枕").rise(0.3)
                row(.fadeBars, "你安静下来，音乐自动变轻").rise(0.4)
                row(.tide, "早上一份看得懂的睡眠报告").rise(0.5)
            }
            .padding(.top, 28)
            Spacer(minLength: 24)
            Button("连接我的枕头") { onDone(true) }
                .buttonStyle(PillButtonStyle(height: 56))
                .rise(0.6)
            Button("还没有枕头？先看演示") {
                client.demo = true
                onDone(false)
            }
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.78))
            .frame(height: 48)
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background {
            ZStack {
                NightBackground()
                Circle()
                    .fill(RadialGradient(colors: [Theme.violet.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 280))
                    .frame(width: 560, height: 560)
                    .scaleEffect(breathe ? 1.08 : 1)
                    .opacity(breathe ? 1 : 0.6)
                    .offset(y: -200)
                    .allowsHitTesting(false)
            }
            .clipped()
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.linear(duration: 50).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.easeInOut(duration: 2.15).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private enum RowIcon { case pillowWave, fadeBars, tide }

    private func row(_ icon: RowIcon, _ text: String) -> some View {
        HStack(spacing: 14) {
            Group {
                switch icon {
                case .pillowWave: Icon(kind: .pillow, size: 22, color: Theme.lilac, cutout: Color(red: 0.2, green: 0.16, blue: 0.36))
                case .fadeBars: Icon(kind: .fadeBars, size: 20, color: Theme.lilac)
                case .tide: Icon(kind: .tide, size: 20, color: Theme.lilac)
                }
            }
            .frame(width: 38, height: 38)
            .background(Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255).opacity(0.22), in: RoundedRectangle(cornerRadius: 13))
            Text(text).font(.system(size: 15))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glass(22)
    }

    private var orb: some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .foregroundStyle(Theme.lilac.opacity(0.35))
                .frame(width: 248, height: 248)
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle()
                .fill(LinearGradient(colors: [Theme.lavender.opacity(0.55), Theme.indigo.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(.ultraThinMaterial.opacity(0.4), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.22)))
                .shadow(color: Theme.violet.opacity(0.8), radius: 40, y: 20)
                .frame(width: 220, height: 220)
            Icon(kind: .moonPlain, size: 96, color: .white)
                .offset(x: 10, y: bob ? -42 : -34)
            PuffyPillow()
                .fill(RadialGradient(colors: [.white, Color(red: 0.93, green: 0.91, blue: 1), Color(red: 0.76, green: 0.70, blue: 0.97)],
                                     center: UnitPoint(x: 0.38, y: 0.28), startRadius: 2, endRadius: 110))
                .overlay(PuffyPillow().fill(LinearGradient(colors: [.clear, Theme.indigo.opacity(0.35)], startPoint: UnitPoint(x: 0.5, y: 0.45), endPoint: .bottom)))
                .frame(width: 128, height: 71)
                .offset(y: 44)
        }
        .frame(width: 250, height: 250)
        .accessibilityHidden(true)
    }
}
