import Foundation

/// Locates the shared UI assets for the current build.
///
/// Resolution order:
///   1. `ENVBOX_WEB_ROOT` — point the app at the checkout while developing.
///   2. `Contents/Resources/web` — what the packaging script copies.
///   3. `cmd/envbox/web` next to `#filePath` — only for `swift run` from a checkout.
enum WebUIRoot {
    static func resolve() -> URL {
        if let override = ProcessInfo.processInfo.environment["ENVBOX_WEB_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) {
            return bundled
        }
        let checkout = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cmd/envbox/web")
        return checkout
    }
}
