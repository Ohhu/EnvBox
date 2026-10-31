import Foundation
import Testing
@testable import EnvBoxCore

@Suite("Process runner")
struct ProcessRunnerTests {
    @Test func capturesOutputAndStatus() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'ok'; printf 'err' >&2"],
            timeout: 2
        )
        #expect(result.status == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "ok")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "err")
        #expect(!result.timedOut)
    }

    @Test func timeoutTerminatesLongRunningProcess() async throws {
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 10"],
            timeout: 0.2
        )
        #expect(result.timedOut)
        #expect(result.status != 0)
    }
}
