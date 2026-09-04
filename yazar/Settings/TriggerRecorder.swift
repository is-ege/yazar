import SwiftUI

/// The current dictation trigger, drawn as keycaps. Clicking it opens the
/// recorder that rebinds it.
struct TriggerRecorder: View {
    @Binding var trigger: DictationTrigger
    let yazar: Yazar

    @State private var isRecording = false

    var body: some View {
        Button { isRecording = true } label: {
            TriggerKeycaps(modifiers: trigger.modifiers)
                .padding(.horizontal, 8)
                .frame(minWidth: 90, minHeight: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityLabel("Dictation key")
        .accessibilityValue(trigger.displayName)
        .sheet(isPresented: $isRecording) {
            TriggerRecorderSheet(trigger: $trigger, yazar: yazar)
        }
    }
}
