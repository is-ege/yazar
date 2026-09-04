import AVFoundation
import Foundation
import Speech

nonisolated struct AppleSpeechTranscriber: Transcriber {
    let language: String?

    /// One-shot dictation, expressed as a stream of exactly one buffer.
    ///
    /// The analyzer setup lives in `stream` and is not duplicated here: dictation
    /// is a meeting that ends immediately, and the only difference that matters is
    /// the preset. Dictation keeps `.transcription`, which reports finalized
    /// results only, because nothing on screen shows a partial dictation.
    func transcribe(_ recording: Recording) async throws -> String {
        guard !recording.pcm16.isEmpty else { return "" }

        var text = ""
        let audio = MeetingAudio(source: .buffer(recording.pcm16))
        for try await update in stream(audio, preset: .transcription) {
            text += update.finalized
        }
        // The stream ends quietly when the consuming task is cancelled, so the
        // caller is told the difference between "cancelled" and "said nothing".
        try Task.checkCancellation()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Live transcription for a meeting, which uses the progressive preset so the
    /// window can show the sentence being spoken rather than only settled text.
    func transcribe(_ audio: MeetingAudio) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        stream(audio, preset: .progressiveTranscription)
    }

    /// Drives one `SpeechAnalyzer` session for as long as `audio` lasts.
    ///
    /// Three concurrent halves, run as one group so that cancelling the caller
    /// reaches all of them: feeding converts captured samples into analyzer
    /// input, forwarding republishes the module's results, and the analyzer
    /// itself sits between the two until the input sequence ends.
    private func stream(
        _ audio: MeetingAudio,
        preset: SpeechTranscriber.Preset
    ) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    guard SpeechTranscriber.isAvailable else {
                        throw AppleSpeechTranscriberError.unavailable
                    }
                    guard let locale = await Self.supportedLocale(for: language) else {
                        throw AppleSpeechTranscriberError.unsupportedLanguage(
                            Self.displayName(for: language)
                        )
                    }
                    let module = try await Self.downloadedModule(for: locale, preset: preset)
                    try Task.checkCancellation()
                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [module]
                    ) else {
                        throw AppleSpeechTranscriberError.unavailable
                    }
                    let converter = try PCMConverter(to: analyzerFormat)

                    let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
                    let analyzer = SpeechAnalyzer(modules: [module])

                    try await withTaskCancellationHandler {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                // The analyzer waits on this sequence, so it is
                                // finished on every way out, a conversion that
                                // threw included.
                                defer { inputBuilder.finish() }
                                for try await samples in audio {
                                    if let buffer = try converter.convert(samples) {
                                        inputBuilder.yield(AnalyzerInput(buffer: buffer))
                                    }
                                }
                                // A resampler holds a tail of frames it could not
                                // place; without this the last word goes with it.
                                if let tail = try converter.finish() {
                                    inputBuilder.yield(AnalyzerInput(buffer: tail))
                                }
                            }
                            group.addTask {
                                for try await result in module.results {
                                    let text = String(result.text.characters)
                                    continuation.yield(
                                        result.isFinal
                                            ? TranscriptUpdate(finalized: text)
                                            : TranscriptUpdate(volatile: text)
                                    )
                                }
                            }
                            group.addTask {
                                let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)
                                // Finalizing is what produces the last results,
                                // so the forwarding task above is still running.
                                if let lastSampleTime {
                                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                                } else {
                                    await analyzer.cancelAndFinishNow()
                                }
                            }

                            do {
                                try await group.waitForAll()
                            } catch {
                                await analyzer.cancelAndFinishNow()
                                throw error
                            }
                        }
                    } onCancel: {
                        // Finishing the input is not enough to unblock a
                        // cancelled analyzer, and an abandoned one keeps a
                        // speech session open for the rest of the launch.
                        Task { await analyzer.cancelAndFinishNow() }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Covers both ends: a consumer that stops listening and a consuming
            // task that is cancelled both land here and tear the analyzer down.
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}

// Locale resolution and asset installation are shared with the settings screen,
// which reports the same model this transcriber will use.
nonisolated extension AppleSpeechTranscriber {
    /// The locale Apple Speech transcribes `language` with, or nil when it
    /// can't. `SpeechTranscriber.supportedLocale(equivalentTo:)` normalizes any
    /// input it recognizes as a language — "tr" comes back as tr_TR even though
    /// no Turkish model exists — so membership in `supportedLocales` is the
    /// only test that reflects what actually transcribes.
    static func supportedLocale(for language: String?) async -> Locale? {
        guard let resolved = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale(for: language)
        ) else { return nil }

        let supported = await SpeechTranscriber.supportedLocales
        let isSupported = supported.contains {
            $0.identifier(.bcp47) == resolved.identifier(.bcp47)
        }
        return isSupported ? resolved : nil
    }

    /// Returns the module for `locale`, first downloading its on-device model
    /// when macOS doesn't have it. The first dictation in a language pays for
    /// the download unless the settings screen already did.
    static func downloadedModule(
        for locale: Locale,
        preset: SpeechTranscriber.Preset = .transcription
    ) async throws -> SpeechTranscriber {
        let module = SpeechTranscriber(locale: locale, preset: preset)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [module]
        ) {
            try await installationRequest.downloadAndInstall()
        }
        return module
    }

    /// Whether macOS already holds the on-device model for `locale`.
    /// `AssetInventory.status(forModules:)` reports `.installed` only for locales
    /// the app has reserved, and Yazar reserves none, so it answers `.supported`
    /// for models that are in fact on disk. `installedLocales` is the real answer.
    static func isModelInstalled(for locale: Locale) async -> Bool {
        await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }
    }

    /// Names a language for the user, always in the user's own language rather
    /// than the one being named.
    static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    static func displayName(for language: String?) -> String {
        displayName(for: requestedLocale(for: language))
    }

    /// A blank language setting means "whatever this Mac is set to".
    private static func requestedLocale(for language: String?) -> Locale {
        language.map(Locale.init(identifier:)) ?? .current
    }
}

private enum AppleSpeechTranscriberError: LocalizedError {
    case unavailable
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Speech isn't available on this Mac."
        case .unsupportedLanguage(let language):
            "Apple Speech doesn't support \(language)."
        }
    }
}
