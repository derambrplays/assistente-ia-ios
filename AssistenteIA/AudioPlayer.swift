import Foundation
import AVFoundation
import Combine

final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var synthesizer: AVSpeechSynthesizer?
    private var completion: (() -> Void)?

    func play(data: Data, voiceMode: Bool = false, completion: @escaping () -> Void) throws {
        stop()

        let session = AVAudioSession.sharedInstance()
        if voiceMode {
            if session.category != .playAndRecord {
                try session.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
            }
        } else {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try session.setActive(true, options: [])

        let audio = try AVAudioPlayer(data: data)
        audio.delegate = self
        audio.prepareToPlay()

        player = audio
        self.completion = completion
        isPlaying = audio.play()
    }

    func speakOffline(_ text: String, voiceMode: Bool = false, completion: @escaping () -> Void) {
        stop()

        let session = AVAudioSession.sharedInstance()
        if voiceMode {
            try? session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true, options: [])

        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        synthesizer = synth
        self.completion = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0

        isPlaying = true
        synth.speak(utterance)
    }

    func stop() {
        player?.stop()
        player = nil

        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil

        completion = nil
        isPlaying = false
    }

    private func finish() {
        let block = completion
        completion = nil
        player = nil
        synthesizer = nil
        isPlaying = false

        DispatchQueue.main.async {
            block?()
        }
    }

    // MARK: - Delegates

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }
}
