import CoreGraphics
import IOKit.hidsystem

/// One side of one modifier key.
///
/// CGEventFlags reports `.maskCommand` for either Command key, so telling left
/// from right means reading the device-dependent bits IOKit sets alongside it.
/// NSEvent.ModifierFlags carries the same bits in its raw value, which is how
/// the settings screen and the global tap can share one reading.
enum TriggerModifier: String, CaseIterable, Identifiable, Sendable {
    case fn
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case leftShift
    case rightShift

    var id: Self { self }

    var displayName: String {
        switch self {
        case .fn: "🌐 Globe"
        case .leftControl: "Left ⌃"
        case .rightControl: "Right ⌃"
        case .leftOption: "Left ⌥"
        case .rightOption: "Right ⌥"
        case .leftCommand: "Left ⌘"
        case .rightCommand: "Right ⌘"
        case .leftShift: "Left ⇧"
        case .rightShift: "Right ⇧"
        }
    }

    /// What the key reads as on a keycap. Sides are kept, because a trigger of
    /// Left ⌘ drawn as plain ⌘ would name a combination the tap does not match.
    var keycap: String {
        switch self {
        case .fn: "🌐"
        case .leftControl: "L⌃"
        case .rightControl: "R⌃"
        case .leftOption: "L⌥"
        case .rightOption: "R⌥"
        case .leftCommand: "L⌘"
        case .rightCommand: "R⌘"
        case .leftShift: "L⇧"
        case .rightShift: "R⇧"
        }
    }

    /// The bit set while this key is held. Fn has no side, so it uses the
    /// ordinary secondary-function flag; the rest come from IOLLEvent.h.
    var flagMask: UInt64 {
        switch self {
        case .fn: UInt64(NX_SECONDARYFNMASK)
        case .leftControl: UInt64(NX_DEVICELCTLKEYMASK)
        case .rightControl: UInt64(NX_DEVICERCTLKEYMASK)
        case .leftOption: UInt64(NX_DEVICELALTKEYMASK)
        case .rightOption: UInt64(NX_DEVICERALTKEYMASK)
        case .leftCommand: UInt64(NX_DEVICELCMDKEYMASK)
        case .rightCommand: UInt64(NX_DEVICERCMDKEYMASK)
        case .leftShift: UInt64(NX_DEVICELSHIFTKEYMASK)
        case .rightShift: UInt64(NX_DEVICERSHIFTKEYMASK)
        }
    }

    static func held(inRawFlags flags: UInt64) -> Set<TriggerModifier> {
        Set(allCases.filter { flags & $0.flagMask != 0 })
    }

    /// One order for every place a combination is drawn or written, so a
    /// half-recorded set reads the same way as the saved trigger it replaces.
    static func ordered(_ modifiers: Set<TriggerModifier>) -> [TriggerModifier] {
        modifiers.sorted { $0.rawValue < $1.rawValue }
    }
}

/// The modifier combination held to dictate.
///
/// Matching is exact rather than containment: a trigger of Left ⌘ alone must not
/// fire on every ⌘C. The cost is that pressing an unrelated modifier while
/// holding the trigger ends the dictation, which is the safer way to be wrong.
struct DictationTrigger: Hashable, Sendable {
    /// One or two modifiers, all of which must be held and nothing else.
    let modifiers: Set<TriggerModifier>

    static let maximumModifiers = 2
    static let `default` = DictationTrigger(modifiers: [.fn])

    var usesFn: Bool { modifiers.contains(.fn) }

    var displayName: String {
        TriggerModifier.ordered(modifiers)
            .map(\.displayName)
            .joined(separator: " + ")
    }

    func isHeld(_ held: Set<TriggerModifier>) -> Bool {
        !modifiers.isEmpty && held == modifiers
    }
}

extension DictationTrigger: RawRepresentable {
    var rawValue: String {
        modifiers.map(\.rawValue).sorted().joined(separator: "+")
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "+").map(String.init)
        let modifiers = parts.compactMap(TriggerModifier.init(rawValue:))
        guard !modifiers.isEmpty,
              modifiers.count == parts.count,
              modifiers.count <= Self.maximumModifiers else { return nil }
        self.init(modifiers: Set(modifiers))
    }
}
