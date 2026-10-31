import CryptoKit
import Foundation

public enum ProfileTint: String, Codable, CaseIterable, Sendable {
    case aurora
    case ocean
    case ember
    case orchid
    case lime
    case slate
}

public struct EnvProfile: Identifiable, Codable, Hashable, Sendable {
    public static let maxNameLength = 60
    public static let maxVariables = 500

    public var id: UUID
    public var name: String
    public var note: String
    public var tint: ProfileTint
    public var symbol: String
    public var variables: [EnvVariable]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        tint: ProfileTint = .aurora,
        symbol: String = "shippingbox.fill",
        variables: [EnvVariable] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.tint = tint
        self.symbol = symbol
        self.variables = variables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var enabledVariables: [EnvVariable] {
        variables.filter(\.isEnabled)
    }

    public var secretCount: Int {
        variables.lazy.filter(\.isSecret).count
    }

    public var sortedVariables: [EnvVariable] {
        variables.sorted {
            let comparison = $0.trimmedKey.localizedStandardCompare($1.trimmedKey)
            if comparison == .orderedSame {
                return $0.id.uuidString < $1.id.uuidString
            }
            return comparison == .orderedAscending
        }
    }

    public var normalized: EnvProfile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(EnvVariable.maxNoteLength))
        copy.symbol = symbol.isEmpty ? "shippingbox.fill" : symbol
        copy.variables = variables.map { variable in
            var item = variable
            item.key = variable.trimmedKey
            item.note = String(variable.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(EnvVariable.maxNoteLength))
            return item
        }
        return copy
    }

    /// A stable, non-reversible digest of the enabled environment.
    public func fingerprint() -> String {
        var canonical = "EnvBoxProfileV1\n"
        for variable in enabledVariables.sorted(by: { $0.trimmedKey < $1.trimmedKey }) {
            let key = variable.trimmedKey
            canonical += "\(key.utf8.count):\(key)=\(variable.value.utf8.count):\(variable.value)\n"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var autoRestoreActiveProfile: Bool
    public var includeLoginShellEnvironment: Bool
    public var showInternalVariables: Bool
    public var concealSensitiveValues: Bool
    public var autoClearSensitiveClipboard: Bool
    public var hasCompletedFirstApply: Bool
    public var shellIntegrationEnabled: Bool
    public var mcpEnabled: Bool
    public var mcpAllowReveal: Bool
    public var launchAtLogin: Bool
    public var hasAcknowledgedRestartHint: Bool

    public init(
        autoRestoreActiveProfile: Bool = true,
        includeLoginShellEnvironment: Bool = true,
        showInternalVariables: Bool = false,
        concealSensitiveValues: Bool = true,
        autoClearSensitiveClipboard: Bool = true,
        hasCompletedFirstApply: Bool = false,
        shellIntegrationEnabled: Bool = false,
        mcpEnabled: Bool = false,
        mcpAllowReveal: Bool = false,
        launchAtLogin: Bool = true,
        hasAcknowledgedRestartHint: Bool = false
    ) {
        self.autoRestoreActiveProfile = autoRestoreActiveProfile
        self.includeLoginShellEnvironment = includeLoginShellEnvironment
        self.showInternalVariables = showInternalVariables
        self.concealSensitiveValues = concealSensitiveValues
        self.autoClearSensitiveClipboard = autoClearSensitiveClipboard
        self.hasCompletedFirstApply = hasCompletedFirstApply
        self.shellIntegrationEnabled = shellIntegrationEnabled
        self.mcpEnabled = mcpEnabled
        self.mcpAllowReveal = mcpAllowReveal
        self.launchAtLogin = launchAtLogin
        self.hasAcknowledgedRestartHint = hasAcknowledgedRestartHint
    }

    private enum CodingKeys: String, CodingKey {
        case autoRestoreActiveProfile
        case includeLoginShellEnvironment
        case showInternalVariables
        case concealSensitiveValues
        case autoClearSensitiveClipboard
        case hasCompletedFirstApply
        case shellIntegrationEnabled
        case mcpEnabled
        case mcpAllowReveal
        case launchAtLogin
        case hasAcknowledgedRestartHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        autoRestoreActiveProfile = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreActiveProfile) ?? defaults.autoRestoreActiveProfile
        includeLoginShellEnvironment = try container.decodeIfPresent(Bool.self, forKey: .includeLoginShellEnvironment) ?? defaults.includeLoginShellEnvironment
        showInternalVariables = try container.decodeIfPresent(Bool.self, forKey: .showInternalVariables) ?? defaults.showInternalVariables
        concealSensitiveValues = try container.decodeIfPresent(Bool.self, forKey: .concealSensitiveValues) ?? defaults.concealSensitiveValues
        autoClearSensitiveClipboard = try container.decodeIfPresent(Bool.self, forKey: .autoClearSensitiveClipboard) ?? defaults.autoClearSensitiveClipboard
        hasCompletedFirstApply = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstApply) ?? defaults.hasCompletedFirstApply
        shellIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .shellIntegrationEnabled) ?? defaults.shellIntegrationEnabled
        mcpEnabled = try container.decodeIfPresent(Bool.self, forKey: .mcpEnabled) ?? defaults.mcpEnabled
        mcpAllowReveal = try container.decodeIfPresent(Bool.self, forKey: .mcpAllowReveal) ?? defaults.mcpAllowReveal
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        hasAcknowledgedRestartHint = try container.decodeIfPresent(Bool.self, forKey: .hasAcknowledgedRestartHint) ?? defaults.hasAcknowledgedRestartHint
    }
}

public struct VaultPayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let maxProfiles = 100

    public var schemaVersion: Int
    public var profiles: [EnvProfile]
    public var activeProfileID: UUID?
    public var appliedKeys: [String]
    public var appliedFingerprint: String?
    public var settings: AppSettings
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = VaultPayload.currentSchemaVersion,
        profiles: [EnvProfile] = [],
        activeProfileID: UUID? = nil,
        appliedKeys: [String] = [],
        appliedFingerprint: String? = nil,
        settings: AppSettings = AppSettings(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.appliedKeys = appliedKeys
        self.appliedFingerprint = appliedFingerprint
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func empty(now: Date = Date()) -> VaultPayload {
        VaultPayload(createdAt: now, updatedAt: now)
    }

    public var activeProfile: EnvProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first(where: { $0.id == activeProfileID })
    }

    public func profile(id: UUID) -> EnvProfile? {
        profiles.first(where: { $0.id == id })
    }

    public mutating func touch() {
        updatedAt = Date()
    }

    public var isActiveProfilePending: Bool {
        guard let activeProfile else { return false }
        return activeProfile.fingerprint() != appliedFingerprint
    }

    public var totalVariableCount: Int {
        profiles.reduce(0) { $0 + $1.variables.count }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profiles
        case activeProfileID
        case appliedKeys
        case appliedFingerprint
        case settings
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try container.decodeIfPresent([EnvProfile].self, forKey: .profiles) ?? []
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        appliedKeys = try container.decodeIfPresent([String].self, forKey: .appliedKeys) ?? []
        appliedFingerprint = try container.decodeIfPresent(String.self, forKey: .appliedFingerprint)
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
