import Foundation

struct GeminiError: LocalizedError {
    let message: String
    var retryable: Bool = false
    var status: Int = 0
    var dailyQuota: Bool = false

    var errorDescription: String? { message }
}

enum GeminiClient {
    static let apiBase = "https://generativelanguage.googleapis.com/v1beta"

    static let chatFallbacks = [
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-flash-lite-latest",
        "gemini-2.5-flash"
    ]

    static let ttsModels = [
        "gemini-3.8-flash-lite-tts",
        "gemini-3.8-flash-tts",
        "gemini-2.5-flash-preview-tts"
    ]

    static let voices = [
        "Kore", "Puck", "Charon", "Aoede", "Leda", "Orus",
        "Zephyr", "Sulafat", "Achird", "Laomedeia", "Callirrhoe", "Fenrir"
    ]

    /// Prefere modelos rápidos e baratos, mas mantém os demais como alternativa.
    private static func preferenceScore(_ id: String) -> Int {
        let lower = id.lowercased()
        var score = 0
        if lower.contains("flash") { score += 40 }
        if lower.contains("lite") { score += 12 }
        if lower.contains("pro") { score += 6 }
        if lower.contains("latest") { score += 5 }
        if lower.contains("preview") || lower.contains("exp") { score -= 4 }
        if lower.hasSuffix("-001") || lower.hasSuffix("-002") || lower.hasSuffix("-003") { score -= 3 }
        if lower.contains("thinking") { score -= 2 }
        return score
    }

    static func preferredOrder(_ models: [String]) -> [String] {
        models.sorted { a, b in
            let sa = preferenceScore(a)
            let sb = preferenceScore(b)
            if sa != sb { return sa > sb }
            return a < b
        }
    }

    private static let modelCacheLock = NSLock()
    private static var modelCache: [String] = []
    private static var modelCacheDate: Date?

    /// Lista de modelos de conversa disponíveis, priorizando os mais adequados.
    static func chatModels() async -> [String] {
        modelCacheLock.lock()
        let cached = modelCache
        let stamp = modelCacheDate
        modelCacheLock.unlock()

        if !cached.isEmpty, let stamp, Date().timeIntervalSince(stamp) < 600 {
            return cached
        }

        let listed = (try? await listModels()) ?? []
        let ordered = preferredOrder(listed.filter { !$0.isEmpty })
        let result = ordered.isEmpty ? chatFallbacks : ordered

        modelCacheLock.lock()
        modelCache = result
        modelCacheDate = Date()
        modelCacheLock.unlock()
        return result
    }

