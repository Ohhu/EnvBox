import EnvBoxCore
import SwiftUI

struct ProfileEditorSheet: View {
    let profileID: UUID?
    let prefillSystem: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var name = ""
    @State private var note = ""
    @State private var tint: ProfileTint = .aurora
    @State private var symbol = "shippingbox.fill"
    @State private var includeCurrentEnvironment = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @FocusState private var nameFocused: Bool
    @FocusState private var noteFocused: Bool

    init(profileID: UUID? = nil, prefillSystem: Bool = false) {
        self.profileID = profileID
        self.prefillSystem = prefillSystem
        _includeCurrentEnvironment = State(initialValue: prefillSystem)
    }

    private var isEditing: Bool { profileID != nil }

    private var availableSystemCount: Int {
        guard let snapshot = model.snapshot else { return 0 }
        return snapshot.variables.filter { model.payload.settings.showInternalVariables || !$0.isInternal }.count
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= EnvProfile.maxNameLength
            && note.count <= EnvVariable.maxNoteLength
            && model.isVaultUnlocked
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            PanelDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    noteSection
                    tintSection
                    symbolSection
                    if !isEditing {
                        systemImportSection
                    }
                    if let errorMessage {
                        Text(errorMessage)
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
        .frame(width: 520, height: 560)
        .background(.regularMaterial)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProfileGlyph(tint: tint, symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "编辑配置信息" : "新建配置")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(isEditing ? "名称、说明与外观" : "为一组环境变量命名，并选择一个容易识别的图标")
                    .font(.system(size: 11.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("配置名称", trailing: "\(name.count)/\(EnvProfile.maxNameLength)")
            TextField("例如：后端开发、生产排查", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($nameFocused)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(fieldBackground(isFocused: nameFocused))
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("说明", trailing: "\(note.count)/\(EnvVariable.maxNoteLength)")
            TextField("这个配置用于什么场景？", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(2...4)
                .focused($noteFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(fieldBackground(isFocused: noteFocused))
        }
    }

    private var tintSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("色彩")
            HStack(spacing: 10) {
                ForEach(ProfileTint.allCases, id: \.self) { candidate in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { tint = candidate }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(candidate.gradient)
                                .frame(width: 27, height: 27)
                            if tint == candidate {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                                    .frame(width: 21, height: 21)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    tint == candidate ? Color.white.opacity(0.55) : Color.clear,
                                    lineWidth: 1
                                )
                                .frame(width: 33, height: 33)
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .help(candidate.displayName)
                    .accessibilityLabel(candidate.displayName)
                }
                Spacer()
                Text(tint.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
        }
    }

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("图标")
            HStack(spacing: 7) {
                ForEach(ProfileSymbols.options, id: \.self) { candidate in
                    Button {
                        withAnimation(.snappy(duration: 0.16)) { symbol = candidate }
                    } label: {
                        Image(systemName: candidate)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(symbol == candidate ? .white : EnvBoxTheme.textSecondary(for: scheme))
                            .frame(width: 31, height: 31)
                            .background {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        symbol == candidate
                                            ? AnyShapeStyle(tint.gradient)
                                            : AnyShapeStyle(Color.primary.opacity(0.04))
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(candidate)
                }
            }
        }
    }

    private var systemImportSection: some View {
        HStack(spacing: 11) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EnvBoxTheme.aqua)
                .frame(width: 30, height: 30)
                .background(EnvBoxTheme.aqua.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("包含当前系统变量")
                    .font(.system(size: 12, weight: .medium))
                Text("将读取到的 \(availableSystemCount) 个非内部变量作为初始值")
                    .font(.system(size: 10.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer()
            EnvBoxSwitch(
                isOn: $includeCurrentEnvironment,
                tint: EnvBoxTheme.mint,
                accessibilityLabel: "包含当前系统变量"
            )
        }
        .padding(12)
        .background(fieldBackground(isFocused: false))
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(EnvBoxSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "保存更改" : "创建配置") {
                save()
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

    private func sectionTitle(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme).opacity(0.7))
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let profileID, let profile = model.payload.profile(id: profileID) {
            name = profile.name
            note = profile.note
            tint = profile.tint
            symbol = profile.symbol
        } else {
            let baseName = model.payload.profiles.isEmpty ? "默认配置" : "新配置"
            name = EnvBoxValidation.uniqueProfileName(baseName, existing: model.payload.profiles)
            tint = ProfileTint.allCases[model.payload.profiles.count % ProfileTint.allCases.count]
            nameFocused = true
        }
    }

    private func save() {
        errorMessage = nil
        do {
            if let profileID {
                try model.updateProfileMetadata(
                    profileID: profileID,
                    name: name,
                    note: note,
                    tint: tint,
                    symbol: symbol
                )
            } else {
                try model.createProfile(
                    name: name,
                    note: note,
                    tint: tint,
                    symbol: symbol,
                    includeSystemEnvironment: includeCurrentEnvironment
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
