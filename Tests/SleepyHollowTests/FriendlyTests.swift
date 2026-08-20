import Foundation
@testable import SleepyHollow
import Testing

/// Verifies the `Friendly` convention every SleepyHollow type adopts.
struct FriendlyTests {
    /// A minimal adopter proving the composed requirements are satisfiable together.
    private struct Sample: Friendly {
        let name: String
        let count: Int
    }

    @Test func `friendly type round trips through JSON`() throws {
        let original = Sample(name: "publish", count: 2)
        let data: Data = try JSONEncoder().encode(original)
        let decoded: Sample = try JSONDecoder().decode(Sample.self, from: data)
        #expect(decoded == original)
    }

    @Test func `friendly type is hashable`() {
        let set: Set<Sample> = [
            Sample(name: "a", count: 1),
            Sample(name: "a", count: 1),
            Sample(name: "b", count: 2),
        ]
        #expect(set.count == 2)
    }
}
