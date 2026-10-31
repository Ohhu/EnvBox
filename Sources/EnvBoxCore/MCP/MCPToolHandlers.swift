import Foundation

public struct MCPToolResponse: Sendable, Equatable {
    public let isError: Bool
    public let text: String

    public init(isError: Bool, text: String) {
        self.isError = isError
        self.text = text
    }

    static func json(_ object: [String: Any], isError: Bool = false) -> MCPToolResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return MCPToolResponse(isError: isError, text: String(decoding: data, as: UTF8.self))
    }

    static func failure(_ reason: String) -> MCPToolResponse {
        json(["error": reason], isError: true)
    }
}

/// Tool surface shared by the MCP server and the CLI so both behave identically.
public struct MCPToolHandlers: Sendable {
    public static let toolNames = ["env_describe", "env_exec", "env_reveal"]

    private let store: ActiveEnvironmentStore
    private let policyProvider: @Sendable () -> MCPPolicy

    /// The policy is re-read for every call so disabling MCP in the app takes effect immediately.
    public init(
        store: ActiveEnvironmentStore = ActiveEnvironmentStore(),
        policyProvider: @escaping @Sendable () -> MCPPolicy = { MCPPolicy.load() }
    ) {
        self.store = store
        self.policyProvider = policyProvider
    }

    public init(store: ActiveEnvironmentStore, policy: MCPPolicy) {
        self.init(store: store, policyProvider: { policy })
    }

    public func call(name: String, arguments: [String: Any]) async -> MCPToolResponse {
        let policy = policyProvider()
        guard policy.enabled else {
            return .failure("MCP 已在 EnvBox 设置中关闭")
        }
        switch name {
        case "env_describe":
            return describe(arguments)
        case "env_exec":
            return await execute(arguments)
        case "env_reveal":
            return reveal(arguments, policy: policy)
        default:
            return .failure("未知工具：\(name)")
        }
    }

    // MARK: - Tools

    private func describe(_ arguments: [String: Any]) -> MCPToolResponse {
        let snapshot = store.snapshot()
        guard snapshot.isAvailable else {
            return .json(["available": false, "reason": "shell_integration_disabled"])
        }

        let requested = (arguments["keys"] as? [Any])?
            .compactMap { $0 as? String }
            .filter { !$0.isEmpty }
        var payload: [String: Any] = [
            "available": true,
            "generation": snapshot.generation ?? "",
            "count": snapshot.entries.count
        ]
        if let profileName = snapshot.profileName {
            payload["profile"] = profileName
        }

        if let requested, !requested.isEmpty {
            var found: [[String: Any]] = []
            var missing: [String] = []
            for key in requested {
                if let entry = snapshot.entry(named: key) {
                    found.append(["name": entry.name, "length": entry.length, "fingerprint": entry.fingerprint])
                } else {
                    missing.append(key)
                }
            }
            payload["vars"] = found
            payload["missing"] = missing
        } else {
            payload["vars"] = snapshot.entries.map {
                ["name": $0.name, "length": $0.length, "fingerprint": $0.fingerprint]
            }
            payload["removed"] = snapshot.removedKeys
        }
        return .json(payload)
    }

    private func execute(_ arguments: [String: Any]) async -> MCPToolResponse {
        guard let command = arguments["command"] as? String, !command.isEmpty else {
            return .failure("缺少 command")
        }
        let requiredKeys = (arguments["requiredKeys"] as? [Any])?.compactMap { $0 as? String } ?? []
        let timeout = (arguments["timeoutSeconds"] as? NSNumber)?.doubleValue ?? 60
        let loginShell = (arguments["login"] as? Bool) ?? false

        do {
            let result = try await store.execute(
                command: command,
                requiredKeys: requiredKeys,
                timeout: timeout,
                loginShell: loginShell
            )
            var payload: [String: Any] = [
                "generation": result.generation ?? "",
                "exit": Int(result.exitCode),
                "stdout": String(decoding: result.stdout, as: UTF8.self),
                "stderr": String(decoding: result.stderr, as: UTF8.self),
                "truncated": result.outputTruncated,
                "timedOut": result.timedOut
            ]
            if let signal = result.signal { payload["signal"] = Int(signal) }
            return .json(payload, isError: result.exitCode != 0 || result.timedOut)
        } catch let error as EnvBoxError {
            return .failure(error.errorDescription ?? "执行失败")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func reveal(_ arguments: [String: Any], policy: MCPPolicy) -> MCPToolResponse {
        guard policy.allowReveal else {
            return .failure("env_reveal 未启用")
        }
        guard let key = arguments["key"] as? String, !key.isEmpty else {
            return .failure("缺少 key")
        }
        let snapshot = store.snapshot()
        guard snapshot.isAvailable else {
            return .json(["available": false, "reason": "shell_integration_disabled"])
        }
        guard snapshot.entry(named: key) != nil, let value = store.value(forKey: key) else {
            return .json(["available": true, "key": key, "missing": true])
        }
        return .json(["available": true, "key": key, "value": value, "generation": snapshot.generation ?? ""])
    }

    // MARK: - Descriptors

    /// Tool descriptors used by `tools/list`.
    public static func descriptors() -> [[String: Any]] {
        [
            [
                "name": "env_describe",
                "description": "返回变量名、值长度与指纹，不含明文。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "keys": ["type": "array", "items": ["type": "string"]]
                    ]
                ]
            ],
            [
                "name": "env_exec",
                "description": "用最新配置的环境执行命令，返回退出码、stdout、stderr 和配置版本。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string"],
                        "requiredKeys": ["type": "array", "items": ["type": "string"]],
                        "timeoutSeconds": ["type": "number"],
                        "login": ["type": "boolean"]
                    ],
                    "required": ["command"]
                ]
            ],
            [
                "name": "env_reveal",
                "description": "返回指定变量的明文，需先在 EnvBox 中启用。",
                "inputSchema": [
                    "type": "object",
                    "properties": ["key": ["type": "string"]],
                    "required": ["key"]
                ]
            ]
        ]
    }
}
