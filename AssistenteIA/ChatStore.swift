import Foundation
import SwiftUI
import Combine

final class ChatStore: ObservableObject {
    enum VoiceState: Equatable {
        case idle
        case listening
        case thinking
        case speaking
    }

    @Published var conversations: [Conversation] = []
    @Published var activeID: UUID?
    @Published var settings = AppSettings()
    @Published var isSending = false
    @Published var hasKey = false
    @Published var banner: String?
    @Published var micLevel: CGFloat = 0
    @Published var voiceMode = false
    @Published var voiceState: VoiceState = .idle
    @Published var liveTranscript = ""
    @Published var availableModels: [String] = GeminiClient.chatFallbacks

    let speech = SpeechController()
    let player = AudioPlayer()

    private var sendTask: Task<Void, Never>?
    private var lastSpoken = ""
    private var speechGeneration = 0
    private let storageKey = "assistente.ios.v1"

    init() {
        load()
        hasKey = GeminiClient.hasKey

        speech.onLevel = { [weak self] level in
            self?.micLevel = level
        }
    }

    // MARK: - Leitura

    var messages: [ChatMessage] {
        guard let id = activeID,
              let conversation = conversations.first(where: { $0.id == id }) else {
            return []
        }
        return conversation.messages
    }

    var activeTitle: String {
        guard let id = activeID,
              let conversation = conversations.first(where: { $0.id == id }) else {
            return "Assistente"
        }
        return conversation.title
    }

    // MARK: - Chave

    func saveKey(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        Keychain.save(clean)
        hasKey = true
        banner = nil
        refreshModels()
    }

    func refreshModels() {
        Task {
            let models = (try? await GeminiClient.listModels()) ?? GeminiClient.chatFallbacks
            await MainActor.run {
                self.availableModels = models
                if !models.contains(self.settings.model), let first = models.first {
                    self.settings.model = first
                    self.save()
                }
            }
        }
    }

    // MARK: - Conversas

    func newConversation() {
        if let id = activeID,
           let conversation = conversations.first(where: { $0.id == id }),
           conversation.messages.isEmpty {
            return
        }
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        activeID = conversation.id
        save()
    }

    func open(_ id: UUID) {
        activeID = id
        save()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeID == id {
            activeID = conversations.first?.id
        }
        save()
    }

    // MARK: - Enviar

