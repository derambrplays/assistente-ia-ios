import SwiftUI

/// Tela de novidades: abre sozinha quando o app é atualizado e também pode
/// ser aberta pelos Ajustes.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // Só a versão atual e a anterior: nada de arrastar histórico antigo.
                    ForEach(Array(Changelog.releases.prefix(2).enumerated()), id: \.element.id) { index, release in
                        releaseCard(release, isLatest: index == 0)
                    }

                    continueButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 30)
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent2],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Novidades")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Versão \(AppInfo.version) (\(AppInfo.build))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textDim)
                }
            }

            Text("O que foi atualizado e melhorado no Joguim AI.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Cartão de cada versão

    private func releaseCard(_ release: ChangelogRelease, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("v\(release.version)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isLatest ? Theme.bg : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            isLatest ? Theme.accent2 : Color.white.opacity(0.12)
                        )
                    )

                Text(release.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(release.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent2)
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(item.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 26, strength: isLatest ? 1.0 : 0.65)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    isLatest ? Theme.accent2.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Botão

    private var continueButton: some View {
        Button {
            onClose?()
            dismiss()
        } label: {
            Text("Continuar")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accent.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22)))
                .shadow(color: Theme.accent.opacity(0.4), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(PressableStyle())
        .padding(.top, 4)
    }
}
