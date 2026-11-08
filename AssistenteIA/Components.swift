import SwiftUI

struct SparkleMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.5), radius: size * 0.35, x: 0, y: size * 0.18)
    }
}

struct TypingIndicator: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.55)
                    .opacity(animate ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.16),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

struct GlassButtonLabel: View {
    let icon: String
    var active: Bool = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.9))
            .frame(width: 40, height: 40)
            .background(
                Circle()
                    .fill(active ? Theme.accent.opacity(0.85) : Color.white.opacity(0.08))
            )
            .overlay(Circle().strokeBorder(Theme.hairline))
    }
}
