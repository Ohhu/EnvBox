import Darwin
import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool

    public init(status: Int32, stdout: Data, stderr: Data, timedOut: Bool) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var data = Data()

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func append(_ chunk: Data) {
        lock.lock()
        let remaining = max(0, maxBytes - data.count)
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

public enum ProcessRunner {
    private static let maxCapturedBytes = 4 * 1024 * 1024

    /// Runs a short-lived process without blocking the caller. stdout and stderr are drained concurrently
    /// with a hard output cap. The process exit has its own deadline so a closed pipe cannot hang the caller.
    public static func run(
        executable: URL,
        arguments: [String] = [],
        input: Data? = nil,
        timeout: TimeInterval = 10,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let environment {
                    process.environment = environment
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let inputPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.standardInput = input == nil ? FileHandle.nullDevice : inputPipe

                let stdoutAccumulator = DataAccumulator(maxBytes: maxCapturedBytes)
                let stderrAccumulator = DataAccumulator(maxBytes: maxCapturedBytes)
                let outputGroup = DispatchGroup()
                let exitSemaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    exitSemaphore.signal()
                }

                func readLoop(_ handle: FileHandle, accumulator: DataAccumulator) {
                    while true {
                        guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                            break
                        }
                        accumulator.append(chunk)
                    }
                }

                outputGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    readLoop(stdoutPipe.fileHandleForReading, accumulator: stdoutAccumulator)
                    outputGroup.leave()
                }

                outputGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    readLoop(stderrPipe.fileHandleForReading, accumulator: stderrAccumulator)
                    outputGroup.leave()
                }

                do {
                    try process.run()

                    if let input {
                        DispatchQueue.global(qos: .userInitiated).async {
                            inputPipe.fileHandleForWriting.write(input)
                            try? inputPipe.fileHandleForWriting.close()
                        }
                    }

                    let deadline = DispatchTime.now() + max(0.1, timeout)
                    var timedOut = false
                    if exitSemaphore.wait(timeout: deadline) == .timedOut {
                        timedOut = true
                        if process.isRunning {
                            process.terminate()
                        }
                        if exitSemaphore.wait(timeout: .now() + 1.0) == .timedOut {
                            if process.isRunning {
                                kill(process.processIdentifier, SIGKILL)
                            }
                            _ = exitSemaphore.wait(timeout: .now() + 1.0)
                        }
                    }

                    // A child process can keep the inherited pipe open after the parent exits. Do not let
                    // that hold the caller past the deadline.
                    if outputGroup.wait(timeout: .now() + 2.0) == .timedOut {
                        timedOut = true
                    }

                    process.waitUntilExit()
                    let result = ProcessResult(
                        status: process.terminationStatus,
                        stdout: stdoutAccumulator.snapshot(),
                        stderr: stderrAccumulator.snapshot(),
                        timedOut: timedOut
                    )
                    continuation.resume(returning: result)
                } catch {
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    try? inputPipe.fileHandleForWriting.close()
                    continuation.resume(
                        throwing: EnvBoxError.processFailed("无法启动 (executable.lastPathComponent)")
                    )
                }
            }
        }
    }
}
