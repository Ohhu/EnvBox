import Foundation

public enum EnvBoxValidation {
    public static let maxKeyLength = 128
    public static let maxProfileValueBytes = 512 * 1024
    public static let maxAggregateValueBytes = 8 * 1024 * 1024
    public static let maxVaultFileBytes = 20 * 1024 * 1024
    public static let maxTotalImportedVariables = 5_000

    public static func isValidKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.utf8.count <= maxKeyLength else { return false }
        let scalars = Array(key.unicodeScalars)
        guard let first = scalars.first else { return false }
        guard (first == "_") || (first.value >= 65 && first.value <= 90) || (first.value >= 97 && first.value <= 122) else {
            return false
        }
        for scalar in scalars.dropFirst() {
            let isUppercase = scalar.value >= 65 && scalar.value <= 90
            let isLowercase = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            guard isUppercase || isLowercase || isDigit || scalar == "_" else { return false }
        }
        return true
    }

    public static func validatePassphrase(_ passphrase: String) throws {
        let count = passphrase.count
        if count < 8 { throw EnvBoxError.passphraseTooShort }
        if count > 1024 { throw EnvBoxError.passphraseTooLong }
    }

    public static func validateKey(_ key: String) throws {
        if key.isEmpty { throw EnvBoxError.emptyKey }
        if !isValidKey(key) { throw EnvBoxError.invalidKey(key) }
    }

    public static func validateValue(_ value: String, key: String) throws {
        if value.utf8.count > EnvVariable.maxValueBytes {
            throw EnvBoxError.valueTooLong(key)
        }
        if value.utf8.contains(0) {
            throw EnvBoxError.valueContainsNUL
        }
    }

    public static func validateNoDuplicateKeys(_ variables: [EnvVariable]) throws {
        var seen = Set<String>()
        for variable in variables {
            let key = variable.trimmedKey
            if seen.contains(key) { throw EnvBoxError.duplicateKey(key) }
            seen.insert(key)
        }
    }

    public static func validate(profile: EnvProfile) throws {
        let profile = profile.normalized
        if profile.name.isEmpty { throw EnvBoxError.emptyProfileName }
        if profile.name.count > EnvProfile.maxNameLength { throw EnvBoxError.profileNameTooLong }
        if profile.note.count > EnvVariable.maxNoteLength { throw EnvBoxError.noteTooLong }
        if profile.variables.count > EnvProfile.maxVariables { throw EnvBoxError.tooManyVariables }
        if profile.symbol.utf8.count > 80 { throw EnvBoxError.invalidArchive }

        var totalValueBytes = 0
        var ids = Set<UUID>()
        for variable in profile.variables {
            if !ids.insert(variable.id).inserted { throw EnvBoxError.invalidArchive }
            try validateKey(variable.trimmedKey)
            try validateValue(variable.value, key: variable.trimmedKey)
            totalValueBytes += variable.value.utf8.count
            if totalValueBytes > maxProfileValueBytes { throw EnvBoxError.profileTooLarge }
        }
        try validateNoDuplicateKeys(profile.variables)
    }

    public static func validate(payload: VaultPayload) throws {
        if payload.schemaVersion > VaultPayload.currentSchemaVersion {
            throw EnvBoxError.unsupportedArchiveVersion(payload.schemaVersion)
        }
        if payload.profiles.count > VaultPayload.maxProfiles { throw EnvBoxError.tooManyProfiles }
        var profileIDs = Set<UUID>()
        var totalVariables = 0
        var totalValueBytes = 0
        for profile in payload.profiles {
            if !profileIDs.insert(profile.id).inserted { throw EnvBoxError.invalidArchive }
            try validate(profile: profile)
            totalVariables += profile.variables.count
            totalValueBytes += profile.variables.reduce(0) { $0 + $1.value.utf8.count }
            if totalValueBytes > maxAggregateValueBytes { throw EnvBoxError.configurationTooLarge }
        }
        if totalVariables > maxTotalImportedVariables { throw EnvBoxError.tooManyVariablesInArchive }
        if let active = payload.activeProfileID, !profileIDs.contains(active) {
            throw EnvBoxError.invalidArchive
        }
        for key in payload.appliedKeys {
            try validateKey(key)
        }
    }

    public static func uniqueProfileName(_ proposed: String, existing: [EnvProfile], excluding id: UUID? = nil) -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = base.isEmpty ? "未命名配置" : String(base.prefix(EnvProfile.maxNameLength))
        let names = Set(existing.filter { $0.id != id }.map { normalizedName($0.name) })
        if !names.contains(normalizedName(fallback)) { return fallback }
        var index = 2
        while true {
            let suffix = " \(index)"
            let prefixLength = max(1, EnvProfile.maxNameLength - suffix.count)
            let candidate = String(fallback.prefix(prefixLength)) + suffix
            if !names.contains(normalizedName(candidate)) { return candidate }
            index += 1
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    public static func sanitizedExportFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).union(.init(charactersIn: "年月日"))
        let filtered = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "EnvBox-Configuration" : String(result.prefix(80))
    }
}
