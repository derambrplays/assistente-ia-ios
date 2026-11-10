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
        case .idle: return "Toque nas barras para começar"
        case .listening: return "Fale normalmente. Eu paro quando você ficar em silêncio."
        case .thinking: return "Só um instante."
        case .speaking: return "Fale por cima ou toque nas barras para me interromper."
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            // Câmera ao vivo cobrindo a tela inteira, como uma chamada de vídeo.
            if store.cameraEnabled {
                CameraPreview(session: store.camera.session)
                    .ignoresSafeArea()
                    .transition(.opacity)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.12),
                        Color.black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header

                if let until = store.serverBusyUntil {
                    ServerBusyBanner(until: until) {
                        store.serverBusyUntil = nil
                    }
                    .padding(.top, 10)
                }

                Spacer(minLength: 8)

                VoiceBars(level: store.micLevel, state: store.voiceState)
                    .frame(height: store.cameraEnabled ? 190 : 250)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.voiceState == .speaking {
                            store.interruptFromUser()
                        }
                    }

                Text(status)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                Text(hint)
                    .font(.system(size: 13.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(store.cameraEnabled ? Color.white.opacity(0.8) : Theme.textDim)
                    .padding(.horizontal, 36)
                    .padding(.top, 6)

                transcript

                Spacer(minLength: 10)

                controls
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Joguim AI")
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
                    .padding(16)
            }
            .frame(maxHeight: 130)
            .glassCard(radius: 26, strength: 0.8)
            .padding(.top, 18)
        }
    }

    // MARK: - Controles

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    store.toggleCamera()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.cameraEnabled ? "video.fill" : "video")
                            .font(.system(size: 13, weight: .bold))
                        Text(store.cameraEnabled ? "Câmera ligada" : "Mostrar câmera")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            store.cameraEnabled
                                ? Theme.accent.opacity(0.35)
                                : Color.white.opacity(0.10)
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            store.cameraEnabled
                                ? Theme.accent.opacity(0.65)
                                : Theme.hairline
                        )
                    )
                }
                .buttonStyle(PressableStyle())

                Button {
                    store.lookAtScreen()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 13, weight: .bold))
                        Text("Ver tela")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                }
                .buttonStyle(PressableStyle())
            }

            HStack(spacing: 12) {
                if store.voiceState == .speaking {
                    Button {
                        store.interruptFromUser()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Interromper")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                    }
                    .buttonStyle(PressableStyle())
                }

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
    }
}

/// Quatro barras que sobem e descem como um medidor de volume.
private struct VoiceBars: View {
    var level: CGFloat
    var state: ChatStore.VoiceState

    private var speed: Double {
        switch state {
        case .speaking: return 5.6
        case .thinking: return 2.3
        default: return 1.7
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let mic = Double(max(0.05, min(1.0, level)))

            HStack(alignment: .center, spacing: 15) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = time * speed + Double(index) * 1.1
                    let wave = (sin(phase) + 1) / 2
                    let amount = height(for: wave, mic: mic)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.accent2.opacity(0.95),
                                    Theme.accent
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 30, height: 40 + CGFloat(amount) * 175)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 16, x: 0, y: 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func height(for wave: Double, mic: Double) -> Double {
        switch state {
        case .speaking:
            return 0.30 + 0.62 * wave
        case .thinking:
            return 0.14 + 0.22 * wave
        case .listening:
            return 0.08 + mic * 0.85 * (0.55 + 0.45 * wave)
        case .idle:
            return 0.06 + 0.09 * wave
        }
    }
}
