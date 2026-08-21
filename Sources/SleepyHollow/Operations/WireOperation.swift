import Foundation

/// Reads the page's wire log — `sleepy wire`.
///
/// Two layers, one result: the ``ResourceEntry`` inventory of everything the
/// page requested, and the ``FetchExchange`` log of every `window.fetch` call.
/// The inventory needs no preparation; the fetch log needs the recorder, which
/// must be installed **before** the load — ``LoadOptions/recordingWire(byteCap:)``.
///
/// ```swift
/// let host = PageHost(options: LoadOptions().recordingWire())
/// _ = try await host.load(url)
/// let log = try await host.execute(WireOperation())
/// ```
///
/// Settling is host-side, deliberately. A page that fetches from its `load`
/// handler is still talking when the navigation finishes, and a headless web
/// view throttles page timers whenever the host is not evaluating JavaScript —
/// so the page cannot be trusted to time itself. This operation polls the
/// recorder until it is quiet or the budget runs out, and reports bodies that
/// never arrived as ``FetchExchange/Truncation/budget`` rather than as absent.
public struct WireOperation: ExecutablePageOperation {
    /// The log this operation returns.
    public typealias Output = WireLog

    /// The wire identifier.
    public static let kind: String = "wire"

    /// What the recorder reports about work still in flight.
    private struct Activity: Friendly {
        /// Fetches called but not yet answered.
        var inflight: Int
        /// Response bodies still being read.
        var pendingBodies: Int
        /// When the recorder last saw anything happen.
        var lastActivityAt: Double
        /// The page's clock at the moment it answered.
        var now: Double

        /// Quiet means nothing in flight and nothing recorded for a while:
        /// a page between two sequential fetches is busy, not quiet.
        func isQuiet(afterMilliseconds milliseconds: Int) -> Bool {
            inflight == 0 && pendingBodies == 0 && (now - lastActivityAt) >= Double(milliseconds)
        }
    }

    /// How long, in milliseconds, to keep waiting for the page to stop
    /// fetching before reporting what there is.
    public var settleBudgetMilliseconds: Int

    /// How long the recorder must have been idle, in milliseconds, before the
    /// page counts as quiet.
    public var quietMilliseconds: Int

    /// Creates the operation.
    public init(settleBudgetMilliseconds: Int = 2000, quietMilliseconds: Int = 50) {
        self.settleBudgetMilliseconds = settleBudgetMilliseconds
        self.quietMilliseconds = quietMilliseconds
    }

    /// Settles, then reads both layers.
    @MainActor
    public func execute(on host: PageHost) async throws -> WireLog {
        try await settle(on: host)
        return try await WireLog(
            inventory: readInventory(on: host),
            fetches: readFetches(on: host),
        )
    }

    // MARK: - Settling

    /// How often the host asks the page whether it is still fetching.
    private static let pollIntervalNanoseconds: UInt64 = 25_000_000

    /// Two consecutive quiet answers, so a poll landing in the gap between two
    /// sequential fetches cannot end the settle early.
    private static let requiredQuietPolls: Int = 2

    @MainActor
    private func settle(on host: PageHost) async throws {
        let deadline = Date().addingTimeInterval(Double(settleBudgetMilliseconds) / 1000)
        var quietPolls = 0
        while true {
            let activity: Activity = try await readActivity(on: host)
            quietPolls = activity.isQuiet(afterMilliseconds: quietMilliseconds) ? quietPolls + 1 : 0
            if quietPolls >= Self.requiredQuietPolls { return }
            if Date() >= deadline { return }
            try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
        }
    }

    @MainActor
    private func readActivity(on host: PageHost) async throws -> Activity {
        let text: String = try await host.evaluate(WireRecorder.activityExpression, in: .page)
        guard let activity: Activity = try? JSONDecoder().decode(Activity.self, from: Data(text.utf8)) else {
            throw Self.recorderMissing
        }
        return activity
    }

    // MARK: - Reading

    @MainActor
    private func readInventory(on host: PageHost) async throws -> [ResourceEntry] {
        let text: String = try await host.evaluate(WireInventoryScript.expression)
        guard var entries: [ResourceEntry] = try? JSONDecoder().decode(
            [ResourceEntry].self,
            from: Data(text.utf8),
        ) else {
            throw SleepyError(
                kind: .environment,
                message: "The page's resource timeline could not be read.",
                nextMove: "Reload the page and try again.",
            )
        }
        // The main frame's status is the one status this layer can have, and it
        // comes from the navigation, not from the timeline.
        if let index: Int = entries.firstIndex(where: { $0.initiatorType == "navigation" }) {
            entries[index].httpStatus = host.facts.httpStatus
        }
        return entries
    }

    @MainActor
    private func readFetches(on host: PageHost) async throws -> [FetchExchange] {
        let text: String = try await host.evaluate(WireRecorder.exchangesExpression, in: .page)
        guard let exchanges: [FetchExchange] = try? JSONDecoder().decode(
            [FetchExchange].self,
            from: Data(text.utf8),
        ) else {
            throw Self.recorderMissing
        }
        return exchanges
            .map(Self.markingBodiesLeftPending)
            .sorted { ($0.startedAtMilliseconds, $0.id) < ($1.startedAtMilliseconds, $1.id) }
    }

    /// A response whose body never arrived within the budget is reported as
    /// truncated, not as a body-less response.
    private static func markingBodiesLeftPending(_ exchange: FetchExchange) -> FetchExchange {
        guard
            exchange.status != nil,
            exchange.responseType != "opaque",
            exchange.responseType != "opaqueredirect",
            exchange.responseBody == nil,
            exchange.truncated == nil,
            exchange.error == nil
        else {
            return exchange
        }
        var pending: FetchExchange = exchange
        pending.truncated = .budget
        return pending
    }

    private static let recorderMissing = SleepyError(
        kind: .environment,
        message: "This page has no fetch recorder, so the fetch log cannot be read.",
        nextMove: "The recorder installs before the load: run `sleepy wire <url>`, "
            + "or build the host with LoadOptions.recordingWire().",
    )
}
