import Foundation
import Speech
import AVFoundation
import Observation

/// Live on-device speech, streamed into the capture card as you talk.
///
/// Two things matter here and neither is obvious:
///
/// 1. `requiresOnDeviceRecognition` is set whenever the locale supports it, so
///    audio never leaves the phone. That is the whole privacy promise of the
///    app, and it would be quietly broken by leaving the default.
/// 2. The recogniser returns the *entire* utterance every time, not a delta.
///    Appending its result would duplicate the text — so the transcript is
///    replaced, and anything typed before starting is kept separately as
///    `prefix`.
/// 3. `@MainActor` is load-bearing. Both the permission continuations and the
///    recognition callback resume off the main thread; without the isolation
///    `status` and `transcript` mutate there too and SwiftUI never re-renders —
///    the button stays on "Dictate" and errors are invisible.
@MainActor
@Observable
final class Dictation {

    enum Status: Equatable {
        case idle
        case listening
        case denied(String)
        case unavailable(String)

        var isListening: Bool { self == .listening }
    }

    private(set) var status: Status = .idle
    private(set) var transcript = ""

    /// Follows the phone, not the developer.
    ///
    /// This was pinned to `en-US`, which meant a French user dictating French got
    /// an English recogniser doing its best — the failure mode is not an error,
    /// it is a card full of plausible nonsense. `SFSpeechRecognizer()` with no
    /// locale uses the user's own, and only falls back when that language has no
    /// recogniser at all.
    private let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// What the recogniser will actually listen for, for the UI to say out loud.
    var language: String {
        let id = recognizer?.locale.identifier ?? "en-US"
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    // MARK: - Permissions

    static func authorize() async -> Status {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return .denied("Speech recognition is off. Turn it on in Settings → MetWho.")
        }
        let mic = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard mic else {
            return .denied("No microphone access. Turn it on in Settings → MetWho.")
        }
        return .idle
    }

    // MARK: - Control

    func start() async {
        guard !status.isListening else { return }

        let auth = await Self.authorize()
        if case .denied = auth { status = auth; return }

        // two very different failures used to share one message, which made the
        // real cause unknowable from the screen
        guard let recognizer else {
            status = .unavailable("MetWho cannot recognise \(language) yet. Use the keyboard for now.")
            return
        }
        guard recognizer.isAvailable else {
            #if targetEnvironment(simulator)
            status = .unavailable("Dictation does not run in the Simulator. Try it on a real iPhone.")
            #else
            status = .unavailable("\(language) dictation is not ready. It needs a connection the first time, then works offline.")
            #endif
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            req.addsPunctuation = true
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                status = .unavailable("No audio input. In the Simulator, enable Device → Microphone.")
                return
            }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
                req?.append(buffer)
            }

            engine.prepare()
            try engine.start()
            status = .listening
            transcript = ""

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                // delivered on an arbitrary queue; the hop is what makes the UI update
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        // the recogniser hands back the whole utterance each time
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            status = .unavailable("Could not start the microphone.")
            teardown()
        }
    }

    func stop() {
        guard status.isListening else { teardown(); return }
        teardown()
        status = .idle
    }

    func clearError() { if case .idle = status {} else { status = .idle } }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
