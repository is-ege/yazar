import SwiftUI

/// The transcript of the meeting being recorded, as it arrives.
///
/// Its own view rather than part of `MeetingDetailView` so that the text is the
/// only thing that redraws when the text changes. Read a level up, every
/// revision would also rebuild the header, its buttons and its dialog, several
/// times a second.
struct LiveTranscriptView: View {
    let session: MeetingSession

    var body: some View {
        if session.liveTranscript.isEmpty, session.liveVolatileText.isEmpty {
            Text("Nothing yet. Only what this Mac plays is recorded, so your own voice will not appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            // Lazy and in blocks: only the block being spoken into is laid out
            // again, and a long meeting's earlier ones are not laid out at all
            // until they are scrolled to.
            LazyVStack(alignment: .leading, spacing: 8) {
                let blocks = blocks
                ForEach(blocks.indices, id: \.self) { index in
                    block(blocks[index], isLast: index == blocks.count - 1)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textSelection(.enabled)
        }
    }

    /// The volatile tail rides on the last block rather than standing alone, so
    /// the sentence being spoken reads as one line and does not jump to its own
    /// as the provider settles it.
    private func block(_ text: String, isLast: Bool) -> Text {
        // Verbatim and attributed on purpose. A localized interpolation, which
        // is what `Text("\(a)\(b)")` builds, looks its whole contents up as a
        // string key — every time a word lands, for as much text as is on
        // screen.
        guard isLast, !session.liveVolatileText.isEmpty else { return Text(verbatim: text) }
        var tail = AttributedString(session.liveVolatileText)
        tail.foregroundColor = .secondary
        return Text(AttributedString(text) + tail)
    }

    private var blocks: [String] {
        let blocks = TranscriptBlocks.split(session.liveTranscript)
        // Nothing settled yet, but there is a guess to show it on.
        return blocks.isEmpty ? [""] : blocks
    }
}
