import Foundation
import Testing
@testable import EnvBoxCore

@Suite("MCP tools")
struct MCPToolTests {
    private func makeHandlers(
        contents: String,
        enabled: Bool = true,
        allowReveal: Bool = false
    ) throws -> (MCPToolHandlers, URL) {
        let home = try makeTemporaryDirectory()
        let directory = home.appendingPathComponent(".envbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("active.zsh")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        let store = ActiveEnvironmentStore(url: url)
        let handlers = MCPToolHandlers(store: store, policy: MCPPolicy(enabled: enabled, allowReveal: allowReveal))
        return (handlers, home)
    }

    @Test func disabledPolicyBlocksEveryTool() async throws {
        let (handlers, home) = try makeHandlers(contents: "# Generation: g\nexport A='1'\n", enabled: false)
        defer { try? FileManager.default.removeItem(at: home) }
        for name in MCPToolHandlers.toolNames {
            let response = await handlers.call(name: name, arguments: ["key": "A", "command": "true"])
            #expect(response.isError)
        }
    }

    @Test func describeReturnsMetadataWithoutPlaintext() async throws {
        let (handlers, home) = try makeHandlers(contents: "# Generation: g1\nexport BAIDU_COOKIES='0123456789'\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let response = await handlers.call(name: "env_describe", arguments: [:])
        #expect(!response.isError)
        #expect(response.text.contains("BAIDU_COOKIES"))
        #expect(response.text.contains("\"length\" : 10") || response.text.contains("\"length\":10"))
        #expect(!response.text.contains("0123456789"))
        #expect(response.text.contains("g1"))
    }

    @Test func describeReportsMissingKeys() async throws {
        let (handlers, home) = try makeHandlers(contents: "# Generation: g2\nexport PRESENT='1'\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let response = await handlers.call(name: "env_describe", arguments: ["keys": ["PRESENT", "GONE"]])
        #expect(response.text.contains("PRESENT"))
        #expect(response.text.contains("GONE"))
    }

    @Test func execReturnsOnlyCommandOutput() async throws {
        let (handlers, home) = try makeHandlers(contents: "# Generation: g3\nexport DEMO_TOKEN='abc123'\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let response = await handlers.call(
            name: "env_exec",
            arguments: ["command": "printf '%s' \"$DEMO_TOKEN\"", "requiredKeys": ["DEMO_TOKEN"]]
        )
        #expect(!response.isError)
        #expect(response.text.contains("\"stdout\" : \"abc123\"") || response.text.contains("\"stdout\":\"abc123\""))
        #expect(response.text.contains("g3"))
    }

    @Test func execFailsForRemovedKey() async throws {
        let (handlers, home) = try makeHandlers(contents: "# Generation: g4\nexport PRESENT='1'\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let response = await handlers.call(
            name: "env_exec",
            arguments: ["command": "true", "requiredKeys": ["REMOVED_KEY"]]
        )
        #expect(response.isError)
    }

    @Test func revealIsDeniedByDefaultAndAllowedWhenEnabled() async throws {
        let (denied, homeA) = try makeHandlers(contents: "# Generation: g5\nexport TOKEN='secret'\n")
        defer { try? FileManager.default.removeItem(at: homeA) }
        let deniedResponse = await denied.call(name: "env_reveal", arguments: ["key": "TOKEN"])
        #expect(deniedResponse.isError)
        #expect(!deniedResponse.text.contains("secret"))

        let (allowed, homeB) = try makeHandlers(
            contents: "# Generation: g6\nexport TOKEN='secret'\n",
            allowReveal: true
        )
        defer { try? FileManager.default.removeItem(at: homeB) }
        let allowedResponse = await allowed.call(name: "env_reveal", arguments: ["key": "TOKEN"])
        #expect(!allowedResponse.isError)
        #expect(allowedResponse.text.contains("secret"))
    }

    @Test func policyRoundTripsOnDisk() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appendingPathComponent("mcp.json")
        try MCPPolicy(enabled: true, allowReveal: false).write(to: url)
        #expect(MCPPolicy.load(from: url) == MCPPolicy(enabled: true, allowReveal: false))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #expect(MCPPolicy.load(from: home.appendingPathComponent("absent.json")) == MCPPolicy())
    }
}
