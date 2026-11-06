import SwiftUI
import WebKit

/// What the web UI needs from the native side.
///
/// Both replies are complete JSON envelopes, so the host stays dumb and the
/// adapter owns the shape:
///     {"ok": true, "message": "配置已保存", "state": { ... }}
protocol WebUIBridge: AnyObject {
    /// Full application state for the first render and after every mutation.
    func webUIState(_ completion: @escaping (Result<Data, Error>) -> Void)
    /// One UI action, mirroring the Go/macOS dispatch table.
    func webUIDispatch(_ action: String, payload: String?, _ completion: @escaping (Result<Data, Error>) -> Void)
}

/// Bridges `window.webkit.messageHandlers.envbox` into Swift.
final class WebUIMessageRouter: NSObject, WKScriptMessageHandler {
    weak var bridge: (any WebUIBridge)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "envbox",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let kind = body["kind"] as? String else { return }

        let webView = message.webView
        let finish: (Result<Data, Error>) -> Void = { result in
            DispatchQueue.main.async {
                guard let webView else { return }
                switch result {
                case .success(let data):
                    Self.reply(on: webView, id: id, body: String(data: data, encoding: .utf8) ?? Self.failureEnvelope("原生桥返回了空响应"))
                case .failure(let error):
                    Self.reply(on: webView, id: id, body: Self.failureEnvelope((error as NSError).localizedDescription))
                }
            }
        }

        switch kind {
        case "state":
            bridge?.webUIState(finish)
        case "dispatch":
            let action = body["action"] as? String ?? ""
            let payload = body["payload"] as? String
            bridge?.webUIDispatch(action, payload: payload, finish)
        default:
            finish(.failure(NSError(domain: "EnvBoxWebUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "未知的桥接请求：\(kind)"])))
        }
    }

    private static func reply(on webView: WKWebView, id: String, body: String) {
        guard let idLiteral = jsLiteral(id), let bodyLiteral = jsLiteral(body) else { return }
        webView.evaluateJavaScript("window.__envboxReply(\(idLiteral), \(bodyLiteral))")
    }

    /// JSON-encodes a Swift string into a JS string literal.
    private static func jsLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func failureEnvelope(_ message: String) -> String {
        let payload: [String: Any] = ["ok": false, "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return "{\"ok\":false}"
        }
        return String(data: data, encoding: .utf8) ?? "{\"ok\":false}"
    }
}

/// Hosts the shared UI (shared/ui/assets) inside WKWebView.
///
/// The same files render on Windows via WebView2, so this view is the whole
/// macOS "UI layer"; everything platform specific stays on the Swift side.
struct WebUIView: NSViewRepresentable {
    let bridge: any WebUIBridge
    var root: URL = WebUIRoot.resolve()

    func makeCoordinator() -> WebUIMessageRouter {
        let router = WebUIMessageRouter()
        router.bridge = bridge
        return router
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            WebAssetSchemeHandler(root: root),
            forURLScheme: WebAssetSchemeHandler.scheme
        )

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "envbox")
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        if let url = URL(string: "\(WebAssetSchemeHandler.scheme)://\(WebAssetSchemeHandler.host)/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
