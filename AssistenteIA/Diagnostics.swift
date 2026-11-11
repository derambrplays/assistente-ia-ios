import Foundation

/// Diagnóstico da conexão com o servidor.
///
/// Faz um teste pequeno de verdade (lista de modelos + uma mensagem em cada
/// modelo + a voz) e guarda o resultado. Serve para descobrir se o problema é
/// cota, chave ou modelo — sem precisar de computador.
enum Diagnostics {
    private static let lock = NSLock()
    private static var lines: [String] = []

    static var summary: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    static func record(_ line: String) {
        lock.lock()
        lines.append("\(clock()) \(line)")
        if lines.count > 60 {
            lines.removeFirst(lines.count - 60)
        }
        lock.unlock()

        // Aparece no log do sistema, para eu conseguir ler pelo cabo.
        NSLog("[JoguimDiag] %@", line)
    }

    static func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }

    /// Quebra listas longas em várias linhas: o log pelo cabo corta linhas grandes.
    private static func recordList(_ prefix: String, _ items: [String]) {
        guard !items.isEmpty else {
            record("\(prefix) (vazio)")
            return
        }
        var index = 0
        while index < items.count {
            let end = min(index + 3, items.count)
            record("\(prefix) \(items[index..<end].joined(separator: ", "))")
            index = end
        }
    }

    private static func clock() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    /// Roda o teste completo. Chamado pelo botão "Diagnóstico" nos Ajustes.
    /// - Parameter deep: `false` faz só o teste de imagem (usado uma vez por
    ///   atualização, sem gastar a cota de voz e de conversa).
    static func run(primary: String, deep: Bool = true) async {
        clear()
        record(deep ? "teste iniciado" : "teste de imagem iniciado")

        guard GeminiClient.hasKey else {
            record("sem chave configurada")
            return
        }

        let count = await GeminiClient.modelCount()
        record("lista de modelos: \(count)")

        let all = await GeminiClient.modelIDs()
        recordList("ids:", all)

        let image = await GeminiClient.imageModels()
        recordList("imagem:", image)

        for model in image.prefix(3) {
            let status = await GeminiClient.probeImageModel(model)
            record("imagem teste \(model) -> \(status)")
        }

        // Teste de verdade, com um pedido mínimo: é o único jeito de saber se
        // a chave pode mesmo gerar imagem. Quatro modelos bastam para saber se
        // o bloqueio é da chave (todos falham igual) ou de um modelo só.
        for model in image.prefix(4) {
            let status = await GeminiClient.probeImageGenerate(model)
            record("imagem gerar \(model) -> \(status)")
        }

        // Uma palavra na voz natural: mostra na hora se o problema é cota.
        record("voz -> \(await GeminiClient.probeVoice())")
        record("voz iphone: \(AudioPlayer.offlineVoiceName) [\(AudioPlayer.offlineVoiceQuality)]")
        recordList("vozes pt:", AudioPlayer.portugueseVoiceNames)

        guard deep else {
            record("teste concluído")
            return
        }

        var candidates: [String] = [primary]
        for model in GeminiClient.chatFallbacks where !candidates.contains(model) {
            candidates.append(model)
        }
        for model in candidates.prefix(4) {
            let result = await GeminiClient.probe(model: model)
            record("chat \(model) -> \(result)")
        }

        if let first = candidates.first {
            let search = await GeminiClient.probeSearch(model: first)
            record("busca \(first) -> \(search)")
        }

        record("teste concluído")
    }
}
