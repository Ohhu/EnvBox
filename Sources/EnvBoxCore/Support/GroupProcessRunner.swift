import Darwin
import Foundation

public struct GroupProcessResult: Sendable {
    public let exitCode: Int32
    public let signal: Int32?
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool
    public let outputTruncated: Bool

    public init(
        exitCode: Int32,
        signal: Int32?,
        stdout: Data,
        stderr: Data,
        timedOut: Bool,
        outputTruncated: Bool
    ) {
        self.exitCode = exitCode
        self.signal = signal
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.outputTruncated = outputTruncated
    }
}

/// Runs a command that may spawn children (a shell running an arbitrary command line) with a hard output cap
/// and a deadline that terminates the whole process tree instead of leaving orphans behind.
public enum GroupProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 60,
        maxOutputBytes: Int = 256 * 1024,
        currentDirectory: URL? = nil
    ) async throws -> GroupProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try runBlocking(
                        executable: executable,
                        arguments: arguments,
                        environment: environment,
                        timeout: timeout,
                        maxOutputBytes: maxOutputBytes,
                        currentDirectory: currentDirectory
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval,
        maxOutputBytes: Int,
        currentDirectory: URL?
    ) throws -> GroupProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBox = CappedBuffer(maxBytes: maxOutputBytes)
        let stderrBox = CappedBuffer(maxBytes: maxOutputBytes)
        let drained = DispatchGroup()

        func drain(_ handle: FileHandle, into box: CappedBuffer) {
            drained.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let chunk = try? handle.read(upToCount: 64 * 1024)
                    guard let chunk, !chunk.isEmpty else { break }
                    box.append(chunk)
                }
                drained.leave()
            }
        }

        drain(stdoutPipe.fileHandleForReading, into: stdoutBox)
        drain(stderrPipe.fileHandleForReading, into: stderrBox)

        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            throw EnvBoxError.processFailed("无法启动 \(executable.lastPathComponent)")
        }

        // Best effort: put the child into its own process group so a timeout can signal the whole tree.
        let pid = process.processIdentifier
        let hasOwnGroup = setpgid(pid, pid) == 0

        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                terminateTree(pid: pid, hasOwnGroup: hasOwnGroup)
                break
            }
            usleep(20_000)
        }
        process.waitUntilExit()

        // A grandchild can keep the inherited pipe open after the parent exits; never block past the deadline.
        if drained.wait(timeout: .now() + 1.0) == .timedOut {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }

        let status = process.terminationStatus
        let reason = process.terminationReason
        let signal: Int32? = reason == .uncaughtSignal ? status : nil
        let exitCode: Int32 = reason == .uncaughtSignal ? 128 + status : status

        return GroupProcessResult(
            exitCode: exitCode,
            signal: signal,
            stdout: stdoutBox.snapshot(),
            stderr: stderrBox.snapshot(),
            timedOut: timedOut,
            outputTruncated: stdoutBox.didTruncate || stderrBox.didTruncate
        )
    }

    private static func terminateTree(pid: pid_t, hasOwnGroup: Bool) {
        if hasOwnGroup {
            kill(-pid, SIGTERM)
            usleep(200_000)
            kill(-pid, SIGKILL)
        }
        killTree(pid: pid, depth: 0)
    }

    private static func killTree(pid: pid_t, depth: Int) {
        guard depth < 8, pid > 0 else { return }
        var children = [pid_t](repeating: 0, count: 256)
        let byteCount = Int32(children.count * MemoryLayout<pid_t>.size)
        let listed = proc_listchildpids(pid, &children, byteCount)
        if listed > 0 {
            for child in children.prefix(min(Int(listed), children.count)) where child > 0 {
                killTree(pid: child, depth: depth + 1)
            }
        }
        kill(pid, SIGKILL)
    }
}

private final class CappedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var data = Data()
    private var truncated = false

    init(maxBytes: Int) {
        self.maxBytes = max(0, maxBytes)
    }

    func append(_ chunk: Data) {
        lock.lock()
        let remaining = max(0, maxBytes - data.count)
        if remaining == 0 {
            truncated = truncated || !chunk.isEmpty
        } else {
            data.append(chunk.prefix(remaining))
            if chunk.count > remaining { truncated = true }
        }
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }

    var didTruncate: Bool {
        lock.lock()
        let value = truncated
        lock.unlock()
        return value
    }
}
