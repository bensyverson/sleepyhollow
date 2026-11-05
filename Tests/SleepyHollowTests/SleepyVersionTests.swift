@testable import SleepyCLIKit
import Testing

/// `scripts/release` reads and rewrites this line, so it must stay plain `X.Y.Z`.
struct SleepyVersionTests {
    @Test func `the version is plain major, minor and patch`() {
        let parts: [Substring] = SleepyVersion.current.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { part in Int(part) != nil })
    }
}
