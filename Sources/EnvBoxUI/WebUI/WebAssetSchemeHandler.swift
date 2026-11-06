import Foundation
import WebKit

/// Serves the shared web UI to WKWebView over a custom scheme.
///
/// file:// is not good enough: WKWebView refuses ES modules and cross-origin
/// fetches there. Registering `envbox://` and streaming the same files from disk
/// keeps the macOS host byte-identical to what WebView2 loads on Windows.
final class WebAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "envbox"
    static let host = "ui"

    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(Self.badRequest)
            return
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        guard let file = resolve(path) else {
            urlSchemeTask.didFailWithError(Self.notFound)
            return
        }
        do {
            let data = try Data(contentsOf: file)
            let response = URLResponse(
                url: url,
                mimeType: Self.mimeType(for: file.pathExtension),
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func resolve(_ path: String) -> URL? {
        var relative = path
        if relative.hasPrefix("/") { relative.removeFirst() }
        guard !relative.isEmpty, !relative.contains("..") else { return nil }
        let file = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }

    private static let badRequest = NSError(
        domain: "EnvBoxWebUI",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "无效的界面资源地址"]
    )
    private static let notFound = NSError(
        domain: "EnvBoxWebUI",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "界面资源不存在"]
    )
}
