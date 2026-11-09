import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: ChatStore
    @Binding var showSettings: Bool
    @Binding var showConversations: Bool

    @State private var draft = ""
    @State private var attachments: [Attachment] = []
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "Pesquise na internet as notícias de hoje",
        "Explique algo complicado de um jeito simples",
        "Resuma o arquivo que eu anexar",
        "Monte um plano para a minha semana"
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            messageList
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(
                text: $draft,
                attachments: $attachments,
                isSending: store.isSending,
                focused: $inputFocused,
                onSend: send,
                onStop: { store.stop() },
                onVoice: { store.startVoiceMode() },
                onError: { store.banner = $0 }
            )
        }
    }

    // MARK: - Barra superior

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                showConversations = true
            } label: {
                GlassButtonLabel(icon: "line.3.horizontal")
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: 1) {
                Text(store.activeTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(store.settings.model)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                showSettings = true
            } label: {
                GlassButtonLabel(icon: "slider.horizontal.3")
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
        }
    }

    // MARK: - Mensagens

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if store.messages.isEmpty {
                        welcome
                    }

                    ForEach(store.messages) { message in
                        MessageRow(message: message) {
                            store.speak(message.text)
                        }
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: store.messages.last?.text.count ?? 0) { _ in
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let scroll = { proxy.scrollTo("bottom", anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { scroll() }
        } else {
            scroll()
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SparkleMark(size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assistente IA")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Seu assistente pessoal, por texto, voz e arquivos.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textDim)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 4)

            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    draft = suggestion
                    send()
                } label: {
                    HStack(spacing: 10) {
                        Text(suggestion)
                            .font(.system(size: 14.5))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(radius: 18, strength: 0.75)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let pending = attachments
        draft = ""
        attachments = []
        inputFocused = false
        store.send(text, attachments: pending)
    }
}
