import Foundation

/// On-disk switch for the MCP helper. The app owns this file; the helper only reads it.
public struct MCPPolicy: Sendable, Equatable {
    public var enabled: Bool
    public var allowReveal: Bool

    public init(enabled: Bool = false, allowReveal: Bool = false) {
        self.enabled = enabled
        self.allowReveal = allowReveal
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".envbox", isDirectory: true)
            .appendingPathComponent("mcp.json", isDirectory: false)
    }

    public static func load(from url: URL = MCPPolicy.defaultURL) -> MCPPolicy {
        guard let data = try? SafeFileReader.readData(at: url, maxBytes: 64 * 1024) else {
            return MCPPolicy()
        }
        struct Stored: Decodable {
            var enabled: Bool?
            var allowReveal: Bool?
        }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return MCPPolicy()
        }
        return MCPPolicy(enabled: stored.enabled ?? false, allowReveal: stored.allowReveal ?? false)
    }

    public func write(to url: URL = MCPPolicy.defaultURL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            struct Stored: Encodable {
                let enabled: Bool
                let allowReveal: Bool
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Stored(enabled: enabled, allowReveal: allowReveal))
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }
}

/// The path a client should spawn. Prefers the copy inside the running app bundle.
public enum MCPHelper {
    public static func executablePath(bundle: Bundle = .main) -> String {
        let bundled = bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("envbox", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return "/Applications/EnvBox.app/Contents/Helpers/envbox"
    }
}

/// Client-specific wiring shown in Settings. Snippets are meant to be pasted verbatim.
public enum MCPClient: String, CaseIterable, Identifiable, Sendable {
    case generic
    case claudeCode
    case dsh

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .generic: return "通用 JSON"
        case .claudeCode: return "Claude Code"
        case .dsh: return "DSH"
        }
    }

    /// Describes what the copy button will actually put on the pasteboard.
    public var snippetLabel: String {
        switch self {
        case .generic: return "复制 JSON"
        case .claudeCode: return "复制命令"
        case .dsh: return "复制 YAML"
        }
    }

    public func snippet(helperPath: String) -> String {
        switch self {
        case .generic:
            return """
            {
              "mcpServers": {
                "envbox": {
                  "command": "\(helperPath)",
                  "args": ["mcp"]
                }
              }
            }
            """
        case .claudeCode:
            return "claude mcp add envbox -- \"\(helperPath)\" mcp"
        case .dsh:
            return """
            - insert:
                - id: envbox-mcp
                  name: '@deepseek-ai/dsh-mcp-client'
                  config:
                    serverName: envbox
                    transport: stdio
                    command: \(helperPath)
                    args: [mcp]
            """
        }
    }

    public func prompt(helperPath: String) -> String {
        let target: String
        switch self {
        case .generic: target = "你当前的 MCP 配置"
        case .claudeCode: target = "Claude Code 的 MCP 配置"
        case .dsh: target = "~/.dsh/cordis.patch.yml"
        }
        return """
        将以下 MCP 服务器加入\(target)，并调用 env_describe 验证。

        \(snippet(helperPath: helperPath))
        """
    }
}
