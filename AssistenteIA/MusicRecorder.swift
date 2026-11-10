import Foundation
import AVFoundation

/// Grava alguns segundos do microfone para o Joguim identificar a música.
/// Usa WAV (PCM 16 kHz mono) porque o Gemini aceita esse formato direto.
final class MusicRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("joguim-musica.wav")
    }

    func start(seconds: TimeInterval = 9) -> Bool {
        stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: [])
        } catch {
            return false
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let audio = try? AVAudioRecorder(url: fileURL, settings: settings) else {
            return false
        }

        recorder = audio
        isRecording = audio.record(forDuration: seconds)
        return isRecording
    }

    /// Encerra e devolve o áudio gravado.
    func finish() -> (data: Data, mimeType: String, seconds: Double)? {
        guard let audio = recorder else { return nil }
        let duration = audio.currentTime
        audio.stop()
        recorder = nil
        isRecording = false

        guard let data = try? Data(contentsOf: fileURL), data.count > 2048 else {
            return nil
        }
        return (data, "audio/wav", duration)
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }
}
