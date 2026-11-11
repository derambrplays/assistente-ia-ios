import Foundation

enum AppInfo {
    /// Nome de quem criou o app (aparece na interface e no que a IA responde).
    static let creator = "Kalleb Ribeiro de Souza Silva"

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    /// Muda a cada atualização instalada (versão + build).
    static var buildKey: String { "\(version) (\(build))" }

    /// Nome amigável do modelo, sem citar o provedor por trás do app.
    static func modelName(_ id: String) -> String {
        let lower = id.lowercased()
        var base = "Joguim Equilibrado"
        if lower.contains("lite") {
            base = "Joguim Rápido"
        } else if lower.contains("pro") {
            base = "Joguim Pro"
        } else if lower.contains("flash") {
            base = "Joguim Ágil"
        }

        let version = id.split(separator: "-").first { $0.first?.isNumber == true }
        if let version = version {
            return "\(base) \(version)"
        }
        return base
    }
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
            version: "2.12",
            headline: "A voz voltou a falar sempre",
            items: [
                ChangelogItem(
                    icon: "speaker.wave.2.fill",
                    title: "Nunca fica mudo",
                    detail: "Se a voz natural falhar de vez em uma resposta, ele fala com a voz do iPhone em vez de ficar em silêncio, e avisa que foi por causa de uma falha."
                ),
                ChangelogItem(
                    icon: "arrow.clockwise",
                    title: "Recupera a voz natural sozinho",
                    detail: "Se um erro passageiro derrubar todos os modelos de voz, o app recomeça a lista na resposta seguinte em vez de ficar sem voz até reiniciar."
                ),
                ChangelogItem(
                    icon: "stethoscope",
                    title: "Diagnóstico mostra a voz",
                    detail: "O teste automático agora mostra o que o servidor respondeu para a voz, para saber na hora se é cota ou falha de modelo."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.11",
            headline: "Áudio entendido de verdade e imagens explicadas",
            items: [
                ChangelogItem(
                    icon: "waveform",
                    title: "Áudio agora é entendido sempre",
                    detail: "O áudio é transcrito antes da resposta e a transcrição fica salva na conversa. Assim o modelo responde ao que você falou, sem dizer que é um assistente só de texto."
                ),
                ChangelogItem(
                    icon: "photo",
                    title: "Imagens: o motivo real da falha",
                    detail: "Quando a geração de imagem não está liberada na chave, o app diz isso claramente em vez de culpar o modelo, e para de tentar vários modelos à toa."
                ),
                ChangelogItem(
                    icon: "clock",
                    title: "Sem gastar cota sem você",
                    detail: "O teste automático de imagem roda só uma vez por atualização; o teste completo continua no botão Diagnóstico dos Ajustes."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.10",
            headline: "Sem voz de robô e entendendo áudio",
            items: [
                ChangelogItem(
                    icon: "speaker.slash.fill",
                    title: "A voz de robô saiu",
                    detail: "Com a voz natural ligada, o app nunca mais troca sozinho para a voz robótica do iPhone. Se a voz natural falhar, ele tenta de novo algumas vezes em vez de mudar o timbre."
                ),
                ChangelogItem(
                    icon: "waveform",
                    title: "Agora ele entende áudio",
                    detail: "Todo áudio enviado é transcrito antes da resposta, então qualquer modelo entende o que foi falado — e ele não diz mais que é um assistente só de texto."
                ),
                ChangelogItem(
                    icon: "photo",
                    title: "Imagens com o motivo certo",
                    detail: "Quando a imagem não sai, a mensagem agora diz o motivo real (cota do plano, permissão ou modelo indisponível), e o Diagnóstico testa a geração de verdade."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.9",
            headline: "A mesma voz, sem parar no meio",
            items: [
                ChangelogItem(
                    icon: "person.wave.2.fill",
                    title: "Chega de voz de homem do nada",
                    detail: "Quando a voz natural falhava, o app usava a voz padrão do iPhone — que podia ser masculina. Agora ele escolhe sempre a melhor voz feminina instalada, e a resposta inteira mantém o mesmo timbre."
                ),
                ChangelogItem(
                    icon: "ear.badge.waveform",
                    title: "Ele não se interrompe mais sozinho",
                    detail: "O microfone ficava ouvindo o próprio alto-falante e às vezes entendia a própria fala como se fosse você, cortando a resposta. Agora só uma fala nova e bem diferente interrompe."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.8",
            headline: "Uma voz só, do começo ao fim",
            items: [
                ChangelogItem(
                    icon: "waveform",
                    title: "Sem trocar de voz no meio",
                    detail: "Se a voz natural falhar em um trecho, ele tenta de novo. Se ainda assim não der, o resto da resposta continua na mesma voz, sem alternar."
                ),
                ChangelogItem(
                    icon: "sparkles.rectangle.stack",
                    title: "Novidades mais curtas",
                    detail: "A tela agora mostra só a versão atual e a anterior, em vez de arrastar o histórico inteiro."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.7",
            headline: "Escuta e fala do jeito certo",
            items: [
                ChangelogItem(
                    icon: "mic.fill",
                    title: "Ele não desiste mais de ouvir",
                    detail: "Antes o app encerrava a escuta 0,8 s depois de começar, antes mesmo de você falar. Agora o silêncio só conta depois que ele te ouve."
                ),
                ChangelogItem(
                    icon: "waveform.badge.exclamationmark",
                    title: "Escuta que se recupera",
                    detail: "Se o ditado falhar, ele troca sozinho para o modo do servidor e recomeça na mesma hora, sem perder a sua fala."
                ),
                ChangelogItem(
                    icon: "person.crop.circle.badge.xmark",
                    title: "Chega de falar seu nome",
                    detail: "O nome do criador só aparece se você perguntar quem criou o app. Nas conversas normais ele não fala mais isso."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.6",
            headline: "Texto voltou a funcionar",
            items: [
                ChangelogItem(
                    icon: "text.bubble.fill",
                    title: "Conversa por texto corrigida",
                    detail: "Quando a busca do Google estourava a cota, o app achava que tudo estava esgotado. Agora ele responde mesmo sem a busca."
                ),
                ChangelogItem(
                    icon: "arrow.clockwise",
                    title: "Tentar agora",
                    detail: "O aviso de servidor ocupado ganhou um botão que limpa o bloqueio e repete a última pergunta na hora."
                ),
                ChangelogItem(
                    icon: "stethoscope",
                    title: "Diagnóstico completo",
                    detail: "O teste agora também verifica a busca, que é o que mais travava o modo texto."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.5",
            headline: "Diagnóstico na mão",
            items: [
                ChangelogItem(
                    icon: "stethoscope",
                    title: "Testar servidor",
                    detail: "Em Ajustes → Diagnóstico, um botão testa a conexão e mostra o que o servidor respondeu."
                ),
                ChangelogItem(
                    icon: "checklist",
                    title: "Resposta exata",
                    detail: "Aparece o status de cada modelo testado, para saber se é cota, chave ou modelo."
                )
            ]
        ),
        ChangelogRelease(
            version: "2.4",
            headline: "Mais seu, mais esperto",
            items: [
                ChangelogItem(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Criador no comando",
                    detail: "O Joguim agora responde que foi criado por Kalleb Ribeiro de Souza Silva."
                ),
                ChangelogItem(
                    icon: "text.badge.xmark",
                    title: "Sem nomes de fora",
                    detail: "A interface não cita mais outras empresas ou modelos — é só o Joguim AI."
                ),
                ChangelogItem(
                    icon: "timer",
                    title: "Servidor ocupado com cronômetro",
                    detail: "Quando o servidor enche, aparece a contagem regressiva até ele voltar, já convertida para o horário de Brasília."
                ),
                ChangelogItem(
                    icon: "camera.fill",
                    title: "Câmera em tela cheia",
                    detail: "No modo voz, a câmera cobre a tela toda e sem distorção."
                ),
                ChangelogItem(
                    icon: "rectangle.on.rectangle",
                    title: "Ver tela",
                    detail: "Botão novo no modo voz: ele olha o seu print de tela e comenta o que importa."
                )
            ]
        ),
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
                    detail: "No modo voz, a busca na internet só acontece quando você pede."
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
