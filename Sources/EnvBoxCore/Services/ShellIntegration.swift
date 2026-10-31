import Foundation

public enum ShellIntegrationMarkers {
    public static let start = "# >>> EnvBox shell integration >>>"
    public static let end = "# <<< EnvBox shell integration <<<"
}

public struct ShellIntegrationStatus: Sendable, Equatable {
    public let isInstalled: Bool
    public let isSupported: Bool
    public let shellName: String
    public let rcURL: URL
    public let activationURL: URL
    public let hasActiveConfiguration: Bool

    public init(
        isInstalled: Bool,
        isSupported: Bool,
        shellName: String,
        rcURL: URL,
        activationURL: URL,
        hasActiveConfiguration: Bool
    ) {
        self.isInstalled = isInstalled
        self.isSupported = isSupported
        self.shellName = shellName
        self.rcURL = rcURL
        self.activationURL = activationURL
        self.hasActiveConfiguration = hasActiveConfiguration
    }
}

/// Owns the opt-in .zshrc hook and the plaintext activation script that a login shell can source.
public actor ShellIntegrationService {
    public nonisolated let homeDirectory: URL
    public nonisolated let rcURL: URL
    public nonisolated let activationDirectoryURL: URL
    public nonisolated let activationURL: URL
    private let shellPath: String
    private let fileManager: FileManager
    private let maxRCBytes = 2 * 1024 * 1024

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.rcURL = homeDirectory.appendingPathComponent(".zshrc", isDirectory: false)
        self.activationDirectoryURL = homeDirectory.appendingPathComponent(".envbox", isDirectory: true)
        self.activationURL = activationDirectoryURL.appendingPathComponent("active.zsh", isDirectory: false)
        self.shellPath = environment["SHELL"] ?? "/bin/zsh"
        self.fileManager = fileManager
    }

    public func status() -> ShellIntegrationStatus {
        let installed = (try? readRC())?.contains(ShellIntegrationMarkers.start) ?? false
        return ShellIntegrationStatus(
            isInstalled: installed,
            isSupported: isSupportedShell,
            shellName: (shellPath as NSString).lastPathComponent,
            rcURL: rcURL,
            activationURL: activationURL,
            hasActiveConfiguration: fileManager.fileExists(atPath: activationURL.path)
        )
    }

    public func install() throws {
        guard isSupportedShell else { throw EnvBoxError.shellIntegrationUnavailable }
        let target = resolvedWriteURL(for: rcURL)
        var content: String
        let stamp = fileStamp(at: target)
        if fileManager.fileExists(atPath: target.path) {
            content = try readRC(at: target)
        } else {
            content = ""
        }
        if Self.hasMalformedManagedBlock(in: content) {
            throw EnvBoxError.io("~/.zshrc 中的 EnvBox 标记不完整，已拒绝修改；请手动修复标记后重试。")
        }
        var lines = Self.removingManagedBlock(from: content)
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        if !lines.isEmpty { lines.append("") }
        lines.append(ShellIntegrationMarkers.start)
        lines.append("if [ -f \"$HOME/.envbox/active.zsh\" ]; then")
        lines.append("  source \"$HOME/.envbox/active.zsh\"")
        lines.append("fi")
        lines.append(ShellIntegrationMarkers.end)
        let updated = lines.joined(separator: "\n") + "\n"

        guard stamp == fileStamp(at: target) else {
            throw EnvBoxError.io("~/.zshrc 在读取后被其他程序修改，请重试。")
        }
        let permissions = filePermissions(at: target) ?? 0o600
        if fileManager.fileExists(atPath: target.path), updated != content {
            try backupRC(at: target)
        }
        try write(updated, to: target, permissions: permissions)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: activationDirectoryURL.path
        )
    }

    public func uninstall() throws {
        let target = resolvedWriteURL(for: rcURL)
        guard fileManager.fileExists(atPath: target.path) else { return }
        let stamp = fileStamp(at: target)
        let content = try readRC(at: target)
        if Self.hasMalformedManagedBlock(in: content) {
            throw EnvBoxError.io("~/.zshrc 中的 EnvBox 标记不完整，已拒绝修改；请手动修复标记后重试。")
        }
        let lines = Self.removingManagedBlock(from: content)
        var updated = lines.joined(separator: "\n")
        if !updated.isEmpty && !updated.hasSuffix("\n") { updated += "\n" }
        guard stamp == fileStamp(at: target) else {
            throw EnvBoxError.io("~/.zshrc 在读取后被其他程序修改，请重试。")
        }
        let permissions = filePermissions(at: target) ?? 0o600
        if updated != content {
            try backupRC(at: target)
        }
        try write(updated, to: target, permissions: permissions)
    }

    public func writeActivationScript(profile: EnvProfile, staleKeys: [String]) throws -> URL {
        let normalized = profile.normalized
        try EnvBoxValidation.validate(profile: normalized)
        try EnvBoxValidation.validateNoDuplicateKeys(normalized.enabledVariables)
        for key in staleKeys { try EnvBoxValidation.validateKey(key) }

        var lines: [String] = [
            "# Generated by EnvBox. Do not edit this file.",
            "# Generation: \(Self.makeGeneration())",
            "# Profile: \(Self.singleLine(normalized.name))",
            "# This file contains plaintext values because a shell must read them."
        ]

        let currentKeys = Set(normalized.enabledVariables.map { $0.trimmedKey })
        for key in Set(staleKeys).subtracting(currentKeys).sorted() {
            lines.append("unset \(key)")
        }
        for variable in normalized.enabledVariables.sorted(by: { $0.trimmedKey < $1.trimmedKey }) {
            lines.append(try ShellEscaping.exportLine(variable))
        }
        let content = lines.joined(separator: "\n") + "\n"

        try fileManager.createDirectory(
            at: activationDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: activationDirectoryURL.path
        )
        try write(content, to: activationURL, permissions: 0o600)
        return activationURL
    }

    public func removeActivationScript() throws {
        guard fileManager.fileExists(atPath: activationURL.path) else { return }
        do {
            try fileManager.removeItem(at: activationURL)
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }

    public nonisolated var isSupportedShell: Bool {
        (shellPath as NSString).lastPathComponent == "zsh"
    }

    public nonisolated static func hasMalformedManagedBlock(in content: String) -> Bool {
        var inside = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == ShellIntegrationMarkers.start {
                if inside { return true }
                inside = true
            } else if trimmed == ShellIntegrationMarkers.end {
                if !inside { return true }
                inside = false
            }
        }
        return inside
    }

    public nonisolated static func removingManagedBlock(from content: String) -> [String] {
        let allLines = content.components(separatedBy: .newlines)
        guard !hasMalformedManagedBlock(in: content) else { return allLines }

        var result: [String] = []
        var inside = false
        for line in allLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == ShellIntegrationMarkers.start {
                inside = true
                continue
            }
            if trimmed == ShellIntegrationMarkers.end {
                inside = false
                continue
            }
            if !inside { result.append(line) }
        }
        return result
    }

    private struct FileStamp: Equatable {
        let size: Int
        let modified: Date?
    }

    private func fileStamp(at url: URL) -> FileStamp? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return FileStamp(
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            modified: attributes[.modificationDate] as? Date
        )
    }

    private func backupRC(at url: URL) throws {
        let backupDirectory = activationDirectoryURL.appendingPathComponent("backups", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: backupDirectory.path
            )
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let name = "zshrc-\(timestamp)-\(UUID().uuidString.prefix(6)).bak"
            let destination = backupDirectory.appendingPathComponent(name)
            try fileManager.copyItem(at: url, to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

            let backups = (try? fileManager.contentsOfDirectory(atPath: backupDirectory.path))?
                .filter { $0.hasPrefix("zshrc-") && $0.hasSuffix(".bak") }
                .sorted() ?? []
            for old in backups.dropLast(5) {
                try? fileManager.removeItem(at: backupDirectory.appendingPathComponent(old))
            }
        } catch {
            throw EnvBoxError.io("无法备份 ~/.zshrc：\(error.localizedDescription)")
        }
    }

    private func filePermissions(at url: URL) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    private func resolvedWriteURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        return url.resolvingSymlinksInPath()
    }

    private func readRC(at url: URL? = nil) throws -> String {
        let target = url ?? resolvedWriteURL(for: rcURL)
        do {
            let attributes = try fileManager.attributesOfItem(atPath: target.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > maxRCBytes {
                throw EnvBoxError.fileTooLarge
            }
            let data = try SafeFileReader.readData(at: target, maxBytes: maxRCBytes)
            return String(decoding: data, as: UTF8.self)
        } catch let error as EnvBoxError {
            throw error
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }

    private func write(_ content: String, to url: URL, permissions: Int) throws {
        do {
            let data = Data(content.utf8)
            if data.count > maxRCBytes { throw EnvBoxError.fileTooLarge }
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        } catch let error as EnvBoxError {
            throw error
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }

    /// Monotonic, collision-resistant marker: two applies inside the same millisecond must not look identical to
    /// consumers that compare generations to decide whether their view is stale.
    private static func makeGeneration() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return "\(stamp)-\(suffix)"
    }

    private static func singleLine(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                return " "
            }
            return String(scalar)
        }.joined()
        return String(cleaned.prefix(80))
    }
}
