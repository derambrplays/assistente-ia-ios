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

/// O que o Joguim sabe sobre a pessoa (preenchido na primeira conversa).
struct UserProfile: Codable, Equatable {
    var name: String = ""
    var age: String = ""
    var work: String = ""
    var city: String = ""
    var likes: String = ""
    var notes: String = ""

    var isEmpty: Bool {
        [name, age, work, city, likes, notes]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var promptLines: [String] {
        var lines: [String] = []
        if !name.isEmpty { lines.append("Nome: \(name)") }
        if !age.isEmpty { lines.append("Idade: \(age)") }
        if !work.isEmpty { lines.append("O que faz / trabalha: \(work)") }
        if !city.isEmpty { lines.append("Cidade: \(city)") }
        if !likes.isEmpty { lines.append("Gostos e interesses: \(likes)") }
        if !notes.isEmpty { lines.append("Outras informações: \(notes)") }
        return lines
    }
}

struct AppSettings: Codable, Equatable {
    var model: String = "gemini-flash-lite-latest"
    var temperature: Double = 0.8
    var systemPrompt: String = AppSettings.defaultSystem
    var ttsVoice: String = "Kore"
    var naturalVoice: Bool = true

    var profile = UserProfile()
    var onboardingDone = false
    var memories: [String] = []
    var autoMemory: Bool = true
    var useLocation: Bool = false

    static let defaultSystem = """
    Você é o Joguim AI, um assistente pessoal inteligente, caloroso e direto. Responda sempre em português do Brasil, a menos que o usuário peça outro idioma. Seja claro e objetivo; use listas curtas quando ajudar. Se não souber algo, diga que não sabe em vez de inventar. Ao escrever código, use blocos de código com a linguagem indicada. Use o que você sabe sobre o usuário e a memória para personalizar as respostas, sem repetir essas informações sem necessidade.
    """

    init() {}

    private enum CodingKeys: String, CodingKey {
        case model, temperature, systemPrompt, ttsVoice, naturalVoice
        case profile, onboardingDone, memories, autoMemory, useLocation
    }

    // Tolerante: configurações salvas por versões antigas continuam válidas.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "gemini-flash-lite-latest"
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.8
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? AppSettings.defaultSystem
        ttsVoice = try container.decodeIfPresent(String.self, forKey: .ttsVoice) ?? "Kore"
        naturalVoice = try container.decodeIfPresent(Bool.self, forKey: .naturalVoice) ?? true
        profile = try container.decodeIfPresent(UserProfile.self, forKey: .profile) ?? UserProfile()
        onboardingDone = try container.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        memories = try container.decodeIfPresent([String].self, forKey: .memories) ?? []
        autoMemory = try container.decodeIfPresent(Bool.self, forKey: .autoMemory) ?? true
        useLocation = try container.decodeIfPresent(Bool.self, forKey: .useLocation) ?? false
    }

    /// Junta personalidade + perfil + memória + localização num único texto de sistema.
    func composedSystem(location: String?) -> String {
        var blocks: [String] = [systemPrompt]

        let lines = profile.promptLines
        if !lines.isEmpty {
            blocks.append("Sobre o usuário:\n" + lines.joined(separator: "\n"))
        }

        let cleanMemories = memories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanMemories.isEmpty {
            let recent = cleanMemories.suffix(50)
            blocks.append("Memória (fatos importantes que você deve lembrar):\n" + recent.map { "- \($0)" }.joined(separator: "\n"))
        }

        if let location, !location.isEmpty {
            blocks.append("Localização atual do usuário: \(location). Quando ele perguntar por lugares próximos (escola, mercado, farmácia, restaurante), use a busca do Google com essa localização para responder com nomes reais e a distância aproximada.")
        }

        if !profile.name.isEmpty {
            blocks.append("Trate o usuário pelo nome (\(profile.name)) de vez em quando, sem exagero.")
        }

        // Garante o nome novo mesmo quando a personalidade foi escrita antes
        // da troca de nome (configurações antigas continuam válidas).
        if systemPrompt.range(of: "Joguim", options: .caseInsensitive) == nil {
            blocks.append("Seu nome é Joguim AI. Se a personalidade acima disser outro nome, use Joguim AI.")
        }

        blocks.append("""
        Quem criou você: Kalleb Ribeiro de Souza Silva. \
        Se perguntarem quem te criou, quem te desenvolveu, quem é o seu dono ou de onde você veio, \
        responda que foi criado por Kalleb Ribeiro de Souza Silva. \
        Nunca diga que foi feito por outra empresa, marca ou assistente, e não mencione nomes de modelos ou empresas por trás do app.
        """)

        return blocks.joined(separator: "\n\n")
    }
}

struct PersistedState: Codable {
    var conversations: [Conversation] = []
    var activeID: UUID?
    var settings: AppSettings = AppSettings()
}
