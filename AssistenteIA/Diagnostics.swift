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

    private static func clock() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    /// Roda o teste completo. É chamado ao abrir o app e pelo botão dos Ajustes.
    static func run(primary: String) async {
        clear()
        record("teste iniciado")

        guard GeminiClient.hasKey else {
            record("sem chave configurada")
            return
        }

        let count = await GeminiClient.modelCount()
        record("lista de modelos: \(count)")

        var candidates: [String] = [primary]
        for model in GeminiClient.chatFallbacks where !candidates.contains(model) {
            candidates.append(model)
        }
        for model in candidates.prefix(4) {
            let result = await GeminiClient.probe(model: model)
            record("chat \(model) -> \(result)")
        }

        let tts = await GeminiClient.probeVoice()
        record("voz -> \(tts)")

        record("teste concluído")
    }
}
