import SwiftUI

enum Theme {
    static let bg = Color(red: 0.019, green: 0.023, blue: 0.047)
    static let accent = Color(red: 0.545, green: 0.490, blue: 1.000)
    static let accent2 = Color(red: 0.243, green: 0.878, blue: 0.812)
    static let danger = Color(red: 1.000, green: 0.420, blue: 0.506)
    static let textDim = Color.white.opacity(0.64)
    static let textFaint = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.10)
}

struct AuroraBackground: View {
    @State private var drift: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.bg

            blob(color: Theme.accent.opacity(0.55), size: 540)
                .offset(x: -130 + 34 * sin(drift), y: -250 + 26 * cos(drift))
            blob(color: Theme.accent2.opacity(0.42), size: 470)
                .offset(x: 150 - 30 * sin(drift), y: -210 + 34 * cos(drift))
            blob(color: Color(red: 1.0, green: 0.37, blue: 0.56).opacity(0.32), size: 500)
                .offset(x: 120, y: 330 - 28 * cos(drift))
            blob(color: Color(red: 0.20, green: 0.42, blue: 1.0).opacity(0.34), size: 460)
                .offset(x: -140, y: 380 + 24 * sin(drift))
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                drift = 1
            }
        }
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 70)
    }
}

struct GlassBackground: ViewModifier {
    var radius: CGFloat = 24
    var strength: Double = 1.0

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(strength)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.34), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.45), radius: 26, x: 0, y: 16)
    }
}

extension View {
    func glassCard(radius: CGFloat = 24, strength: Double = 1.0) -> some View {
        modifier(GlassBackground(radius: radius, strength: strength))
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
