import Foundation

enum AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    /// Muda a cada atualização instalada (versão + build).
    static var buildKey: String { "\(version) (\(build))" }
}

struct ChangelogItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

struct ChangelogRelease: Identifiable {
    let id = UUID()
    let version: String
    let headline: String
    let items: [ChangelogItem]
}

/// Histórico do que mudou em cada atualização.
/// Ao publicar uma versão nova, coloque a entrada dela no topo desta lista.
enum Changelog {
    static let releases: [ChangelogRelease] = [
        ChangelogRelease(
            version: "2.3",
            headline: "Agora o Joguim conta o que mudou",
            items: [
                ChangelogItem(
                    icon: "sparkles",
                    title: "Tela de novidades",
                    detail: "Toda vez que o app for atualizado, ela abre sozinha mostrando o que melhorou."
                ),
                ChangelogItem(
                    icon: "gearshape.fill",
                    title: "Sempre à mão",
                    detail: "Dá para rever quando quiser em Ajustes → Novidades."
                ),
                ChangelogItem(
                    icon: "number",
                    title: "Versão visível",
                    detail: "Mostra a versão e o build que estão instalados no seu iPhone."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.2",
            headline: "Voz muito mais rápida",
            items: [
                ChangelogItem(
                    icon: "bolt.fill",
                    title: "Resposta falada quase imediata",
                    detail: "Silêncio detectado em 0,8 s, reconhecimento no próprio iPhone e microfone sempre pronto."
                ),
                ChangelogItem(
                    icon: "globe",
                    title: "Sem espera de busca",
                    detail: "No modo voz, o Google só é consultado quando você pede."
                ),
                ChangelogItem(
                    icon: "text.bubble.fill",
                    title: "Respostas curtas",
                    detail: "No modo voz, respostas diretas em até 2 frases."
                ),
                ChangelogItem(
                    icon: "waveform",
                    title: "Fala começa na primeira vírgula",
                    detail: "A primeira parte da voz toca antes de a resposta terminar."
                ),
                ChangelogItem(
                    icon: "wifi",
                    title: "Conexão aquecida",
                    detail: "O app prepara a conexão e a lista de modelos ao abrir o modo voz."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.1",
            headline: "Imagens e câmera ao vivo",
            items: [
                ChangelogItem(
                    icon: "photo.badge.plus",
                    title: "Gerar imagem",
                    detail: "Peça pelo menu de anexos ou falando: “gere uma foto de…”."
                ),
                ChangelogItem(
                    icon: "wand.and.stars",
                    title: "Editar foto",
                    detail: "Anexe uma foto e peça, por exemplo, para remover uma pessoa."
                ),
                ChangelogItem(
                    icon: "camera.fill",
                    title: "Câmera ao vivo na voz",
                    detail: "Botão de câmera dentro do modo voz: ele vê o que você está vendo."
                ),
                ChangelogItem(
                    icon: "square.and.arrow.down",
                    title: "Salvar em Fotos",
                    detail: "Toque e segure na imagem para salvar na galeria."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.0",
            headline: "Joguim AI",
            items: [
                ChangelogItem(
                    icon: "person.fill",
                    title: "Nome e personalidade",
                    detail: "Joguim AI, com memória do que é importante para você."
                ),
                ChangelogItem(
                    icon: "list.bullet.clipboard.fill",
                    title: "Onboarding",
                    detail: "Nome, idade, trabalho, cidade e interesses para respostas sob medida."
                ),
                ChangelogItem(
                    icon: "location.fill",
                    title: "Localização",
                    detail: "Escolas, mercados e lugares perto de você."
                ),
                ChangelogItem(
                    icon: "music.note",
                    title: "Identificar música",
                    detail: "Cante ou cantarole que ele descobre a música."
                ),
                ChangelogItem(
                    icon: "hand.raised.fill",
                    title: "Interromper",
                    detail: "Fale por cima ou toque para cortar a resposta."
                ),
                ChangelogItem(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: "Nova conversa a cada abertura",
                    detail: "O app sempre começa limpo, sem arrastar o papo antigo."
                )
            ]
        )
    ]
}
