import Foundation
@testable import SleepyHollow
import Testing

/// Session and jar names become directory names under ~/.sleepyhollow — the
/// validation here is a security boundary, not a style preference.
struct StateNameTests {
    @Test(arguments: ["login", "login-flow", "a", "Flow_2", "v1.2"])
    func `accepts reasonable names`(raw: String) {
        #expect(SessionName(raw) != nil)
        #expect(JarName(raw) != nil)
    }

    @Test(arguments: ["", "../evil", "a/b", ".hidden", "has space", "semi;colon", String(repeating: "x", count: 65)])
    func `rejects unsafe names`(raw: String) {
        #expect(SessionName(raw) == nil)
        #expect(JarName(raw) == nil)
    }

    @Test func `valid name survives JSON transport`() throws {
        let name = try #require(JarName("login"))
        let data: Data = try JSONEncoder().encode(name)
        let decoded: JarName = try JSONDecoder().decode(JarName.self, from: data)
        #expect(decoded == name)
    }

    @Test func `decoding an unsafe name fails`() throws {
        let data: Data = try JSONEncoder().encode("../evil")
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SessionName.self, from: data)
        }
    }
}
