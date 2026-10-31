import EnvBoxCore
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let envBoxConfiguration = UTType(
        exportedAs: "com.ohhu.envbox.configuration",
        conformingTo: .json
    )
}

enum SidebarSelection: Hashable {
    case system
    case profile(UUID)

    var profileID: UUID? {
        if case .profile(let id) = self { return id }
        return nil
    }
}

enum VariableFilter: String, CaseIterable, Identifiable {
    case all
    case enabled
    case disabled
    case sensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .enabled: return "已启用"
        case .disabled: return "已停用"
        case .sensitive: return "敏感"
        }
    }

    var systemTitle: String {
        switch self {
        case .all: return "全部"
        case .sensitive: return "敏感"
        default: return title
        }
    }
}

enum VaultSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed(String)
}

enum ToastStyle: Equatable {
    case success
    case info
    case warning
    case error
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct TransferRoute {
    enum Mode {
        case export(profileIDs: [UUID], title: String)
        case importFile(name: String, data: Data)
    }

    let id = UUID()
    let mode: Mode
}

struct SheetRoute: Identifiable {
    enum Kind {
        case newProfile(prefillSystem: Bool)
        case editProfile(UUID)
        case variable(profileID: UUID, variable: EnvVariable?)
        case transfer(TransferRoute)
        case firstApply(UUID)
    }

    let id = UUID()
    let kind: Kind
}

@MainActor
@Observable
final class AppModel {
    var payload: VaultPayload = .empty()
    var selection: SidebarSelection = .system
    var snapshot: EnvironmentSnapshot?
    var shellStatus: ShellIntegrationStatus?
    var isBootstrapping = true
    var isRefreshingEnvironment = false
    var isVaultUnlocked = false
    var vaultError: String?
    var saveState: VaultSaveState = .idle
    var searchText = ""
    var filter: VariableFilter = .all
    var revealedKeys: Set<String> = []
    var revealAllSensitive = false
    var isApplying = false
    var applyingProfileID: UUID?
    var isTogglingShellIntegration = false
    var sheet: SheetRoute?
    var alert: AppAlert?
    var toast: ToastMessage?
    var menuActionError: String?
    var hasUnsavedChanges = false

    @ObservationIgnored private let store: VaultStore
    @ObservationIgnored private let environmentReader: SystemEnvironmentReading
    @ObservationIgnored private let shellIntegration: ShellIntegrationService
    @ObservationIgnored private let activationService: ProfileActivationService
    @ObservationIgnored private let transferService: ConfigTransferService
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherSave = false
    @ObservationIgnored private var isSavingNow = false
    @ObservationIgnored private var lastImportRequestPath: String?
    @ObservationIgnored private var lastImportRequestDate: Date?
    @ObservationIgnored private var pendingEnvironmentRefresh = false
    @ObservationIgnored private var activeFingerprintCache: (id: UUID, value: String)?

    @MainActor static let shared = AppModel()

    init(
        store: VaultStore = VaultStore(),
        environmentReader: SystemEnvironmentReading = ShellEnvironmentReader(),
        shellIntegration: ShellIntegrationService = ShellIntegrationService(),
        transferService: ConfigTransferService = ConfigTransferService()
    ) {
        self.store = store
        self.environmentReader = environmentReader
        self.shellIntegration = shellIntegration
        self.transferService = transferService
        self.activationService = ProfileActivationService(shellIntegration: shellIntegration)
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        isBootstrapping = true

        #if DEBUG
        if ProcessInfo.processInfo.environment["ENVBOX_DEMO"] == "1" {
            payload = DemoData.payload()
            snapshot = DemoData.snapshot()
            shellStatus = DemoData.shellStatus()
            isVaultUnlocked = true
            saveState = .saved(Date())
            if ProcessInfo.processInfo.environment["ENVBOX_DEMO_SCREEN"] == "system" {
                selection = .system
            } else {
                selection = .profile(DemoData.activeProfileID)
            }
            if let demoSheet = ProcessInfo.processInfo.environment["ENVBOX_DEMO_SHEET"] {
                switch demoSheet {
                case "variable":
                    if let profile = payload.profile(id: DemoData.activeProfileID),
                       let variable = profile.variables.first(where: { $0.key == "DATABASE_URL" }) {
                        sheet = SheetRoute(kind: .variable(profileID: profile.id, variable: variable))
                    }
                case "transfer":
                    sheet = SheetRoute(
                        kind: .transfer(
                            TransferRoute(mode: .export(profileIDs: [DemoData.activeProfileID], title: "本地开发"))
                        )
                    )
                case "profile":
                    sheet = SheetRoute(kind: .newProfile(prefillSystem: false))
                case "firstApply":
                    sheet = SheetRoute(kind: .firstApply(DemoData.activeProfileID))
                default:
                    break
                }
            }
            isBootstrapping = false
            return
        }
        #endif

        async let shellTask = shellIntegration.status()
        do {
            payload = try await store.load()
            isVaultUnlocked = true
            saveState = .saved(payload.updatedAt)
        } catch {
            isVaultUnlocked = false
            vaultError = error.localizedDescription
            saveState = .failed(error.localizedDescription)
        }
        shellStatus = await shellTask

        if isVaultUnlocked {
            refreshActiveFingerprintCache()
            let installed = shellStatus?.isInstalled ?? false
            if payload.settings.shellIntegrationEnabled != installed {
                payload.settings.shellIntegrationEnabled = installed
            }
            if payload.activeProfile != nil && payload.settings.autoRestoreActiveProfile {
                await restoreActiveProfile()
            }
        }

        if isVaultUnlocked {
            syncLoginItem()
            syncMCPPolicy()
        }
        await refreshSystemEnvironment()
        isBootstrapping = false
    }

