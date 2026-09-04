import Foundation

/// One rewrite Yazar can apply to a transcript before inserting it.
///
/// Rules are the columns of the Formatting page, so adding one is this case plus
/// one arm in `TranscriptFormatter.apply`. The settings grid, persistence, and
/// per-group behaviour all follow from `allCases`.
enum FormattingRule: String, CaseIterable, Codable, Identifiable, Sendable {
    case lowercase

    var id: Self { self }

    /// Column header on the Formatting page. Short, because it sets the column
    /// width for every row.
    var title: String {
        switch self {
        case .lowercase: "All lowercase"
        }
    }

    var explanation: String {
        switch self {
        case .lowercase: "Insert transcripts entirely in lowercase."
        }
    }

    /// Rules read back from storage. A raw value written by a newer build drops
    /// out instead of failing the decode, so moving back a version leaves the
    /// user's groups intact rather than erasing them.
    static func set(fromStored rawValues: [String]) -> Set<FormattingRule> {
        Set(rawValues.compactMap(FormattingRule.init(rawValue:)))
    }
}
