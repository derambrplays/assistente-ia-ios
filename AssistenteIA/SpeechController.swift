import Foundation
import AVFoundation
import Speech

/// Ditado nativo do iPhone (Speech framework), com detecção de silêncio.
final class SpeechController {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let engine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?
    private var tapInstalled = false
    private var running = false
    private var lastText = ""

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func requestAuthorization() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }

        let micOK: Bool = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return micOK
    }

    func start(silence: TimeInterval = 1.5) {
        guard !running else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            onError?("O ditado do iPhone não está disponível agora. Verifique em Ajustes → Geral → Teclado → Ditado.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.defaultToSpeaker, .allowBluetooth]
                )
            }
            try session.setActive(true, options: [])
        } catch {
            onError?("Não consegui ligar o microfone.")
            return
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        request = recognitionRequest
        lastText = ""
        running = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.request?.append(buffer)
            self.publishLevel(buffer)
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            running = false
            cleanup()
            onError?("Não consegui ligar o microfone.")
            return
        }

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.lastText = text
                DispatchQueue.main.async { self.onPartial?(text) }
                self.scheduleSilence(silence)
                if result.isFinal {
                    self.finish(deliver: true)
                }
            }
            if error != nil {
                self.finish(deliver: true)
            }
        }

        scheduleSilence(silence)
    }

    func stop() {
        finish(deliver: false)
    }

    // MARK: - Interno

    private func scheduleSilence(_ seconds: TimeInterval) {
        DispatchQueue.main.async {
            self.silenceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.finish(deliver: true)
            }
            self.silenceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }

    private func publishLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for index in 0..<frames {
            let value = channel[index]
            sum += value * value
        }
        let rms = sqrt(sum / Float(frames))
        let level = CGFloat(min(1.0, rms * 14))
        DispatchQueue.main.async { self.onLevel?(level) }
    }

    private func finish(deliver: Bool) {
        guard running else { return }
        running = false

        DispatchQueue.main.async {
            self.silenceWork?.cancel()
            self.silenceWork = nil
        }

        cleanup()

        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastText = ""

        DispatchQueue.main.async {
            self.onLevel?(0)
            if deliver {
                self.onFinal?(text)
            }
        }
    }

    private func cleanup() {
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
