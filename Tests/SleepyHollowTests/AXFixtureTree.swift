import Foundation
import SleepyHollow
import TestSupport

/// Loads a fixture page in a real headless host and returns its accessibility
/// tree — the apparatus every `ax` suite shares.
enum AXFixtureTree {
    /// Serves `fileName` from the fixtures directory, loads it, and runs
    /// ``AXOperation`` against it.
    @MainActor
    static func tree(of fileName: String) async throws -> AXNode {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: fileName, relativeTo: base)!)
            return try await host.execute(AXOperation())
        }
    }
}

extension AXNode {
    /// The first node in preorder with this role, and this name when given.
    func first(role: AXRole, named name: String? = nil) -> AXNode? {
        flattened.first { node in
            node.role == role && (name == nil || node.name == name)
        }
    }

    /// Every accessible name in the tree, for absence assertions.
    var names: [String] {
        flattened.compactMap(\.name)
    }
}
