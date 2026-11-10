import Foundation
import AVFoundation
import Speech

/// Ditado nativo do iPhone (Speech framework), com detecção de silêncio.
///
/// O motor de áudio fica ligado entre os turnos: assim a escuta recomeça
/// quase instantaneamente, sem repetir a preparação do microfone a cada fala.
final class SpeechController {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let engine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?
    private var tapInstalled = false
    private var running = false
    private var lastText = ""
    private var onDeviceBroken = false

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

    /// Prepara o microfone antes do primeiro turno (ganha ~0,3 s na primeira fala).
    func warm() {
        guard !running else { return }
        guard activateSession() else { return }
        ensureTap()
        _ = startEngine()
    }

    func start(silence: TimeInterval = 0.9, onDevice: Bool = true) {
        guard !running else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            onError?("O ditado do iPhone não está disponível agora. Verifique em Ajustes → Geral → Teclado → Ditado.")
            return
        }
        guard activateSession() else {
            onError?("Não consegui ligar o microfone.")
            return
        }

        ensureTap()
        guard startEngine() else {
            onError?("Não consegui ligar o microfone.")
            return
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        // Reconhecimento no aparelho: sem ida e volta para o servidor.
        let useOnDevice = onDevice && recognizer.supportsOnDeviceRecognition && !onDeviceBroken
        if useOnDevice {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        request = recognitionRequest
        lastText = ""
        running = true

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                if text != self.lastText {
                    self.lastText = text
                    DispatchQueue.main.async { self.onPartial?(text) }
                    self.scheduleSilence(silence)
                }
                if result.isFinal {
                    self.finish(deliver: true)
                }
            }
            if error != nil {
                // Se o modo no aparelho falhar de cara, volta para o servidor.
                if useOnDevice && self.lastText.isEmpty {
                    self.onDeviceBroken = true
                }
                self.finish(deliver: true)
            }
        }

        scheduleSilence(silence)
    }

    func stop() {
        finish(deliver: false)
    }

    /// Desliga o microfone e o motor (ao sair do modo de voz).
    func shutdown() {
        finish(deliver: false)

        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Interno

    private func activateSession() -> Bool {
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
            return true
        } catch {
            return false
        }
    }

    private func ensureTap() {
        guard !tapInstalled else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.request?.append(buffer)
            self.publishLevel(buffer)
        }
        tapInstalled = true
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        engine.prepare()
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

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

        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastText = ""

        DispatchQueue.main.async {
            self.onLevel?(0)
            if deliver {
                self.onFinal?(text)
            }
        }
    }
}