    func send(_ raw: String, speakReply: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard hasKey else {
            banner = "Configure sua chave do Gemini para conversar."
            return
        }

        mutateActive { conversation in
            conversation.messages.append(ChatMessage(role: .user, text: text))
        }

        let assistantID = UUID()
        mutateActive { conversation in
            conversation.messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))
        }

        let history = messages.filter { $0.id != assistantID }
        let system = settings.systemPrompt
        let model = settings.model
        let temperature = settings.temperature

        isSending = true
        banner = nil

        sendTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await GeminiClient.streamChat(
                    messages: history,
                    system: system,
                    model: model,
                    temperature: temperature
                ) { delta in
                    self.appendDelta(assistantID, delta)
                }
                self.complete(assistantID, speakReply: speakReply)
            } catch is CancellationError {
                self.complete(assistantID, speakReply: false, interrupted: true)
            } catch {
                if Task.isCancelled {
                    self.complete(assistantID, speakReply: false, interrupted: true)
                    return
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.fail(assistantID, message)
            }
        }
    }

    func stop() {
        sendTask?.cancel()
        sendTask = nil
    }

    private func appendDelta(_ id: UUID, _ delta: String) {
        DispatchQueue.main.async {
            self.mutateMessage(id) { message in
                message.text += delta
            }
        }
    }

    private func complete(_ id: UUID, speakReply: Bool, interrupted: Bool = false) {
        DispatchQueue.main.async {
            self.isSending = false

            var text = ""
            if let conversation = self.conversations.first(where: { $0.messages.contains(where: { $0.id == id }) }),
               let message = conversation.messages.first(where: { $0.id == id }) {
                text = message.text
            }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.mutateMessage(id) { message in
                    message.text = interrupted
                        ? "Resposta interrompida."
                        : "Não recebi resposta. Tente de novo."
                }
            } else if interrupted {
                self.mutateMessage(id) { message in
                    message.text += "\n\n_[resposta interrompida]_"
                }
            }

            self.save()

            if speakReply || self.voiceMode {
                self.speak(text)
            }
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        DispatchQueue.main.async {
            self.isSending = false

            self.mutateMessage(id) { item in
                item.text = message
                item.isError = true
            }

            self.save()

            if self.voiceMode {
                self.voiceState = .listening
                self.listenAgain()
            }
        }
    }

    private func mutateMessage(_ id: UUID, _ block: (inout ChatMessage) -> Void) {
        guard let conversationIndex = conversations.firstIndex(where: {
                  $0.messages.contains(where: { $0.id == id })
              }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        block(&conversations[conversationIndex].messages[messageIndex])
        conversations[conversationIndex].updatedAt = Date()
    }

    // MARK: - Voz

    func startVoiceMode() {
        voiceMode = true
        voiceState = .listening
        liveTranscript = ""

        Task {
            let allowed = await speech.requestAuthorization()
            await MainActor.run {
                if allowed {
                    self.listenAgain()
                } else {
                    self.voiceMode = false
                    self.voiceState = .idle
                    self.banner = "Autorize o microfone e o reconhecimento de fala nos Ajustes do iPhone."
                }
            }
        }
    }

    func stopVoiceMode() {
        voiceMode = false
        voiceState = .idle
        liveTranscript = ""
        speechGeneration += 1
        speech.stop()
        player.stop()
        micLevel = 0
    }

    func listenAgain() {
        guard voiceMode else { return }

        voiceState = .listening
        liveTranscript = ""

        speech.onPartial = { [weak self] text in
            self?.liveTranscript = text
        }
        speech.onFinal = { [weak self] text in
            self?.handleHeard(text)
        }
        speech.onError = { [weak self] message in
            self?.banner = message
        }

        speech.start(silence: 1.5)
    }

    private func handleHeard(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard voiceMode else { return }

        guard !clean.isEmpty else {
            listenAgain()
            return
        }

        liveTranscript = clean
        voiceState = .thinking
        send(clean, speakReply: true)
    }

    func speak(_ raw: String) {
        let text = stripMarkdown(raw)
        guard !text.isEmpty else {
            if voiceMode { listenAgain() }
            return
        }

        lastSpoken = text
        voiceState = .speaking
        speechGeneration += 1
        let generation = speechGeneration

        if settings.naturalVoice {
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    let data = try await GeminiClient.speak(text: text, voice: self.settings.ttsVoice)
                    await MainActor.run {
                        guard generation == self.speechGeneration else { return }
                        do {
                            try self.player.play(data: data, voiceMode: self.voiceMode) { [weak self] in
                                self?.afterSpeech()
                            }
                            if self.voiceMode { self.startBargeIn() }
                        } catch {
                            self.speakOffline(text)
                        }
                    }
                } catch {
                    await MainActor.run {
                        guard generation == self.speechGeneration else { return }
                        self.speakOffline(text)
                    }
                }
            }
        } else {
            speakOffline(text)
        }
    }

    private func speakOffline(_ text: String) {
        player.speakOffline(text, voiceMode: voiceMode) { [weak self] in
            self?.afterSpeech()
        }
        if voiceMode { startBargeIn() }
    }

    private func afterSpeech() {
        speech.stop()

        if voiceMode {
            voiceState = .listening
            listenAgain()
        } else {
            voiceState = .idle
        }
    }

    private func startBargeIn(after delay: TimeInterval = 0.6) {
        guard voiceMode else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.voiceMode, self.player.isPlaying else { return }

            self.speech.onPartial = { [weak self] text in
                guard let self = self else { return }
                let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard heard.split(separator: " ").count >= 2 else { return }
                if self.overlaps(heard, self.lastSpoken) { return }
                self.interrupt()
            }
            self.speech.onFinal = { _ in }
            self.speech.onError = { _ in }

            self.speech.start(silence: 30)
        }
    }

    private func interrupt() {
        speechGeneration += 1
        player.stop()
        speech.stop()
        liveTranscript = ""
        voiceState = .listening
        listenAgain()
    }

    private func overlaps(_ first: String, _ second: String) -> Bool {
        func words(_ text: String) -> Set<String> {
            let folded = text
                .lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            let pieces = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            return Set(pieces.filter { $0.count > 1 })
        }

        let firstWords = words(first)
        let secondWords = words(second)
        guard !firstWords.isEmpty else { return true }

        let common = firstWords.intersection(secondWords).count
        return Double(common) / Double(firstWords.count) >= 0.7
    }

    // MARK: - Persistência

    func save() {
        let state = PersistedState(
            conversations: conversations,
            activeID: activeID,
            settings: settings
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        conversations = state.conversations
        activeID = state.activeID
        settings = state.settings
    }

    private func mutateActive(_ block: (inout Conversation) -> Void) {
        if activeID == nil {
            let conversation = Conversation()
            conversations.insert(conversation, at: 0)
            activeID = conversation.id
        }

        guard let id = activeID,
              let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        block(&conversations[index])
        conversations[index].updatedAt = Date()

        if conversations[index].title == "Nova conversa",
           let firstUser = conversations[index].messages.first(where: { $0.role == .user }) {
            let title = firstUser.text.replacingOccurrences(of: "\n", with: " ")
            conversations[index].title = String(title.prefix(42))
        }
    }

    func stripMarkdown(_ text: String) -> String {
        var clean = text
        clean = clean.replacingOccurrences(of: "```", with: " ")
        clean = clean.replacingOccurrences(of: "`", with: " ")
        clean = clean.replacingOccurrences(of: "**", with: "")
        clean = clean.replacingOccurrences(of: "__", with: "")
        clean = clean.replacingOccurrences(of: "#", with: "")
        clean = clean.replacingOccurrences(of: ">", with: "")
        clean = clean.replacingOccurrences(of: "*", with: "")
        clean = clean.replacingOccurrences(of: "_", with: " ")

        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^\\)]+\\)") {
            let range = NSRange(clean.startIndex..., in: clean)
            clean = regex.stringByReplacingMatches(
                in: clean,
                range: range,
                withTemplate: "$1"
            )
        }

        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