    static var apiKey: String {
        (Keychain.load() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasKey: Bool { !apiKey.isEmpty }

    private static func friendly(_ code: Int) -> String {
        switch code {
        case 400: return "Requisição inválida. Verifique o modelo escolhido nas Configurações."
        case 401, 403: return "Chave do Gemini inválida ou sem permissão. Confira a chave nas Configurações."
        case 404: return "Modelo não encontrado. Escolha outro nas Configurações."
        case 413: return "Arquivo muito grande para enviar."
        case 429: return "O limite de uso do Gemini foi atingido. Se for a cota diária, troque de modelo nas Configurações (cada modelo tem cota própria) ou aguarde a renovação, à meia-noite no horário do Pacífico."
        case 500, 502, 503: return "O Gemini está sobrecarregado agora. Tente de novo em instantes."
        default: return "Erro \(code) ao falar com o Gemini."
        }
    }

    private static func applyHeaders(_ request: inout URLRequest, key: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    }

    static let searchInstruction = """

    Você tem acesso à busca do Google. Use a busca sempre que o usuário pedir para pesquisar na internet, conferir algo, ou quando a resposta depender de informações atuais, notícias ou dados recentes. Baseie a resposta nos resultados encontrados e cite as fontes.
    """

    private static let searchLock = NSLock()
    private static var searchUnsupported: Set<String> = []

    private static func supportsSearch(_ model: String) -> Bool {
        searchLock.lock()
        defer { searchLock.unlock() }
        return !searchUnsupported.contains(model)
    }

    private static func markSearchUnsupported(_ model: String) {
        searchLock.lock()
        searchUnsupported.insert(model)
        searchLock.unlock()
    }

    // MARK: - Cota diária (cada modelo tem a própria cota no plano gratuito)

    private static let quotaLock = NSLock()
    private static var exhaustedModels: Set<String> = []
    private static var quotaDay: String = ""

    private static func dayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return formatter.string(from: Date())
    }

    private static func refreshQuotaDayLocked() {
        let day = dayKey()
        if quotaDay != day {
            quotaDay = day
            exhaustedModels.removeAll()
        }
    }

    static func isExhausted(_ model: String) -> Bool {
        quotaLock.lock()
        defer { quotaLock.unlock() }
        refreshQuotaDayLocked()
        return exhaustedModels.contains(model)
    }

    static func exhaustedList() -> Set<String> {
        quotaLock.lock()
        defer { quotaLock.unlock() }
        refreshQuotaDayLocked()
        return exhaustedModels
    }

    private static func markExhausted(_ model: String) {
        quotaLock.lock()
        refreshQuotaDayLocked()
        exhaustedModels.insert(model)
        quotaLock.unlock()
    }

    // MARK: - Conversa (streaming)

    private static func contentParts(
        for message: ChatMessage,
        budget: inout Int
    ) -> [[String: Any]] {
        var parts: [[String: Any]] = []

        for attachment in message.attachments {
            if attachment.isText, let text = AttachmentStore.text(for: attachment) {
                guard attachment.byteCount <= budget else { continue }
                budget -= attachment.byteCount
                parts.append(["text": "Arquivo anexado: \(attachment.name)\n\n\(text)"])
                continue
            }

            guard let data = AttachmentStore.data(for: attachment) else { continue }
            guard data.count <= budget else {
                parts.append([
                    "text": "[O arquivo \(attachment.name) não foi incluído porque o limite de tamanho da conversa foi atingido.]"
                ])
                continue
            }
            budget -= data.count
            parts.append([
                "inlineData": [
                    "mimeType": attachment.mimeType,
                    "data": data.base64EncodedString()
                ]
            ])
        }

        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            parts.append(["text": text])
        }
        return parts
    }

