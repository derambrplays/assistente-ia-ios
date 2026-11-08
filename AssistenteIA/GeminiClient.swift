import Foundation

struct GeminiError: LocalizedError {
    let message: String
    var retryable: Bool = false

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
        case 429: return "Limite de uso atingido. Aguarde um pouco e tente de novo."
        case 500, 502, 503: return "O Gemini está sobrecarregado agora. Tente de novo em instantes."
        default: return "Erro \(code) ao falar com o Gemini."
        }
    }

    private static func applyHeaders(_ request: inout URLRequest, key: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
    }

    // MARK: - Conversa (streaming)

    static func streamChat(
        messages: [ChatMessage],
        system: String,
        model: String,
        temperature: Double,
        onDelta: @escaping (String) -> Void
    ) async throws {
        let key = apiKey
        guard !key.isEmpty else {
            throw GeminiError(message: "Configure sua chave do Gemini para começar.")
        }

        var contents: [[String: Any]] = []
        for message in messages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            contents.append([
                "role": message.role == .user ? "user" : "model",
                "parts": [["text": text]]
            ])
        }
        if contents.count > 40 {
            contents = Array(contents.suffix(40))
        }
        while let first = contents.first, (first["role"] as? String) == "model" {
            contents.removeFirst()
        }
        guard !contents.isEmpty else {
            throw GeminiError(message: "Escreva ou fale alguma coisa para enviar.")
        }

        let generation: [String: Any] = [
            "temperature": max(0.0, min(2.0, temperature)),
            "maxOutputTokens": 8192
        ]

        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": system]]],
            "generationConfig": generation
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var candidates = [model]
        for fallback in chatFallbacks where fallback != model {
            candidates.append(fallback)
        }

        var lastError: GeminiError = GeminiError(message: "O Gemini não respondeu. Tente de novo.")
        for candidate in candidates {
            var emitted = false
            do {
                try await streamOnce(model: candidate, bodyData: bodyData, key: key) { delta in
                    emitted = true
                    onDelta(delta)
                }
                return
            } catch let error as GeminiError {
                if emitted { throw error }
                lastError = error
                if error.retryable { continue }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = GeminiError(message: error.localizedDescription, retryable: true)
            }
        }
        throw lastError
    }

    private static func streamOnce(
        model: String,
        bodyData: Data,
        key: String,
        onDelta: @escaping (String) -> Void
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
                if detail.count > 400 { break }
            }
            let retryable = [429, 500, 502, 503].contains(http.statusCode)
            throw GeminiError(
                message: friendly(http.statusCode),
                retryable: retryable
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
                  let content = candidates.first?["content"] as? [String: Any],
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

        let blocked = ["image", "imagen", "tts", "transcribe", "lyria", "embed", "aqa", "veo", "robotics", "computer-use", "deep-research"]
        var found: [String] = []
        for model in models {
            guard let name = model["name"] as? String else { continue }
            let id = name.split(separator: "/").last.map(String.init) ?? name
            let lower = id.lowercased()
            if blocked.contains(where: { lower.contains($0) }) { continue }
            if !lower.contains("gemini") { continue }
            if !found.contains(id) { found.append(id) }
        }

        if found.isEmpty { return chatFallbacks }
        found.sort()
        return found
    }
}
