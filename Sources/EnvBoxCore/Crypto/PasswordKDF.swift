import CommonCrypto
import CryptoKit
import Foundation

public enum PasswordKDF {
    /// 600k PBKDF2-HMAC-SHA256 iterations is a deliberately expensive default for a desktop app.
    public static let defaultIterations = 600_000
    public static let minimumAcceptedIterations = 100_000
    public static let maximumIterations = 2_000_000
    public static let saltByteCount = 16
    public static let keyByteCount = 32

    public static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard iterations >= minimumAcceptedIterations, iterations <= maximumIterations else {
            throw EnvBoxError.invalidArchive
        }
        guard salt.count >= 16, salt.count <= 64 else { throw EnvBoxError.invalidArchive }
        let normalized = passphrase.precomposedStringWithCanonicalMapping
        let passwordBytes = Data(normalized.utf8)
        var derived = Data(count: keyByteCount)

        let status: Int32 = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordBytes.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                        passwordBytes.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBuffer.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw EnvBoxError.invalidArchive
        }
        return SymmetricKey(data: derived)
    }
}
