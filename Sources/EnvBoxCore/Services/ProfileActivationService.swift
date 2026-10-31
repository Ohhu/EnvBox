import Foundation

public struct ActivationReport: Sendable {
    public let appliedKeys: [String]
    public let staleKeys: [String]
    public let activationScriptURL: URL?
    public let warnings: [String]

    public init(appliedKeys: [String], staleKeys: [String], activationScriptURL: URL?, warnings: [String]) {
        self.appliedKeys = appliedKeys
        self.staleKeys = staleKeys
        self.activationScriptURL = activationScriptURL
        self.warnings = warnings
    }
}

/// Applies a profile to the current user's launchd domain and writes the shell activation file.
public actor ProfileActivationService {
    private let launchctlURL: URL
    private let shellIntegration: ShellIntegrationService

    public init(
        launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl"),
        shellIntegration: ShellIntegrationService
    ) {
        self.launchctlURL = launchctlURL
        self.shellIntegration = shellIntegration
    }

    public func activate(
        profile: EnvProfile,
        previousAppliedKeys: [String],
        writeShellActivation: Bool = true
    ) async throws -> ActivationReport {
        let normalized = profile.normalized
        try EnvBoxValidation.validate(profile: normalized)
        try EnvBoxValidation.validateNoDuplicateKeys(normalized.enabledVariables)
        for key in previousAppliedKeys { try EnvBoxValidation.validateKey(key) }

        let enabled = normalized.enabledVariables.sorted { $0.trimmedKey < $1.trimmedKey }
        let enabledKeys = enabled.map { $0.trimmedKey }
        let enabledSet = Set(enabledKeys)
        let staleKeys = Array(Set(previousAppliedKeys).subtracting(enabledSet)).sorted()
        let script = try Self.makeLaunchctlScript(enabled: enabled, staleKeys: staleKeys)

        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-s"],
            input: Data(script.utf8),
            timeout: 60
        )

        if result.timedOut {
            await Self.bestEffortCleanup(keys: enabledKeys)
            throw EnvBoxError.activationFailed("系统环境写入超时，已尝试回收本次写入")
        }
        if result.status != 0 {
            let message = String(decoding: result.stderr.prefix(400), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await Self.bestEffortCleanup(keys: enabledKeys)
            throw EnvBoxError.activationFailed(message.isEmpty ? "launchctl 返回状态码 \(result.status)，已尝试回收本次写入" : message)
        }

        var warnings: [String] = []
        var scriptURL: URL?
        if writeShellActivation {
            do {
                scriptURL = try await shellIntegration.writeActivationScript(profile: normalized, staleKeys: staleKeys)
            } catch {
                warnings.append("系统环境已应用，但 Shell 激活文件写入失败：\(error.localizedDescription)")
            }
        }

        return ActivationReport(
            appliedKeys: enabledKeys,
            staleKeys: staleKeys,
            activationScriptURL: scriptURL,
            warnings: warnings
        )
    }

    public func deactivate(keys: [String]) async throws {
        for key in keys { try EnvBoxValidation.validateKey(key) }
        if !keys.isEmpty {
            let script = try Self.makeLaunchctlScript(enabled: [], staleKeys: keys)
            let result = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-s"],
                input: Data(script.utf8),
                timeout: 30
            )
            if result.timedOut { throw EnvBoxError.activationFailed("系统环境清理超时") }
            if result.status != 0 {
                let message = String(decoding: result.stderr.prefix(400), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw EnvBoxError.activationFailed(message.isEmpty ? "launchctl 清理失败" : message)
            }
        }
        try await shellIntegration.removeActivationScript()
    }

    private static func bestEffortCleanup(keys: [String]) async {
        let unique = Array(Set(keys)).sorted()
        guard !unique.isEmpty else { return }
        guard let script = try? makeLaunchctlScript(enabled: [], staleKeys: unique) else { return }
        _ = try? await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-s"],
            input: Data(script.utf8),
            timeout: 30
        )
    }

    public static func makeLaunchctlScript(enabled: [EnvVariable], staleKeys: [String]) throws -> String {
        var lines = ["#!/bin/sh", "set -e"]
        for key in staleKeys {
            lines.append(try ShellEscaping.launchctlUnsetenvLine(key: key))
        }
        for variable in enabled {
            lines.append(try ShellEscaping.launchctlSetenvLine(variable))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