    private static func requestBody(
        contents: [[String: Any]],
        system: String,
        temperature: Double,
        search: Bool
    ) throws -> Data {
        let systemText = search ? system + searchInstruction : system
        var body: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": systemText]]],
            "generationConfig": [
                "temperature": max(0.0, min(2.0, temperature)),
                "maxOutputTokens": 8192
            ]
        ]
        if search {
            body["tools"] = [["google_search": [String: Any]()]]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func streamChat(
        messages: [ChatMessage],
        system: String,
        model: String,
        temperature: Double,
        search: Bool = true,
        onDelta: @escaping (String) -> Void,
        onSources: (([WebSource]) -> Void)? = nil
    ) async throws {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError(message: "Configure sua chave do Gemini para começar.")
        }

        var contents: [[String: Any]] = []
        var budget = AttachmentStore.maxTotalBytes
        for message in messages.reversed() {
            let parts = contentParts(for: message, budget: &budget)
            guard !parts.isEmpty else { continue }
            contents.append([
                "role": message.role == .user ? "user" : "model",
                "parts": parts
            ])
        }
        contents.reverse()

        if contents.count > 40 {
            contents = Array(contents.suffix(40))
        }
        while let first = contents.first, (first["role"] as? String) == "model" {
            contents.removeFirst()
        }
        guard !contents.isEmpty else {
            throw GeminiError(message: "Escreva ou fale alguma coisa para enviar.")
        }

        var candidates: [String] = []
        for candidate in [model] + (await chatModels()) + chatFallbacks where !candidates.contains(candidate) {
            candidates.append(candidate)
        }

        let withQuota = candidates.filter { !isExhausted($0) }
        if withQuota.isEmpty {
            throw GeminiError(
                message: """
                A cota diária gratuita do Gemini acabou para todos os modelos conhecidos. \
                Ela renova à meia-noite no horário do Pacífico (por volta das 05h no Brasil). \
                Se quiser continuar agora, crie outra chave no Google AI Studio e cole nas Configurações.
                """,
                status: 429,
                dailyQuota: true
            )
        }
        candidates = Array(withQuota.prefix(6))

        let hasMedia = contents.contains { content in
            guard let parts = content["parts"] as? [[String: Any]] else { return false }
            return parts.contains { $0["inlineData"] != nil }
        }

        var lastError = GeminiError(message: "O Gemini não respondeu. Tente de novo.")
        for candidate in candidates {
            var tryingSearch = search && supportsSearch(candidate)
            while true {
                var emitted = false
                do {
                    let bodyData = try requestBody(
                        contents: contents,
                        system: system,
                        temperature: temperature,
                        search: tryingSearch
                    )
                    try await streamOnce(
                        model: candidate,
                        bodyData: bodyData,
                        key: key,
                        onDelta: { delta in
                            emitted = true
                            onDelta(delta)
                        },
                        onSources: onSources
                    )
                    return
                } catch let error as GeminiError {
                    if emitted { throw error }
                    // Alguns modelos não aceitam a ferramenta de busca.
                    // Tenta o mesmo modelo sem ela antes de trocar de modelo.
                    if tryingSearch && error.status == 400 {
                        markSearchUnsupported(candidate)
                        tryingSearch = false
                        continue
                    }
                    if error.dailyQuota { markExhausted(candidate) }
                    lastError = error
                    // Modelo sem cota hoje, inexistente, ou que não aceita imagem:
                    // em vez de desistir, tenta o próximo da lista.
                    if error.retryable || error.status == 404 || (error.status == 400 && hasMedia) {
                        break
                    }
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    lastError = GeminiError(message: error.localizedDescription, retryable: true)
                    break
                }
            }
        }
        throw lastError
    }

    /// Extrai a mensagem real devolvida pela API, para diagnóstico.
    private static func apiReason(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any] {
            let status = (error["status"] as? String) ?? ""
            let message = (error["message"] as? String) ?? ""
            let joined = [status, message].filter { !$0.isEmpty }.joined(separator: " — ")
            if !joined.isEmpty { return String(joined.prefix(300)) }
        }

