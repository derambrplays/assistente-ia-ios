import Foundation

/// Fonte da web devolvida pela busca do Google (grounding).
struct WebSource: Identifiable, Codable, Equatable, Hashable {
    var title: String
    var uri: String

    var id: String { uri }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id: UUID
    var role: Role
    var text: String
    var isError: Bool
    var date: Date
    var attachments: [Attachment]
    var sources: [WebSource]

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        isError: Bool = false,
        date: Date = Date(),
        attachments: [Attachment] = [],
        sources: [WebSource] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isError = isError
        self.date = date
        self.attachments = attachments
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text, isError, date, attachments, sources
    }

    // Decodificação tolerante: conversas salvas por versões antigas (sem
    // anexos/fontes) continuam funcionando depois da atualização.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        sources = try container.decodeIfPresent([WebSource].self, forKey: .sources) ?? []
    }
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
