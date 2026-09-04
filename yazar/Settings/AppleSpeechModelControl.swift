import SwiftUI

/// The on-device model selected by Apple Speech for one language, including
/// installation state and the deliberate download action.
struct AppleSpeechModelControl: View {
    let language: String?
    @State private var speechModel = AppleSpeechModel()

    var body: some View {
        HStack(spacing: 8) {
            Text(modelLanguage)
                .lineLimit(1)

            switch speechModel.state {
            case .checking, .downloading:
                ProgressView()
                    .controlSize(.small)
            case .unsupported:
                Label("Unsupported", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .notInstalled, .failed:
                Button("Download", action: speechModel.download)
                    .buttonStyle(.bordered)
            case .installed:
                // Icon only: the row is narrow enough that the word would eat
                // the language name. The row's help text names the state.
                GrantedLabel("Downloaded")
                    .labelStyle(.iconOnly)
            }
        }
        .help(modelDescription)
        .onAppear(perform: refresh)
        .onChange(of: language) { _, _ in refresh() }
    }

    private func refresh() {
        speechModel.refresh(language: language)
    }

    private var modelLanguage: String {
        if let locale = speechModel.locale {
            return AppleSpeechTranscriber.displayName(for: locale)
        }
        return AppleSpeechTranscriber.displayName(for: language)
    }

    private var modelDescription: String {
        switch speechModel.state {
        case .checking:
            "Checking the on-device model for \(modelLanguage)."
        case .unsupported:
            "Apple Speech has no model for \(modelLanguage)."
        case .notInstalled:
            "macOS downloads the \(modelLanguage) model on first use, or fetch it now."
        case .downloading:
            "Downloading the \(modelLanguage) model."
        case .installed:
            "The \(modelLanguage) model is on this Mac."
        case .failed(let message):
            message
        }
    }
}