    func retryVaultUnlock() async {
        do {
            payload = try await store.load()
            isVaultUnlocked = true
            vaultError = nil
            saveState = .saved(payload.updatedAt)
            refreshActiveFingerprintCache()
            if let id = selection.profileID, payload.profile(id: id) == nil {
                selection = .system
            }
            shellStatus = await shellIntegration.status()
            await refreshSystemEnvironment()
            showToast("配置库已解锁", style: .success)
        } catch {
            vaultError = error.localizedDescription
            showAlert(title: "无法解锁配置库", message: error.localizedDescription)
        }
    }

    func refreshSystemEnvironment() async {
        if isRefreshingEnvironment {
            pendingEnvironmentRefresh = true
            return
        }
        isRefreshingEnvironment = true
        var shouldRepeat = true
        while shouldRepeat {
            pendingEnvironmentRefresh = false
            let includeShell = payload.settings.includeLoginShellEnvironment
            let newSnapshot = await environmentReader.capture(includeLoginShell: includeShell)
            snapshot = newSnapshot
            shouldRepeat = pendingEnvironmentRefresh
        }
        isRefreshingEnvironment = false
    }

    // MARK: - Computed navigation

    var activeProfile: EnvProfile? {
        payload.activeProfile
    }

    var activeProfileID: UUID? {
        payload.activeProfileID
    }

    var selectedProfile: EnvProfile? {
        guard let id = selection.profileID else { return nil }
        return payload.profile(id: id)
    }

    var activeProfileNeedsApply: Bool {
        guard let active = payload.activeProfile else { return false }
        let fingerprint: String
        if let cache = activeFingerprintCache, cache.id == active.id {
            fingerprint = cache.value
        } else {
            fingerprint = active.fingerprint()
            activeFingerprintCache = (active.id, fingerprint)
        }
        return fingerprint != payload.appliedFingerprint
    }

