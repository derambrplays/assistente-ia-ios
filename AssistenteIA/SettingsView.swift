import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var newMemory = ""
    @State private var showWhatsNew = false
    @State private var diagLines: [String] = []
    @State private var diagRunning = false
    @State private var showClearConfirm = false

    @AppStorage("speechRate") private var speechRate: Double = 0.48
    @AppStorage("chatTextSize") private var chatTextSize: Double = 15.5
    @AppStorage("appLockEnabled") private var appLockEnabled = false

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
                    profileCard
                    memoryCard
                    locationCard
                    personalityCard
                    voiceCard
                    appearanceCard
                    privacyCard
                    diagnosticsCard
                    whatsNewCard
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
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
                .environmentObject(store)
        }
        .alert("Apagar todas as conversas?", isPresented: $showClearConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                store.clearAllConversations()
                dismiss()
            }
        } message: {
            Text("Isso remove todas as conversas e os anexos deste iPhone. A sua chave é mantida.")
        }
    }

    // MARK: - Chave

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sua chave de acesso", systemImage: "key.fill")
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    Text(GeminiClient.isExhausted(model) ? "\(AppInfo.modelName(model)) — ocupado hoje" : AppInfo.modelName(model))
                        .tag(model)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)

            Text("O modo Rápido responde mais rápido na conversa por voz. Se um modelo estiver ocupado, o app tenta outro sozinho.")
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

    // MARK: - Perfil

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sobre você", systemImage: "person.crop.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("O Joguim usa isso para personalizar as respostas. Fica só neste iPhone.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            profileField("Nome", placeholder: "Como quer ser chamado?", text: $store.settings.profile.name)
            profileField("Idade", placeholder: "Ex.: 17", text: $store.settings.profile.age)
            profileField("O que faz / trabalha", placeholder: "Estudos, trabalho…", text: $store.settings.profile.work)
            profileField("Cidade", placeholder: "Onde você mora?", text: $store.settings.profile.city)
            profileField("Gostos e interesses", placeholder: "Música, jogos, esportes…", text: $store.settings.profile.likes)
            profileField("Outras informações", placeholder: "Qualquer coisa útil", text: $store.settings.profile.notes)

            Button("Refazer apresentação inicial") {
                store.settings.onboardingDone = false
                store.save()
                dismiss()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textDim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func profileField(
        _ title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textDim)

            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )
        }
    }

    // MARK: - Memória

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Memória", systemImage: "brain.head.profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("O que o Joguim acha importante guardar aparece aqui e é lembrado nas próximas conversas.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            Toggle(isOn: $store.settings.autoMemory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guardar sozinho")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Ele decide o que é importante e salva.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .tint(Theme.accent)

            if store.settings.memories.isEmpty {
                Text("Nada guardado ainda.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.settings.memories, id: \.self) { memory in
                        HStack(alignment: .top, spacing: 10) {
                            Text(memory)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                store.removeMemory(memory)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.danger.opacity(0.9))
                                    .padding(6)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.hairline)
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Adicionar à memória…", text: $newMemory, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.hairline)
                    )

                Button {
                    store.addMemory(newMemory)
                    newMemory = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.accent.opacity(0.3)))
                        .overlay(Circle().strokeBorder(Theme.accent.opacity(0.5)))
                }
                .buttonStyle(PressableStyle())
                .disabled(newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Localização

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Localização em tempo real", systemImage: "location.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Toggle(isOn: $store.settings.useLocation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Usar minha localização")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Para achar a escola, mercado ou farmácia mais perto.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .tint(Theme.accent)
            .onChange(of: store.settings.useLocation) { enabled in
                if enabled {
                    store.location.request()
                }
                store.save()
            }

            if let summary = store.location.summary, store.settings.useLocation {
                Text(summary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim)
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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

            Toggle("Voz natural", isOn: $store.settings.naturalVoice)
                .font(.system(size: 13))
                .tint(Theme.accent)

            Text(store.settings.naturalVoice
                 ? "Voz humana gerada no servidor. Precisa de internet."
                 : "Voz do próprio iPhone, mais rápida e sem usar o servidor.")
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

            // Voz de reserva: é a que fala quando a voz natural está sem cota
            // ou falha. A qualidade depende da voz instalada no iPhone.
            VStack(alignment: .leading, spacing: 7) {
                Text("Voz do iPhone: \(AudioPlayer.offlineVoiceName) (\(AudioPlayer.offlineVoiceQuality))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textDim)

                if !AudioPlayer.hasGoodOfflineVoice {
                    Text("Essa é a voz básica do sistema e soa robotizada. Baixe \"Luciana\" ou \"Fernanda\" na versão Premium em Ajustes → Acessibilidade → Conteúdo Falado → Vozes → Português (Brasil). O app passa a usar a melhor voz instalada sozinho.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openVoiceSettings()
                } label: {
                    Label("Abrir ajustes de voz do iPhone", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent2)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Velocidade da voz do iPhone")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(speechRate < 0.46 ? "Devagar" : (speechRate > 0.54 ? "Rápida" : "Normal"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim)
                }

                Slider(value: $speechRate, in: 0.4...0.6, step: 0.02)
                    .tint(Theme.accent)
            }

            HStack(spacing: 8) {
                Button {
                    store.speak("Oi! Eu sou seu assistente. Como posso ajudar?")
                } label: {
                    Label("Voz natural", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                }
                .buttonStyle(PressableStyle())

                Button {
                    store.previewOfflineVoice()
                } label: {
                    Label("Voz do iPhone", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Theme.hairline))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// Abre os Ajustes do iOS na tela de vozes. Se o link direto não for aceito,
    /// cai nos ajustes do próprio app.
    private func openVoiceSettings() {
        if let url = URL(string: "App-prefs:root=ACCESSIBILITY&path=Spoken%20Content") {
            UIApplication.shared.open(url, options: [:]) { opened in
                guard !opened, let fallback = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(fallback)
            }
        }
    }

    // MARK: - Aparência

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aparência", systemImage: "textformat.size")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Tamanho do texto das mensagens.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            HStack(spacing: 10) {
                Text("A")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                Slider(value: $chatTextSize, in: 13...21, step: 0.5)
                    .tint(Theme.accent)
                Text("A")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }

            Text("Assim ficam as mensagens na conversa.")
                .font(.system(size: CGFloat(chatTextSize)))
                .foregroundStyle(.white)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Privacidade

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Privacidade", systemImage: "faceid")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Toggle(isOn: $appLockEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pedir Face ID ao abrir")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Protege suas conversas se alguém pegar o iPhone.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .tint(Theme.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Diagnóstico

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Diagnóstico", systemImage: "stethoscope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Testa a conexão com o servidor e mostra a resposta exata. Use se a IA parar de responder.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textDim)

            Button {
                diagRunning = true
                Task {
                    await Diagnostics.run(primary: store.settings.model)
                    await MainActor.run {
                        diagLines = Diagnostics.summary
                        diagRunning = false
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: diagRunning ? "hourglass" : "bolt.horizontal.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(diagRunning ? "Testando…" : "Testar servidor agora")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.accent.opacity(0.85)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2)))
            }
            .buttonStyle(PressableStyle())
            .disabled(diagRunning)

            if !diagLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(diagLines.suffix(8), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onAppear { diagLines = Diagnostics.summary }
    }

    // MARK: - Novidades

    private var whatsNewCard: some View {
        Button {
            showWhatsNew = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Novidades")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Veja o que mudou na versão \(AppInfo.version)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textDim)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 24, strength: 0.8)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Sobre

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sobre", systemImage: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text("Joguim AI \(AppInfo.version) (\(AppInfo.build)) — roda inteiro no iPhone, sem computador.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)

            Text("Criado por \(AppInfo.creator).")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent2)

            Text("Anexe fotos e arquivos, fale por voz, identifique músicas e peça para pesquisar na internet.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)

            Text("Sua chave e suas conversas ficam apenas neste aparelho.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)

            Divider()
                .overlay(Theme.hairline)
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                Text("Anexos guardados: \(store.storageText)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)

                Spacer(minLength: 8)

                Button {
                    showClearConfirm = true
                } label: {
                    Text("Apagar conversas")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }

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
