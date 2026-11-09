import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""
    @State private var showKey = false

    private var models: [String] {
        var list = store.availableModels
        if !list.contains(store.settings.model) {
            list.insert(store.settings.model, at: 0)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    keyCard
                    modelCard
                    personalityCard
                    voiceCard
                    aboutCard
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background {
                AuroraBackground()
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pronto") {
                        store.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onDisappear { store.save() }
    }

    // MARK: - Chave

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Chave do Gemini", systemImage: "key.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Fica guardada só no seu iPhone. Gere a sua em aistudio.google.com/apikey.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField("AIza…", text: $keyDraft)
                    } else {
                        SecureField("AIza…", text: $keyDraft)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

                Button("Salvar") {
                    store.saveKey(keyDraft)
                    keyDraft = ""
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accent.opacity(0.85))
                )
                .foregroundStyle(.white)
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }

            Toggle("Mostrar chave", isOn: $showKey)
                .font(.system(size: 12))
                .tint(Theme.accent)

            HStack(spacing: 6) {
                Image(systemName: store.hasKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.hasKey ? Theme.accent2 : Theme.danger)
                Text(store.hasKey ? "Chave configurada neste iPhone" : "Nenhuma chave configurada")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Modelo

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Modelo", systemImage: "cpu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Picker("Modelo", selection: $store.settings.model) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)

            Text("Para conversa por voz, o flash-lite responde mais rápido.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textFaint)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Criatividade")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "%.1f", store.settings.temperature))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
                Slider(value: $store.settings.temperature, in: 0...2, step: 0.1)
                    .tint(Theme.accent)
            }

            Button {
                store.refreshModels()
            } label: {
                Label("Atualizar lista de modelos", systemImage: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Personalidade

    private var personalityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Personalidade", systemImage: "text.quote")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Como o assistente deve responder.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            TextEditor(text: $store.settings.systemPrompt)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )

            Button("Restaurar padrão") {
                store.settings.systemPrompt = AppSettings.defaultSystem
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textDim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Voz

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Voz", systemImage: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Toggle("Voz natural (Gemini)", isOn: $store.settings.naturalVoice)
                .font(.system(size: 13))
                .tint(Theme.accent)

            Text(store.settings.naturalVoice
                 ? "Voz humana gerada pelo Google. Precisa de internet."
                 : "Voz do próprio iPhone, mais rápida e sem gastar cota.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textFaint)

            if store.settings.naturalVoice {
                Picker("Voz", selection: $store.settings.ttsVoice) {
                    ForEach(GeminiClient.voices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }

            Button {
                store.speak("Oi! Eu sou seu assistente. Como posso ajudar?")
            } label: {
                Label("Testar voz", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )
                    .overlay(Capsule().strokeBorder(Theme.hairline))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Sobre

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sobre", systemImage: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Assistente IA 1.2 — roda inteiro no iPhone, sem computador.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            Text("Sua chave e suas conversas ficam apenas neste aparelho.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)

            Text(screenInfo)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textFaint.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var screenInfo: String {
        let b = UIScreen.main.bounds
        let win = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.bounds ?? .zero
        return "Tela \(Int(b.width))x\(Int(b.height)) @\(Int(UIScreen.main.scale))x · janela \(Int(win.width))x\(Int(win.height))"
    }
}
