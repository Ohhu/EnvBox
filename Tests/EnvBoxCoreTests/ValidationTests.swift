import Testing
@testable import EnvBoxCore

@Suite("Validation")
struct ValidationTests {
    @Test func validKeys() {
        #expect(EnvBoxValidation.isValidKey("PATH"))
        #expect(EnvBoxValidation.isValidKey("_PRIVATE"))
        #expect(EnvBoxValidation.isValidKey("A1_b2"))
        #expect(!EnvBoxValidation.isValidKey(""))
        #expect(!EnvBoxValidation.isValidKey("1ABC"))
        #expect(!EnvBoxValidation.isValidKey("WITH-DASH"))
        #expect(!EnvBoxValidation.isValidKey("WITH SPACE"))
        #expect(!EnvBoxValidation.isValidKey("中文"))
    }

    @Test func duplicateKeysRejected() {
        let variables = [
            EnvVariable(key: "A", value: "1"),
            EnvVariable(key: "A", value: "2")
        ]
        do {
            try EnvBoxValidation.validateNoDuplicateKeys(variables)
            Issue.record("Expected duplicate key failure")
        } catch {
            #expect((error as? EnvBoxError) == .duplicateKey("A"))
        }
    }

    @Test func profileValidationRejectsNULAndOversizeValues() {
        var variable = EnvVariable(key: "TOKEN", value: "a\0b")
        do {
            try EnvBoxValidation.validate(profile: EnvProfile(name: "x", variables: [variable]))
            Issue.record("Expected NUL failure")
        } catch {
            #expect((error as? EnvBoxError) == .valueContainsNUL)
        }
        variable.value = String(repeating: "a", count: EnvVariable.maxValueBytes + 1)
        do {
            try EnvBoxValidation.validate(profile: EnvProfile(name: "x", variables: [variable]))
            Issue.record("Expected oversize failure")
        } catch {
            #expect((error as? EnvBoxError) == .valueTooLong("TOKEN"))
        }
    }

    @Test func uniqueNames() {
        let existing = [EnvProfile(name: "Work"), EnvProfile(name: "Work 2")]
        #expect(EnvBoxValidation.uniqueProfileName("Work", existing: existing) == "Work 3")
        #expect(EnvBoxValidation.uniqueProfileName("Home", existing: existing) == "Home")
    }

    @Test func sensitivityHeuristics() {
        #expect(EnvironmentSensitivity.isSensitive(key: "API_TOKEN"))
        #expect(EnvironmentSensitivity.isSensitive(key: "AWS_SECRET_ACCESS_KEY"))
        #expect(EnvironmentSensitivity.isSensitive(key: "DATABASE_PASSWORD"))
        #expect(EnvironmentSensitivity.isSensitive(key: "PRIVATE_KEY"))
        #expect(!EnvironmentSensitivity.isSensitive(key: "PATH"))
        #expect(!EnvironmentSensitivity.isSensitive(key: "SSH_AUTH_SOCK"))
        #expect(!EnvironmentSensitivity.isSensitive(key: "KEYBOARD_LAYOUT"))
    }
}
