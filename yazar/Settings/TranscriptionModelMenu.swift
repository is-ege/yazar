import SwiftUI

/// The shared OpenRouter model menu for the fixed configuration and routed
/// input sources.
struct TranscriptionModelMenu: View {
    @Binding var model: String
    let accessibilityName: String
    @State private var isAddingCustomModel = false

    var body: some View {
        Menu {
            Section("Suggested Models") {
                ForEach(SuggestedModel.all) { suggestion in
                    Toggle(isOn: selection(of: suggestion.id)) {
                        Text(suggestion.id)
                        Text(suggestion.summary)
                    }
                }
            }

            if !isSuggested(model) {
                Section("Custom Model") {
                    Toggle(isOn: selection(of: model)) {
                        Text(model)
                    }
                }
            }

            Button("Add a Custom Model…", action: startAddingCustomModel)
        } label: {
            Text(model)
                .lineLimit(1)
        }
        .accessibilityLabel(accessibilityName)
        .sheet(isPresented: $isAddingCustomModel) {
            CustomTranscriptionModelSheet(model: $model)
        }
    }

    /// Re-picking the selected item must leave it selected, even though Menu
    /// represents its checkmark with a toggle.
    private func selection(of candidate: String) -> Binding<Bool> {
        Binding {
            model == candidate
        } set: { isSelected in
            if isSelected { model = candidate }
        }
    }

    private func isSuggested(_ candidate: String) -> Bool {
        SuggestedModel.all.contains { $0.id == candidate }
    }

    private func startAddingCustomModel() {
        isAddingCustomModel = true
    }
}
