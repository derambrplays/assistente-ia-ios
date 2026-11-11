import Foundation
import AVFoundation
import Combine

/// Toca áudio do Gemini e voz offline do iPhone em sequência, permitindo
/// enfileirar pedaços enquanto a resposta ainda está chegando (a fala começa
/// na primeira frase, em vez de esperar a resposta inteira).
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var isPlaying = false

    /// Uma única voz do iPhone para toda a sessão.
    ///
    /// `AVSpeechSynthesisVoice(language:)` devolve a voz padrão escolhida pelo
    /// usuário no aparelho — que pode ser masculina. Como a voz natural é
    /// feminina, isso fazia a assistente "trocar de voz" entre uma resposta e
    /// outra. Aqui escolhemos sempre a melhor voz feminina pt-BR instalada.
    static let offlineVoice: AVSpeechSynthesisVoice? = {
        let all = AVSpeechSynthesisVoice.speechVoices()

        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            var points = 0

            if voice.language == "pt-BR" {
                points += 100
            } else if voice.language.hasPrefix("pt") {
                points += 40
            } else {
                points -= 100
            }

            let name = voice.name.lowercased()
            let femaleNames = [
                "luciana", "fernanda", "camila", "joana", "maria",
                "ana", "catarina", "ines", "inês", "helena"
            ]
            if femaleNames.contains(where: { name.contains($0) }) {
                points += 30
            }
            if voice.gender == .female {
                points += 20
            }

            switch voice.quality {
            case .premium:
                points += 6
            case .enhanced:
                points += 4
            default:
                points += 2
            }

            return points
        }

        let portuguese = all.filter { $0.language.hasPrefix("pt") }
        let best = portuguese.max(by: { score($0) < score($1) })
        return best ?? AVSpeechSynthesisVoice(language: "pt-BR")
    }()

    private enum Item {
        case audio(Data)
        case speech(String)
    }

    private var queue: [Item] = []
    private var current: AVAudioPlayer?
    private var activeSpeech: AVSpeechSynthesizer?
    private var completion: (() -> Void)?
    private var streaming = false

    // MARK: - Sessão de áudio

    /// Deixa a sessão pronta antes de precisar tocar (evita atraso na primeira fala).
    func prepare(voiceMode: Bool = false) {
        try? configure(voiceMode: voiceMode)
    }

    private func configure(voiceMode: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if voiceMode {
            if session.category != .playAndRecord {
                try session.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
            }
        } else if session.category != .playback {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try session.setActive(true, options: [])
    }

    // MARK: - Reprodução simples

    func play(data: Data, voiceMode: Bool = false, completion: @escaping () -> Void) throws {
        stop()
        try configure(voiceMode: voiceMode)
        self.completion = completion
        streaming = false
        queue = [.audio(data)]
        playNext()
    }

    func speakOffline(_ text: String, voiceMode: Bool = false, completion: @escaping () -> Void) {
        stop()
        try? configure(voiceMode: voiceMode)
        self.completion = completion
        streaming = false
        queue = [.speech(text)]
        playNext()
    }

    // MARK: - Reprodução em fluxo (fala enquanto a resposta chega)

    func beginStream(voiceMode: Bool, completion: @escaping () -> Void) {
        stop()
        try? configure(voiceMode: voiceMode)
        self.completion = completion
        streaming = true
        isPlaying = false
    }

    func enqueue(data: Data) {
        queue.append(.audio(data))
        if current == nil && activeSpeech == nil {
            playNext()
        } else {
            isPlaying = true
        }
    }

    func enqueueSpeech(_ text: String) {
        queue.append(.speech(text))
        if current == nil && activeSpeech == nil {
            playNext()
        } else {
            isPlaying = true
        }
    }

    func endStream() {
        streaming = false
        if current == nil && activeSpeech == nil && queue.isEmpty {
            finish()
        }
    }

    // MARK: - Controle

    func stop() {
        queue.removeAll()
        streaming = false
        completion = nil

        current?.stop()
        current = nil

        let speech = activeSpeech
        activeSpeech = nil
        speech?.stopSpeaking(at: .immediate)

        isPlaying = false
    }

    private func playNext() {
        guard current == nil, activeSpeech == nil else { return }
        guard !queue.isEmpty else {
            if !streaming { finish() }
            return
        }

        let item = queue.removeFirst()
        switch item {
        case .audio(let data):
            do {
                let audio = try AVAudioPlayer(data: data)
                audio.delegate = self
                audio.prepareToPlay()
                current = audio
                isPlaying = true
                if !audio.play() {
                    current = nil
                    playNext()
                }
            } catch {
                playNext()
            }

        case .speech(let text):
            let synth = AVSpeechSynthesizer()
            synth.delegate = self
            activeSpeech = synth
            isPlaying = true

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AudioPlayer.offlineVoice
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            synth.speak(utterance)
        }
    }

    private func finish() {
        let block = completion
        completion = nil
        current = nil
        activeSpeech = nil
        queue.removeAll()
        streaming = false
        isPlaying = false

        DispatchQueue.main.async {
            block?()
        }
    }

    // MARK: - Delegates

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Os delegates podem chegar fora da main; a fila só pode ser mexida nela.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.current === player else { return }
            self.current = nil
            self.playNext()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.current === player else { return }
            self.current = nil
            self.playNext()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, synthesizer === self.activeSpeech else { return }
            self.activeSpeech = nil
            self.playNext()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, synthesizer === self.activeSpeech else { return }
            self.activeSpeech = nil
            self.playNext()
        }
    }
}
