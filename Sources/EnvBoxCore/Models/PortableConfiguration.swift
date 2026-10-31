import Foundation

public struct PortableConfiguration: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profiles: [EnvProfile]
    public var exportedAt: Date
    public var generator: String

    public init(
        schemaVersion: Int = PortableConfiguration.currentSchemaVersion,
        profiles: [EnvProfile],
        exportedAt: Date = Date(),
        generator: String = "EnvBox"
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.exportedAt = exportedAt
        self.generator = generator
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case exportedAt
        case generator
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try container.decode([EnvProfile].self, forKey: .profiles)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        generator = try container.decodeIfPresent(String.self, forKey: .generator) ?? "EnvBox"
    }
}

public struct VaultEnvelope: Codable, Sendable {
    public static let formatIdentifier = "envbox.vault"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var keyID: String
    public var sealed: Data

    public init(format: String = VaultEnvelope.formatIdentifier, version: Int = VaultEnvelope.currentVersion, keyID: String, sealed: Data) {
        self.format = format
        self.version = version
        self.keyID = keyID
        self.sealed = sealed
    }
}

public struct ExportEnvelope: Codable, Sendable {
    public static let formatIdentifier = "envbox.export"
    public static let currentVersion = 1
    public static let kdfIdentifier = "PBKDF2-HMAC-SHA256"

    public var format: String
    public var version: Int
    public var createdAt: Date
    public var kdf: String
    public var iterations: Int
    public var salt: Data
    public var sealed: Data

    public init(
        format: String = ExportEnvelope.formatIdentifier,
        version: Int = ExportEnvelope.currentVersion,
        createdAt: Date = Date(),
        kdf: String = ExportEnvelope.kdfIdentifier,
        iterations: Int,
        salt: Data,
        sealed: Data
    ) {
        self.format = format
        self.version = version
        self.createdAt = createdAt
        self.kdf = kdf
        self.iterations = iterations
        self.salt = salt
        self.sealed = sealed
    }
}
