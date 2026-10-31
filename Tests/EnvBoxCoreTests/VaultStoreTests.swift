import CryptoKit
import Foundation
import Testing
@testable import EnvBoxCore

@Suite("Vault store")
struct VaultStoreTests {
    @Test func vaultRoundTripAndCiphertextAtRest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("vault.envbox")
        let provider = StaticKeyProvider()
        let store = VaultStore(fileURL: fileURL, keyProvider: provider)
        var profile = sampleProfile()
        profile.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        profile.updatedAt = Date(timeIntervalSince1970: 1_700_000_010)
        var payload = VaultPayload.empty(now: Date(timeIntervalSince1970: 1_700_000_000))
        payload.profiles = [profile]
        payload.activeProfileID = profile.id
        payload.appliedKeys = ["API_TOKEN"]
        payload.appliedFingerprint = profile.fingerprint()

        try await store.save(payload)
        let loaded = try await store.load()
        #expect(loaded == payload)

        let raw = try Data(contentsOf: fileURL)
        #expect(!String(decoding: raw, as: UTF8.self).contains("secret"))
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func vaultWithWrongKeyIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("vault.envbox")
        let firstStore = VaultStore(fileURL: fileURL, keyProvider: StaticKeyProvider())
        try await firstStore.save(VaultPayload.empty())

        let differentKey = VaultKey(id: "other-key", key: SymmetricKey(size: .bits256))
        let secondStore = VaultStore(fileURL: fileURL, keyProvider: StaticKeyProvider(key: differentKey))
        do {
            _ = try await secondStore.load()
            Issue.record("Expected key mismatch")
        } catch {
            #expect((error as? EnvBoxError) == .vaultKeyMismatch)
        }
    }

    @Test func missingKeyDoesNotSilentlyOverwriteExistingVault() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("vault.envbox")
        let store = VaultStore(fileURL: fileURL, keyProvider: MissingKeyProvider())

        let saved = VaultStore(fileURL: fileURL, keyProvider: StaticKeyProvider())
        try await saved.save(VaultPayload.empty())
        do {
            _ = try await store.load()
            Issue.record("Expected missing key")
        } catch {
            #expect((error as? EnvBoxError) == .missingVaultKey)
        }
    }
}

private final class MissingKeyProvider: VaultKeyProviding, @unchecked Sendable {
    func existingKey() throws -> VaultKey? { nil }
    func loadOrCreateKey() throws -> VaultKey {
        VaultKey(id: "new", key: SymmetricKey(size: .bits256))
    }
}
