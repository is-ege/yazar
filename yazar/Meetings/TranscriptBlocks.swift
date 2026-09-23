import Foundation

/// Splits a transcript that is still growing into blocks a view can draw
/// separately.
///
/// SwiftUI lays a `Text` out whole, so an hour of transcript in one of them is
/// re-measured every time a word is added — which, live, is several times a
/// second. Blocks bound that work to the last one.
///
/// Boundaries are chosen left to right and depend only on the text before them,
/// so appending never moves an earlier boundary: every block but the last is
/// identical to the one drawn a moment ago, and SwiftUI skips it.
nonisolated struct TranscriptBlocks {
    /// Long enough that a meeting is not hundreds of views, short enough that
    /// re-laying out the last block is cheap.
    static let minimumLength = 800
    /// A provider that returns no punctuation at all would otherwise grow one
    /// block without limit, so a block also ends at a space once it is this long.
    static let maximumLength = 2_400

    private static let terminators: Set<Character> = [".", "!", "?"]

    static func split(_ transcript: String) -> [String] {
        guard !transcript.isEmpty else { return [] }

        var blocks: [String] = []
        var start = transcript.startIndex
        var index = transcript.startIndex
        var length = 0
        // A sentence ends at its terminator, but the space after it belongs to
        // the block that is ending, not to the one starting: cutting between the
        // two would indent every block but the first.
        var afterTerminator = false

        while index < transcript.endIndex {
            let character = transcript[index]
            index = transcript.index(after: index)
            length += 1

            let ends = length >= minimumLength
                && (character.isNewline
                    || (afterTerminator && character.isWhitespace)
                    || (length >= maximumLength && character.isWhitespace))
            afterTerminator = terminators.contains(character)
            guard ends else { continue }

            blocks.append(String(transcript[start..<index]))
            start = index
            length = 0
        }

        if start < transcript.endIndex {
            blocks.append(String(transcript[start...]))
        }
        return blocks
    }
}