    private func refreshActiveFingerprintCache() {
        if let active = payload.activeProfile {
            activeFingerprintCache = (active.id, active.fingerprint())
        } else {
            activeFingerprintCache = nil
        }
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var vaultFileURL: URL {
        store.fileURL
    }

    var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(_ candidates: [String]) -> Bool {
        guard !normalizedSearch.isEmpty else { return true }
        return candidates.contains {
            $0.range(of: normalizedSearch, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var visibleSystemVariables: [SystemVariable] {
        guard let snapshot else { return [] }
        return snapshot.variables.filter { variable in
            if !payload.settings.showInternalVariables && variable.isInternal { return false }
            if filter == .sensitive && !variable.isSensitive { return false }
            return matchesSearch([variable.key, variable.value])
        }
    }

    var visibleProfileVariables: [EnvVariable] {
        guard let profile = selectedProfile else { return [] }
        return profile.sortedVariables.filter { variable in
            switch filter {
            case .enabled where !variable.isEnabled: return false
            case .disabled where variable.isEnabled: return false
            case .sensitive where !variable.isSecret: return false
            default: break
            }
            return matchesSearch([variable.key, variable.value, variable.note])
        }
    }

    var totalSystemCount: Int {
        snapshot?.variables.count ?? 0
    }

    func select(_ newSelection: SidebarSelection) {
        guard selection != newSelection else { return }
        selection = newSelection
        searchText = ""
        if case .system = newSelection, filter != .all && filter != .sensitive {
            filter = .all
        }
        if case .profile = newSelection, filter == .sensitive {
            filter = .all
        }
    }

    func isActive(profileID: UUID) -> Bool {
        payload.activeProfileID == profileID
    }

    // MARK: - Reveal and copy

    func isRevealed(system variable: SystemVariable) -> Bool {
        if !variable.isSensitive { return true }
        if revealAllSensitive || !payload.settings.concealSensitiveValues { return true }
        return revealedKeys.contains("system:\(variable.key)")
    }

    func isRevealed(profile variable: EnvVariable) -> Bool {
        if !variable.isSecret { return true }
        if revealAllSensitive || !payload.settings.concealSensitiveValues { return true }
        return revealedKeys.contains("variable:\(variable.id.uuidString)")
    }

    func toggleReveal(system variable: SystemVariable) {
        let key = "system:\(variable.key)"
        if revealedKeys.contains(key) { revealedKeys.remove(key) } else { revealedKeys.insert(key) }
    }

    func toggleReveal(profile variable: EnvVariable) {
        let key = "variable:\(variable.id.uuidString)"
        if revealedKeys.contains(key) { revealedKeys.remove(key) } else { revealedKeys.insert(key) }
    }

    func concealSensitiveValues() {
        revealAllSensitive = false
        revealedKeys.removeAll()
    }

    func hideAllSensitiveValues() {
        concealSensitiveValues()
        showToast("已隐藏所有敏感值", style: .info)
    }

    func copyKeyToClipboard(_ key: String) {
        ClipboardService.shared.copy(key, clearAfter: nil)
        showToast("已复制变量名", style: .success)
    }

    func copyToClipboard(_ value: String, sensitive: Bool) {
        let autoClear = sensitive && payload.settings.autoClearSensitiveClipboard
        ClipboardService.shared.copy(value, clearAfter: autoClear ? 45 : nil, concealed: sensitive)
        showToast(
            autoClear ? "已复制，45 秒后自动清除" : "已复制到剪贴板",
            style: .success
        )
    }

    // MARK: - Profile editing

    func presentNewProfile(prefillSystem: Bool = false) {
        guard isVaultUnlocked else {
            showAlert(title: "配置库未解锁", message: EnvBoxError.vaultLocked.localizedDescription)
            return
        }
        sheet = SheetRoute(kind: .newProfile(prefillSystem: prefillSystem))
    }

    func presentEditProfile(_ profileID: UUID) {
        sheet = SheetRoute(kind: .editProfile(profileID))
    }

    func presentVariableEditor(profileID: UUID, variable: EnvVariable? = nil) {
        sheet = SheetRoute(kind: .variable(profileID: profileID, variable: variable))
    }

    @discardableResult
    func createProfile(
        name: String,
        note: String,
        tint: ProfileTint,
        symbol: String,
        includeSystemEnvironment: Bool
    ) throws -> UUID {
        guard isVaultUnlocked else { throw EnvBoxError.vaultLocked }
        guard payload.profiles.count < VaultPayload.maxProfiles else { throw EnvBoxError.tooManyProfiles }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateUniqueProfileName(trimmedName)
        guard trimmedName.count <= EnvProfile.maxNameLength else { throw EnvBoxError.profileNameTooLong }
        guard note.count <= EnvVariable.maxNoteLength else { throw EnvBoxError.noteTooLong }

        var variables: [EnvVariable] = []
        if includeSystemEnvironment, let snapshot {
            variables = snapshot.variables
                .filter { payload.settings.showInternalVariables || !$0.isInternal }
                .prefix(EnvProfile.maxVariables)
                .map {
                    EnvVariable(
                        key: $0.key,
                        value: $0.value,
                        isEnabled: true,
                        isSecret: $0.isSensitive
                    )
                }
        }

        let profile = EnvProfile(
            name: trimmedName,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            tint: tint,
            symbol: symbol,
            variables: variables
        ).normalized
        try EnvBoxValidation.validate(profile: profile)
        payload.profiles.append(profile)
        payload.touch()
        selection = .profile(profile.id)
        searchText = ""
        filter = .all
        scheduleSave()
        showToast("配置已创建", style: .success)
        return profile.id
    }

    func updateProfileMetadata(
        profileID: UUID,
        name: String,
        note: String,
        tint: ProfileTint,
        symbol: String
    ) throws {
        guard isVaultUnlocked else { throw EnvBoxError.vaultLocked }
        guard let index = payload.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw EnvBoxError.invalidArchive
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateUniqueProfileName(trimmedName, excluding: profileID)
        guard trimmedName.count <= EnvProfile.maxNameLength else { throw EnvBoxError.profileNameTooLong }
        guard note.count <= EnvVariable.maxNoteLength else { throw EnvBoxError.noteTooLong }

        var profile = payload.profiles[index]
        profile.name = trimmedName
        profile.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.tint = tint
        profile.symbol = symbol
        profile.updatedAt = Date()
        try EnvBoxValidation.validate(profile: profile)
        payload.profiles[index] = profile.normalized
        payload.touch()
        scheduleSave()
    }

    func duplicateProfile(_ profileID: UUID) {
        guard isVaultUnlocked else { return }
        guard payload.profiles.count < VaultPayload.maxProfiles else {
            showAlert(title: "无法复制", message: EnvBoxError.tooManyProfiles.localizedDescription)
            return
        }
        guard let source = payload.profile(id: profileID) else { return }
        var copy = source
        copy.id = UUID()
        copy.name = EnvBoxValidation.uniqueProfileName(source.name + " 副本", existing: payload.profiles)
        copy.variables = source.variables.map { variable in
            var item = variable
            item.id = UUID()
            return item
        }
        copy.createdAt = Date()
        copy.updatedAt = Date()
        payload.profiles.append(copy)
        payload.touch()
        selection = .profile(copy.id)
        scheduleSave()
        showToast("已复制配置", style: .success)
    }

    func deleteProfile(_ profileID: UUID) async {
        guard isVaultUnlocked else { return }
        guard payload.profile(id: profileID) != nil else { return }
        if payload.activeProfileID == profileID {
            do {
                try await deactivateActiveProfile(showSuccessToast: false)
            } catch {
                showAlert(title: "无法删除已启用的配置", message: error.localizedDescription)
                return
            }
        }
        payload.profiles.removeAll { $0.id == profileID }
        if selection == .profile(profileID) {
            selection = .system
        }
        payload.touch()
        scheduleSave()
        showToast("配置已删除", style: .info)
        if selection == .system {
            Task { await refreshSystemEnvironment() }
        }
    }

    // MARK: - Variable editing

    func saveVariable(_ variable: EnvVariable, profileID: UUID) throws {
        guard isVaultUnlocked else { throw EnvBoxError.vaultLocked }
        guard let profileIndex = payload.profiles.firstIndex(where: { $0.id == profileID }) else {
            throw EnvBoxError.invalidArchive
        }
        var profile = payload.profiles[profileIndex]
        var normalized = variable
        normalized.key = variable.trimmedKey
        normalized.note = String(variable.note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(EnvVariable.maxNoteLength))

        try EnvBoxValidation.validateKey(normalized.key)
        try EnvBoxValidation.validateValue(normalized.value, key: normalized.key)

        if let existingIndex = profile.variables.firstIndex(where: { $0.id == normalized.id }) {
            profile.variables[existingIndex] = normalized
        } else {
            guard profile.variables.count < EnvProfile.maxVariables else { throw EnvBoxError.tooManyVariables }
            profile.variables.append(normalized)
        }
        try EnvBoxValidation.validate(profile: profile)
        profile.updatedAt = Date()
        payload.profiles[profileIndex] = profile
        payload.touch()
        scheduleSave()
    }

    func deleteVariable(_ variableID: UUID, profileID: UUID) {
        guard isVaultUnlocked else { return }
        guard let profileIndex = payload.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        payload.profiles[profileIndex].variables.removeAll { $0.id == variableID }
        payload.profiles[profileIndex].updatedAt = Date()
        payload.touch()
        scheduleSave()
    }

    func toggleVariable(_ variableID: UUID, profileID: UUID) {
        guard isVaultUnlocked else { return }
        guard let profileIndex = payload.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        guard let variableIndex = payload.profiles[profileIndex].variables.firstIndex(where: { $0.id == variableID }) else { return }
        payload.profiles[profileIndex].variables[variableIndex].isEnabled.toggle()
        payload.profiles[profileIndex].updatedAt = Date()
        payload.touch()
        scheduleSave()
    }

    func variable(_ variableID: UUID, in profileID: UUID) -> EnvVariable? {
        payload.profile(id: profileID)?.variables.first(where: { $0.id == variableID })
    }

    @discardableResult
    func importSystemVariables(into profileID: UUID) -> Int {
        guard isVaultUnlocked else { return 0 }
        guard let profileIndex = payload.profiles.firstIndex(where: { $0.id == profileID }) else { return 0 }
        guard let snapshot else {
            showAlert(title: "暂无系统快照", message: "请先返回系统环境页面刷新一次。")
            return 0
        }
        var profile = payload.profiles[profileIndex]
        let existingKeys = Set(profile.variables.map(\.key))
        let remaining = EnvProfile.maxVariables - profile.variables.count
        guard remaining > 0 else {
            showAlert(title: "无法导入", message: EnvBoxError.tooManyVariables.localizedDescription)
            return 0
        }
        let candidates = snapshot.variables
            .filter { (payload.settings.showInternalVariables || !$0.isInternal) && !existingKeys.contains($0.key) }
            .prefix(remaining)
        guard !candidates.isEmpty else {
            showToast("当前系统变量已全部包含在此配置中", style: .info)
            return 0
        }
        profile.variables.append(contentsOf: candidates.map { variable in
            EnvVariable(
                key: variable.key,
                value: variable.value,
                isEnabled: true,
                isSecret: variable.isSensitive
            )
        })
        profile.updatedAt = Date()
        payload.profiles[profileIndex] = profile
        payload.touch()
        scheduleSave()
        showToast("已从系统环境补充 \(candidates.count) 个变量", style: .success)
        return candidates.count
    }

    private func validateUniqueProfileName(_ name: String, excluding id: UUID? = nil) throws {
        guard !name.isEmpty else { throw EnvBoxError.emptyProfileName }
        let collision = payload.profiles.contains {
            $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if collision { throw EnvBoxError.duplicateProfileName(name) }
    }

    // MARK: - Applying profiles

    func requestApply(_ profileID: UUID) {
        guard isVaultUnlocked else {
            showAlert(title: "配置库未解锁", message: EnvBoxError.vaultLocked.localizedDescription)
            return
        }
        guard let profile = payload.profile(id: profileID) else { return }
        if isActive(profileID: profileID), payload.appliedFingerprint == profile.fingerprint() {
            showToast("该配置已在当前 Mac 上生效", style: .info)
            return
        }
        if !payload.settings.hasCompletedFirstApply {
            sheet = SheetRoute(kind: .firstApply(profileID))
            return
        }
        Task { await applyProfile(profileID) }
    }

    func confirmFirstApply(_ profileID: UUID) {
        sheet = nil
        Task { await applyProfile(profileID) }
    }

    private func applyProfile(_ profileID: UUID) async {
        guard !isApplying else { return }
        isApplying = true
        applyingProfileID = profileID
        do {
            let report = try await performActivation(profileID: profileID)
            isApplying = false
            applyingProfileID = nil
            if let warning = report.warnings.first {
                showToast(warning, style: .warning)
            } else {
                showToast("配置已应用", style: .success)
            }
            Task { await refreshSystemEnvironment() }
        } catch {
            isApplying = false
            applyingProfileID = nil
            showAlert(title: "应用配置失败", message: error.localizedDescription)
        }
    }

    @discardableResult
    private func performActivation(profileID: UUID) async throws -> ActivationReport {
        guard isVaultUnlocked else { throw EnvBoxError.vaultLocked }
        guard let profile = payload.profile(id: profileID) else { throw EnvBoxError.invalidArchive }
        let report = try await activationService.activate(
            profile: profile,
            previousAppliedKeys: payload.appliedKeys,
            writeShellActivation: shouldWriteShellActivation
        )
        payload.activeProfileID = profile.id
        payload.appliedKeys = report.appliedKeys
        let fingerprint = profile.fingerprint()
        payload.appliedFingerprint = fingerprint
        activeFingerprintCache = (profile.id, fingerprint)
        payload.settings.hasCompletedFirstApply = true
        payload.settings.hasAcknowledgedRestartHint = false
        payload.touch()
        hasUnsavedChanges = true
        let saved = await flush()
        var warnings = report.warnings
        if !saved {
            warnings.append("环境已写入，但加密配置库保存失败。请检查 Keychain 权限后使用侧边栏的“重试保存”。")
        }
        return ActivationReport(
            appliedKeys: report.appliedKeys,
            staleKeys: report.staleKeys,
            activationScriptURL: report.activationScriptURL,
            warnings: warnings
        )
    }

    func quickSwitch(_ profileID: UUID) async {
        menuActionError = nil
        guard !isApplying else { return }
        guard let profile = payload.profile(id: profileID) else { return }
        if isActive(profileID: profileID), payload.appliedFingerprint == profile.fingerprint() {
            return
        }
        isApplying = true
        applyingProfileID = profileID
        do {
            let report = try await performActivation(profileID: profileID)
            isApplying = false
            applyingProfileID = nil
            menuActionError = report.warnings.first
            Task { await refreshSystemEnvironment() }
        } catch {
            isApplying = false
            applyingProfileID = nil
            menuActionError = error.localizedDescription
        }
    }

    func reapplyActiveProfile() {
        guard let id = payload.activeProfileID, !isApplying else { return }
        Task { await applyProfile(id) }
    }

    func requestDeactivate() {
        guard activeProfile != nil && !isApplying else { return }
        Task {
            do {
                try await deactivateActiveProfile(showSuccessToast: true)
            } catch {
                showAlert(title: "停用配置失败", message: error.localizedDescription)
            }
        }
    }

    private func deactivateActiveProfile(showSuccessToast: Bool) async throws {
        guard isVaultUnlocked else { throw EnvBoxError.vaultLocked }
        isApplying = true
        do {
            try await activationService.deactivate(keys: payload.appliedKeys)
        } catch {
            isApplying = false
            throw error
        }
        payload.activeProfileID = nil
        payload.appliedKeys = []
        payload.appliedFingerprint = nil
        activeFingerprintCache = nil
        payload.touch()
        isApplying = false
        applyingProfileID = nil
        hasUnsavedChanges = true
        let saved = await flush()
        if showSuccessToast {
            if saved {
                showToast("已停用当前配置", style: .info)
            } else {
                showToast("已停用，但状态尚未保存；请检查 Keychain 后重试保存", style: .warning)
            }
        }
        Task { await refreshSystemEnvironment() }
    }

    private func restoreActiveProfile() async {
        guard let profile = payload.activeProfile else { return }
        do {
            let report = try await activationService.activate(
                profile: profile,
                previousAppliedKeys: payload.appliedKeys,
                writeShellActivation: shouldWriteShellActivation
            )
            payload.appliedKeys = report.appliedKeys
            payload.appliedFingerprint = profile.fingerprint()
            payload.touch()
            scheduleSave()
            if let warning = report.warnings.first {
                showToast("自动恢复配置时出现警告：\(warning)", style: .warning)
            }
        } catch {
            showToast("无法自动恢复上次的配置：\(error.localizedDescription)", style: .warning)
        }
    }

    // MARK: - Shell integration

    func setShellIntegration(_ enabled: Bool) async {
        guard requireVaultUnlocked() else { return }
        guard !isTogglingShellIntegration else { return }
        isTogglingShellIntegration = true
        do {
            if enabled {
                try await shellIntegration.install()
                var warning: String?
                if let profile = activeProfile {
                    do {
                        _ = try await shellIntegration.writeActivationScript(profile: profile, staleKeys: [])
                    } catch {
                        warning = "Shell 集成已写入，但激活文件更新失败：\(error.localizedDescription)"
                    }
                }
                shellStatus = await shellIntegration.status()
                payload.settings.shellIntegrationEnabled = true
                payload.touch()
                scheduleSave()
                if let warning {
                    showToast(warning, style: .warning)
                } else {
                    showToast("Zsh 集成已启用，新终端会自动载入配置", style: .success)
                }
            } else {
                try await shellIntegration.uninstall()
                var warning: String?
                do {
                    try await shellIntegration.removeActivationScript()
                } catch {
                    warning = "集成已移除，但明文激活脚本删除失败：\(error.localizedDescription)"
                }
                shellStatus = await shellIntegration.status()
                payload.settings.shellIntegrationEnabled = false
                payload.touch()
                scheduleSave()
                if let warning {
                    showToast(warning, style: .warning)
                } else {
                    showToast("Zsh 集成与明文激活脚本已移除", style: .success)
                }
            }
        } catch {
            showAlert(title: "Shell 集成失败", message: error.localizedDescription)
        }
        isTogglingShellIntegration = false
    }

    func refreshShellStatus() async {
        shellStatus = await shellIntegration.status()
    }

    private var shouldWriteShellActivation: Bool {
        payload.settings.shellIntegrationEnabled && (shellStatus?.isInstalled ?? false)
    }

    // MARK: - MCP

    var mcpEnabled: Bool { payload.settings.mcpEnabled }
    var mcpAllowReveal: Bool { payload.settings.mcpAllowReveal }
    var mcpHelperPath: String { MCPHelper.executablePath() }

    func setMCPEnabled(_ enabled: Bool) {
        guard requireVaultUnlocked() else { return }
        payload.settings.mcpEnabled = enabled
        syncMCPPolicy()
        payload.touch()
        scheduleSave()
        showToast(enabled ? "MCP 已启用" : "MCP 已关闭", style: enabled ? .success : .info)
    }

    func setMCPAllowReveal(_ allowed: Bool) {
        guard requireVaultUnlocked() else { return }
        payload.settings.mcpAllowReveal = allowed
        syncMCPPolicy()
        payload.touch()
        scheduleSave()
        showToast(allowed ? "env_reveal 已启用" : "env_reveal 已关闭", style: allowed ? .warning : .info)
    }

    func mcpSnippet(for client: MCPClient) -> String {
        client.snippet(helperPath: mcpHelperPath)
    }

    func copyMCPSnippet(for client: MCPClient) {
        ClipboardService.shared.copy(mcpSnippet(for: client), clearAfter: nil)
        showToast("已复制配置", style: .success)
    }

    func copyMCPPrompt(for client: MCPClient) {
        ClipboardService.shared.copy(client.prompt(helperPath: mcpHelperPath), clearAfter: nil)
        showToast("已复制提示词", style: .success)
    }

    private func syncMCPPolicy() {
        let policy = MCPPolicy(enabled: payload.settings.mcpEnabled, allowReveal: payload.settings.mcpAllowReveal)
        try? policy.write()
    }

    // MARK: - Login item

    var launchAtLogin: Bool { payload.settings.launchAtLogin }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            payload.settings.launchAtLogin = enabled
            payload.touch()
            scheduleSave()
            showToast(enabled ? "登录时启动已启用" : "登录时启动已关闭", style: .success)
        } catch {
            showAlert(title: "无法修改登录项", message: error.localizedDescription)
        }
    }

    private func syncLoginItem() {
        guard payload.settings.launchAtLogin, LoginItemService.isAvailable else { return }
        if !LoginItemService.isEnabled {
            try? LoginItemService.setEnabled(true)
        }
    }

    // MARK: - Restart hint

    var showsRestartHint: Bool {
        payload.settings.hasCompletedFirstApply
            && !payload.settings.hasAcknowledgedRestartHint
            && !payload.appliedKeys.isEmpty
    }

    func acknowledgeRestartHint() {
        payload.settings.hasAcknowledgedRestartHint = true
        payload.touch()
        scheduleSave()
    }

    // MARK: - Settings

    private func requireVaultUnlocked() -> Bool {
        guard isVaultUnlocked else {
            showAlert(title: "配置库未解锁", message: EnvBoxError.vaultLocked.localizedDescription)
            return false
        }
        return true
    }

    func setAutoRestore(_ value: Bool) {
        guard requireVaultUnlocked() else { return }
        guard payload.settings.autoRestoreActiveProfile != value else { return }
        payload.settings.autoRestoreActiveProfile = value
        payload.touch()
        scheduleSave()
    }

    func setIncludeLoginShell(_ value: Bool) {
        guard requireVaultUnlocked() else { return }
        guard payload.settings.includeLoginShellEnvironment != value else { return }
        payload.settings.includeLoginShellEnvironment = value
        payload.touch()
        scheduleSave()
        Task { await refreshSystemEnvironment() }
    }

    func setShowInternalVariables(_ value: Bool) {
        guard requireVaultUnlocked() else { return }
        guard payload.settings.showInternalVariables != value else { return }
        payload.settings.showInternalVariables = value
        payload.touch()
        scheduleSave()
    }

    func setConcealSensitiveValues(_ value: Bool) {
        guard requireVaultUnlocked() else { return }
        guard payload.settings.concealSensitiveValues != value else { return }
        payload.settings.concealSensitiveValues = value
        if value { revealAllSensitive = false }
        payload.touch()
        scheduleSave()
    }

    func setAutoClearSensitiveClipboard(_ value: Bool) {
        guard requireVaultUnlocked() else { return }
        guard payload.settings.autoClearSensitiveClipboard != value else { return }
        payload.settings.autoClearSensitiveClipboard = value
        payload.touch()
        scheduleSave()
    }

    // MARK: - Import and export

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入 EnvBox 加密配置"
        panel.message = "选择一个 .envbox 配置文件"
        panel.allowedContentTypes = [.envBoxConfiguration]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await prepareImport(from: url) }
    }

    func handleOpenURL(_ url: URL) {
        let path = url.standardizedFileURL.path
        if lastImportRequestPath == path,
           let lastImportRequestDate,
           Date().timeIntervalSince(lastImportRequestDate) < 3 {
            return
        }
        lastImportRequestPath = path
        lastImportRequestDate = Date()
        Task { await prepareImport(from: url) }
    }

    private func prepareImport(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > EnvBoxValidation.maxVaultFileBytes {
                throw EnvBoxError.fileTooLarge
            }
            let data = try SafeFileReader.readData(at: url, maxBytes: EnvBoxValidation.maxVaultFileBytes)
            sheet = SheetRoute(
                kind: .transfer(
                    TransferRoute(mode: .importFile(name: url.lastPathComponent, data: data))
                )
            )
        } catch {
            showAlert(title: "无法读取文件", message: error.localizedDescription)
        }
    }

