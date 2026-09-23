import Foundation
import Testing
@testable import yazar

@Suite("Transcript blocks")
struct TranscriptBlocksTests {
    @Test("Splits nothing out of an empty transcript")
    func emptyTranscript() {
        #expect(TranscriptBlocks.split("").isEmpty)
    }

    @Test("Keeps a short transcript whole")
    func shortTranscript() {
        #expect(TranscriptBlocks.split("Hello there. How are you?") == ["Hello there. How are you?"])
    }

    @Test("Rejoins to exactly the transcript it was given")
    func losesNothing() {
        let transcript = sentences(count: 200)
        #expect(TranscriptBlocks.split(transcript).joined() == transcript)
    }

    @Test("Ends a block at a sentence, not mid-word")
    func endsAtSentences() {
        for block in TranscriptBlocks.split(sentences(count: 200)).dropLast() {
            #expect(block.last == " ")
            #expect(block.dropLast().last == ".")
        }
    }

    @Test("Bounds a block even when nothing is punctuated")
    func boundsUnpunctuatedText() {
        let transcript = Array(repeating: "word", count: 4_000).joined(separator: " ")
        let blocks = TranscriptBlocks.split(transcript)
        #expect(blocks.count > 1)
        #expect(blocks.allSatisfy { $0.count <= TranscriptBlocks.maximumLength + 16 })
    }

    /// Appending must never move a boundary that has already been drawn, which
    /// is the whole reason the earlier blocks are cheap to redraw.
    @Test("Leaves earlier blocks untouched as the transcript grows")
    func earlierBlocksAreStable() {
        let transcript = sentences(count: 200)
        var previous = TranscriptBlocks.split(String(transcript.prefix(1_000)))
        for length in stride(from: 1_100, through: transcript.count, by: 100) {
            let blocks = TranscriptBlocks.split(String(transcript.prefix(length)))
            #expect(Array(blocks.prefix(previous.count - 1)) == Array(previous.dropLast()))
            previous = blocks
        }
    }

    private func sentences(count: Int) -> String {
        (0..<count).map { "This is sentence number \($0). " }.joined()
    }
}
