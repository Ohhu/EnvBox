import CryptoKit
import Foundation

/// Performs password-based export/import off the main actor.
public actor ConfigTransferService {
    public init() {}

    public func exportConfiguration(
        profiles: [EnvProfile],
        passphrase: String,
        iterations: Int = PasswordKDF.defaultIterations,
        now: Date = Date()
    ) throws -> Data {
        try EnvBoxValidation.validatePassphrase(passphrase)
        guard !profiles.isEmpty else { throw EnvBoxError.invalidArchive }
        if profiles.count > VaultPayload.maxProfiles { throw EnvBoxError.tooManyProfiles }

        var ids = Set<UUID>()
        var totalVariables = 0
        var totalValueBytes = 0
        for profile in profiles {
            if !ids.insert(profile.id).inserted { throw EnvBoxError.invalidArchive }
            try EnvBoxValidation.validate(profile: profile)
            totalVariables += profile.variables.count
            totalValueBytes += profile.variables.reduce(0) { $0 + $1.value.utf8.count }
            if totalValueBytes > EnvBoxValidation.maxAggregateValueBytes {
                throw EnvBoxError.configurationTooLarge
            }
        }
        if totalVariables > EnvBoxValidation.maxTotalImportedVariables {
            throw EnvBoxError.tooManyVariablesInArchive
        }

        let portable = PortableConfiguration(profiles: profiles, exportedAt: now)
        let plaintext = try VaultStore.makeEncoder().encode(portable)
        let salt = try CryptoBox.randomSalt(byteCount: PasswordKDF.saltByteCount)
        let key = try PasswordKDF.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let aad = CryptoBox.exportAAD(
            format: ExportEnvelope.formatIdentifier,
            version: ExportEnvelope.currentVersion,
            kdf: ExportEnvelope.kdfIdentifier,
            iterations: iterations,
            salt: salt
        )
        let sealed = try CryptoBox.seal(plaintext, key: key, aad: aad)
        let envelope = ExportEnvelope(
            createdAt: now,
            iterations: iterations,
            salt: salt,
            sealed: sealed
        )
        let encoded = try VaultStore.makeEncoder().encode(envelope)
        guard encoded.count <= EnvBoxValidation.maxVaultFileBytes else {
            throw EnvBoxError.configurationTooLarge
        }
        return encoded
    }

    public func importConfiguration(from data: Data, passphrase: String) throws -> PortableConfiguration {
        if data.count > EnvBoxValidation.maxVaultFileBytes { throw EnvBoxError.fileTooLarge }
        try EnvBoxValidation.validatePassphrase(passphrase)

        let envelope: ExportEnvelope
        do {
            envelope = try VaultStore.makeDecoder().decode(ExportEnvelope.self, from: data)
        } catch {
            throw EnvBoxError.invalidArchive
        }

        guard envelope.format == ExportEnvelope.formatIdentifier else { throw EnvBoxError.invalidArchive }
        guard envelope.version <= ExportEnvelope.currentVersion else {
            throw EnvBoxError.unsupportedArchiveVersion(envelope.version)
        }
        guard envelope.kdf == ExportEnvelope.kdfIdentifier else { throw EnvBoxError.invalidArchive }
        guard envelope.iterations >= PasswordKDF.minimumAcceptedIterations,
              envelope.iterations <= PasswordKDF.maximumIterations else {
            throw EnvBoxError.invalidArchive
        }
        guard envelope.salt.count >= 16, envelope.salt.count <= 64 else { throw EnvBoxError.invalidArchive }
        guard !envelope.sealed.isEmpty, envelope.sealed.count <= data.count else {
            throw EnvBoxError.invalidArchive
        }

        let key = try PasswordKDF.deriveKey(passphrase: passphrase, salt: envelope.salt, iterations: envelope.iterations)
        let aad = CryptoBox.exportAAD(
            format: envelope.format,
            version: envelope.version,
            kdf: envelope.kdf,
            iterations: envelope.iterations,
            salt: envelope.salt
        )
        let plaintext: Data
        do {
            plaintext = try CryptoBox.open(envelope.sealed, key: key, aad: aad)
        } catch {
            throw EnvBoxError.incorrectPassphrase
        }

        let portable: PortableConfiguration
        do {
            portable = try VaultStore.makeDecoder().decode(PortableConfiguration.self, from: plaintext)
        } catch {
            throw EnvBoxError.invalidArchive
        }

        guard portable.schemaVersion <= PortableConfiguration.currentSchemaVersion else {
            throw EnvBoxError.unsupportedArchiveVersion(portable.schemaVersion)
        }
        if portable.profiles.count > VaultPayload.maxProfiles { throw EnvBoxError.tooManyProfiles }
        var ids = Set<UUID>()
        var totalVariables = 0
        var totalValueBytes = 0
        for profile in portable.profiles {
            if !ids.insert(profile.id).inserted { throw EnvBoxError.invalidArchive }
            try EnvBoxValidation.validate(profile: profile)
            totalVariables += profile.variables.count
            totalValueBytes += profile.variables.reduce(0) { $0 + $1.value.utf8.count }
            if totalValueBytes > EnvBoxValidation.maxAggregateValueBytes {
                throw EnvBoxError.configurationTooLarge
            }
        }
        if totalVariables > EnvBoxValidation.maxTotalImportedVariables {
            throw EnvBoxError.tooManyVariablesInArchive
        }
        return portable
    }
}
