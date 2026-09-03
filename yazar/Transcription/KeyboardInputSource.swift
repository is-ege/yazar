import Carbon.HIToolbox
import Foundation

/// A keyboard input source enabled in macOS, reduced to the identity and
/// intended language transcription routing needs.
nonisolated struct KeyboardInputSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let languageIdentifier: String?

    /// The input sources the user has enabled in System Settings.
    static var enabled: [KeyboardInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource,
        ] as CFDictionary
        let values = TISCreateInputSourceList(filter, false).takeRetainedValue() as [AnyObject]
        return values
            // Carbon guarantees this array contains TISInputSource references;
            // its CFArray bridge erases their element type to AnyObject.
            .compactMap { Self.init($0 as! TISInputSource) }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    /// The source selected at the instant a dictation finishes.
    static var current: KeyboardInputSource? {
        KeyboardInputSource(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    /// Kept internal so tests can exercise Apple's language-list contract
    /// without changing the Mac's real selected input source.
    init(id: String, name: String, languages: [String]) {
        self.id = id
        self.name = name
        languageIdentifier = Self.intendedLanguage(in: languages)
    }

    private init?(_ source: TISInputSource) {
        guard let id = Self.property(source, key: kTISPropertyInputSourceID) as String?,
              let name = Self.property(source, key: kTISPropertyLocalizedName) as String?
        else { return nil }

        self.init(
            id: id,
            name: name,
            languages: Self.property(source, key: kTISPropertyInputSourceLanguages) ?? []
        )
    }

    /// Text Input Source Services defines the first entry as the intended
    /// language. A leading empty entry means the source has no intended one.
    private static func intendedLanguage(in languages: [String]) -> String? {
        guard let language = languages.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !language.isEmpty
        else { return nil }
        return Locale.Language(identifier: language).minimalIdentifier
    }

    private static func property<Value>(
        _ source: TISInputSource,
        key: CFString
    ) -> Value? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? Value
    }
}
