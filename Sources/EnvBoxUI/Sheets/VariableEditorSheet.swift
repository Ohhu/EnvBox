import EnvBoxCore
import SwiftUI

struct VariableEditorSheet: View {
    let profileID: UUID
    let variable: EnvVariable?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var key: String
    @State private var value: String
    @State private var isEnabled: Bool
    @State private var isSecret: Bool
    @State private var note: String
    @State private var secretWasEditedManually: Bool
    @State private var isValueRevealed = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case key
        case value
        case note
    }

    init(profileID: UUID, variable: EnvVariable?) {
        self.profileID = profileID
        self.variable = variable
        _key = State(initialValue: variable?.key ?? "")
        _value = State(initialValue: variable?.value ?? "")
        _isEnabled = State(initialValue: variable?.isEnabled ?? true)
        _isSecret = State(initialValue: variable?.isSecret ?? false)
        _note = State(initialValue: variable?.note ?? "")
        _secretWasEditedManually = State(initialValue: variable != nil)
    }

    private var profile: EnvProfile? {
        model.payload.profile(id: profileID)
    }

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var valueBytes: Int {
        value.utf8.count
    }

    private var validationMessage: String? {
        if trimmedKey.isEmpty { return nil }
        if !EnvBoxValidation.isValidKey(trimmedKey) {
            return "变量名只能包含字母、数字和下划线，且不能以数字开头。"
        }
        if value.utf8.count > EnvVariable.maxValueBytes {
            return "值超过 32 KB 限制。"
        }
        if value.utf8.contains(0) {
            return "值不能包含空字符（NUL）。"
        }
        if let profile {
            let duplicate = profile.variables.contains {
                $0.id != variable?.id && $0.key == trimmedKey
            }
            if duplicate { return "此配置中已存在同名变量。" }
        }
        return nil
    }

    private var canSave: Bool {
        !trimmedKey.isEmpty
            && validationMessage == nil
            && note.count <= EnvVariable.maxNoteLength
            && model.isVaultUnlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            PanelDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    keySection
                    valueSection
                    toggles
                    noteSection
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(EnvBoxTheme.rose)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(EnvBoxTheme.rose)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            PanelDivider()
            footer
        }
        .frame(width: 510, height: 520)
        .background(.regularMaterial)
        .onAppear {
            if variable == nil { focusedField = .key }
        }
        .onChange(of: key) { _, newValue in
            if !secretWasEditedManually {
                isSecret = EnvironmentSensitivity.isSensitive(key: newValue)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: variable == nil ? "plus.circle.fill" : "curlybraces")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(EnvBoxTheme.mint)
                .frame(width: 42, height: 42)
                .background(EnvBoxTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(variable == nil ? "添加变量" : "编辑变量")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(profile?.name ?? "配置")
                    .font(.system(size: 11.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("变量名", trailing: "\(trimmedKey.count)/128")
            TextField("例如 API_BASE_URL", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .focused($focusedField, equals: .key)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(fieldBackground(isFocused: focusedField == .key))
                .autocorrectionDisabled()
        }
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                fieldLabel("值", trailing: "\(valueBytes)/\(EnvVariable.maxValueBytes) 字节")
                if isSecret {
                    Button(isValueRevealed ? "隐藏" : "显示") {
                        isValueRevealed.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(EnvBoxTheme.amber)
                    .accessibilityLabel(isValueRevealed ? "隐藏敏感值" : "显示敏感值")
                }
            }

            Group {
                if isSecret && !isValueRevealed {
                    SecureField("敏感值已遮盖", text: $value)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .focused($focusedField, equals: .value)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(fieldBackground(isFocused: focusedField == .value))
                } else {
                    TextField("变量值", text: $value, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineLimit(3...8)
                        .focused($focusedField, equals: .value)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(fieldBackground(isFocused: focusedField == .value))
                }
            }
            .privacySensitive()

            if isSecret && !isValueRevealed {
                Text("敏感值默认遮盖；点击“显示”后才会以明文编辑。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
        }
    }

    private var toggles: some View {
        HStack(spacing: 16) {
            LabeledSwitch(
                title: "启用变量",
                subtitle: "停用后不会被应用",
                tint: EnvBoxTheme.mint,
                isOn: $isEnabled
            )
            LabeledSwitch(
                title: "敏感值",
                subtitle: "默认以圆点遮盖",
                tint: EnvBoxTheme.amber,
                isOn: Binding(
                    get: { isSecret },
                    set: {
                        isSecret = $0
                        secretWasEditedManually = true
                        if $0 { isValueRevealed = false }
                    }
                )
            )
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("备注", trailing: "\(note.count)/500")
            TextField("可选，说明这个变量的用途", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .focused($focusedField, equals: .note)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(fieldBackground(isFocused: focusedField == .note))
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("值会加密保存在本机配置库中")
                .font(.system(size: 9.5))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(EnvBoxSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            if variable == nil {
                Button("保存并继续") {
                    save(keepOpen: true)
                }
                .buttonStyle(EnvBoxSecondaryButtonStyle())
                .disabled(!canSave)
            }
            Button(variable == nil ? "添加" : "保存") {
                save(keepOpen: false)
            }
            .buttonStyle(EnvBoxPrimaryButtonStyle())
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private func fieldBackground(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(scheme == .dark ? 0.045 : 0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isFocused ? EnvBoxTheme.mint.opacity(0.42) : EnvBoxTheme.hairline(for: scheme),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            }
    }

    private func fieldLabel(_ text: String, trailing: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            Spacer()
            Text(trailing)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.7))
        }
    }

    private func save(keepOpen: Bool) {
        errorMessage = nil
        let item = EnvVariable(
            id: variable?.id ?? UUID(),
            key: trimmedKey,
            value: value,
            isEnabled: isEnabled,
            isSecret: isSecret,
            note: note
        )
        do {
            try model.saveVariable(item, profileID: profileID)
            if keepOpen {
                key = ""
                value = ""
                note = ""
                isSecret = false
                secretWasEditedManually = false
                focusedField = .key
                model.showToast("变量已添加，可继续输入", style: .success)
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
