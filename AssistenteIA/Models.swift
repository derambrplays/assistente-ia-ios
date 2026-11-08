import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var text: String
    var isError: Bool = false
    var date: Date = Date()
}

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "Nova conversa"
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()
}

struct AppSettings: Codable, Equatable {
    var model: String = "gemini-3.5-flash-lite"
    var temperature: Double = 0.8
    var systemPrompt: String = AppSettings.defaultSystem
    var ttsVoice: String = "Kore"
    var naturalVoice: Bool = true

    static let defaultSystem = """
    Você é um assistente pessoal inteligente, prestativo e direto. Responda sempre em português do Brasil, a menos que o usuário peça outro idioma. Seja claro e objetivo; use listas e exemplos quando ajudar. Se não souber algo, diga que não sabe em vez de inventar. Ao escrever código, use blocos de código com a linguagem indicada.
    """
}

struct PersistedState: Codable {
    var conversations: [Conversation] = []
    var activeID: UUID?
    var settings: AppSettings = AppSettings()
}
