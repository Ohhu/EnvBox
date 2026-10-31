import Foundation

public protocol SystemEnvironmentReading: Sendable {
    func capture(includeLoginShell: Bool) async -> EnvironmentSnapshot
}

/// Captures the app's environment plus a login Zsh environment. Shell startup is sandboxed by a timeout
/// and all parsing happens off the main actor.
public struct ShellEnvironmentReader: SystemEnvironmentReading {
    private let shellURL: URL
    private let timeout: TimeInterval

    public init(shellURL: URL? = nil, timeout: TimeInterval = 5) {
        self.shellURL = shellURL ?? Self.defaultShellURL()
        self.timeout = timeout
    }

    private static func defaultShellURL() -> URL {
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            let name = (shell as NSString).lastPathComponent
            if name == "zsh" || name == "bash" {
                return URL(fileURLWithPath: shell)
            }
        }
        return URL(fileURLWithPath: "/bin/zsh")
    }

    private static let beginMarker = Data([0]) + Data("__ENVBOX_BEGIN__".utf8) + Data([0])
    private static let endMarker = Data([0]) + Data("__ENVBOX_END__".utf8) + Data([0])
    private static let command = "printf '\\000__ENVBOX_BEGIN__\\000'; command /usr/bin/env -0; printf '\\000__ENVBOX_END__\\000'"

    public func capture(includeLoginShell: Bool) async -> EnvironmentSnapshot {
        let started = Date()
        var merged = ProcessInfo.processInfo.environment
        var source: EnvironmentCaptureSource = .processOnly
        var warning: String?

        if includeLoginShell {
            do {
                let result = try await ProcessRunner.run(
                    executable: shellURL,
                    arguments: ["-ilc", Self.command],
                    timeout: timeout
                )
                if result.timedOut {
                    source = .fallback
                    warning = "登录 Shell 响应超时，已回退到应用进程环境。"
                } else if result.status == 0 {
                    let parsed = Self.parse(result.stdout)
                    if parsed.isEmpty {
                        source = .fallback
                        warning = "登录 Shell 未返回可用变量，已回退到应用进程环境。"
                    } else {
                        for (key, value) in parsed {
                            merged[key] = value
                        }
                        source = .loginShell
                    }
                } else {
                    source = .fallback
                    warning = "登录 Shell 返回错误（状态码 \(result.status)），已回退到应用进程环境。"
                }
            } catch {
                source = .fallback
                warning = "无法读取登录 Shell 环境：\(error.localizedDescription)"
            }
        }

        var variables: [SystemVariable] = []
        variables.reserveCapacity(merged.count)
        for (key, value) in merged {
            guard EnvBoxValidation.isValidKey(key) else { continue }
            guard !key.hasPrefix("__ENVBOX_") else { continue }
            variables.append(SystemVariable(key: key, value: value))
        }
        variables.sort {
            let result = $0.key.localizedStandardCompare($1.key)
            return result == .orderedSame ? $0.key < $1.key : result == .orderedAscending
        }

        return EnvironmentSnapshot(
            variables: variables,
            source: source,
            capturedAt: Date(),
            duration: Date().timeIntervalSince(started),
            warning: warning,
            shellName: shellURL.lastPathComponent
        )
    }

    /// Parses NUL-delimited env output, using markers to ignore noisy interactive shell startup output.
    static func parse(_ data: Data) -> [String: String] {
        let payload: Data
        if let begin = data.range(of: Self.beginMarker),
           let end = data.range(of: Self.endMarker, in: begin.upperBound..<data.endIndex) {
            payload = data.subdata(in: begin.upperBound..<end.lowerBound)
        } else {
            payload = data
        }

        var result: [String: String] = [:]
        for field in payload.split(separator: 0, omittingEmptySubsequences: true) {
            guard let separator = field.firstIndex(of: 61) else { continue } // '='
            let keyData = field[field.startIndex..<separator]
            let valueData = field[field.index(after: separator)..<field.endIndex]
            guard let key = String(data: keyData, encoding: .utf8) else { continue }
            guard EnvBoxValidation.isValidKey(key) else { continue }
            result[key] = String(decoding: valueData, as: UTF8.self)
        }
        return result
    }
}
