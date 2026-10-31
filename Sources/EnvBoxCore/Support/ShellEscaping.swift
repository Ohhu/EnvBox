import Foundation

public enum ShellEscaping {
    /// POSIX single-quote escaping. Safe for values containing quotes, newlines and dollar signs.
    public static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func exportLine(_ variable: EnvVariable) throws -> String {
        try EnvBoxValidation.validateKey(variable.trimmedKey)
        try EnvBoxValidation.validateValue(variable.value, key: variable.trimmedKey)
        return "export \(variable.trimmedKey)=\(singleQuoted(variable.value))"
    }

    public static func launchctlSetenvLine(_ variable: EnvVariable) throws -> String {
        try EnvBoxValidation.validateKey(variable.trimmedKey)
        try EnvBoxValidation.validateValue(variable.value, key: variable.trimmedKey)
        return "/bin/launchctl setenv \(variable.trimmedKey) \(singleQuoted(variable.value))"
    }

    public static func launchctlUnsetenvLine(key: String) throws -> String {
        try EnvBoxValidation.validateKey(key)
        return "/bin/launchctl unsetenv \(key)"
    }

    public static func unsetLine(key: String) throws -> String {
        try EnvBoxValidation.validateKey(key)
        return "unset \(key)"
    }
}
