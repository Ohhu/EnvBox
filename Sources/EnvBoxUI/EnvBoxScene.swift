import EnvBoxCore
import SwiftUI

@MainActor
public struct EnvBoxMainScene: Scene {
    @State private var model: AppModel

    public init() {
        let model = AppModel.shared
        _model = State(initialValue: model)
        EnvBoxApplicationDelegate.attach(model: model)
    }

    public var body: some Scene {
        Window("EnvBox", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            EnvBoxCommands(model: model)
        }

        MenuBarExtra {
            MenuBarQuickSwitchView()
                .environment(model)
                .task { await model.bootstrap() }
        } label: {
            Image(systemName: model.activeProfile == nil ? "shippingbox" : "shippingbox.fill")
                .accessibilityLabel("EnvBox")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

private struct EnvBoxCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建配置…") {
                model.presentNewProfile()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!model.isVaultUnlocked)

            Divider()

            Button("导入加密配置…") {
                model.presentImportPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(!model.isVaultUnlocked)

            Button("导出全部配置…") {
                model.presentExportAll()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!model.isVaultUnlocked || model.payload.profiles.isEmpty)
        }

        CommandMenu("环境") {
            Button("刷新系统环境") {
                Task { await model.refreshSystemEnvironment() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(model.isRefreshingEnvironment)

            Button("应用当前配置") {
                if let id = model.payload.activeProfileID {
                    model.requestApply(id)
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(model.activeProfile == nil || model.isApplying)

            Button("停用当前配置") {
                model.requestDeactivate()
            }
            .disabled(model.activeProfile == nil || model.isApplying)

            Divider()

            Button("隐藏所有敏感值") {
                model.hideAllSensitiveValues()
            }
        }

        CommandGroup(replacing: .help) {
            Button("EnvBox GitHub") {
                model.openGitHub()
            }
        }
    }
}
