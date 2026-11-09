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
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.accent.opacity(0.22)))
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.45)))
            }
            .buttonStyle(PressableStyle())
            .fixedSize()

            TextField("Pergunte algo…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .focused($focused)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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
                    .foregroundStyle(isSending || canSend ? Color.white : Color.white.opacity(0.45))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(
                            isSending
                                ? AnyShapeStyle(Color.white.opacity(0.16))
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: canSend
                                            ? [Theme.accent, Theme.accent.opacity(0.75)]
                                            : [Color.white.opacity(0.10), Color.white.opacity(0.07)],
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
            .fixedSize()
        }
        .padding(8)
        .frame(maxWidth: .infinity)
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