    func presentExport(profileIDs: [UUID], title: String) {
        guard isVaultUnlocked else {
            showAlert(title: "配置库未解锁", message: EnvBoxError.vaultLocked.localizedDescription)
            return
        }
        let validIDs = profileIDs.filter { payload.profile(id: $0) != nil }
        guard !validIDs.isEmpty else { return }
        sheet = SheetRoute(
            kind: .transfer(
                TransferRoute(mode: .export(profileIDs: validIDs, title: title))
            )
        )
    }

    func presentExportAll() {
        presentExport(profileIDs: payload.profiles.map(\.id), title: "全部配置")
    }

    func exportConfiguration(profileIDs: [UUID], passphrase: String) async throws -> URL? {
        let profiles = profileIDs.compactMap { payload.profile(id: $0) }
        guard !profiles.isEmpty else { throw EnvBoxError.invalidArchive }
        let panel = NSSavePanel()
        panel.title = "导出 EnvBox 加密配置"
        panel.message = "配置文件使用你设置的密码加密，密码不会保存在磁盘上。"
        panel.allowedContentTypes = [.envBoxConfiguration]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = Self.exportFileName(for: profiles)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = try await transferService.exportConfiguration(
            profiles: profiles,
            passphrase: passphrase
        )
        do {
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
        showToast("加密配置已导出", style: .success)
        return url
    }

    @discardableResult
    func importConfiguration(data: Data, passphrase: String) async throws -> Int {
        guard isVaultUnlocked else { throw EnvBoxError.vaultLocked }
        let portable = try await transferService.importConfiguration(from: data, passphrase: passphrase)
        guard payload.profiles.count + portable.profiles.count <= VaultPayload.maxProfiles else {
            throw EnvBoxError.tooManyProfiles
        }

        var usedIDs = Set(payload.profiles.map(\.id))
        var workingProfiles = payload.profiles
        var importedProfiles: [EnvProfile] = []
        let now = Date()

        for original in portable.profiles {
            var profile = original.normalized
            if usedIDs.contains(profile.id) { profile.id = UUID() }
            usedIDs.insert(profile.id)
            profile.name = EnvBoxValidation.uniqueProfileName(profile.name, existing: workingProfiles)
            profile.variables = profile.variables.map { variable in
                var item = variable
                item.id = UUID()
                return item
            }
            profile.createdAt = now
            profile.updatedAt = now
            workingProfiles.append(profile)
            importedProfiles.append(profile)
        }

        guard let first = importedProfiles.first else { return 0 }
        payload.profiles.append(contentsOf: importedProfiles)
        payload.touch()
        selection = .profile(first.id)
        searchText = ""
        filter = .all
        hasUnsavedChanges = true
        let saved = await flush()
        if saved {
            showToast("已导入 \(importedProfiles.count) 个配置", style: .success)
        } else {
            showToast("配置已载入内存，但保存失败；请检查 Keychain 后重试保存", style: .warning)
        }
        return importedProfiles.count
    }

    private static func exportFileName(for profiles: [EnvProfile]) -> String {
        if profiles.count == 1, let profile = profiles.first {
            return EnvBoxValidation.sanitizedExportFileName(profile.name) + ".envbox"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "EnvBox-Configs-\(formatter.string(from: Date())).envbox"
    }

    // MARK: - Persistence

    func scheduleSave() {
        guard isVaultUnlocked else { return }
        refreshActiveFingerprintCache()
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    @discardableResult
    func saveNow(force: Bool = false) async -> Bool {
        guard isVaultUnlocked else { return true }
        if !force && !hasUnsavedChanges { return true }
        if isSavingNow {
            needsAnotherSave = true
            return false
        }
        hasUnsavedChanges = true
        saveTask = nil
        isSavingNow = true
        saveState = .saving

        repeat {
            needsAnotherSave = false
            let snapshot = payload
            do {
                try await store.save(snapshot)
                saveState = .saved(Date())
                if payload == snapshot {
                    hasUnsavedChanges = false
                } else {
                    needsAnotherSave = true
                }
            } catch {
                saveState = .failed(error.localizedDescription)
                isSavingNow = false
                showAlert(title: "保存失败", message: error.localizedDescription)
                return false
            }
        } while needsAnotherSave

        isSavingNow = false
        return true
    }

    /// Flushes pending edits before application termination. Returns false if the vault could not be saved.
    func flush() async -> Bool {
        guard isVaultUnlocked else { return true }
        saveTask?.cancel()
        saveTask = nil
        var attempts = 0
        while isSavingNow && attempts < 100 {
            needsAnotherSave = true
            try? await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }
        if isSavingNow { return false }
        return await saveNow()
    }

    // MARK: - Misc

    func showToast(_ text: String, style: ToastStyle = .info) {
        toast = ToastMessage(text: text, style: style)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func showAlert(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    func openVaultFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([vaultFileURL])
    }

    func openGitHub() {
        if let url = URL(string: "https://github.com/Ohhu/EnvBox") {
            NSWorkspace.shared.open(url)
        }
    }

    func clearMenuError() {
        menuActionError = nil
    }
}
