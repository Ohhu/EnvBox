import EnvBoxCore
import AppKit
import Combine
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model

        ZStack {
            EnvBoxBackground()

            HStack(spacing: 0) {
                SidebarView()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            ToastOverlay(toast: model.toast)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(minWidth: 980, minHeight: 640)
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: 28)
                .padding(.leading, 78)
                .accessibilityHidden(true)
        }
        .background(WindowConfigurator())
        .sheet(item: $model.sheet) { route in
            sheetView(route)
                .environment(model)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
        .task {
            await model.bootstrap()
            #if DEBUG
            if ProcessInfo.processInfo.environment["ENVBOX_DEMO_SETTINGS"] == "1" {
                openSettings()
            }
            if DebugSnapshot.outputPath != nil {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                DebugSnapshot.capture()
            }
            #endif
        }
        .onOpenURL { url in
            model.handleOpenURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.concealSensitiveValues()
            Task { await model.saveNow() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .system:
            SystemEnvironmentView()
                .id("system")
        case .profile(let id):
            ProfileDetailView(profileID: id)
                .id(id)
        }
    }

    @ViewBuilder
    private func sheetView(_ route: SheetRoute) -> some View {
        switch route.kind {
        case .newProfile(let prefillSystem):
            ProfileEditorSheet(prefillSystem: prefillSystem)
        case .editProfile(let profileID):
            ProfileEditorSheet(profileID: profileID)
        case .variable(let profileID, let variable):
            VariableEditorSheet(profileID: profileID, variable: variable)
        case .transfer(let transferRoute):
            TransferSheet(route: transferRoute)
        case .firstApply(let profileID):
            FirstApplySheet(profileID: profileID)
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
