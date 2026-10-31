import EnvBoxCore
import SwiftUI

struct TransferSheet: View {
    let route: TransferRoute

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case passphrase
        case confirmation
    }

    private var isExport: Bool {
        if case .export = route.mode { return true }
        return false
    }

    private var exportedProfiles: [EnvProfile] {
        guard case .export(let ids, _) = route.mode else { return [] }
        return ids.compactMap { model.payload.profile(id: $0) }
    }

    private var exportTitle: String {
        guard case .export(_, let title) = route.mode else { return "" }
        return title
    }

    private var importFile: (name: String, data: Data)? {
        guard case .importFile(let name, let data) = route.mode else { return nil }
        return (name, data)
    }

    private var canSubmit: Bool {
        guard passphrase.count >= 8, passphrase.count <= 1024 else { return false }
        if isExport { return passphrase == confirmation }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            PanelDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    passphraseSection
                    if isExport { confirmationSection }
                    passwordStrength
                    warning
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
        .frame(width: 510, height: isExport ? 545 : 505)
        .background(.regularMaterial)
        .onAppear { focusedField = .passphrase }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: isExport ? "lock.doc.fill" : "lock.open.doc.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(EnvBoxTheme.mint)
                .frame(width: 42, height: 42)
                .background(EnvBoxTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(isExport ? "导出加密配置" : "导入加密配置")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(isExport ? "使用独立密码保护可移植文件" : "输入导出时设置的密码")
                    .font(.system(size: 11.5))
                    .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var summaryCard: some View {
        if isExport {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(exportTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("\(exportedProfiles.count) 个配置 · \(exportedProfiles.reduce(0) { $0 + $1.variables.count }) 个变量")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
                HStack(spacing: 5) {
                    ForEach(exportedProfiles.prefix(4)) { profile in
                        Pill(text: profile.name, icon: "shippingbox.fill", tint: profile.tint.primary)
                    }
                    if exportedProfiles.count > 4 {
                        Text("+\(exportedProfiles.count - 4)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                    }
                }
            }
            .padding(12)
            .background(fieldBackground(isFocused: false))
        } else if let importFile {
            HStack(spacing: 11) {
                Image(systemName: "doc.badge.lock")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(EnvBoxTheme.aqua)
                    .frame(width: 36, height: 36)
                    .background(EnvBoxTheme.aqua.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(importFile.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(byteCount(importFile.data.count) + " · EnvBox 加密配置")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
                }
                Spacer()
            }
            .padding(12)
            .background(fieldBackground(isFocused: false))
        }
    }

    private var passphraseSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(isExport ? "设置导出密码" : "配置文件密码")
            SecureField("至少 8 个字符", text: $passphrase)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($focusedField, equals: .passphrase)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(fieldBackground(isFocused: focusedField == .passphrase))
                .onSubmit { if canSubmit && !isWorking { submit() } }
            Text(isExport ? "密码仅用于此文件，不会写入磁盘或钥匙串。" : "密码不会保存。")
                .font(.system(size: 9.5))
                .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel("确认密码")
            SecureField("再次输入密码", text: $confirmation)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($focusedField, equals: .confirmation)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(fieldBackground(isFocused: focusedField == .confirmation))
                .onSubmit { if canSubmit && !isWorking { submit() } }
            if !confirmation.isEmpty && confirmation != passphrase {
                Text("两次输入的密码不一致")
                    .font(.system(size: 10))
                    .foregroundStyle(EnvBoxTheme.rose)
            }
        }
    }

    @ViewBuilder
    private var passwordStrength: some View {
        if !passphrase.isEmpty {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index < strength.score ? strength.color : Color.primary.opacity(0.08))
                            .frame(height: 4)
                    }
                }
                .frame(width: 96)
                Text(strength.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(strength.color)
                Spacer()
            }
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(EnvBoxTheme.amber)
            Text(
                isExport
                    ? "请妥善保存密码。文件只包含密文，忘记密码后 EnvBox 也无法恢复。"
                    : "导入会新增配置，不会覆盖现有配置。同名配置会自动重命名。"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .background(EnvBoxTheme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(EnvBoxTheme.amber.opacity(0.12), lineWidth: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(EnvBoxSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button {
                    submit()
                } label: {
                    if isWorking {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(isExport ? "正在加密…" : "正在解密…")
                        }
                    } else {
                        Label(isExport ? "选择位置并导出" : "解密并导入", systemImage: isExport ? "square.and.arrow.up" : "square.and.arrow.down")
                    }
                }
                .buttonStyle(EnvBoxPrimaryButtonStyle())
                .disabled(!canSubmit || isWorking)
                .keyboardShortcut(.defaultAction)
            }
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

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(EnvBoxTheme.textSecondary(for: scheme))
    }

    private func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var strength: (score: Int, label: String, color: Color) {
        var score = 0
        if passphrase.count >= 8 { score += 1 }
        if passphrase.count >= 12 { score += 1 }
        if passphrase.rangeOfCharacter(from: .uppercaseLetters) != nil,
           passphrase.rangeOfCharacter(from: .lowercaseLetters) != nil { score += 1 }
        if passphrase.rangeOfCharacter(from: .decimalDigits) != nil,
           passphrase.rangeOfCharacter(from: .punctuationCharacters) != nil { score += 1 }
        switch score {
        case 0, 1: return (1, "较弱", EnvBoxTheme.rose)
        case 2: return (2, "一般", EnvBoxTheme.amber)
        case 3: return (3, "良好", EnvBoxTheme.aqua)
        default: return (4, "很强", EnvBoxTheme.mint)
        }
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        errorMessage = nil
        isWorking = true
        switch route.mode {
        case .export(let ids, _):
            Task {
                do {
                    if let _ = try await model.exportConfiguration(profileIDs: ids, passphrase: passphrase) {
                        dismiss()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isWorking = false
            }
        case .importFile(_, let data):
            Task {
                do {
                    _ = try await model.importConfiguration(data: data, passphrase: passphrase)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isWorking = false
            }
        }
    }
}
