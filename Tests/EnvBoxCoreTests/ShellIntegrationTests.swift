import Foundation
import Testing
@testable import EnvBoxCore

@Suite("Shell integration")
struct ShellIntegrationTests {
    @Test func installAndUninstallAreIdempotentAndPreserveContent() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let rc = home.appendingPathComponent(".zshrc")
        try "# my zshrc\nalias ll='ls -la'\n".write(to: rc, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: rc.path)

        let service = ShellIntegrationService(homeDirectory: home, environment: ["SHELL": "/bin/zsh"])
        try await service.install()
        try await service.install()
        let status = await service.status()
        #expect(status.isInstalled)

        let content = try String(contentsOf: rc, encoding: .utf8)
        #expect(content.components(separatedBy: ShellIntegrationMarkers.start).count - 1 == 1)
        #expect(content.contains("alias ll='ls -la'"))
        let permissions = try FileManager.default.attributesOfItem(atPath: rc.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o644)

        let backupDirectory = home.appendingPathComponent(".envbox/backups")
        let backups = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
        #expect(!backups.filter { $0.hasSuffix(".bak") }.isEmpty)
        let backupContent = try String(
            contentsOf: backupDirectory.appendingPathComponent(backups.filter { $0.hasSuffix(".bak") }.sorted()[0]),
            encoding: .utf8
        )
        #expect(backupContent.contains("alias ll='ls -la'"))

        try await service.uninstall()
        let uninstalled = try String(contentsOf: rc, encoding: .utf8)
        #expect(!uninstalled.contains(ShellIntegrationMarkers.start))
        #expect(uninstalled.contains("alias ll='ls -la'"))
    }

    @Test func malformedManagedBlockIsRejectedWithoutLosingContent() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let rc = home.appendingPathComponent(".zshrc")
        let original = "# user content\n\(ShellIntegrationMarkers.start)\n# missing end marker\nexport KEEP=1\n"
        try original.write(to: rc, atomically: true, encoding: .utf8)

        let service = ShellIntegrationService(homeDirectory: home, environment: ["SHELL": "/bin/zsh"])
        do {
            try await service.install()
            Issue.record("Expected malformed marker failure")
        } catch {
            #expect((error as? EnvBoxError) != nil)
        }
        let preserved = try String(contentsOf: rc, encoding: .utf8)
        #expect(preserved == original)
    }

    @Test func activationScriptEscapesValuesAndClearsStaleKeys() async throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let service = ShellIntegrationService(homeDirectory: home, environment: ["SHELL": "/bin/zsh"])
        let profile = sampleProfile()
        let url = try await service.writeActivationScript(profile: profile, staleKeys: ["REMOVED"])
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("unset REMOVED"))
        #expect(content.contains("export API_TOKEN='secret'\\''with $pecial"))
        #expect(!content.contains("DISABLED_FLAG"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}
