import AppKit
import EnvBoxUI
import SwiftUI

@main
struct EnvBoxApp: App {
    @NSApplicationDelegateAdaptor(EnvBoxApplicationDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["ENVBOX_DARK"] == "1" {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        } else if ProcessInfo.processInfo.environment["ENVBOX_LIGHT"] == "1" {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
        #endif
    }

    var body: some Scene {
        EnvBoxMainScene()
    }
}
