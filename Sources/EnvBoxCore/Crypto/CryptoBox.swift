import CryptoKit
import Foundation
import Security

public enum CryptoBox {
    public static func vaultAAD(keyID: String) -> Data {
        Data("EnvBox.Vault.v1|keyID=\(keyID)".utf8)
    }

    public static func exportAAD(
        format: String,
        version: Int,
        kdf: String,
        iterations: Int,
        salt: Data
    ) -> Data {
        let header = [
            "EnvBox.Export.v1",
            "format=\(format)",
            "version=\(version)",
            "kdf=\(kdf)",
            "iterations=\(iterations)",
            "salt=\(salt.base64EncodedString())"
        ].joined(separator: "|")
        return Data(header.utf8)
    }

    public static func randomKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    public static func randomSalt(byteCount: Int = 16) throws -> Data {
        guard byteCount > 0, byteCount <= 64 else { throw EnvBoxError.invalidArchive }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw EnvBoxError.invalidArchive }
        return Data(bytes)
    }

    public static func seal(_ plaintext: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
            guard let combined = box.combined else { throw EnvBoxError.invalidArchive }
            return combined
        } catch let error as EnvBoxError {
            throw error
        } catch {
            throw EnvBoxError.invalidArchive
        }
    }

    public static func open(_ sealed: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw EnvBoxError.incorrectPassphrase
        }
    }
}
