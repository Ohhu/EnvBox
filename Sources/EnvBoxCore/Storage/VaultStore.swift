import CryptoKit
import Foundation

/// Encrypted local vault. The AES key lives in Keychain; only ciphertext touches disk.
public actor VaultStore {
    public nonisolated let fileURL: URL
    private let keyProvider: VaultKeyProviding
    private let fileManager: FileManager
    private var cachedKey: VaultKey?

    public init(
        fileURL: URL? = nil,
        keyProvider: VaultKeyProviding = KeychainVaultKeyProvider(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? Self.defaultVaultURL(fileManager: fileManager)
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    public static func defaultVaultURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("EnvBox", isDirectory: true)
            .appendingPathComponent("vault.envbox", isDirectory: false)
    }

    public func load() throws -> VaultPayload {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return VaultPayload.empty()
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > EnvBoxValidation.maxVaultFileBytes {
                throw EnvBoxError.fileTooLarge
            }

            let data = try SafeFileReader.readData(at: fileURL, maxBytes: EnvBoxValidation.maxVaultFileBytes)

            let decoder = Self.makeDecoder()
            let envelope = try decoder.decode(VaultEnvelope.self, from: data)
            guard envelope.format == VaultEnvelope.formatIdentifier else { throw EnvBoxError.invalidArchive }
            guard envelope.version <= VaultEnvelope.currentVersion else {
                throw EnvBoxError.unsupportedArchiveVersion(envelope.version)
            }

            let vaultKey: VaultKey
            if let cachedKey {
                vaultKey = cachedKey
            } else {
                guard let existing = try keyProvider.existingKey() else {
                    throw EnvBoxError.missingVaultKey
                }
                cachedKey = existing
                vaultKey = existing
            }

            guard vaultKey.id == envelope.keyID else { throw EnvBoxError.vaultKeyMismatch }

            let plaintext: Data
            do {
                plaintext = try CryptoBox.open(
                    envelope.sealed,
                    key: vaultKey.key,
                    aad: CryptoBox.vaultAAD(keyID: envelope.keyID)
                )
            } catch {
                throw EnvBoxError.vaultKeyMismatch
            }

            let payload = try decoder.decode(VaultPayload.self, from: plaintext)
            guard payload.schemaVersion <= VaultPayload.currentSchemaVersion else {
                throw EnvBoxError.unsupportedArchiveVersion(payload.schemaVersion)
            }
            try EnvBoxValidation.validate(payload: payload)
            return payload
        } catch let error as EnvBoxError {
            throw error
        } catch is DecodingError {
            throw EnvBoxError.invalidArchive
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }

    public func save(_ payload: VaultPayload) throws {
        try EnvBoxValidation.validate(payload: payload)

        let vaultKey: VaultKey
        if let cachedKey {
            vaultKey = cachedKey
        } else {
            let key = try keyProvider.loadOrCreateKey()
            cachedKey = key
            vaultKey = key
        }

        do {
            let plaintext = try Self.makeEncoder().encode(payload)
            let sealed = try CryptoBox.seal(
                plaintext,
                key: vaultKey.key,
                aad: CryptoBox.vaultAAD(keyID: vaultKey.id)
            )
            let envelope = VaultEnvelope(keyID: vaultKey.id, sealed: sealed)
            let archive = try Self.makeEncoder().encode(envelope)
            guard archive.count <= EnvBoxValidation.maxVaultFileBytes else {
                throw EnvBoxError.configurationTooLarge
            }

            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

            try archive.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as EnvBoxError {
            throw error
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }

    public nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601String(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Self.date(fromISO8601: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }

    private nonisolated static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private nonisolated static func date(fromISO8601 string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
