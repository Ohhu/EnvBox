#if DEBUG
import AppKit
import EnvBoxCore
import Foundation

enum DemoData {
    static let activeProfileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static func payload() -> VaultPayload {
        let devID = activeProfileID
        let stagingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let prodID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        let dev = EnvProfile(
            id: devID,
            name: "本地开发",
            note: "本地 API、调试日志与开发数据库",
            tint: .aurora,
            symbol: "shippingbox.fill",
            variables: [
                EnvVariable(key: "API_BASE_URL", value: "https://api.staging.envbox.dev/v2", isEnabled: true),
                EnvVariable(key: "NODE_ENV", value: "development", isEnabled: true),
                EnvVariable(key: "LOG_LEVEL", value: "debug", isEnabled: true),
                EnvVariable(key: "DATABASE_URL", value: "postgres://envbox:demo@127.0.0.1:5432/envbox_dev", isEnabled: true, isSecret: true, note: "本地 Docker"),
                EnvVariable(key: "OPENAI_API_KEY", value: "sk-demo-not-a-real-key", isEnabled: true, isSecret: true),
                EnvVariable(key: "FEATURE_FLAGS", value: "new-editor,fast-sync,command-palette", isEnabled: true),
                EnvVariable(key: "HTTP_PROXY", value: "http://127.0.0.1:6152", isEnabled: true),
                EnvVariable(key: "TZ", value: "Asia/Shanghai", isEnabled: true),
                EnvVariable(key: "LEGACY_MODE", value: "1", isEnabled: false, note: "仅旧项目使用")
            ],
            createdAt: Date().addingTimeInterval(-86400 * 12),
            updatedAt: Date().addingTimeInterval(-420)
        )

        let staging = EnvProfile(
            id: stagingID,
            name: "预发布",
            note: "Staging 环境，只读凭据",
            tint: .ocean,
            symbol: "cloud.fill",
            variables: [
                EnvVariable(key: "API_BASE_URL", value: "https://api.staging.envbox.dev/v2", isEnabled: true),
                EnvVariable(key: "NODE_ENV", value: "production", isEnabled: true),
                EnvVariable(key: "LOG_LEVEL", value: "info", isEnabled: true),
                EnvVariable(key: "SENTRY_DSN", value: "https://demo@sentry.envbox.dev/42", isEnabled: true, isSecret: true),
                EnvVariable(key: "FEATURE_FLAGS", value: "new-editor", isEnabled: true)
            ],
            createdAt: Date().addingTimeInterval(-86400 * 30),
            updatedAt: Date().addingTimeInterval(-86400 * 2)
        )

        let prod = EnvProfile(
            id: prodID,
            name: "生产排障",
            note: "只读令牌；使用前先确认 VPN",
            tint: .ember,
            symbol: "flame.fill",
            variables: [
                EnvVariable(key: "API_BASE_URL", value: "https://api.envbox.dev/v2", isEnabled: true),
                EnvVariable(key: "LOG_LEVEL", value: "warn", isEnabled: true),
                EnvVariable(key: "READ_ONLY_TOKEN", value: "demo-readonly-token", isEnabled: true, isSecret: true),
                EnvVariable(key: "SENTRY_DSN", value: "https://demo@sentry.envbox.dev/7", isEnabled: true, isSecret: true),
                EnvVariable(key: "TZ", value: "UTC", isEnabled: true)
            ],
            createdAt: Date().addingTimeInterval(-86400 * 44),
            updatedAt: Date().addingTimeInterval(-86400 * 6)
        )

        var payload = VaultPayload(
            profiles: [dev, staging, prod],
            activeProfileID: devID,
            appliedKeys: dev.enabledVariables.map { $0.key },
            appliedFingerprint: dev.fingerprint(),
            settings: AppSettings(
                autoRestoreActiveProfile: true,
                includeLoginShellEnvironment: true,
                showInternalVariables: false,
                concealSensitiveValues: true,
                autoClearSensitiveClipboard: true,
                hasCompletedFirstApply: true,
                shellIntegrationEnabled: true
            ),
            createdAt: Date().addingTimeInterval(-86400 * 50),
            updatedAt: Date()
        )
        payload.settings.shellIntegrationEnabled = true
        return payload
    }

    static func snapshot() -> EnvironmentSnapshot {
        let entries: [(String, String)] = [
            ("HOME", "/Users/ohhu"),
            ("USER", "ohhu"),
            ("SHELL", "/bin/zsh"),
            ("PATH", "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"),
            ("LANG", "zh_CN.UTF-8"),
            ("TMPDIR", "/var/folders/2c/demo/T/"),
            ("EDITOR", "nvim"),
            ("NODE_ENV", "development"),
            ("API_BASE_URL", "https://api.staging.envbox.dev/v2"),
            ("OPENAI_API_KEY", "sk-demo-not-a-real-key"),
            ("DATABASE_URL", "postgres://envbox:demo@127.0.0.1:5432/envbox_dev"),
            ("SENTRY_DSN", "https://demo@sentry.envbox.dev/42"),
            ("HTTP_PROXY", "http://127.0.0.1:6152"),
            ("FEATURE_FLAGS", "new-editor,fast-sync,command-palette"),
            ("TZ", "Asia/Shanghai"),
            ("PWD", "/Users/ohhu/Developer/envbox"),
            ("SHLVL", "1"),
            ("XPC_SERVICE_NAME", "com.ohhu.envbox")
        ]
        return EnvironmentSnapshot(
            variables: entries.map { SystemVariable(key: $0.0, value: $0.1) },
            source: .loginShell,
            capturedAt: Date(),
            duration: 0.28,
            shellName: "zsh"
        )
    }

    static func shellStatus() -> ShellIntegrationStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ShellIntegrationStatus(
            isInstalled: true,
            isSupported: true,
            shellName: "zsh",
            rcURL: home.appendingPathComponent(".zshrc"),
            activationURL: home.appendingPathComponent(".envbox/active.zsh"),
            hasActiveConfiguration: true
        )
    }
}

enum DebugSnapshot {
    static var outputPath: String? {
        ProcessInfo.processInfo.environment["ENVBOX_SNAPSHOT"]
    }

    @MainActor
    static func capture() {
        guard let path = outputPath else { return }
        guard let mainWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
            NSLog("EnvBox snapshot: no visible window")
            return
        }
        let requestedSettings = ProcessInfo.processInfo.environment["ENVBOX_DEMO_SETTINGS"] == "1"
        let alternateWindow = requestedSettings
            ? NSApp.windows.last(where: { $0.isVisible && $0.contentView != nil && $0 != mainWindow })
            : nil
        let window = alternateWindow ?? mainWindow.attachedSheet ?? mainWindow
        window.displayIfNeeded()
        guard let view = window.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("EnvBox snapshot: no bitmap representation")
            return
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            NSLog("EnvBox snapshot: PNG encoding failed")
            return
        }
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            NSLog("EnvBox snapshot written to \(path)")
        } catch {
            NSLog("EnvBox snapshot failed: \(error.localizedDescription)")
        }
        if ProcessInfo.processInfo.environment["ENVBOX_SNAPSHOT_QUIT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                exit(0)
            }
        }
    }
}
#endif
