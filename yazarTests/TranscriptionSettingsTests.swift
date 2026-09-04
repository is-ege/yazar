import Foundation
import Testing
@testable import yazar

@MainActor
@Suite("Transcription settings")
struct TranscriptionSettingsTests {
    private static func makeSettings() -> TranscriptionSettings {
        let suiteName = "transcription-tests-\(UUID().uuidString)"
        return TranscriptionSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private static func source(
        id: String,
        language: String? = "en"
    ) -> KeyboardInputSource {
        KeyboardInputSource(
            id: id,
            name: id,
            languages: language.map { [$0] } ?? []
        )
    }

    @Test("Input source routing starts disabled")
    func inputSourceRoutingStartsDisabled() {
        let settings = Self.makeSettings()

        #expect(!settings.isInputSourceRoutingEnabled)
    }

    @Test("Disabled routing always uses the fixed route")
    func disabledRoutingUsesFixedRoute() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "fixed/model"
        settings.language = "de"
        settings.setModel(.appleSpeech, for: "abc")

        let route = settings.dictationRoute(for: Self.source(id: "abc"))

        #expect(route == TranscriptionRoute(model: .openRouter("fixed/model"), language: "de"))
    }

    @Test("Enabled routing selects by exact input-source ID")
    func enabledRoutingSelectsBySourceID() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "fixed/model"
        settings.setModel(.appleSpeech, for: "abc")
        settings.setModel(.openRouter("turkish/model"), for: "turkish")
        settings.isInputSourceRoutingEnabled = true

        #expect(
            settings.dictationRoute(for: Self.source(id: "abc", language: "en"))
                == TranscriptionRoute(model: .appleSpeech, language: "en")
        )
        #expect(
            settings.dictationRoute(for: Self.source(id: "turkish", language: "tr"))
                == TranscriptionRoute(model: .openRouter("turkish/model"), language: "tr")
        )
    }

    @Test("Sources with the same language keep independent models")
    func sameLanguageSourcesStayIndependent() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "fixed/model"
        settings.setModel(.appleSpeech, for: "abc")
        settings.setModel(.openRouter("alternate/model"), for: "us")
        settings.isInputSourceRoutingEnabled = true

        #expect(
            settings.dictationRoute(for: Self.source(id: "abc"))
                == TranscriptionRoute(model: .appleSpeech, language: "en")
        )
        #expect(
            settings.dictationRoute(for: Self.source(id: "us"))
                == TranscriptionRoute(model: .openRouter("alternate/model"), language: "en")
        )
    }

    @Test("An unmapped source inherits the fixed model and its own language")
    func unmappedSourceUsesFixedModel() {
        let settings = Self.makeSettings()
        settings.provider = .appleSpeech
        settings.language = "de"
        settings.isInputSourceRoutingEnabled = true

        let route = settings.dictationRoute(for: Self.source(id: "turkish", language: "tr"))

        #expect(route == TranscriptionRoute(model: .appleSpeech, language: "tr"))
    }

    @Test("Missing source language falls back to the fixed language")
    func missingSourceLanguageUsesFixedLanguage() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "fixed/model"
        settings.language = "de"
        settings.setModel(.appleSpeech, for: "unicode")
        settings.isInputSourceRoutingEnabled = true

        let route = settings.dictationRoute(for: Self.source(id: "unicode", language: nil))

        #expect(route == TranscriptionRoute(model: .appleSpeech, language: "de"))
    }

    @Test("An unavailable current source uses the full fixed route")
    func unavailableSourceUsesFixedRoute() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "fixed/model"
        settings.language = "de"
        settings.isInputSourceRoutingEnabled = true

        #expect(
            settings.dictationRoute(for: nil)
                == TranscriptionRoute(model: .openRouter("fixed/model"), language: "de")
        )
    }

    @Test("A source pinned to the current fixed model keeps it when that changes")
    func pinnedSourceSurvivesFixedModelChange() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "first/model"
        settings.setModel(.openRouter("first/model"), for: "abc")

        settings.openRouterModel = "second/model"

        #expect(settings.model(for: "abc") == .openRouter("first/model"))
    }

    @Test("Clearing an override returns the source to the fixed model")
    func clearedOverrideFollowsFixedModel() {
        let settings = Self.makeSettings()
        settings.provider = .openRouter
        settings.openRouterModel = "first/model"
        settings.setModel(.appleSpeech, for: "abc")

        settings.setModel(nil, for: "abc")

        #expect(settings.modelOverride(for: "abc") == nil)
        #expect(settings.model(for: "abc") == .openRouter("first/model"))

        settings.openRouterModel = "second/model"

        #expect(settings.model(for: "abc") == .openRouter("second/model"))
    }

    @Test("Routing choices persist")
    func routingChoicesPersist() {
        let suiteName = "transcription-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = TranscriptionSettings(defaults: defaults)
        settings.isInputSourceRoutingEnabled = true
        settings.setModel(.appleSpeech, for: "abc")
        settings.setModel(.openRouter("turkish/model"), for: "turkish")

        let reloaded = TranscriptionSettings(defaults: defaults)

        #expect(reloaded.isInputSourceRoutingEnabled)
        #expect(reloaded.model(for: "abc") == .appleSpeech)
        #expect(reloaded.model(for: "turkish") == .openRouter("turkish/model"))
    }
}
