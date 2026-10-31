import Foundation
import Testing
@testable import EnvBoxCore

@Suite("File reading")
struct SafeFileReaderTests {
    @Test func boundedReadAcceptsExactSizeAndRejectsLargerFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("payload.bin")
        let data = Data(repeating: 0x41, count: 64)
        try data.write(to: file)

        let exact = try SafeFileReader.readData(at: file, maxBytes: 64)
        #expect(exact == data)

        do {
            _ = try SafeFileReader.readData(at: file, maxBytes: 63)
            Issue.record("Expected fileTooLarge")
        } catch {
            #expect((error as? EnvBoxError) == .fileTooLarge)
        }
    }

    @Test func missingFileIsReportedAsIOError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnvBox-missing-\(UUID().uuidString)")
        do {
            _ = try SafeFileReader.readData(at: url, maxBytes: 1024)
            Issue.record("Expected IO error")
        } catch {
            guard case .io = error as? EnvBoxError else {
                Issue.record("Expected EnvBoxError.io, got \(error)")
                return
            }
        }
    }
}
