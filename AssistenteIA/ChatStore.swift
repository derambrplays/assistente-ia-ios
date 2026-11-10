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

    // Fala em fluxo: a primeira frase é falada enquanto o resto é gerado.
    private var speechStreaming = false
    private var speechStreamDone = false
    private var speechBuffer = ""
    private var speechPending = 0
    private var speechScheduled = 0
    private var speechStarted = false
    private var lastSpeechFetch: Task<Void, Never>?

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
            let models = await GeminiClient.chatModels()
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
        if let conversation = conversations.first(where: { $0.id == id }) {
            for message in conversation.messages {
                for attachment in message.attachments {
                    AttachmentStore.remove(attachment)
                }
            }
        }
        conversations.removeAll { $0.id == id }
        if activeID == id {
            activeID = conversations.first?.id
        }
        save()
    }

    // MARK: - Enviar

    func send(_ raw: String, attachments: [Attachment] = [], speakReply: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !isSending else { return }
        guard hasKey else {
            banner = "Configure sua chave do Gemini para conversar."
            return
        }

        mutateActive { conversation in
            conversation.messages.append(
                ChatMessage(role: .user, text: text, attachments: attachments)
            )
        }

        let assistantID = UUID()
        mutateActive { conversation in
            conversation.messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))
        }

        let history = messages.filter { $0.id != assistantID }
        var system = settings.systemPrompt
        if Self.looksLikeSearchRequest(text) {
            system += "\n\nO usuário pediu explicitamente para pesquisar na internet. Use a busca do Google agora e cite as fontes."
        }
        let model = settings.model
        let temperature = settings.temperature

        isSending = true
        banner = nil

        if speakReply || voiceMode {
            beginSpeechPipeline()
        }

        sendTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                try await GeminiClient.streamChat(
                    messages: history,
                    system: system,
                    model: model,
                    temperature: temperature,
                    search: true,
                    onDelta: { delta in
                        self.appendDelta(assistantID, delta)
                    },
                    onSources: { sources in
                        self.mergeSources(assistantID, sources)
                    }
                )
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

        if speechStreaming || speechStreamDone || speechStarted {
            cancelSpeechPipeline()
        }
    }

    private func appendDelta(_ id: UUID, _ delta: String) {
        DispatchQueue.main.async {
            self.mutateMessage(id) { message in
                message.text += delta
            }
            self.consumeSpeechDelta(delta)
        }
    }

    private func mergeSources(_ id: UUID, _ sources: [WebSource]) {
        DispatchQueue.main.async {
            self.mutateMessage(id) { message in
                for source in sources where !message.sources.contains(where: { $0.uri == source.uri }) {
                    message.sources.append(source)
                }
                if message.sources.count > 8 {
                    message.sources = Array(message.sources.prefix(8))
                }
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

            if interrupted {
                self.cancelSpeechPipeline()
                if self.voiceMode {
                    self.voiceState = .listening
                    self.listenAgain()
                }
                return
            }

            if self.speechStreaming {
                self.finishSpeechStream(fallback: text)
            } else if speakReply || self.voiceMode {
                self.speak(text)
            }
        }
    }

    private func fail(_ id: UUID, _ message: String) {
        DispatchQueue.main.async {
            self.isSending = false
            self.cancelSpeechPipeline()

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

        // Deixa o alto-falante pronto antes da primeira resposta.
        player.prepare(voiceMode: true)

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

        sendTask?.cancel()
        sendTask = nil
        cancelSpeechPipeline()
        speech.stop()
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

        speech.start(silence: 1.3)
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
        cancelSpeechPipeline()
        beginSpeechPipeline()
        speechBuffer = text
        finishSpeechStream(fallback: text)
    }

    // MARK: - Fala em fluxo (primeira frase antes da resposta terminar)

    private func beginSpeechPipeline() {
        lastSpeechFetch?.cancel()
        speechGeneration += 1
        speechBuffer = ""
        speechStreaming = true
        speechStreamDone = false
        speechPending = 0
        speechScheduled = 0
        speechStarted = false
        lastSpeechFetch = nil

        let generation = speechGeneration
        player.beginStream(voiceMode: voiceMode) { [weak self] in
            self?.afterStreamSpeech(generation)
        }
    }

    private func cancelSpeechPipeline() {
        lastSpeechFetch?.cancel()
        speechGeneration += 1
        speechStreaming = false
        speechStreamDone = false
        speechBuffer = ""
        speechPending = 0
        speechScheduled = 0
        speechStarted = false
        lastSpeechFetch = nil
        player.stop()
    }

    private func consumeSpeechDelta(_ delta: String) {
        guard speechStreaming else { return }
        speechBuffer += delta
        for chunk in extractSpeechChunks(flush: false) {
            enqueueSpeechChunk(chunk)
        }
    }

    private func finishSpeechStream(fallback: String) {
        guard speechStreaming || speechStreamDone else { return }
        speechStreaming = false
        speechStreamDone = true

        for chunk in extractSpeechChunks(flush: true) {
            enqueueSpeechChunk(chunk)
        }

        if speechScheduled == 0 {
            let clean = stripMarkdown(fallback)
            if !clean.isEmpty {
                speechScheduled += 1
                player.enqueueSpeech(clean)
                markSpeechStarted()
            }
        }

        maybeEndSpeech()
    }

    private func maybeEndSpeech() {
        guard speechStreamDone, speechPending == 0 else { return }
        player.endStream()
    }

    private func enqueueSpeechChunk(_ raw: String) {
        let text = stripMarkdown(raw)
        guard !text.isEmpty else { return }

        speechScheduled += 1
        let generation = speechGeneration

        if !settings.naturalVoice {
            player.enqueueSpeech(text)
            markSpeechStarted()
            return
        }

        speechPending += 1
        let previous = lastSpeechFetch
        let voice = settings.ttsVoice

        let task = Task { [weak self] in
            await previous?.value
            guard let self = self else { return }
            do {
                let data = try await GeminiClient.speak(text: text, voice: voice)
                await MainActor.run {
                    guard generation == self.speechGeneration else { return }
                    self.speechPending -= 1
                    self.player.enqueue(data: data)
                    self.markSpeechStarted()
                    self.maybeEndSpeech()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.speechGeneration else { return }
                    self.speechPending -= 1
                    self.player.enqueueSpeech(text)
                    self.markSpeechStarted()
                    self.maybeEndSpeech()
                }
            }
        }
        lastSpeechFetch = task
    }

    private func markSpeechStarted() {
        guard !speechStarted else { return }
        speechStarted = true
        voiceState = .speaking
        startBargeIn()
    }

    private func afterStreamSpeech(_ generation: Int) {
        DispatchQueue.main.async {
            guard generation == self.speechGeneration else { return }

            self.speechStreaming = false
            self.speechStreamDone = false
            self.speechBuffer = ""
            self.speechPending = 0
            self.speechScheduled = 0
            self.speechStarted = false
            self.lastSpeechFetch = nil
            self.afterSpeech()
        }
    }

    /// Separa a resposta em frases para começar a falar o quanto antes.
    private func extractSpeechChunks(flush: Bool) -> [String] {
        var chunks: [String] = []
        let minLength = 24
        let maxLength = 240

        while true {
            let text = speechBuffer
            guard !text.isEmpty else { break }

            var cut: String.Index?

            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                if character == "." || character == "!" || character == "?" || character == "…" || character == "\n" {
                    let next = text.index(after: index)
                    if next == text.endIndex {
                        if flush { cut = next }
                        break
                    }
                    if character == "\n" {
                        if text.distance(from: text.startIndex, to: next) >= minLength {
                            cut = next
                            break
                        }
                    } else {
                        let after = text[next]
                        if after == " " || after == "\n" || after == "\"" {
                            if text.distance(from: text.startIndex, to: next) >= minLength {
                                cut = next
                                break
                            }
                        }
                    }
                }
                index = text.index(after: index)
            }

            if cut == nil && text.count >= maxLength {
                let limit = text.index(text.startIndex, offsetBy: maxLength)
                let prefix = text[text.startIndex..<limit]
                if let space = prefix.lastIndex(of: " ") {
                    cut = space
                }
            }

            if cut == nil && flush {
                cut = text.endIndex
            }

            guard let boundary = cut else { break }

            let piece = String(text[text.startIndex..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            speechBuffer = String(text[boundary...])

            if !piece.isEmpty {
                chunks.append(piece)
            }
        }

        return chunks
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
        sendTask?.cancel()
        sendTask = nil
        cancelSpeechPipeline()
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
            let base = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String
            if !base.isEmpty {
                title = base
            } else if let first = firstUser.attachments.first {
                title = "Anexo: " + first.name
            } else {
                title = "Nova conversa"
            }
            if title != "Nova conversa" {
                let singleLine = title.replacingOccurrences(of: "\n", with: " ")
                conversations[index].title = String(singleLine.prefix(42))
            }
        }
    }

    /// Detecta pedidos explícitos de busca para reforçar a instrução do modelo.
    static func looksLikeSearchRequest(_ text: String) -> Bool {
        let folded = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
        let keywords = [
            "pesquis", "procure", "procura", "busque", "buscar",
            "google", "internet", "noticia", "atualizad", "cotacao",
            "previsao do tempo", "o que aconteceu"
        ]
        return keywords.contains { folded.contains($0) }
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
