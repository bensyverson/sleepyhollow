import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The operation behind `sleepy resize`: the viewport verb a live session
/// carries over its socket.
@Suite("Resize operation")
struct ResizeOperationTests {
    @Test
    @MainActor
    func `resizing a host reports the viewport it now has`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
            _ = try await host.load(#require(URL(string: "capture-breakpoint.html", relativeTo: base)))
            let size = ViewportSize(width: 390, height: 844)
            let reported: ViewportSize = try await host.execute(ResizeOperation(size: size))
            #expect(reported == size)
            #expect(host.viewport == size)
            let narrow: String = try await host.evaluate(
                "return window.matchMedia('(max-width: 999px)').matches;",
            )
            #expect(narrow == "true")
        }
    }

    @Test func `the operation round-trips through an envelope`() throws {
        let size = ViewportSize(width: 480, height: 640)
        let envelope = try OperationEnvelope(ResizeOperation(size: size))
        let decoded = try SessionOperations.registry.decode(envelope)
        #expect((decoded as? ResizeOperation)?.size == size)
    }
}
