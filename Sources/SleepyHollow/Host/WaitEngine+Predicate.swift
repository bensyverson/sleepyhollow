import Foundation

/// The `--wait-for js:<expression>` half of the settle phase.
///
/// The page re-evaluates the expression itself (``PredicateWatch``) and pushes
/// once; the host checks at the load event, keeps a slow backstop for an
/// expression that never parsed, and owns the deadline.
extension WaitEngine {
    /// Waits for `expression` to be truthy: the load-event check, then the
    /// page's pushes raced against the host's slow backstop.
    func settlePredicate(
        _ expression: String,
        in host: PageHost,
        url: URL,
        by deadline: DispatchTime,
        budget: TimeInterval,
    ) async throws {
        lastFailure = nil
        // The load event's own check: a predicate already true settles without
        // waiting for the page's next tick.
        if await check(expression, in: host) { return }
        let settled: Bool = await race(
            by: deadline,
            accepting: { [weak self] text in await self?.accept(push: text) ?? true },
            checking: { [weak self] in await self?.check(expression, in: host) ?? false },
        )
        guard settled else {
            throw timeout(
                url: url,
                budget: budget,
                what: "did not satisfy --wait-for 'js:\(expression)'",
                detail: lastFailure.map { "The predicate threw every time it ran: \($0)." },
                nextMove: "Raise --budget, or fix the expression — it is evaluated in the page's own world and must become truthy.",
            )
        }
    }

    /// Reads one push from ``PredicateWatch``: `truthy` ends the wait, and a
    /// failure payload is kept for the timeout message — the page reports its
    /// first failure itself, so a starved host still knows why.
    ///
    /// Anything that is not a ``Probe`` ends the wait: only instrumentation
    /// posts on this name, and a push it cannot parse is still a push.
    private func accept(push text: String) -> Bool {
        guard let probe: Probe = try? Self.decode(Probe.self, from: text) else { return true }
        if let failure = probe.failure { lastFailure = failure }
        return probe.truthy
    }

    /// The host's own evaluation of the predicate, recording any failure.
    private func check(_ expression: String, in host: PageHost) async -> Bool {
        let probe: Probe = await (try? probe(expression: expression, in: host)) ?? Probe(truthy: false)
        if let failure = probe.failure { lastFailure = failure }
        return probe.truthy
    }

    /// One host-side evaluation of the predicate, counted in ``probeCount``.
    private func probe(expression: String, in host: PageHost) async throws -> Probe {
        probeCount += 1
        // The page's own world: a wait predicate is a statement about the
        // page's state, and an isolated world would read every page global as
        // `undefined` — a silently wrong answer rather than a slow one.
        let text: String = try await host.evaluate(
            """
            try {
              return { truthy: !!(\(expression)) };
            } catch (error) {
              return { truthy: false, failure: String(error) };
            }
            """,
            in: .page,
        )
        return try Self.decode(Probe.self, from: text)
    }
}
