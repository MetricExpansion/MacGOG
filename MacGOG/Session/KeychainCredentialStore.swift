import Foundation
import Security
import SwiftyGOG

/// Keeps the app's GOG OAuth credentials in one generic-password Keychain item, separate from the
/// `gogdl` CLI's token file.
nonisolated struct KeychainCredentialStore: CredentialStore {
    static let defaultService = "com.metricexpansion.MacGOG.credentials"

    let service: String
    let account: String

    init(service: String = Self.defaultService, account: String = "gog") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func load() throws -> [String: OAuthToken] {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                let credentials = try? JSONDecoder().decode([String: OAuthToken].self, from: data)
            else { throw GOGError.authentication(.invalidCredentialStore) }
            return credentials
        case errSecItemNotFound:
            return [:]
        default:
            throw AppError.keychain(status)
        }
    }

    func save(_ credentials: [String: OAuthToken]) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "MacGOG GOG sign-in"
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppError.keychain(status) }
        default:
            throw AppError.keychain(update)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.keychain(status) }
    }
}
