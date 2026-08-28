import Foundation

/// A latch a fixture page can block on, so a test controls *when* the page's
/// next thing happens instead of racing it on the wall clock.
///
/// ``install(on:path:)`` registers a route that holds every request until
/// ``open()`` is called and answers `204 No Content` from then on. A fixture
/// that does its late work when that request resolves (`wait-late.html`'s
/// `?flip=gate`) turns "the element is not there yet" into *program order*:
/// the page cannot have flipped before the test opened the gate, however
/// slow or loaded the machine is.
///
/// That is what the wait-family tests need. A margin — "settling at once must
/// beat a 3-second timer" — is a bet on the host being quicker than the page,
/// and a Mac running seven agents loses it; a happens-before cannot be lost.
/// See `project/2026-08-28-wait-test-timing.md`.
///
/// A held request is released after ``holdLimit`` even if nothing opens the
/// gate, so a test that fails before its ``open()`` leaves no task parked for
/// the rest of the run.
public actor FixtureGate {
    /// How long a request is held before it answers anyway — a safety net for
    /// a test that never opens the gate, never a deadline a test relies on.
    public static let holdLimit: TimeInterval = 30

    /// How often a held request re-checks the latch. Polling rather than a
    /// continuation keeps the release path free of bookkeeping that a torn-down
    /// server could strand; 25ms is far below any wait this apparatus tests.
    private static let pollInterval: TimeInterval = 0.025

    /// The path the gate answers on.
    public let path: String

    private var isOpen = false
    private var requests = 0

    /// Creates a closed gate for a route path.
    public init(path: String = "/gate") {
        self.path = path
    }

    /// How many requests have reached the gate.
    public var requestCount: Int {
        requests
    }

    /// Registers the gate's route on a running server.
    public func install(on server: FixtureServer) async {
        await server.register(path: path) { [weak self] _ in
            await self?.hold()
            return FixtureResponse(status: 204, contentType: FixtureContentType.plainText, body: Data())
        }
    }

    /// Opens the latch: every held request answers, and later ones answer at
    /// once. Opening an open gate is a no-op.
    public func open() {
        isOpen = true
    }

    /// Waits — generously, as a liveness check rather than a discriminator —
    /// for the page to have reached the gate at least `count` times.
    ///
    /// - Returns: `true` when the request arrived inside `timeout`.
    public func awaitRequest(count: Int = 1, timeout: TimeInterval = 15) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while requests < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
        return requests >= count
    }

    /// Counts a request and holds it until the gate opens or ``holdLimit``
    /// passes.
    private func hold() async {
        requests += 1
        let deadline = Date().addingTimeInterval(Self.holdLimit)
        while !isOpen, Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }
}
