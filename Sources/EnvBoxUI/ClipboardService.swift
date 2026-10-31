import AppKit
import Foundation

@MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    private var clearTask: Task<Void, Never>?

    private init() {}

    func copy(_ value: String, clearAfter seconds: TimeInterval?, concealed: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        if concealed {
            // Well-behaved clipboard managers skip the ConcealedType marker instead of persisting secrets.
            pasteboard.setData(
                Data(),
                forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            )
        }
        let changeCount = pasteboard.changeCount

        clearTask?.cancel()
        guard let seconds else { return }

        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let current = NSPasteboard.general
            if current.changeCount == changeCount {
                current.clearContents()
            }
            self?.clearTask = nil
        }
    }

}
