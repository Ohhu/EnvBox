import Foundation

/// User-facing, value-safe errors. Error messages never interpolate secret values.
public enum EnvBoxError: Error, LocalizedError, Sendable, Equatable {
    case emptyKey
    case invalidKey(String)
    case duplicateKey(String)
    case emptyProfileName
    case profileNameTooLong
    case noteTooLong
    case tooManyProfiles
    case duplicateProfileName(String)
    case vaultLocked
    case tooManyVariables
    case tooManyVariablesInArchive
    case valueTooLong(String)
    case valueContainsNUL
    case invalidArchive
    case unsupportedArchiveVersion(Int)
    case fileTooLarge
    case configurationTooLarge
    case profileTooLarge
    case passphraseTooShort
    case passphraseTooLong
    case incorrectPassphrase
    case missingVaultKey
    case vaultKeyMismatch
    case keychain(Int32)
    case io(String)
    case processFailed(String)
    case shellIntegrationUnavailable
    case activationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "变量名不能为空。"
        case .invalidKey(let key):
            return "“\(key)”不是合法的环境变量名。仅支持字母、数字和下划线，且不能以数字开头。"
        case .duplicateKey(let key):
            return "变量名“\(key)”已存在。"
        case .emptyProfileName:
            return "配置名称不能为空。"
        case .profileNameTooLong:
            return "配置名称不能超过 60 个字符。"
        case .noteTooLong:
            return "备注不能超过 500 个字符。"
        case .tooManyProfiles:
            return "最多只能保存 100 个配置。"
        case .duplicateProfileName(let name):
            return "配置名称“\(name)”已存在，请换一个名称。"
        case .vaultLocked:
            return "配置库当前未解锁，无法修改或保存。"
        case .tooManyVariables:
            return "单个配置最多包含 500 个变量。"
        case .tooManyVariablesInArchive:
            return "导入文件包含过多变量，已拒绝处理。"
        case .valueTooLong(let key):
            return "变量“\(key)”的值过长，单个值不能超过 32 KB。"
        case .valueContainsNUL:
            return "变量值不能包含空字符（NUL）。"
        case .invalidArchive:
            return "文件不是有效的 EnvBox 配置文件，或已损坏。"
        case .unsupportedArchiveVersion(let version):
            return "该配置文件版本（\(version)）暂不受支持，请升级 EnvBox。"
        case .fileTooLarge:
            return "文件过大，EnvBox 已拒绝读取。"
        case .configurationTooLarge:
            return "配置数据超过安全上限，请减少变量数量或缩短变量值。"
        case .profileTooLarge:
            return "单个配置的数据量超过 512 KB，请缩短变量值或拆分配置。"
        case .passphraseTooShort:
            return "密码至少需要 8 个字符。"
        case .passphraseTooLong:
            return "密码不能超过 1024 个字符。"
        case .incorrectPassphrase:
            return "密码不正确，或文件已被篡改。"
        case .missingVaultKey:
            return "钥匙串中的 EnvBox 主密钥已丢失，无法解锁本地配置库。"
        case .vaultKeyMismatch:
            return "本地配置库与当前钥匙串密钥不匹配，无法解锁。"
        case .keychain(let status):
            return "访问 macOS 钥匙串失败（错误码 \(status)）。"
        case .io(let message):
            return "文件操作失败：\(message)"
        case .processFailed(let message):
            return "系统命令执行失败：\(message)"
        case .shellIntegrationUnavailable:
            return "当前 Shell 不是 Zsh，EnvBox 暂不支持自动集成。"
        case .activationFailed(let message):
            return "配置应用失败：\(message)"
        }
    }
}
