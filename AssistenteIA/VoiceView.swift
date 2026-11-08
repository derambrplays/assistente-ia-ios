import SwiftUI

struct VoiceView: View {
    @EnvironmentObject private var store: ChatStore

    private var status: String {
        switch store.voiceState {
        case .idle: return "Pronto"
        case .listening: return "Estou ouvindo…"
        case .thinking: return "Pensando…"
        case .speaking: return "Falando…"
        }
    }

    private var hint: String {
        switch store.voiceState {
        case .idle: return "Toque para começar"
        case .listening: return "Fale normalmente. Eu paro quando você ficar em silêncio."
        case .thinking: return "Só um instante."
        case .speaking: return "Você pode falar por cima para me interromper."
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 12)

                orb
                    .frame(height: 300)

                Text(status)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                Text(hint)
                    .font(.system(size: 13.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textDim)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                transcript

                Spacer(minLength: 12)

                endButton
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modo voz")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Conversa por voz, tudo no iPhone")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer()

            Button {
                store.stopVoiceMode()
            } label: {
                GlassButtonLabel(icon: "xmark")
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    // MARK: - Orbe

    private var orb: some View {
        let level = max(0.08, min(1.0, store.micLevel))
        let speaking = store.voiceState == .speaking
        let thinking = store.voiceState == .thinking

        return ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.55 - Double(ring) * 0.13),
                                Theme.accent2.opacity(0.35 - Double(ring) * 0.09)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .frame(width: 200 + CGFloat(ring) * 34, height: 200 + CGFloat(ring) * 34)
                    .scaleEffect(thinking ? 1.06 : 1 + (speaking ? 0.03 : level * 0.06 * CGFloat(ring + 1)))
                    .opacity(thinking ? 0.85 : 1)
                    .animation(
                        thinking
                            ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.18),
                        value: thinking ? 1 : level
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Theme.accent.opacity(0.92),
                            Theme.accent.opacity(0.42)
                        ],
                        center: .topLeading,
                        startRadius: 6,
                        endRadius: 150
                    )
                )
                .frame(width: 176, height: 176)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Theme.accent.opacity(0.55), radius: 44, x: 0, y: 22)
                .scaleEffect(speaking ? 1.04 : 1 + level * 0.10)
                .animation(.easeOut(duration: 0.16), value: level)

            Image(systemName: iconName)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
                .opacity(speaking ? 0.92 : 1)
        }
    }

    private var iconName: String {
        switch store.voiceState {
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        case .speaking: return "speaker.wave.2.fill"
        case .idle: return "mic.fill"
        }
    }

    // MARK: - Transcrição

    @ViewBuilder
    private var transcript: some View {
        let text = store.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(maxHeight: 130)
            .glassCard(radius: 20, strength: 0.8)
            .padding(.top, 22)
        }
    }

    // MARK: - Encerrar

    private var endButton: some View {
        Button {
            store.stopVoiceMode()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Encerrar")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Theme.danger.opacity(0.9))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
            .shadow(color: Theme.danger.opacity(0.45), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PressableStyle())
    }
}
