import Testing
@testable import EnvBoxCore

@Suite("Shell escaping")
struct ShellEscapingTests {
    @Test func singleQuoteEscaping() {
        #expect(ShellEscaping.singleQuoted("plain") == "'plain'")
        #expect(ShellEscaping.singleQuoted("a'b") == "'a'\\''b'")
        #expect(ShellEscaping.singleQuoted("$HOME $(id)") == "'$HOME $(id)'")
        #expect(ShellEscaping.singleQuoted("line1\nline2") == "'line1\nline2'")
    }

    @Test func exportLine() throws {
        let variable = EnvVariable(key: "TOKEN", value: "a'b")
        #expect(try ShellEscaping.exportLine(variable) == "export TOKEN='a'\\''b'")
    }

    @Test func invalidKeyRejected() {
        #expect(throws: (any Error).self) {
            _ = try ShellEscaping.exportLine(EnvVariable(key: "BAD KEY", value: "x"))
        }
    }

    @Test func launchctlScript() throws {
        let script = try ProfileActivationService.makeLaunchctlScript(
            enabled: [EnvVariable(key: "A", value: "1")],
            staleKeys: ["OLD"]
        )
        #expect(script.contains("/bin/launchctl unsetenv OLD"))
        #expect(script.contains("/bin/launchctl setenv A '1'"))
        #expect(script.hasPrefix("#!/bin/sh"))
    }
}
