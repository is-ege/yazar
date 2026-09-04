import SwiftUI

/// Edits one OpenRouter model string, whether it belongs to the fixed
/// configuration or one input source.
struct CustomTranscriptionModelSheet: View {
    @Binding private var model: String
    @State private var customModel: String
    @FocusState private var customModelFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: Binding<String>) {
        _model = model
        let current = model.wrappedValue
        _customModel = State(
            initialValue: SuggestedModel.all.contains { $0.id == current } ? "" : current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Custom Model")
                    .font(.headline)
                Text("Enter the OpenRouter model string, for example openai/gpt-transcribe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("provider/model", text: $customModel)
                .textFieldStyle(.roundedBorder)
                .focused($customModelFocused)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedModel.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { customModelFocused = true }
    }

    private var trimmedModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        model = trimmedModel
        dismiss()
    }

    private func cancel() {
        dismiss()
    }
}
