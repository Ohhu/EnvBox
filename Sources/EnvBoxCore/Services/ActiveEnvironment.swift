import CryptoKit
import Foundation

/// One variable exported by the active activation script. Values never leave this type unless asked for
/// explicitly via `value(forKey:)`.
public struct ActiveEnvironmentEntry: Sendable, Equatable {
    public let name: String
    public let length: Int
    public let fingerprint: String

    public init(name: String, length: Int, fingerprint: String) {
        self.name = name
        self.length = length
        self.fingerprint = fingerprint
    }
}

/// A read-only view of `~/.envbox/active.zsh`, the single source of truth for "what is applied right now".
public struct ActiveEnvironmentSnapshot: Sendable, Equatable {
    public let url: URL
    public let isAvailable: Bool
    public let generation: String?
    public let appliedAt: String?
    public let entries: [ActiveEnvironmentEntry]
    public let removedKeys: [String]
    public let profileName: String?

    public init(
        url: URL,
        isAvailable: Bool,
        generation: String?,
        appliedAt: String?,
        entries: [ActiveEnvironmentEntry],
        removedKeys: [String],
        profileName: String?
    ) {
        self.url = url
        self.isAvailable = isAvailable
        self.generation = generation
        self.appliedAt = appliedAt
        self.entries = entries
        self.removedKeys = removedKeys
        self.profileName = profileName
    }

    public static func unavailable(url: URL) -> ActiveEnvironmentSnapshot {
        ActiveEnvironmentSnapshot(
            url: url,
            isAvailable: false,
            generation: nil,
            appliedAt: nil,
            entries: [],
            removedKeys: [],
            profileName: nil
        )
    }

    public func entry(named name: String) -> ActiveEnvironmentEntry? {
        entries.first { $0.name == name }
    }

    public var names: [String] { entries.map(\.name) }
}

public struct ActiveEnvironmentExecResult: Sendable {
    public let generation: String?
    public let exitCode: Int32
    public let signal: Int32?
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool
    public let outputTruncated: Bool
}

/// Reads, describes and executes against the active environment.
///
/// Nothing here pushes state into other processes: every call re-reads the activation file, which is why a
/// value applied a second ago is visible to this call while an already running process keeps its snapshot.
public struct ActiveEnvironmentStore: Sendable {
    public static let maxFileBytes = 8 * 1024 * 1024
    public static let maxOutputBytes = 256 * 1024
    public static let maximumTimeout: TimeInterval = 600

    public let url: URL
    private let fileManager: FileManager

