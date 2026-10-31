import EnvBoxCore
import Foundation

@main
struct EnvBoxCLI {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            exit(2)
        }
        arguments.removeFirst()

        switch command {
        case "mcp":
            MCPServer.run()
        case "describe":
            describe(arguments)
        case "exec":
            await exec(arguments)
        case "reveal-policy":
            revealPolicy(arguments)
        case "version", "--version":
            print(EnvBoxVersion.current)
        case "help", "--help", "-h":
            printUsage()
        default:
            FileHandle.standardError.write(Data("未知命令：\(command)\n".utf8))
            printUsage()
            exit(2)
        }
    }

    // MARK: - Commands

    private static func describe(_ arguments: [String]) {
        let store = ActiveEnvironmentStore()
        let snapshot = store.snapshot()
        guard snapshot.isAvailable else {
            print("{\"available\":false}")
            exit(1)
        }
        let keys = arguments.filter { !$0.hasPrefix("-") }
        let entries = keys.isEmpty
            ? snapshot.entries
            : keys.compactMap { store.snapshot().entry(named: $0) }
        var payload: [[String: Any]] = entries.map {
            ["name": $0.name, "length": $0.length, "fingerprint": $0.fingerprint]
        }
        if !keys.isEmpty {
            let missing = keys.filter { snapshot.entry(named: $0) == nil }
            if !missing.isEmpty { payload.append(["missing": missing]) }
        }
        let object: [String: Any] = [
            "generation": snapshot.generation ?? "",
            "count": entries.count,
            "vars": payload
        ]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    private static func exec(_ arguments: [String]) async {
        var commandArguments: [String] = []
        var requiredKeys: [String] = []
        var timeout: Double = 60
        var login = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--":
                commandArguments = Array(arguments[(index + 1)...])
                index = arguments.count
            case "--required-key":
                if index + 1 < arguments.count { requiredKeys.append(arguments[index + 1]) }
                index += 2
            case "--timeout":
                if index + 1 < arguments.count { timeout = Double(arguments[index + 1]) ?? timeout }
                index += 2
            case "--login":
                login = true
                index += 1
            default:
                commandArguments.append(argument)
                index += 1
            }
        }
        guard !commandArguments.isEmpty else {
            FileHandle.standardError.write(Data("缺少要执行的命令\n".utf8))
            exit(2)
        }

        do {
            let result = try await ActiveEnvironmentStore().execute(
                arguments: commandArguments,
                requiredKeys: requiredKeys,
                timeout: timeout,
                loginShell: login
            )
            FileHandle.standardOutput.write(result.stdout)
            FileHandle.standardError.write(result.stderr)
            exit(result.exitCode == 0 ? 0 : (result.exitCode > 0 ? result.exitCode : 1))
        } catch let error as EnvBoxError {
            FileHandle.standardError.write(Data(((error.errorDescription ?? "执行失败") + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func revealPolicy(_ arguments: [String]) {
        var policy = MCPPolicy.load()
        let flag = arguments.first ?? "--status"
        switch flag {
        case "--allow":
            policy.allowReveal = true
            writePolicy(policy)
            print("env_reveal 已启用")
        case "--deny":
            policy.allowReveal = false
            writePolicy(policy)
            print("env_reveal 已关闭")
        case "--enable-mcp":
            policy.enabled = true
            writePolicy(policy)
            print("MCP 已启用")
        case "--disable-mcp":
            policy.enabled = false
            writePolicy(policy)
            print("MCP 已关闭")
        default:
            print("enabled=\(policy.enabled) allowReveal=\(policy.allowReveal)")
        }
    }

    private static func writePolicy(_ policy: MCPPolicy) {
        do {
            try policy.write()
        } catch let error as EnvBoxError {
            FileHandle.standardError.write(Data(((error.errorDescription ?? "写入失败") + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func printUsage() {
        let usage = """
        envbox — EnvBox 命令行助手

        envbox mcp                     以 MCP 服务器方式运行（stdio）
        envbox describe [KEY...]       列出变量名、长度、指纹与代际
        envbox exec [--] <命令>        在最新配置环境中执行命令
               --required-key KEY      执行前校验变量存在
               --timeout 秒            超时时间，默认 60
               --login                 使用登录 Shell
        envbox reveal-policy [--allow|--deny|--status]
        envbox version
        """
        print(usage)
    }
}
