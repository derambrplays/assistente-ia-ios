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
    @Published var cameraEnabled = false
    @Published var serverBusyUntil: Date?
    @Published var availableModels: [String] = GeminiClient.chatFallbacks

    let speech = SpeechController()
    let player = AudioPlayer()
    let location = LocationProvider()
    let musicRecorder = MusicRecorder()
    let camera = CameraProvider()

    private var sendTask: Task<Void, Never>?
    private var lastSpoken = ""
    private var lastRequestText: String?
    private var lastRequestSpeak = false
    private var speechGeneration = 0
    private var turnsSinceMemory = 0
    private var cancellables = Set<AnyCancellable>()
    private let storageKey = "assistente.ios.v1"

    // Fala em fluxo: a primeira frase é falada enquanto o resto é gerado.
    private var speechStreaming = false
    private var speechStreamDone = false
    private var speechBuffer = ""
    private var speechPending = 0
    private var speechScheduled = 0
    private var speechStarted = false
    private var speechChunkCount = 0
    private var lastSpeechFetch: Task<Void, Never>?

    init() {
        load()
        hasKey = GeminiClient.hasKey

        speech.onLevel = { [weak self] level in
            self?.micLevel = level
        }

        // A localização muda por fora (CoreLocation); avisa as telas que observam
        // o store para o endereço aparecer nos Ajustes sem reabrir a tela.
        location.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Toda vez que abre o app, começa em uma conversa nova.
        let fresh = Conversation()
        conversations.removeAll { $0.messages.isEmpty }
        conversations.insert(fresh, at: 0)
        activeID = fresh.id
        save()

        if settings.useLocation {
            location.request()
        }

        // Autoteste silencioso: mostra no log o que o servidor está respondendo.
        if hasKey {
            let primary = settings.model
            Task.detached(priority: .utility) {
                await Diagnostics.run(primary: primary)
            }
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
            return "Joguim AI"
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

    func send(
        _ raw: String,
        attachments: [Attachment] = [],
        speakReply: Bool = false,
        visionFrame: Data? = nil
    ) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !isSending else { return }
        guard hasKey else {
            banner = "Configure sua chave de acesso para conversar."
            return
        }

        if !text.isEmpty {
            lastRequestText = text
            lastRequestSpeak = speakReply
        }

        // Pedidos de gerar/editar imagem vão para o modelo de imagem.
        if Self.wantsImageEdit(text, attachments: attachments) {
            generateImage(prompt: text, attachments: attachments)
            return
        }

        var finalAttachments = attachments
        if let visionFrame,
           let frame = AttachmentStore.make(name: "camera.jpg", mimeType: "image/jpeg", data: visionFrame) {
            finalAttachments.append(frame)
        }

        mutateActive { conversation in
            conversation.messages.append(
                ChatMessage(role: .user, text: text, attachments: finalAttachments)
            )
        }

        let assistantID = UUID()
        mutateActive { conversation in
            conversation.messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))
        }

        let history = messages.filter { $0.id != assistantID }
        let voice = speakReply || voiceMode
        let searchRequested = Self.looksLikeSearchRequest(text)
        var system = settings.composedSystem(location: settings.useLocation ? location.summary : nil)
        if searchRequested {
            system += "\n\nO usuário pediu explicitamente para pesquisar na internet. Use a busca do Google agora e cite as fontes."
        }
        if voice {
            system += "\n\nModo voz: responda em no máximo 2 frases curtas e diretas, sem listas, sem markdown e sem repetir a pergunta. Vá direto ao ponto."
        }
        let model = settings.model
        let temperature = settings.temperature

        isSending = true
        banner = nil

        if voice {
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
                    search: voice ? searchRequested : true,
                    voice: voice,
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
                if let server = error as? GeminiError, server.dailyQuota {
                    DispatchQueue.main.async {
                        self.serverBusyUntil = ServerStatus.nextReset
                    }
                }
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

    // MARK: - Tentar de novo

    /// Botão "Tentar agora": esquece as marcas de cota, limpa o aviso de
    /// servidor ocupado e repete a última pergunta.
    func retryServer() {
        serverBusyUntil = nil
        GeminiClient.resetLimits()

        guard !isSending else { return }
        guard let text = lastRequestText, let activeID = activeID else {
            banner = "Pode falar ou escrever de novo."
            return
        }

        // Tira a pergunta e a resposta que falhou para não duplicar nada.
        if let index = conversations.firstIndex(where: { $0.id == activeID }) {
            var messages = conversations[index].messages
            if let lastUser = messages.lastIndex(where: { $0.role == .user }) {
                messages.removeSubrange(lastUser..<messages.count)
            }
            conversations[index].messages = messages
        }

        banner = "Tentando de novo…"
        send(text, speakReply: lastRequestSpeak)
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
            self.serverBusyUntil = nil

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
            self.maybeExtractMemory()

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
        cameraEnabled = false
        camera.stop()

        // Deixa o alto-falante pronto antes da primeira resposta.
        player.prepare(voiceMode: true)

        Task {
            let allowed = await speech.requestAuthorization()
            await MainActor.run {
                if allowed {
                    // Deixa microfone e conexão prontos antes da primeira fala.
                    self.speech.warm()
                    GeminiClient.warmUp()
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
        cameraEnabled = false
        camera.stop()

        sendTask?.cancel()
        sendTask = nil
        cancelSpeechPipeline()
        speech.shutdown()
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

        speech.start(silence: 0.8)
    }

    private func handleHeard(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard voiceMode else { return }

        guard !clean.isEmpty else {
            // Evita um laço apertado se o reconhecedor falhar em sequência.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.listenAgain()
            }
            return
        }

        liveTranscript = clean
        voiceState = .thinking

        // Com a câmera ligada, manda o quadro atual junto: ele "vê" o que
        // está na sua frente enquanto responde.
        let frame = cameraEnabled ? camera.latestJPEG() : nil
        send(clean, speakReply: true, visionFrame: frame)
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
        speechChunkCount = 0
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

        speechChunkCount += 1
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
        // O primeiro pedaço é bem curto (aceita até vírgula) para a voz começar
        // quase junto com a resposta; depois agrupamos mais texto por pedido.
        let firstOfTurn = speechChunkCount == 0
        let minLength = firstOfTurn ? 14 : 150

        while true {
            let text = speechBuffer
            guard !text.isEmpty else { break }

            let isFirst = firstOfTurn && chunks.isEmpty
            let maxLength = isFirst ? 70 : 320
            var cut: String.Index?

            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]

                if isFirst && (character == "," || character == ";" || character == ":") {
                    let next = text.index(after: index)
                    if text.distance(from: text.startIndex, to: next) >= minLength {
                        cut = next
                        break
                    }
                }

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

    private func startBargeIn(after delay: TimeInterval = 0.35, attempt: Int = 0) {
        guard voiceMode else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.voiceMode else { return }

            let active = self.player.isPlaying || self.speechStreaming || self.isSending
            guard active else {
                // Se a resposta terminou e já voltamos a ouvir normalmente, não mexe.
                if self.voiceState == .listening { return }
                // A fala pode ainda estar sendo gerada; tenta de novo por alguns segundos.
                if attempt < 12 {
                    self.startBargeIn(after: 0.3, attempt: attempt + 1)
                }
                return
            }

            self.beginBargeInListening()
        }
    }

    private func beginBargeInListening() {
        speech.onPartial = { [weak self] text in
            guard let self = self else { return }
            let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard heard.split(separator: " ").count >= 2 else { return }
            if self.overlaps(heard, self.lastSpoken) { return }
            self.interrupt()
        }
        speech.onFinal = { [weak self] text in
            guard let self = self else { return }
            let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard heard.split(separator: " ").count >= 2 else { return }
            if self.overlaps(heard, self.lastSpoken) { return }
            self.interrupt()
        }
        speech.onError = { _ in }

        speech.start(silence: 30)
    }

    /// Interrompe pelo toque na tela (funciona mesmo se o microfone não pegar).
    func interruptFromUser() {
        guard voiceMode else { return }
        if player.isPlaying || speechStreaming || isSending {
            interrupt()
        }
    }

    private func interrupt() {
        sendTask?.cancel()
        sendTask = nil
        cancelSpeechPipeline()
        speech.stop()
        player.stop()
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

    // MARK: - Memória

    private func maybeExtractMemory() {
        guard settings.autoMemory else { return }

        turnsSinceMemory += 1
        guard turnsSinceMemory >= 4 else { return }
        turnsSinceMemory = 0

        let recent = messages
            .suffix(12)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.role == .user ? "Usuário" : "Joguim"): \($0.text.prefix(700))" }
            .joined(separator: "\n")
        guard !recent.isEmpty else { return }

        let known = settings.memories
        Task { [weak self] in
            let facts = (try? await GeminiClient.extractMemories(transcript: recent, known: known)) ?? []
            guard !facts.isEmpty else { return }
            await MainActor.run {
                guard let self = self else { return }
                for fact in facts {
                    let clean = fact.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard clean.count > 3 else { continue }
                    let already = self.settings.memories.contains {
                        $0.caseInsensitiveCompare(clean) == .orderedSame
                    }
                    if !already {
                        self.settings.memories.append(clean)
                    }
                }
                if self.settings.memories.count > 60 {
                    self.settings.memories = Array(self.settings.memories.suffix(60))
                }
                self.save()
            }
        }
    }

    func addMemory(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !settings.memories.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        settings.memories.append(clean)
        save()
    }

    func removeMemory(_ text: String) {
        settings.memories.removeAll { $0 == text }
        save()
    }

    // MARK: - Música

    func identifyMusic() {
        guard !musicRecorder.isRecording else { return }
        guard musicRecorder.start(seconds: 9) else {
            banner = "Não consegui ligar o microfone para ouvir a música."
            return
        }

        banner = "Ouvindo… toque ou cante a música agora."

        DispatchQueue.main.asyncAfter(deadline: .now() + 9.2) { [weak self] in
            self?.finishMusic()
        }
    }

    private func finishMusic() {
        guard let result = musicRecorder.finish() else {
            banner = "Não consegui ouvir nada. Tente de novo mais perto do som."
            return
        }

        guard let attachment = AttachmentStore.make(
            name: "musica.wav",
            mimeType: result.mimeType,
            data: result.data
        ) else {
            banner = "A gravação ficou grande demais."
            return
        }

        banner = nil
        send(
            "Identifique a música deste áudio. Se for alguém cantando a letra, pesquise o trecho na internet. Responda com o nome da música, o artista e o ano, e diga em qual trecho você se baseou.",
            attachments: [attachment]
        )
    }

    // MARK: - Câmera ao vivo

    func toggleCamera() {
        if cameraEnabled {
            cameraEnabled = false
            camera.stop()
            return
        }

        Task {
            let granted = await camera.requestAccess()
            await MainActor.run {
                guard granted else {
                    self.banner = "Autorize a câmera nos Ajustes do iPhone para o Joguim ver ao vivo."
                    return
                }
                self.camera.start()
                self.cameraEnabled = true
            }
        }
    }

    // MARK: - Ver a tela do iPhone

    /// Manda para o Joguim o print de tela mais recente da galeria.
    /// É o jeito de ele "ver a tela" do celular sem extensão de transmissão.
    func lookAtScreen() {
        guard voiceMode, !isSending else { return }

        voiceState = .thinking
        banner = nil

        Task {
            let allowed = await ScreenshotSource.requestAccess()
            guard allowed else {
                await MainActor.run {
                    self.voiceState = .listening
                    self.banner = "Autorize o acesso às Fotos nos Ajustes do iPhone para eu ver a sua tela."
                    self.listenAgain()
                }
                return
            }

            let shot = await ScreenshotSource.latest()
            await MainActor.run {
                guard let shot = shot else {
                    self.voiceState = .listening
                    self.banner = "Tire um print da tela (botão lateral + volume) e toque em Ver tela de novo."
                    self.listenAgain()
                    return
                }
                self.send(
                    "O que está nesta captura de tela? Me diga o que importa, em 2 frases.",
                    speakReply: true,
                    visionFrame: shot
                )
            }
        }
    }

    // MARK: - Gerar / editar imagem

    /// Detecta pedidos de imagem para não mandar para o modelo de conversa.
    private static func wantsImageEdit(_ text: String, attachments: [Attachment]) -> Bool {
        let lower = text.lowercased()
        let hasImage = attachments.contains { $0.isImage }

        let direct = [
            "desenhe", "desenhar", "desenha pra mim", "desenhe pra mim",
            "gere uma imagem", "gerar uma imagem", "crie uma imagem", "criar uma imagem",
            "gere uma foto", "gerar uma foto", "crie uma foto", "criar uma foto",
            "faça uma imagem", "fazer uma imagem", "faça uma foto", "fazer uma foto",
            "faca uma imagem", "faca uma foto", "quero uma imagem", "quero uma foto",
            "monte uma imagem", "monte uma foto", "produza uma imagem", "produza uma foto"
        ]
        if direct.contains(where: { lower.contains($0) }) { return true }

        let imageWords = [
            "imagem", "foto", "fotografia", "desenho", "ilustração", "ilustracao",
            "arte", "retrato", "selfie", "figura"
        ]
        let generateWords = [
            "gere", "gerar", "crie", "criar", "desenhe", "desenhar",
            "mostre", "mostra", "produza", "produzir", "monte", "montar",
            "quero uma", "quero um", "faça", "faca"
        ]
        let editStems = [
            "remov", "tir", "apag", "edit", "troc", "mud", "coloc", "adicion",
            "alter", "recort", "melhor", "deix", "transform", "corrig", "limp",
            "substitu"
        ]

        if hasImage && editStems.contains(where: { lower.contains($0) }) {
            return true
        }

        if imageWords.contains(where: { lower.contains($0) }),
           generateWords.contains(where: { lower.contains($0) }) {
            return true
        }

        return false
    }

    func generateImage(prompt raw: String, attachments: [Attachment] = []) {
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }
        guard hasKey else {
            banner = "Configure sua chave de acesso para gerar imagens."
            return
        }

        mutateActive { conversation in
            conversation.messages.append(
                ChatMessage(role: .user, text: prompt, attachments: attachments)
            )
        }

        let assistantID = UUID()
        mutateActive { conversation in
            conversation.messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))
        }

        isSending = true
        banner = nil

        let inputs: [(mimeType: String, data: Data)] = attachments.compactMap { attachment in
            guard attachment.isImage,
                  let data = AttachmentStore.data(for: attachment) else { return nil }
            return (attachment.mimeType, data)
        }

        sendTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let result = try await GeminiClient.generateImage(prompt: prompt, inputImages: inputs)
                await MainActor.run {
                    var saved: [Attachment] = []
                    for (index, image) in result.images.enumerated() {
                        let ext = image.mimeType.lowercased().contains("png") ? "png" : "jpg"
                        let name = "joguim-imagem-\(index + 1).\(ext)"
                        if let attachment = AttachmentStore.make(
                            name: name,
                            mimeType: image.mimeType,
                            data: image.data
                        ) {
                            saved.append(attachment)
                        }
                    }

                    self.mutateMessage(assistantID) { message in
                        message.text = result.text.isEmpty ? "Pronto! Aqui está a imagem." : result.text
                        message.attachments.append(contentsOf: saved)
                        if saved.isEmpty { message.isError = true }
                    }
                    // Em modo de voz o complete já fala sozinho.
                    self.complete(assistantID, speakReply: false)
                }
            } catch is CancellationError {
                self.complete(assistantID, speakReply: false, interrupted: true)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let server = error as? GeminiError, server.dailyQuota {
                    DispatchQueue.main.async {
                        self.serverBusyUntil = ServerStatus.nextReset
                    }
                }
                self.fail(assistantID, message)
            }
        }
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
