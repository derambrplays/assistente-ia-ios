import SwiftUI
import UIKit

struct KeyEntryView: View {
    @EnvironmentObject private var store: ChatStore

    @State private var draft = ""
    @State private var showKey = false
    @FocusState private var focused: Bool

    private var clean: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    SparkleMark(size: 76)

                    Text("Joguim AI")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Seu assistente pessoal com voz, rodando inteiro neste iPhone.")
                        .font(.system(size: 14.5))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textDim)
                        .padding(.horizontal, 24)

                    Text("Criado por \(AppInfo.creator)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent2)
                }
                .padding(.top, 46)

                card

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                    Text("A chave fica guardada no Keychain do iPhone.")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(Theme.textFaint)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sua chave de acesso", systemImage: "key.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("Cole aqui a sua chave de acesso. É gratuita para uso pessoal e fica só neste iPhone.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textDim)

            HStack(spacing: 8) {
                Group {
                    if showKey {
                        TextField("AIza…", text: $draft)
                    } else {
                        SecureField("AIza…", text: $draft)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)

                Button {
                    if let pasted = UIPasteboard.general.string {
                        draft = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent2)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                        .overlay(Circle().strokeBorder(Theme.hairline))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )

            Toggle("Mostrar chave", isOn: $showKey)
                .font(.system(size: 12.5))
                .tint(Theme.accent)

            Button(action: commit) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Começar a usar")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25))
                )
            }
            .buttonStyle(PressableStyle())
            .disabled(clean.isEmpty)
            .opacity(clean.isEmpty ? 0.45 : 1)

            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                HStack(spacing: 6) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 12))
                    Text("Pegar minha chave de acesso")
                        .font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Theme.accent2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func commit() {
        guard !clean.isEmpty else { return }
        focused = false
        store.saveKey(clean)
        draft = ""
    }
}
