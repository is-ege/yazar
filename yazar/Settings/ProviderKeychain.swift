import Foundation
import Security

/// One Keychain item per service Yazar holds a key for.
///
/// Yazar first shipped a single slot — service "ai.yazar.openrouter", account
/// "api-key" — which could only ever hold one provider's key. Migration moves
/// it into the per-provider layout and deletes the old item after the first run.
enum ProviderKeychain {
    private static let service = "ai.yazar.credentials"
    private static let legacyService = "ai.yazar.openrouter"
    private static let legacyAccount = "api-key"

    static func load(for provider: APIProvider) throws -> String {
        guard let data = try read(service: service, account: provider.rawValue) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String, for provider: APIProvider) throws {
        if value.isEmpty {
            try delete(service: service, account: provider.rawValue)
        } else {
            try write(Data(value.utf8), service: service, account: provider.rawValue)
        }
    }

    static func migrateLegacyKey() throws {
        guard let legacy = try read(service: legacyService, account: legacyAccount) else { return }
        let account = APIProvider.openRouter.rawValue
        // A key already stored in the provider layout wins; the old item is stale.
        if try read(service: service, account: account) == nil {
            try write(legacy, service: service, account: account)
        }
        try delete(service: legacyService, account: legacyAccount)
    }

    private static func identity(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(service: String, account: String) throws -> Data? {
        var query = identity(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw Error(status: status)
        }
        return data
    }

    private static func write(_ data: Data, service: String, account: String) throws {
        let identity = identity(service: service, account: account)
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw Error(status: updateStatus)
        }

        var item = identity
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Error(status: addStatus)
        }
    }

    private static func delete(service: String, account: String) throws {
        let status = SecItemDelete(identity(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error(status: status)
        }
    }

    private struct Error: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}
