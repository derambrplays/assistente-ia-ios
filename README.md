# Assistente IA para iPhone

App nativo em **SwiftUI** que roda **inteiro no iPhone**. Não precisa de computador ligado,
não usa servidor local e funciona fora de casa (Wi-Fi ou dados móveis). A única coisa que sai
do aparelho é a chamada para a API do Google Gemini.

- Conversa por texto com streaming
- Conversa por voz: fala → texto → resposta falada (começa a falar na primeira frase)
- Voz natural do Gemini (ou voz offline do iPhone)
- Anexos de fotos e arquivos (imagens, PDF, áudio, vídeo e texto)
- Busca na internet quando você pede (com fontes)
- Histórico de conversas salvo no aparelho
- Chave do Gemini guardada no **Keychain** do iPhone
- Visual "liquid glass" com fundo aurora

---

## O que você precisa

1. Um **iPhone** com iOS 16 ou mais novo.
2. Uma conta no **GitHub** (gratuita) — só para o GitHub compilar o app na nuvem.
3. O **Sideloadly** instalado no Windows: <https://sideloadly.io>
4. O **iTunes** (versão da Microsoft Store ou do site da Apple) instalado no Windows,
   porque o Sideloadly usa os drivers da Apple para conversar com o iPhone.
5. Seu **Apple ID** (o mesmo do iCloud) e o cabo do iPhone.
6. Uma **chave do Gemini**: <https://aistudio.google.com/apikey> (gratuita).

> Não é necessário ter Mac. Quem compila é o GitHub Actions, num Mac virtual gratuito.

---

## Passo 1 — Colocar o projeto no GitHub

