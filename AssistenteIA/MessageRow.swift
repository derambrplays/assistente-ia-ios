import SwiftUI
import UIKit

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

                if !isUser && !message.sources.isEmpty {
                    sourcesView
                }

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
        if message.text.isEmpty && message.attachments.isEmpty && !isUser {
            TypingIndicator()
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .glassCard(radius: 20, strength: 0.75)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.attachments) { attachment in
                    AttachmentPreview(attachment: attachment)
                }

                if !message.text.isEmpty {
                    Text(attributed)
                        .font(.system(size: 15.5))
                        .foregroundStyle(message.isError ? Theme.danger : Color.white)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, message.attachments.isEmpty ? 14 : 8)
            .padding(.vertical, message.attachments.isEmpty ? 11 : 8)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(bubbleBorder, lineWidth: 1)
            )
        }
    }

    private var sourcesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Fontes da web", systemImage: "globe")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textFaint)

            ForEach(message.sources.prefix(5)) { source in
                if let url = URL(string: source.uri) {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: "link")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(source.title.isEmpty ? source.uri : source.title)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.accent2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                    }
                }
            }
        }
        .padding(.horizontal, 2)
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

private struct AttachmentPreview: View {
    let attachment: Attachment

    var body: some View {
        if attachment.isImage, let image = AttachmentStore.image(for: attachment) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16))
                )
        } else {
            HStack(spacing: 8) {
                Image(systemName: attachment.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent2)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(attachment.sizeText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }
}