    public init(url: URL = ActiveEnvironmentStore.defaultURL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".envbox", isDirectory: true)
            .appendingPathComponent("active.zsh", isDirectory: false)
    }

    public func snapshot() -> ActiveEnvironmentSnapshot {
        guard fileManager.fileExists(atPath: url.path) else {
            return .unavailable(url: url)
        }
        let data: Data
        do {
            data = try SafeFileReader.readData(at: url, maxBytes: Self.maxFileBytes)
        } catch {
            return .unavailable(url: url)
        }
        let parsed = Self.parse(String(decoding: data, as: UTF8.self))
        return ActiveEnvironmentSnapshot(
            url: url,
            isAvailable: true,
            generation: parsed.generation ?? parsed.appliedAt,
            appliedAt: parsed.appliedAt,
            entries: parsed.values
                .sorted { $0.key < $1.key }
                .map { key, value in
                    ActiveEnvironmentEntry(
                        name: key,
                        length: value.count,
                        fingerprint: Self.fingerprint(for: value)
                    )
                },
            removedKeys: parsed.removed.sorted(),
            profileName: parsed.profileName
        )
    }

    public func value(forKey key: String) -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? SafeFileReader.readData(at: url, maxBytes: Self.maxFileBytes) else { return nil }
        let parsed = Self.parse(String(decoding: data, as: UTF8.self))
        return parsed.values.first { $0.key == key }?.value
    }

    /// Runs `command` inside a fresh non-interactive zsh that first sources the activation file.
    /// The values are expanded inside that child process, so they never travel back through the caller.
    public func execute(
        command: String,
        requiredKeys: [String] = [],
        timeout: TimeInterval = 60,
        loginShell: Bool = false,
        environment: [String: String]? = nil
    ) async throws -> ActiveEnvironmentExecResult {
        try await run(
            script: command,
            arguments: [],
            requiredKeys: requiredKeys,
            timeout: timeout,
            loginShell: loginShell,
            environment: environment
        )
    }

    /// Runs `arguments` as a program with the activation file already sourced. Nothing is re-quoted, so the
    /// caller keeps full control over argument boundaries.
    public func execute(
        arguments: [String],
        requiredKeys: [String] = [],
        timeout: TimeInterval = 60,
        loginShell: Bool = false,
        environment: [String: String]? = nil
    ) async throws -> ActiveEnvironmentExecResult {
        guard !arguments.isEmpty else {
            throw EnvBoxError.processFailed("缺少要执行的命令")
        }
        return try await run(
            script: nil,
            arguments: arguments,
            requiredKeys: requiredKeys,
            timeout: timeout,
            loginShell: loginShell,
            environment: environment
        )
    }

    private func run(
        script: String?,
        arguments: [String],
        requiredKeys: [String],
        timeout: TimeInterval,
        loginShell: Bool,
        environment: [String: String]?
    ) async throws -> ActiveEnvironmentExecResult {
        let current = snapshot()
        guard current.isAvailable else {
            throw EnvBoxError.activeEnvironmentUnavailable("激活文件不存在，请先在 EnvBox 中应用配置并启用 Shell 集成")
        }
        if !requiredKeys.isEmpty {
            let present = Set(current.names)
            let missing = requiredKeys.filter { !present.contains($0) }
            if !missing.isEmpty {
                throw EnvBoxError.activeEnvironmentUnavailable("当前配置不包含变量 \(missing.joined(separator: "、"))")
            }
        }

        let path = ShellEscaping.singleQuoted(url.path)
        var body = "if [ ! -r \(path) ]; then\n"
        body += "  print -u2 'EnvBox: 激活文件不可读'\n"
        body += "  exit 90\n"
        body += "fi\n"
        body += "source \(path) || exit 91\n"
        if let generation = current.generation {
            body += "export ENVBOX_GENERATION=\(ShellEscaping.singleQuoted(generation))\n"
        }
        if let script {
            body += script
            if !script.hasSuffix("\n") { body += "\n" }
        } else {
            body += "exec \"$@\"\n"
        }

        var childEnvironment = environment ?? ProcessInfo.processInfo.environment
        if (childEnvironment["PATH"] ?? "").isEmpty {
            childEnvironment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        }
        childEnvironment["TERM"] = childEnvironment["TERM"] ?? "dumb"
        childEnvironment["PAGER"] = "cat"
        childEnvironment["GIT_PAGER"] = "cat"
        childEnvironment["ENVBOX_ACTIVE_FILE"] = url.path

        let shellArguments = (loginShell ? ["-l"] : ["-f"]) + ["-c", body, "envbox"] + arguments
        let result = try await GroupProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: shellArguments,
            environment: childEnvironment,
            timeout: min(max(0.5, timeout), Self.maximumTimeout),
            maxOutputBytes: Self.maxOutputBytes
        )

        return ActiveEnvironmentExecResult(
            generation: current.generation,
            exitCode: result.exitCode,
            signal: result.signal,
            stdout: result.stdout,
            stderr: result.stderr,
            timedOut: result.timedOut,
            outputTruncated: result.outputTruncated
        )
    }

    // MARK: - Parsing

    public struct Parsed: Sendable, Equatable {
        public var generation: String?
        public var appliedAt: String?
        public var profileName: String?
        public var values: [(key: String, value: String)]
        public var removed: [String]

        public static func == (lhs: Parsed, rhs: Parsed) -> Bool {
            lhs.generation == rhs.generation
                && lhs.appliedAt == rhs.appliedAt
                && lhs.profileName == rhs.profileName
                && lhs.removed == rhs.removed
                && lhs.values.map(\.key) == rhs.values.map(\.key)
                && lhs.values.map(\.value) == rhs.values.map(\.value)
        }
    }

    /// Parses the exact line forms EnvBox writes. Unknown lines are ignored so a hand-edited file still works.
    public static func parse(_ content: String) -> Parsed {
        var parsed = Parsed(generation: nil, appliedAt: nil, profileName: nil, values: [], removed: [])
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                if let value = markerValue(line, prefix: "# Generation:") {
                    parsed.generation = value
                } else if let value = markerValue(line, prefix: "# Updated:") {
                    parsed.appliedAt = value
                } else if let value = markerValue(line, prefix: "# Profile:") {
                    parsed.profileName = value
                }
                continue
            }
            if line.hasPrefix("unset ") {
                let key = String(line.dropFirst("unset ".count))
                if EnvBoxValidation.isValidKey(key) { parsed.removed.append(key) }
                continue
            }
            guard line.hasPrefix("export ") else { continue }
            let assignment = String(line.dropFirst("export ".count))
            guard let separator = assignment.firstIndex(of: "=") else { continue }
            let key = String(assignment[assignment.startIndex..<separator])
            let rawValue = String(assignment[assignment.index(after: separator)...])
            guard EnvBoxValidation.isValidKey(key),
                  let value = unescapeSingleQuoted(rawValue)
            else { continue }
            parsed.values.append((key: key, value: value))
        }
        return parsed
    }

    /// Reverses `ShellEscaping.singleQuoted`: `'a'\''b'` becomes `a'b`.
    public static func unescapeSingleQuoted(_ raw: String) -> String? {
        guard raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") else { return nil }
        let inner = raw.dropFirst().dropLast()
        var result = ""
        var index = inner.startIndex
        while index < inner.endIndex {
            let character = inner[index]
            if character == "'" {
                guard inner[index...].hasPrefix("'\\''") else { return nil }
                result.append("'")
                index = inner.index(index, offsetBy: 4)
                continue
            }
            result.append(character)
            index = inner.index(after: index)
        }
        return result
    }

    private static func markerValue(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Short, stable digest used to answer "did this value change?" without revealing it.
    public static func fingerprint(for value: String) -> String {
        let digest = SHA256.hash(data: Data("EnvBoxFingerprintV1\n\(value)".utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
