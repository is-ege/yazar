import Foundation
import Observation

/// Every API key Yazar holds, read from the Keychain once at launch.
///
/// Transcription and meeting notes authenticate against the same account, so
/// the credential is owned here rather than by either feature. Both read it
/// through `Settings.credentials`.
@MainActor
@Observable
final class Credentials {
    private(set) var keys: [APIProvider: String] = [:]

    /// The last Keychain failure, shown on the Providers page. Loading and
    /// saving share it because either one failing means the same thing to the
    /// user: the key on screen is not the key on disk.
    private(set) var error: String?

    init() {
        do {
            try ProviderKeychain.migrateLegacyKey()
            for provider in APIProvider.allCases {
                keys[provider] = try ProviderKeychain.load(for: provider)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func key(for provider: APIProvider) -> String {
        keys[provider] ?? ""
    }

    func setKey(_ key: String, for provider: APIProvider) {
        guard self.key(for: provider) != key else { return }
        keys[provider] = key
        do {
            try ProviderKeychain.save(key, for: provider)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
