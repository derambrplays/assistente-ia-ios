import SwiftUI

struct ConversationsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var renameTarget: Conversation?
    @State private var renameText = ""

    /// Busca no título e no texto de todas as mensagens, ignorando acentos.
    private var filtered: [Conversation] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return store.conversations }

        let needle = clean
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .lowercased()

        return store.conversations.filter { conversation in
            let haystack = ([conversation.title] + conversation.messages.map { $0.text })
                .joined(separator: "\n")
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
                .lowercased()
            return haystack.contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    store.newConversation()
                    dismiss()
                } label: {
                    Label("Nova conversa", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                ForEach(filtered) { conversation in
                    Button {
                        store.open(conversation.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                Text(subtitle(for: conversation))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textFaint)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            if conversation.id == store.activeID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent2)
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            renameText = conversation.title
                            renameTarget = conversation
                        } label: {
                            Label("Renomear", systemImage: "pencil")
                        }

                        ShareLink(item: store.exportText(for: conversation)) {
                            Label("Compartilhar", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            store.delete(conversation.id)
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.compactMap { index -> UUID? in
                        guard index < filtered.count else { return nil }
                        return filtered[index].id
                    }
                    ids.forEach { store.delete($0) }
                }

                if filtered.isEmpty && !query.isEmpty {
                    Text("Nenhuma conversa com “\(query)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Conversas")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar nas conversas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .alert("Renomear conversa", isPresented: renameBinding) {
                TextField("Nome da conversa", text: $renameText)
                Button("Cancelar", role: .cancel) { renameTarget = nil }
                Button("Salvar") {
                    if let target = renameTarget {
                        store.rename(target.id, to: renameText)
                    }
                    renameTarget = nil
                }
            } message: {
                Text("Um nome curto ajuda a achar a conversa depois.")
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { showing in
                if !showing { renameTarget = nil }
            }
        )
    }

    /// Data e um resumo curto da última mensagem.
    private func subtitle(for conversation: Conversation) -> String {
        let date = conversation.updatedAt.formatted(date: .abbreviated, time: .shortened)
        let last = conversation.messages
            .last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let last, !last.isEmpty else { return date }
        let summary = last.replacingOccurrences(of: "\n", with: " ")
        return "\(date) · \(String(summary.prefix(48)))"
    }
}
