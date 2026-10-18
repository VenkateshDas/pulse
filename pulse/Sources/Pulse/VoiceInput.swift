import AVFoundation
import Observation
@preconcurrency import Speech

/// On-device, user-initiated dictation. Never starts from launch or an agent tool.
@MainActor @Observable final class VoiceInput {
    static let shared = VoiceInput()
    var isRecording = false
    var status = ""
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var finish: ((String) -> Void)?
    @ObservationIgnored private var transcript = ""
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var generation = UUID()

    /// Speech calls its completion on a background queue. Keep this boundary
    /// nonisolated so Swift 6 never infers a MainActor callback for it.
    nonisolated static func speechPermission(
        using authorize: @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void = {
            SFSpeechRecognizer.requestAuthorization($0)
        }
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            authorize { status in continuation.resume(returning: status == .authorized) }
        }
    }

    func start(finish: @escaping (String) -> Void) {
        guard !isRecording, !starting else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil,
              Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else { status = "Dictation requires the bundled Pulse app."; return }
        generation = UUID(); let expected = generation
        starting = true; status = "Checking dictation permission…"
        Task {
            let speech = await Self.speechPermission()
            let microphone = speech ? await AVCaptureDevice.requestAccess(for: .audio) : false
            guard generation == expected else { return }
            starting = false
            guard speech, microphone else { status = "Allow Speech Recognition and Microphone for Pulse in System Settings to dictate."; return }
            guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.supportsOnDeviceRecognition else { status = "On-device dictation is unavailable for this language on this Mac."; return }
            let engine = AVAudioEngine(), request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            let input = engine.inputNode, format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { status = "No microphone input is available."; return }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in request.append(buffer) }
            do { engine.prepare(); try engine.start() }
            catch { input.removeTap(onBus: 0); status = "Microphone could not start."; return }
            self.engine = engine; self.request = request; self.finish = finish; transcript = ""; isRecording = true; status = "Listening on this Mac…"
            recognition = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString, final = result?.isFinal == true, failed = error != nil
                Task { @MainActor in
                    guard let self, self.isRecording, self.generation == expected else { return }
                    if let text { self.transcript = String(text.prefix(12_000)) }
                    if final || failed { self.stop() }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30)); guard !Task.isCancelled else { return }; self?.stop()
            }
        }
    }
    func stop() {
        generation = UUID(); starting = false
        guard isRecording else { return }
        isRecording = false; timeout?.cancel(); timeout = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); request = nil; recognition?.cancel(); recognition = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines), callback = finish
        finish = nil; transcript = ""; status = text.isEmpty ? "No speech captured. Try again." : "Dictation ready."
        if !text.isEmpty { callback?(text) }
    }
}
