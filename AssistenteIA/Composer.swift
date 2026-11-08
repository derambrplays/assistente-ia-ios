import SwiftUI

struct Composer: View {
    @Binding var text: String
    var isSending: Bool
    @FocusState.Binding var focused: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onVoice: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                focused = false
                onVoice()
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.accent.opacity(0.22)))
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.45)))
            }
            .buttonStyle(PressableStyle())

            TextField("Pergunte algo…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .focused($focused)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

            Button {
                if isSending {
                    onStop()
                } else {
                    focused = false
                    onSend()
                }
            } label: {
                Image(systemName: isSending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(
                            isSending
                                ? AnyShapeStyle(Color.white.opacity(0.14))
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [Theme.accent, Theme.accent.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.22)))
            }
            .buttonStyle(PressableStyle())
            .disabled(!isSending && !canSend)
            .opacity(!isSending && !canSend ? 0.45 : 1)
        }
        .padding(8)
        .glassCard(radius: 23, strength: 0.9)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