        return String(trimmed.prefix(300))
    }

    /// Identifica se o 429 é cota diária (e não apenas limite por minuto).
    private static func isDailyQuota(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("perday")
            || lower.contains("per day")
            || lower.contains("daily")
            || lower.contains("por dia")
    }

    private static func streamOnce(
        model: String,
        bodyData: Data,
        key: String,
        onDelta: @escaping (String) -> Void,
        onSources: (([WebSource]) -> Void)?
    ) async throws {
        guard let url = URL(string: "\(apiBase)/models/\(model):streamGenerateContent?alt=sse") else {
            throw GeminiError(message: "Endereço inválido.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        applyHeaders(&request, key: key)
        request.httpBody = bodyData

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError(message: "Resposta inválida do servidor.", retryable: true)
        }

        if http.statusCode != 200 {
            var detail = ""
            for try await line in bytes.lines {
                detail += line
                if detail.count > 800 { break }
            }
            let retryable = [429, 500, 502, 503].contains(http.statusCode)
            let base = friendly(http.statusCode)
            let reason = apiReason(from: detail)
            let message = reason.isEmpty ? base : "\(base)\n\nDetalhe da API (\(http.statusCode)): \(reason)"
            let daily = http.statusCode == 429 && isDailyQuota(detail)
            throw GeminiError(
                message: message,
                retryable: retryable,
                status: http.statusCode,
                dailyQuota: daily
            )
        }

        var gotAny = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            guard let candidates = object["candidates"] as? [[String: Any]],
                  let candidate = candidates.first else {
                continue
            }

            if let sources = webSources(from: candidate), !sources.isEmpty {
                onSources?(sources)
            }

            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    gotAny = true
                    onDelta(text)
                }
            }
        }

        if !gotAny {
            throw GeminiError(message: "O Gemini não respondeu. Tente de novo.", retryable: true)
        }
    }

    private static func webSources(from candidate: [String: Any]) -> [WebSource]? {
        guard let metadata = candidate["groundingMetadata"] as? [String: Any],
              let chunks = metadata["groundingChunks"] as? [[String: Any]] else {
            return nil
        }
        var sources: [WebSource] = []
        for chunk in chunks {
            guard let web = chunk["web"] as? [String: Any],
                  let uri = web["uri"] as? String, !uri.isEmpty else {
                continue
            }
            let title = (web["title"] as? String) ?? uri
            if !sources.contains(where: { $0.uri == uri }) {
                sources.append(WebSource(title: title, uri: uri))
            }
        }
        return sources
    }

    // MARK: - Voz (Gemini TTS)

    static func speak(text: String, voice: String) async throws -> Data {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError(message: "Configure sua chave do Gemini para usar a voz.")
        }

        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !clean.isEmpty else {
            throw GeminiError(message: "Não há texto para falar.")
        }
        let chosenVoice = voices.contains(voice) ? voice : "Kore"

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": clean]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": ["voiceName": chosenVoice]
                    ]
                ]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var lastError = GeminiError(message: "Não consegui gerar a voz.", retryable: true)

        for model in ttsModels {
            guard let url = URL(string: "\(apiBase)/models/\(model):generateContent") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            applyHeaders(&request, key: key)
            request.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard http.statusCode == 200 else {
                    lastError = GeminiError(message: friendly(http.statusCode), retryable: true)
                    continue
                }
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = object["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    lastError = GeminiError(message: "O Google não devolveu o áudio.", retryable: true)
                    continue
                }
                for part in parts {
                    guard let inline = part["inlineData"] as? [String: Any],
                          let base64 = inline["data"] as? String,
                          let audio = Data(base64Encoded: base64) else { continue }
                    let mime = (inline["mimeType"] as? String) ?? "audio/wav"
                    if mime.contains("wav") {
                        return audio
                    }
                    return wavFromPCM(audio)
                }
                lastError = GeminiError(message: "O Google não devolveu o áudio.", retryable: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = GeminiError(message: error.localizedDescription, retryable: true)
            }
        }

        throw lastError
    }

    /// O Gemini devolve PCM 16-bit, 24 kHz, mono. Empacota num WAV para o player.
    private static func wavFromPCM(_ pcm: Data, sampleRate: Int = 24000) -> Data {
        var data = Data()

        func ascii(_ text: String) {
            data.append(text.data(using: .ascii) ?? Data())
        }
        func u32(_ value: UInt32) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        func u16(_ value: UInt16) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        ascii("RIFF")
        u32(UInt32(36 + pcm.count))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    // MARK: - Transcrição (fallback quando o ditado do iPhone não está disponível)

    static func transcribe(audio: Data, mimeType: String) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError(message: "Configure sua chave do Gemini.")
        }

        let prompt = "Transcreva fielmente o que é falado neste áudio, em português do Brasil. Devolva apenas o texto falado, sem comentários, sem aspas, sem títulos e sem formatação. Use pontuação natural. Se não houver fala, devolva uma resposta vazia."

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inlineData": ["mimeType": mimeType, "data": audio.base64EncodedString()]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": ["temperature": 0.0, "maxOutputTokens": 2048]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        for model in ["gemini-3.5-flash-lite", "gemini-2.5-flash"] {
            guard let url = URL(string: "\(apiBase)/models/\(model):generateContent") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            applyHeaders(&request, key: key)
            request.httpBody = bodyData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = object["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }
            var text = ""
            for part in parts {
                if let piece = part["text"] as? String {
                    text += piece
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw GeminiError(message: "Não consegui entender o áudio. Tente falar de novo.")
    }

    // MARK: - Memória automática

    static func extractMemories(transcript: String, known: [String]) async throws -> [String] {
        guard !apiKey.isEmpty else { return [] }

        let knownText = known.suffix(30).map { "- \($0)" }.joined(separator: "\n")
        let prompt = """
        Leia a conversa abaixo e liste apenas fatos duradouros e úteis sobre o usuário \
        (gostos, rotina, trabalho, estudos, família, planos, preferências, restrições). \
        Não inclua detalhes passageiros nem o que o assistente disse. \
        Ignore o que já está na memória atual. \
        Responda SOMENTE com um array JSON de frases curtas em português, no máximo 3 itens. \
        Se não houver nada novo e importante, responda [].

        Memória atual:
        \(knownText.isEmpty ? "(vazia)" : knownText)

        Conversa:
        \(transcript)
        """

        let text = try await quickText(prompt: prompt, maxTokens: 400, temperature: 0.2)
        return parseStringArray(text)
    }

    private static func parseStringArray(_ raw: String) -> [String] {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "```json", with: "")
        clean = clean.replacingOccurrences(of: "```", with: "")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = clean.firstIndex(of: "["),
           let end = clean.lastIndex(of: "]"),
           start < end {
            clean = String(clean[start...end])
        }

        guard let data = clean.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }

        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Pedido curto sem streaming, para tarefas internas (memória).
    static func quickText(prompt: String, maxTokens: Int = 400, temperature: Double = 0.3) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError(message: "Configure sua chave do Gemini.")
        }

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": max(0.0, min(2.0, temperature)),
                "maxOutputTokens": maxTokens
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var models = Array((await chatModels()).prefix(3))
        if !models.contains("gemini-flash-lite-latest") {
            models.append("gemini-flash-lite-latest")
        }

        var lastError = GeminiError(message: "O Gemini não respondeu.", retryable: true)

        for model in models where !isExhausted(model) {
            guard let url = URL(string: "\(apiBase)/models/\(model):generateContent") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            applyHeaders(&request, key: key)
            request.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                guard http.statusCode == 200 else {
                    if http.statusCode == 429 { markExhausted(model) }
                    lastError = GeminiError(
                        message: friendly(http.statusCode),
                        retryable: true,
                        status: http.statusCode
                    )
                    continue
                }

                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = object["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    continue
                }

                var text = ""
                for part in parts {
                    if let piece = part["text"] as? String {
                        text += piece
                    }
                }
                if !text.isEmpty { return text }
            } catch {
                lastError = GeminiError(message: error.localizedDescription, retryable: true)
            }
        }

        throw lastError
    }

    // MARK: - Modelos disponíveis

    static func listModels() async throws -> [String] {
        let key = apiKey
        guard !key.isEmpty else { return chatFallbacks }

        guard let url = URL(string: "\(apiBase)/models?pageSize=1000") else {
            return chatFallbacks
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        applyHeaders(&request, key: key)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else {
            return chatFallbacks
        }

        let blocked = [
            "image", "imagen", "tts", "transcribe", "lyria", "embed", "aqa", "veo",
            "robotics", "computer-use", "deep-research", "live", "native-audio", "realtime"
        ]
        var found: [String] = []
        for model in models {
            guard let name = model["name"] as? String else { continue }
            let id = name.split(separator: "/").last.map(String.init) ?? name
            let lower = id.lowercased()
            if blocked.contains(where: { lower.contains($0) }) { continue }
            if !lower.contains("gemini") { continue }

            let methods = (model["supportedGenerationMethods"] as? [String]) ?? []
            if !methods.isEmpty && !methods.contains("generateContent") { continue }

            if !found.contains(id) { found.append(id) }
        }

        if found.isEmpty { return chatFallbacks }
        return preferredOrder(found)
    }
}
