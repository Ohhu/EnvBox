import CryptoKit
import Foundation
import Testing
@testable import EnvBoxCore

@Suite("Crypto and transfer")
struct CryptoAndTransferTests {
    private let iterations = PasswordKDF.minimumAcceptedIterations

    @Test func sealOpenAndTamperDetection() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello".utf8)
        let aad = Data("test-aad".utf8)
        let sealed = try CryptoBox.seal(plaintext, key: key, aad: aad)
        #expect(try CryptoBox.open(sealed, key: key, aad: aad) == plaintext)

        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        #expect(throws: (any Error).self) {
            _ = try CryptoBox.open(tampered, key: key, aad: aad)
        }
        #expect(throws: (any Error).self) {
            _ = try CryptoBox.open(sealed, key: key, aad: Data("other-aad".utf8))
        }
    }

    @Test func deriveKeyIsDeterministic() throws {
        let salt = Data(repeating: 7, count: 16)
        let first = try PasswordKDF.deriveKey(passphrase: "correct horse battery", salt: salt, iterations: iterations)
        let second = try PasswordKDF.deriveKey(passphrase: "correct horse battery", salt: salt, iterations: iterations)
        let third = try PasswordKDF.deriveKey(passphrase: "correct horse battery!", salt: salt, iterations: iterations)
        #expect(first.withUnsafeBytes { Data($0) } == second.withUnsafeBytes { Data($0) })
        #expect(first.withUnsafeBytes { Data($0) } != third.withUnsafeBytes { Data($0) })
    }

    @Test func exportRoundTripAndWrongPassphrase() async throws {
        let service = ConfigTransferService()
        let profile = sampleProfile()
        let passphrase = "very-secret-passphrase"
        let data = try await service.exportConfiguration(profiles: [profile], passphrase: passphrase, iterations: iterations)
        let imported = try await service.importConfiguration(from: data, passphrase: passphrase)
        #expect(imported.profiles.count == 1)
        #expect(imported.profiles[0].variables == profile.variables)

        do {
            _ = try await service.importConfiguration(from: data, passphrase: "wrong-passphrase")
            Issue.record("Expected wrong passphrase failure")
        } catch {
            #expect((error as? EnvBoxError) == .incorrectPassphrase)
        }
    }

    @Test func exportTamperingRejected() async throws {
        let service = ConfigTransferService()
        let data = try await service.exportConfiguration(
            profiles: [sampleProfile()],
            passphrase: "very-secret-passphrase",
            iterations: iterations
        )
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sealedString = try #require(object["sealed"] as? String)
        var sealed = try #require(Data(base64Encoded: sealedString))
        sealed[sealed.count / 2] ^= 0x01
        object["sealed"] = sealed.base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object)

        do {
            _ = try await service.importConfiguration(from: tampered, passphrase: "very-secret-passphrase")
            Issue.record("Expected tamper failure")
        } catch {
            #expect((error as? EnvBoxError) == .incorrectPassphrase)
        }
    }

    @Test func exportMetadataIsAuthenticatedByAAD() async throws {
        let service = ConfigTransferService()
        let data = try await service.exportConfiguration(
            profiles: [sampleProfile()],
            passphrase: "very-secret-passphrase",
            iterations: iterations
        )
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["iterations"] = iterations + 1
        let tampered = try JSONSerialization.data(withJSONObject: object)

        do {
            _ = try await service.importConfiguration(from: tampered, passphrase: "very-secret-passphrase")
            Issue.record("Expected metadata tamper failure")
        } catch {
            #expect((error as? EnvBoxError) == .incorrectPassphrase)
        }
    }

    @Test func shortPassphraseRejected() async {
        let service = ConfigTransferService()
        do {
            _ = try await service.exportConfiguration(profiles: [sampleProfile()], passphrase: "short")
            Issue.record("Expected short passphrase failure")
        } catch {
            #expect((error as? EnvBoxError) == .passphraseTooShort)
        }
    }
}
