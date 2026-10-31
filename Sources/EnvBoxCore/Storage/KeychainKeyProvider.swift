import CryptoKit
import Foundation
import Security

public struct VaultKey: Sendable {
    public let id: String
    public let key: SymmetricKey

    public init(id: String, key: SymmetricKey) {
        self.id = id
        self.key = key
    }
}

public protocol VaultKeyProviding: Sendable {
    func existingKey() throws -> VaultKey?
    func loadOrCreateKey() throws -> VaultKey
}

/// Stores the random 256-bit vault key in the user's login Keychain.
public final class KeychainVaultKeyProvider: VaultKeyProviding, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.ohhu.envbox",
        account: String = "vault-master-key-v1"
    ) {
        self.service = service
        self.account = account
    }

    private struct StoredKey: Codable {
        var id: String
        var key: Data
    }

    public func existingKey() throws -> VaultKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        query[kSecAttrSynchronizable as String] = false

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw EnvBoxError.keychain(status) }
        guard let data = item as? Data else { throw EnvBoxError.missingVaultKey }

        do {
            let stored = try JSONDecoder().decode(StoredKey.self, from: data)
            guard stored.key.count == 32, !stored.id.isEmpty else {
                throw EnvBoxError.missingVaultKey
            }
            return VaultKey(id: stored.id, key: SymmetricKey(data: stored.key))
        } catch let error as EnvBoxError {
            throw error
        } catch {
            throw EnvBoxError.missingVaultKey
        }
    }

    public func loadOrCreateKey() throws -> VaultKey {
        if let existing = try existingKey() { return existing }

        let key = CryptoBox.randomKey()
        let stored = StoredKey(id: UUID().uuidString, key: key.withUnsafeBytes { Data($0) })
        let data: Data
        do {
            data = try JSONEncoder().encode(stored)
        } catch {
            throw EnvBoxError.io("无法编码钥匙串数据")
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "EnvBox Vault Key",
            kSecAttrDescription as String: "AES-256-GCM key for the EnvBox local vault",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            if let existing = try existingKey() { return existing }
        }
        guard status == errSecSuccess else { throw EnvBoxError.keychain(status) }
        return VaultKey(id: stored.id, key: key)
    }
}
