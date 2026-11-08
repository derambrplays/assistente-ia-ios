import SwiftUI

struct ConversationsView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss

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

                ForEach(store.conversations) { conversation in
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

                                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textFaint)
                            }

                            Spacer(minLength: 0)

                            if conversation.id == store.activeID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent2)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.compactMap { index -> UUID? in
                        guard index < store.conversations.count else { return nil }
                        return store.conversations[index].id
                    }
                    ids.forEach { store.delete($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Conversas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
