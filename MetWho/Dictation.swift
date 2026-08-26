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

    /// Everything the recogniser has already banked this session. `transcript`
    /// is this plus whatever is being said right now.
    private var settled = ""

    /// The recording kept alongside the live transcript.
    ///
    /// Apple's recogniser is what makes text appear while you talk — free,
    /// instant, on device. It is also the weaker transcriber: it mishears names,
    /// punctuates poorly, and has to be told which language it is listening to.
    /// So the audio is kept, and when a key is set it is sent for a second,
    /// better reading once you stop.
    private var writer: AVAudioFile?
    private(set) var recording: URL?
    /// The utterance in progress, as the recogniser last reported it.
    private var heardNow = ""

    /// Follows the phone, not the developer.
    ///
    /// This was pinned to `en-US`, which meant a French user dictating French got
    /// an English recogniser doing its best — the failure mode is not an error,
    /// it is a card full of plausible nonsense. `SFSpeechRecognizer()` with no
    /// locale uses the user's own, and only falls back when that language has no
    /// recogniser at all.
    /// Set from `Prefs.dictation` before listening starts; nil follows the phone.
    static var preferred: String = ""

    private let recognizer: SFSpeechRecognizer? = {
        if !Dictation.preferred.isEmpty,
           let picked = SFSpeechRecognizer(locale: Locale(identifier: Dictation.preferred)) {
            return picked
        }
        return SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()

    /// Every language this phone can transcribe, newest recognisers first.
    static var available: [(id: String, name: String)] {
        SFSpeechRecognizer.supportedLocales()
            .map { loc in
                (loc.identifier,
                 Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier)
            }
            .sorted { $0.1 < $1.1 }
    }

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

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                status = .unavailable("No audio input. In the Simulator, enable Device → Microphone.")
                return
            }
            let box = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation-\(UUID().uuidString).m4a")
            writer = try? AVAudioFile(forWriting: box, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: 1,
            ])
            recording = writer == nil ? nil : box

            input.removeTap(onBus: 0)
            // the tap feeds whichever request is current, not the one that existed
            // when the tap was installed — segments are replaced underneath it
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                try? self?.writer?.write(from: buffer)
            }

            engine.prepare()
            try engine.start()
            status = .listening
            settled = ""
            heardNow = ""
            transcript = ""
            beginSegment()
        } catch {
            status = .unavailable("Could not start the microphone.")
            teardown()
        }
    }

    /// Starts one utterance's worth of recognition, and starts another when that
    /// one ends.
    ///
    /// `SFSpeechRecognizer` finalises an utterance as soon as you stop talking,
    /// and every result it hands back covers only the utterance in progress. The
    /// first version of this assigned that result straight to `transcript` and
    /// stopped on `isFinal`, so pausing for breath deleted everything said before
    /// the pause. Finalised text is kept in `settled` and the recogniser is
    /// restarted, which is also how dictation survives past the roughly one
    /// minute a single task is allowed to run.
    private func beginSegment() {
        guard let recognizer, status.isListening else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // delivered on an arbitrary queue; the hop is what makes the UI update
            Task { @MainActor [weak self] in
                guard let self, self.status.isListening else { return }

                if let result {
                    let heard = result.bestTranscription.formattedString
                    // The one rule that holds however the recogniser behaves:
                    // what is on screen may never shrink. Every result covers
                    // only the utterance in progress, and a new utterance starts
                    // that string over from nothing — so the moment folding it in
                    // would produce less text than is already shown, the previous
                    // utterance is banked instead of being written over.
                    //
                    // This replaces a comparison of first words, which lost
                    // everything whenever two utterances happened to open on the
                    // same one.
                    if Self.continues(heard, from: self.heardNow) {
                        self.heardNow = heard
                    } else {
                        self.settled = Self.joined(self.settled, self.heardNow)
                        self.heardNow = heard
                    }
                    self.transcript = Self.joined(self.settled, self.heardNow)
                }

                // an ended utterance is a pause, not a decision to stop talking
                if result?.isFinal == true || error != nil {
                    self.settled = Self.joined(self.settled, self.heardNow)
                    self.heardNow = ""
                    self.transcript = self.settled
                    self.task = nil
                    self.request?.endAudio()
                    self.request = nil
                    self.beginSegment()
                }
            }
        }
    }

    /// Whether a result extends the utterance in progress or begins a new one.
    ///
    /// The recogniser revises as it goes — "Marie Dupont" becomes "Marie Dupond
    /// arrive" — so a plain prefix test calls a correction a new sentence. It
    /// also starts a fresh utterance after a pause without ever setting isFinal,
    /// and that one has to be banked rather than written over.
    ///
    /// What separates them is how much of the opening survives. A revision keeps
    /// nearly all of it; a new sentence keeps almost none. Comparing first words
    /// was the previous attempt and it lost everything whenever two sentences
    /// opened on the same one — "Il travaille chez Jacquemus" followed by "Il
    /// veut faire une école".
    private static func continues(_ new: String, from old: String) -> Bool {
        guard !old.isEmpty else { return true }
        if new.hasPrefix(old) { return true }
        let shared = zip(new, old).prefix { $0 == $1 }.count
        return Double(shared) >= Double(old.count) * 0.5
    }

    /// Joins two utterances without gluing words together or doubling a space.
    private static func joined(_ a: String, _ b: String) -> String {
        let left = a.trimmingCharacters(in: .whitespaces)
        let right = b.trimmingCharacters(in: .whitespaces)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }

    /// Leaves `transcript` alone: stopping is how you finish dictating, not how
    /// you discard what you said. The bin button is the only thing that clears it.
    func stop() {
        guard status.isListening else { teardown(); return }
        // before teardown, so a cancellation callback still in flight sees .idle
        // and does not start another segment
        status = .idle
        teardown()
    }

    /// Throws the audio away too. The bin clears the card; nothing should be left
    /// on disk that the card no longer shows.
    func discardRecording() {
        if let recording { try? FileManager.default.removeItem(at: recording) }
        recording = nil
    }

    func clearError() { if case .idle = status {} else { status = .idle } }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        writer = nil   // closes the file so it can be read back
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
