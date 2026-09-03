import Testing
@testable import yazar

@Suite("Keyboard input sources")
struct KeyboardInputSourceTests {
    @Test("Preserves source identity and normalizes its intended language")
    func preservesIdentityAndNormalizesLanguage() {
        let source = KeyboardInputSource(
            id: "com.apple.keylayout.ABC",
            name: "ABC",
            languages: ["en_US", "fr"]
        )

        #expect(source.id == "com.apple.keylayout.ABC")
        #expect(source.name == "ABC")
        #expect(source.languageIdentifier == "en")
    }

    @Test("Preserves a meaningful script distinction")
    func preservesScript() {
        let source = KeyboardInputSource(
            id: "latin-hindi",
            name: "Hindi – Latin",
            languages: ["hi_Latn"]
        )

        #expect(source.languageIdentifier == "hi-Latn")
    }

    @Test("An empty first entry means there is no intended language")
    func emptyIntendedLanguageStaysMissing() {
        let source = KeyboardInputSource(
            id: "unicode-hex",
            name: "Unicode Hex Input",
            languages: ["", "en"]
        )

        #expect(source.languageIdentifier == nil)
    }

    @Test("Sources sharing a language remain distinct")
    func sameLanguageSourcesRemainDistinct() {
        let abc = KeyboardInputSource(id: "abc", name: "ABC", languages: ["en"])
        let us = KeyboardInputSource(id: "us", name: "U.S.", languages: ["en"])

        #expect(abc.languageIdentifier == us.languageIdentifier)
        #expect(abc.id != us.id)
        #expect(Set([abc, us]).count == 2)
    }
}
