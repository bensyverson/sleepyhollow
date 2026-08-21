import Foundation

public extension FixtureServer {
    /// Runs `body` **on the main actor** against a started server, guaranteeing
    /// ``FixtureServer/stop()`` after.
    ///
    /// The shape WebKit tests need: `WKWebView` and everything built on it is
    /// main-actor-bound, while ``FixtureServer/withRunning(fixturesDirectory:_:)``
    /// hands its closure a non-isolated context. Swift Testing's `@MainActor`
    /// async tests service WebKit's callbacks without any run-loop pumping, so
    /// this hop is the only apparatus a host test needs.
    @MainActor
    static func withRunningOnMainActor<T: Sendable>(
        fixturesDirectory: URL = TestSupport.fixturesDirectory,
        _ body: @MainActor @Sendable (FixtureServer, URL) async throws -> T,
    ) async throws -> T {
        try await withRunning(fixturesDirectory: fixturesDirectory) { server, baseURL in
            try await body(server, baseURL)
        }
    }
}
