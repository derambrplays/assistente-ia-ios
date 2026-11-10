import SwiftUI

/// Primeira abertura: o Joguim se apresenta e pergunta o básico sobre a pessoa.
struct OnboardingView: View {
    @EnvironmentObject private var store: ChatStore

    @State private var name = ""
    @State private var age = ""
    @State private var work = ""
    @State private var city = ""
    @State private var likes = ""
    @State private var remember = true
    @State private var step = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, age, work, city, likes
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    switch step {
                    case 0: basicsCard
                    default: tasteCard
                    }

                    actions
                }
                .padding(20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            SparkleMark(size: 62)

            Text("Oi! Eu sou o Joguim AI")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(step == 0
                 ? "Antes de começar, me conta um pouco sobre você. Isso deixa minhas respostas muito mais úteis — e fica só no seu iPhone."
                 : "Quase pronto. Mais duas coisinhas e a gente já conversa.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Seu nome", placeholder: "Como quer ser chamado?", text: $name, field: .name)

            HStack(spacing: 12) {
                field("Idade", placeholder: "Ex.: 17", text: $age, field: .age)
                    .frame(width: 110)
                field("Cidade", placeholder: "Onde você mora?", text: $city, field: .city)
            }

            field("O que você faz", placeholder: "Estuda, trabalha, com o quê?", text: $work, field: .work)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 30, strength: 0.85)
    }

    private var tasteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(
                "Do que você gosta",
                placeholder: "Música, jogos, esportes, séries…",
                text: $likes,
                field: .likes,
                lines: 3
            )

            Toggle(isOn: $remember) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Memória do Joguim")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Ele guarda sozinho o que for importante (gostos, rotina, planos) para lembrar nas próximas conversas.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .tint(Theme.accent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 30, strength: 0.85)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if step == 0 {
                    focus = nil
                    withAnimation(.easeInOut(duration: 0.25)) { step = 1 }
                } else {
                    finish()
                }
            } label: {
                Text(step == 0 ? "Continuar" : "Começar a conversar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28))
                    )
                    .shadow(color: Theme.accent.opacity(0.45), radius: 20, x: 0, y: 10)
            }
            .buttonStyle(PressableStyle())

            if step == 0 {
                Button("Pular por agora") {
                    finish()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .padding(.vertical, 6)
            }
        }
    }

    private func field(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        lines: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textDim)

            TextField(placeholder, text: text, axis: lines > 1 ? .vertical : .horizontal)
                .lineLimit(lines > 1 ? 1...lines : 1...1)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($focus, equals: field)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )
        }
    }

    private func finish() {
        focus = nil
        var profile = store.settings.profile
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.age = age.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.work = work.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.likes = likes.trimmingCharacters(in: .whitespacesAndNewlines)

        store.settings.profile = profile
        store.settings.autoMemory = remember
        store.settings.onboardingDone = true
        store.save()
    }
}
