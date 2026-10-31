import Foundation
import Testing
@testable import EnvBoxCore

@Suite("Models")
struct ModelTests {
    @Test func fingerprintChangesWithEnabledValuesOnly() {
        var profile = sampleProfile(variables: [
            EnvVariable(key: "A", value: "1", isEnabled: true),
            EnvVariable(key: "B", value: "2", isEnabled: false)
        ])
        let original = profile.fingerprint()
        profile.variables[1].value = "3"
        #expect(profile.fingerprint() == original)
        profile.variables[0].value = "2"
        #expect(profile.fingerprint() != original)
    }

    @Test func pendingState() {
        var profile = sampleProfile()
        var payload = VaultPayload(profiles: [profile])
        payload.activeProfileID = profile.id
        payload.appliedFingerprint = profile.fingerprint()
        #expect(!payload.isActiveProfilePending)
        profile.variables[0].value = "changed"
        payload.profiles = [profile]
        #expect(payload.isActiveProfilePending)
    }

    @Test func removingManagedBlockWithMalformedMarkers() {
        let content = "before\n\(ShellIntegrationMarkers.start)\nfoo\n"
        #expect(ShellIntegrationService.hasMalformedManagedBlock(in: content))
        let lines = ShellIntegrationService.removingManagedBlock(from: content)
        #expect(lines.joined(separator: "\n") == content)
    }
}
