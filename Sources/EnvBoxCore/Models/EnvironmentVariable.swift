import Foundation

/// A single editable environment entry stored inside an EnvBox profile.
public struct EnvVariable: Identifiable, Codable, Hashable, Sendable {
    public static let maxValueBytes = 32 * 1024
    public static let maxNoteLength = 500

    public var id: UUID
    public var key: String
    public var value: String
    public var isEnabled: Bool
    public var isSecret: Bool
    public var note: String

    public init(
        id: UUID = UUID(),
        key: String,
        value: String,
        isEnabled: Bool = true,
        isSecret: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.isSecret = isSecret
        self.note = note
    }

    public var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var hasValue: Bool {
        !value.isEmpty
    }

    public var masking: String {
        value.isEmpty ? "—" : "••••••••"
    }
}

public enum EnvironmentSensitivity {
    private static let markers: Set<String> = [
        "PASSWORD", "PASSWD", "PASSPHRASE", "SECRET", "TOKEN",
        "CREDENTIAL", "CREDENTIALS", "AUTH", "APIKEY", "PRIVATEKEY"
    ]

    private static let explicitNonSecretKeys: Set<String> = [
        "SSH_AUTH_SOCK", "GPG_AGENT_INFO", "KEYCHAIN_PATH"
    ]

    /// Heuristic used only to choose a safe default. Users can override it per variable.
    public static func isSensitive(key: String) -> Bool {
        let upper = key.uppercased()
        if explicitNonSecretKeys.contains(upper) { return false }

        let tokens = Set(
            upper
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )

        if !tokens.isDisjoint(with: markers) { return true }

        let secretSuffixes = [
            "_KEY", "_KEY_ID", "_ACCESS_KEY", "_API_KEY", "_PRIVATE_KEY",
            "_TOKEN", "_SECRET", "_PASSWORD", "_PASSWD", "_PASSPHRASE",
            "_CREDENTIALS", "_AUTH"
        ]
        if secretSuffixes.contains(where: { upper.hasSuffix($0) }) { return true }
        if upper == "KEY" { return true }

        // AWS credentials are commonly displayed by other tools; do not miss them.
        if upper.hasPrefix("AWS_ACCESS_KEY") || upper.hasPrefix("AWS_SECRET_") { return true }
        return false
    }
}

public enum EnvironmentInternalKeys {
    private static let exact: Set<String> = [
        "PWD", "OLDPWD", "SHLVL", "_", "__CFBundleIdentifier",
        "XPC_SERVICE_NAME", "XPC_FLAGS", "SECURITYSESSIONID",
        "LaunchInstanceID", "COMMAND_MODE", "CFFIXED_USER_HOME",
        "NSUnbufferedIO", "OS_ACTIVITY_DT_MODE", "MallocNanoZone"
    ]

    private static let prefixes = [
        "__CF", "__XPC", "DYLD_", "XPC_", "OS_ACTIVITY_"
    ]

    public static func isInternal(key: String) -> Bool {
        if exact.contains(key) { return true }
        return prefixes.contains(where: { key.hasPrefix($0) })
    }
}

/// A read-only entry captured from the current process or login shell.
public struct SystemVariable: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: String
    public let isSensitive: Bool
    public let isInternal: Bool

    public init(key: String, value: String) {
        self.key = key
        self.value = value
        self.isSensitive = EnvironmentSensitivity.isSensitive(key: key)
        self.isInternal = EnvironmentInternalKeys.isInternal(key: key)
    }

    public var masking: String {
        value.isEmpty ? "—" : "••••••••"
    }
}

public enum EnvironmentCaptureSource: String, Codable, Sendable {
    case loginShell
    case processOnly
    case fallback
}

public struct EnvironmentSnapshot: Sendable, Equatable {
    public let variables: [SystemVariable]
    public let source: EnvironmentCaptureSource
    public let capturedAt: Date
    public let duration: TimeInterval
    public let warning: String?
    public let shellName: String?

    public init(
        variables: [SystemVariable],
        source: EnvironmentCaptureSource,
        capturedAt: Date = Date(),
        duration: TimeInterval = 0,
        warning: String? = nil,
        shellName: String? = nil
    ) {
        self.variables = variables
        self.source = source
        self.capturedAt = capturedAt
        self.duration = duration
        self.warning = warning
        self.shellName = shellName
    }

    public var sensitiveCount: Int {
        variables.lazy.filter(\.isSensitive).count
    }

    public var internalCount: Int {
        variables.lazy.filter(\.isInternal).count
    }
}
