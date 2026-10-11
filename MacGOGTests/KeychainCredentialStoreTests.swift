import Foundation
import Security
import SwiftyGOG
import Testing

@testable import MacGOG

/// Each test gets a fresh suite instance, so each uses its own Keychain item.
@Suite final class KeychainCredentialStoreTests {
    private let store = KeychainCredentialStore(
        service: "com.metricexpansion.MacGOG.tests.\(UUID().uuidString)"
    )
    private let token = OAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        expiresIn: 3600,
        userID: "42"
    )

    deinit {
        try? store.delete()
    }

    @Test func missingItemLoadsEmpty() throws {
        #expect(try store.load().isEmpty)
    }

    @Test func roundTripsAndUpdates() throws {
        try store.save([Authorization.clientID: token])
        #expect(try store.load()[Authorization.clientID]?.userID == "42")
        let other = OAuthToken(accessToken: "a2", refreshToken: "r2", expiresIn: 3600, userID: "43")
        try store.save([Authorization.clientID: token, "game": other])
        let loaded = try store.load()
        #expect(loaded.count == 2)
        #expect(loaded["game"]?.accessToken == "a2")
    }

    @Test func deleteRemovesAndIgnoresMissing() throws {
        try store.save([Authorization.clientID: token])
        try store.delete()
        #expect(try store.load().isEmpty)
        try store.delete()
    }

    @Test func unreadableItemIsAnInvalidStore() throws {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: store.account,
            kSecValueData as String: Data("not json".utf8),
        ]
        #expect(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)
        #expect(throws: GOGError.authentication(.invalidCredentialStore)) { try self.store.load() }
    }
}
