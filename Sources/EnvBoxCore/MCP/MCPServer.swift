import Foundation

/// Minimal MCP server over stdio: newline-delimited JSON-RPC 2.0 on stdin/stdout.
///
/// Values are never written to stderr and never travel back through the protocol unless a tool explicitly
/// returns them, so a session log stays free of secrets.
public enum MCPServer {
    public static let protocolVersion = "2025-06-18"

    public static func run(
        store: ActiveEnvironmentStore = ActiveEnvironmentStore(),
        policy: MCPPolicy = MCPPolicy.load(),
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        errorLog: FileHandle = .standardError
    ) {
        let handlers = MCPToolHandlers(store: store, policyProvider: { policy })

        // Keep the startup read for logging-free fail-fast behaviour; tool calls re-read the file themselves.
        var buffer = Data()

        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard !line.isEmpty else { continue }
                if let response = handle(line: Data(line), handlers: handlers, errorLog: errorLog) {
                    write(response, to: output)
                }
            }
        }
    }

    private static func handle(line: Data, handlers: MCPToolHandlers, errorLog: FileHandle) -> [String: Any]? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let method = object["method"] as? String
        else {
            return errorResponse(id: nil, code: -32700, message: "Parse error")
        }
        let id = object["id"]
        let params = object["params"] as? [String: Any] ?? [:]

        if method.hasPrefix("notifications/") {
            return nil
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? protocolVersion
            return result(id: id, payload: [
                "protocolVersion": requested,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "envbox", "version": EnvBoxVersion.current]
            ])
        case "ping":
            return result(id: id, payload: [:])
        case "tools/list":
            return result(id: id, payload: ["tools": MCPToolHandlers.descriptors()])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return errorResponse(id: id, code: -32602, message: "Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let semaphore = DispatchSemaphore(value: 0)
            let box = ResponseBox()
            Task {
                let response = await handlers.call(name: name, arguments: arguments)
                box.set(response)
                semaphore.signal()
            }
            semaphore.wait()
            guard let response = box.get() else {
                return errorResponse(id: id, code: -32603, message: "Tool failed")
            }
            return result(id: id, payload: [
                "content": [["type": "text", "text": response.text]],
                "isError": response.isError
            ])
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private static func result(id: Any?, payload: [String: Any]) -> [String: Any] {
        var response: [String: Any] = ["jsonrpc": "2.0", "result": payload]
        if let id { response["id"] = id }
        return response
    }

    private static func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message]
        ]
        if let id { response["id"] = id }
        return response
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: []),
            var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"
        handle.write(Data(line.utf8))
    }
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MCPToolResponse?

    func set(_ response: MCPToolResponse) {
        lock.lock()
        value = response
        lock.unlock()
    }

    func get() -> MCPToolResponse? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public enum EnvBoxVersion {
    /// Bundle version of the running executable, falling back to a literal for the CLI helper.
    public static var current: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.2.0"
    }
}
