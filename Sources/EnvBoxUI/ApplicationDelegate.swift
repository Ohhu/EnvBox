import AppKit
import Foundation

/// Delays termination until the encrypted vault has been flushed. Keeping this in the UI module lets the
/// scene hand the live AppModel to the AppKit delegate without exposing it to the executable target.
public final class EnvBoxApplicationDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?
    @MainActor private static var pendingURLs: [URL] = []

    public override init() {
        super.init()
    }

    @MainActor
    static func attach(model: AppModel) {
        Self.model = model
        let pending = pendingURLs
        pendingURLs.removeAll()
        for url in pending {
            model.handleOpenURL(url)
        }
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard let model = Self.model else {
            Self.pendingURLs.append(contentsOf: urls)
            sender.reply(toOpenOrPrint: .success)
            return
        }
        for url in urls {
            model.handleOpenURL(url)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model, model.isVaultUnlocked, model.hasUnsavedChanges else {
            return .terminateNow
        }

        Task { @MainActor in
            let saved = await model.flush()
            if saved {
                sender.reply(toApplicationShouldTerminate: true)
            } else {
                model.showAlert(
                    title: "已取消退出",
                    message: "配置尚未成功保存。请检查钥匙串访问权限后重试。"
                )
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
