import EnvBoxCore
import SwiftUI

enum VariableDisplay {
    static func singleLine(_ value: String) -> String {
        if value.isEmpty { return "—" }
        return value
            .replacingOccurrences(of: "\r\n", with: " ↵ ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
    }
}

struct SystemVariableRow: View {
    let variable: SystemVariable

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                if variable.isSensitive {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(EnvBoxTheme.amber.opacity(0.9))
                }
                Text(variable.key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if variable.isInternal {
                    Pill(text: "系统", tint: EnvBoxTheme.textSecondary(for: scheme))
                }
            }
            .frame(width: 226, alignment: .leading)

            Text(model.isRevealed(system: variable) ? VariableDisplay.singleLine(variable.value) : variable.masking)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(
                    model.isRevealed(system: variable)
                        ? EnvBoxTheme.textSecondary(for: scheme)
                        : EnvBoxTheme.textSecondary(for: scheme).opacity(0.72)
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                if variable.isSensitive {
                    IconButton(
                        systemName: model.isRevealed(system: variable) ? "eye.slash" : "eye",
                        help: model.isRevealed(system: variable) ? "隐藏值" : "显示值",
                        tint: Color.primary.opacity(0.62),
                        size: 26
                    ) {
                        model.toggleReveal(system: variable)
                    }
                }
                IconButton(
                    systemName: "tag",
                    help: "复制变量名",
                    tint: Color.primary.opacity(0.62),
                    size: 26
                ) {
                    model.copyKeyToClipboard(variable.key)
                }
                IconButton(
                    systemName: "doc.on.doc",
                    help: "复制值",
                    tint: Color.primary.opacity(0.62),
                    size: 26
                ) {
                    model.copyToClipboard(variable.value, sensitive: variable.isSensitive)
                }
            }
            .opacity(isHovering ? 1 : 0.82)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background {
            if isHovering {
                Rectangle().fill(Color.primary.opacity(scheme == .dark ? 0.028 : 0.018))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.13)) { isHovering = hovering }
        }
        .contextMenu {
            if variable.isSensitive {
                Button(model.isRevealed(system: variable) ? "隐藏值" : "显示值") {
                    model.toggleReveal(system: variable)
                }
            }
            Button("复制值") {
                model.copyToClipboard(variable.value, sensitive: variable.isSensitive)
            }
            Button("复制变量名") {
                model.copyToClipboard(variable.key, sensitive: false)
            }
        }
    }
}

struct ProfileVariableRow: View {
    let variable: EnvVariable
    let profileID: UUID
    let onEdit: () -> Void
    let onDeleteRequest: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            EnvBoxSwitch(
                isOn: Binding(
                    get: { variable.isEnabled },
                    set: { _ in
                        model.toggleVariable(variable.id, profileID: profileID)
                    }
                ),
                tint: EnvBoxTheme.mint,
                accessibilityLabel: "启用 \(variable.key)"
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if variable.isSecret {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(EnvBoxTheme.amber.opacity(0.9))
                    }
                    Text(variable.key)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(variable.isEnabled ? .primary : EnvBoxTheme.textSecondary(for: scheme))
                        .lineLimit(1)
                }
                if !variable.note.isEmpty {
                    Text(variable.note)
                        .font(.system(size: 9.5))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                        .lineLimit(1)
                }
            }
            .frame(width: 210, alignment: .leading)

            Text(model.isRevealed(profile: variable) ? VariableDisplay.singleLine(variable.value) : variable.masking)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                if variable.isSecret {
                    IconButton(
                        systemName: model.isRevealed(profile: variable) ? "eye.slash" : "eye",
                        help: model.isRevealed(profile: variable) ? "隐藏值" : "显示值",
                        tint: Color.primary.opacity(0.62),
                        size: 26
                    ) {
                        model.toggleReveal(profile: variable)
                    }
                }
                IconButton(
                    systemName: "tag",
                    help: "复制变量名",
                    tint: Color.primary.opacity(0.62),
                    size: 26
                ) {
                    model.copyKeyToClipboard(variable.key)
                }
                IconButton(
                    systemName: "doc.on.doc",
                    help: "复制值",
                    tint: Color.primary.opacity(0.62),
                    size: 26
                ) {
                    model.copyToClipboard(variable.value, sensitive: variable.isSecret)
                }
                IconButton(
                    systemName: "pencil",
                    help: "编辑变量",
                    tint: Color.primary.opacity(0.62),
                    size: 26,
                    action: onEdit
                )
            }
            .opacity(isHovering ? 1 : 0.82)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background {
            if isHovering {
                Rectangle().fill(Color.primary.opacity(scheme == .dark ? 0.028 : 0.018))
            }
        }
        .opacity(variable.isEnabled ? 1 : 0.62)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.13)) { isHovering = hovering }
        }
        .contextMenu {
            Button("编辑…", action: onEdit)
            if variable.isSecret {
                Button(model.isRevealed(profile: variable) ? "隐藏值" : "显示值") {
                    model.toggleReveal(profile: variable)
                }
            }
            Button("复制变量名") {
                model.copyKeyToClipboard(variable.key)
            }
            Button("复制值") {
                model.copyToClipboard(variable.value, sensitive: variable.isSecret)
            }
            Divider()
            Button(variable.isEnabled ? "停用" : "启用") {
                model.toggleVariable(variable.id, profileID: profileID)
            }
            Button("删除…", role: .destructive, action: onDeleteRequest)
        }
    }
}
