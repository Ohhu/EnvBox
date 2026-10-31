import Foundation
import CryptoKit
@testable import EnvBoxCore

final class StaticKeyProvider: VaultKeyProviding, @unchecked Sendable {
    private(set) var key: VaultKey
    private(set) var createCount = 0

    init(key: VaultKey? = nil) {
        self.key = key ?? VaultKey(id: "test-key", key: SymmetricKey(size: .bits256))
    }

    func existingKey() throws -> VaultKey? { key }

    func loadOrCreateKey() throws -> VaultKey {
        createCount += 1
        return key
    }
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("EnvBoxTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func sampleProfile(name: String = "开发环境", variables: [EnvVariable]? = nil) -> EnvProfile {
    EnvProfile(
        name: name,
        note: "测试配置",
        tint: .aurora,
        variables: variables ?? [
            EnvVariable(key: "API_BASE_URL", value: "https://example.test", isEnabled: true),
            EnvVariable(key: "API_TOKEN", value: "secret'with $pecial\nvalue", isEnabled: true, isSecret: true),
            EnvVariable(key: "DISABLED_FLAG", value: "1", isEnabled: false)
        ]
    )
}
