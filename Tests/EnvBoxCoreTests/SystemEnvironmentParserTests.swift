import Foundation
import Testing
@testable import EnvBoxCore

@Suite("Environment parsing")
struct SystemEnvironmentParserTests {
    @Test func parsesNULDelimitedEnvironmentAndIgnoresNoise() {
        var data = Data("startup noise\n".utf8)
        data.append(Data([0]) + Data("__ENVBOX_BEGIN__".utf8) + Data([0]))
        data.append(Data("HOME=/Users/test\0PATH=/usr/bin:/bin\0MULTI=line1\nline2\0".utf8))
        data.append(Data([0]) + Data("__ENVBOX_END__".utf8) + Data([0]))
        data.append(Data("trailing noise".utf8))

        let parsed = ShellEnvironmentReader.parse(data)
        #expect(parsed["HOME"] == "/Users/test")
        #expect(parsed["PATH"] == "/usr/bin:/bin")
        #expect(parsed["MULTI"] == "line1\nline2")
    }

    @Test func parserFallsBackWhenMarkersMissing() {
        let parsed = ShellEnvironmentReader.parse(Data("A=1\0B=2\0".utf8))
        #expect(parsed["A"] == "1")
        #expect(parsed["B"] == "2")
    }

    @Test func systemVariableClassification() {
        #expect(SystemVariable(key: "PWD", value: "/").isInternal)
        #expect(SystemVariable(key: "__CFBundleIdentifier", value: "x").isInternal)
        #expect(!SystemVariable(key: "PATH", value: "/").isInternal)
        #expect(SystemVariable(key: "API_TOKEN", value: "secret").isSensitive)
    }
}
