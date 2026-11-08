import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    var onSpeak: () -> Void

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser {
                Spacer(minLength: 46)
            } else {
                avatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                content

                if !isUser && !message.text.isEmpty {
                    Button(action: onSpeak) {
                        Label("Ouvir", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            if !isUser {
                Spacer(minLength: 24)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.text.isEmpty && !isUser {
            TypingIndicator()
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .glassCard(radius: 20, strength: 0.75)
        } else {
            Text(attributed)
                .font(.system(size: 15.5))
                .foregroundStyle(message.isError ? Theme.danger : Color.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(bubbleBorder, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [Theme.accent, Theme.accent.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if message.isError {
            Color.red.opacity(0.16)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var bubbleBorder: Color {
        if isUser { return Color.white.opacity(0.22) }
        if message.isError { return Color.red.opacity(0.35) }
        return Theme.hairline
    }

    private var attributed: AttributedString {
        (try? AttributedString(markdown: message.text)) ?? AttributedString(message.text)
    }
}
