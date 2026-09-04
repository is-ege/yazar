import SwiftUI

/// One modifier combination drawn as keycaps, in the order every other place
/// writes it. Empty draws nothing, so a capture in progress needs no branch.
struct TriggerKeycaps: View {
    let modifiers: Set<TriggerModifier>
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TriggerModifier.ordered(modifiers)) { modifier in
                Text(modifier.keycap)
                    .font(.system(size: size, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}
