import Foundation

public enum SafeFileReader {
    /// Reads at most maxBytes and rejects larger inputs instead of allocating the whole file.
    public static func readData(at url: URL, maxBytes: Int) throws -> Data {
        guard maxBytes > 0 else { throw EnvBoxError.fileTooLarge }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
        defer { try? handle.close() }

        do {
            var data = Data()
            while data.count <= maxBytes {
                let remaining = maxBytes + 1 - data.count
                let chunk = try handle.read(upToCount: min(64 * 1024, remaining)) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
            }
            if data.count > maxBytes { throw EnvBoxError.fileTooLarge }
            let extra = try handle.read(upToCount: 1) ?? Data()
            if !extra.isEmpty { throw EnvBoxError.fileTooLarge }
            return data
        } catch let error as EnvBoxError {
            throw error
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }
}