1. Crie um repositório **privado** em <https://github.com/new> chamado `assistente-ia-ios`.
2. Envie **o conteúdo desta pasta `ios/`** para a raiz do repositório.
   - Pela página do repositório: **Add file → Upload files**, arraste `AssistenteIA/` e `project.yml`.
   - A pasta `.github` começa com ponto e às vezes o site do GitHub ignora no arrastar.
     Se ela não aparecer no repositório, crie o arquivo manualmente:
     **Add file → Create new file**, digite `.github/workflows/build.yml` como nome e cole
     o conteúdo do arquivo `build.yml` que está nesta pasta.
   - Alternativa mais confiável: instale o **GitHub Desktop**
     (<https://desktop.github.com>), crie o repositório, copie a pasta `ios/` para ele,
     faça o commit e clique em **Publish repository** (marque **Keep this code private**).
3. Confirme que o arquivo ficou em `.github/workflows/build.yml` na raiz do repositório.

## Passo 2 — Deixar o GitHub compilar

1. Abra a aba **Actions** do repositório.
2. Se aparecer um aviso, clique em **I understand my workflows, go ahead and enable them**.
3. O workflow **Build IPA** começa sozinho. Se não começar, clique nele e em **Run workflow**.
4. Espere de 5 a 10 minutos. O status fica verde quando termina.
5. Abra a execução verde, desça até **Artifacts** e baixe **AssistenteIA-ipa**.
6. Extraia o `.zip` baixado. Dentro está o arquivo **AssistenteIA.ipa**.

## Passo 3 — Instalar no iPhone com o Sideloadly

1. Conecte o iPhone no PC e confie no computador, se o iPhone pedir.
2. Abra o **Sideloadly**.
3. Em **iOS IPA File**, escolha o `AssistenteIA.ipa`.
4. Em **Apple ID**, digite seu Apple ID.
5. Clique em **Start** e digite a senha do Apple ID quando pedir.
   - Se aparecer pedido de código de verificação, digite o código que chegou no seu iPhone/Mac.
   - Se o Sideloadly reclamar de senha de app, gere uma **senha de app** em
     <https://account.apple.com> → **Iniciar sessão e segurança** → **Senhas de app**.
6. Espere aparecer **Done**. O app **Assistente** já estará na tela inicial.

### Primeira abertura

1. Abra o app **Assistente**.
2. Se o iPhone avisar que o desenvolvedor não é confiável, vá em
   **Ajustes → Geral → VPN e Gerenciamento de Dispositivo → seu Apple ID → Confiar**.
3. Cole a chave do Gemini quando o app pedir (ou em **Ajustes → Chave do Gemini**).
4. Pronto: pode usar no Wi-Fi e nos dados móveis, sem o PC.

## Passo 4 — Liberar microfone e ditado

Na primeira vez que usar o modo voz, o iPhone pede permissão de **Microfone** e
**Reconhecimento de Fala**. Autorize os dois.

Se o ditado não funcionar, confira em
**Ajustes → Geral → Teclado → Ditado** se está ligado.

---

## O prazo de 7 dias (importante)

Assinando com um **Apple ID gratuito**, o iOS aceita o app por **7 dias**. Depois disso ele
para de abrir e precisa ser instalado de novo pelo Sideloadly (leva 2 minutos, o histórico
do app é preservado).

- Limite do Apple ID gratuito: **3 apps** assinados ao mesmo tempo.
- Com o **Apple Developer Program** (US$ 99/ano), a assinatura vale **1 ano** e o app pode
  ser renovado sem reinstalar toda semana.

Para renovar: conecte o iPhone, abra o Sideloadly, escolha o mesmo IPA, o mesmo Apple ID e
clique em **Start**. Não precisa apagar o app antes.

---

## Como usar

- **Texto:** digite na barra de baixo e toque na seta.
- **Anexos:** toque no clipe ao lado do campo, escolha **Fotos** ou **Arquivo** e envie.
  Dá para anexar até 5 arquivos por mensagem (8 MB por arquivo, 14 MB no total).
- **Pesquisa:** peça “pesquise na internet…” ou “quais são as notícias de hoje?”.
  O app usa a busca do Google e mostra as fontes abaixo da resposta.
- **Voz:** toque no ícone de onda ao lado do campo de texto. Fale; quando você fizer
  silêncio por 1,3 s, ele entende e responde falando. A fala começa assim que a
  primeira frase da resposta chega, sem esperar o texto inteiro.
- **Interromper:** enquanto ele fala, comece a falar. O app corta a voz e volta a ouvir.
- **Ouvir de novo:** cada resposta tem o botão **Ouvir**.
- **Histórico:** ícone de menu no topo esquerdo.
- **Ajustes:** ícone de controles no topo direito — modelo, criatividade, personalidade,
  voz e chave.

### Se o Gemini ficar lento

Em **Ajustes → Modelo**, use `gemini-3.5-flash-lite`. Modelos maiores respondem melhor,
mas demoram mais — e no modo voz a velocidade importa.

---

## Privacidade

- A chave do Gemini fica no **Keychain** do iPhone, nunca em texto puro no projeto.
- As conversas ficam no armazenamento local do app, neste iPhone.
- Não existe servidor intermediário: o app fala direto com
  `generativelanguage.googleapis.com`.
- Ao desinstalar o app, as conversas locais são apagadas junto.

---

## Estrutura do projeto

```
ios/
├── project.yml                     # configuração do XcodeGen
├── .github/workflows/build.yml     # compila e gera o IPA no GitHub Actions
└── AssistenteIA/
    ├── AssistenteIAApp.swift       # entrada do app
    ├── Info.plist                  # permissões e configuração
    ├── Models.swift                # mensagens, conversas, ajustes
    ├── Attachment.swift            # anexos: fotos e arquivos
    ├── Keychain.swift              # chave no Keychain
    ├── GeminiClient.swift          # API do Gemini (chat, voz, busca, modelos)
    ├── SpeechController.swift      # ditado nativo + detecção de silêncio
    ├── AudioPlayer.swift           # reprodução da voz
    ├── ChatStore.swift             # estado, histórico, modo voz
    ├── Theme.swift                 # cores e vidro líquido
    ├── RootView.swift              # navegação principal
    ├── ChatView.swift              # tela de conversa
    ├── VoiceView.swift             # tela do modo voz
    ├── KeyEntryView.swift          # tela inicial da chave
    ├── SettingsView.swift          # ajustes
    ├── ConversationsView.swift     # histórico
    ├── MessageRow.swift            # balões de mensagem
    ├── Composer.swift              # barra de digitação
    ├── Components.swift            # componentes reutilizáveis
    └── Assets.xcassets             # ícone e cor de destaque
```

---

## Problemas comuns

| Problema | Solução |
| --- | --- |
| O workflow falha no GitHub | Confira se `project.yml` e a pasta `AssistenteIA/` estão na raiz do repositório. |
| "Unable to install" no Sideloadly | Atualize o iTunes e o Sideloadly; troque o cabo/porta USB; confie no computador no iPhone. |
| App fecha ao abrir | A assinatura expirou (7 dias) ou o desenvolvedor não foi confiado em Ajustes. |
| "Chave inválida" | Gere outra chave no AI Studio e cole de novo; veja se copiou sem espaços. |
| Voz não sai | Teste em Ajustes → Voz → Testar voz. Se a voz natural falhar, desligue "Voz natural (Gemini)" para usar a voz offline. |
| Microfone não abre | Ajustes do iPhone → Assistente → Microfone / Reconhecimento de Fala. |
| Modelo não encontrado | Ajustes → Modelo → Atualizar lista de modelos e escolha outro. |

---

## Aviso

Este é um projeto pessoal. A chave do Gemini é sua e o uso da API segue os termos do Google.
Não publique o repositório com a chave dentro: a chave deve ser digitada apenas no app.
