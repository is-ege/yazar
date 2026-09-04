import AppKit
import SwiftUI

/// Records a new dictation trigger by watching which modifiers the user holds.
///
/// The global tap is still running while this is open, so Yazar is told to
/// ignore the trigger for the duration; otherwise choosing a key would start a
/// dictation with it.
struct TriggerRecorderSheet: View {
    @Binding var trigger: DictationTrigger
    let yazar: Yazar

    @Environment(\.dismiss) private var dismiss
    @State private var captured: Set<TriggerModifier> = []
    @State private var isHolding = false
    @State private var monitor: Any?

    private var isValid: Bool {
        !captured.isEmpty && captured.count <= DictationTrigger.maximumModifiers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose a Dictation Key")
                    .font(.system(size: 13, weight: .semibold))
                Text("Hold the modifier keys you want to dictate with, then let go. One or two keys.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if let prompt {
                    Text(prompt)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    TriggerKeycaps(modifiers: captured, size: 15)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    trigger = DictationTrigger(modifiers: captured)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: startRecording)
        .onDisappear(perform: stopRecording)
    }

    /// Words only while the capture is not yet something we can save; once it
    /// is, the keycaps say it.
    private var prompt: String? {
        if captured.isEmpty { return "Hold a modifier key" }
        return isValid ? nil : "Two keys at most"
    }

    private func startRecording() {
        yazar.ignoresTrigger = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            // The CGEvent carries the device-dependent bits that tell left from
            // right; NSEvent.modifierFlags is only a fallback for a synthesised event.
            let raw = event.cgEvent.map(\.flags.rawValue) ?? UInt64(event.modifierFlags.rawValue)
            let held = TriggerModifier.held(inRawFlags: raw)
            if held.isEmpty {
                isHolding = false
            } else {
                // A fresh press starts over; keys added while holding accumulate,
                // so releasing them one at a time still records the whole combination.
                if !isHolding {
                    captured = []
                    isHolding = true
                }
                captured.formUnion(held)
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        yazar.ignoresTrigger = false
    }
}
