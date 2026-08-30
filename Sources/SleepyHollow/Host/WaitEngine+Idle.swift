import Foundation

/// The `--wait-for idle` half of the settle phase.
///
/// Sampled from the host, deliberately: "quiet for 500 ms" is a window
/// *measured* on the host's clock, not a fact the page can push. That is why
/// `.idle` is the one condition the 2026-08-29 page-side work left alone
/// (`project/2026-08-29-woodcase-harness-plan.md`, "Decided against").
extension WaitEngine {
    /// How often the page's activity is sampled while waiting for idle.
    private static let idleSampleInterval: TimeInterval = 0.1

    /// Waits for the page's activity to go quiet for ``IdleWatch/quietWindow``.
    func settleIdle(
        in host: PageHost,
        url: URL,
        by deadline: DispatchTime,
        budget: TimeInterval,
    ) async throws {
        var previous: IdleWatch.Sample?
        var quietSince = DispatchTime.now()
        var last = IdleWatch.Sample.unknown
        var samplesTaken = 0
        var quietResets = 0
        var failedSamples = 0
        while true {
            let sample: IdleWatch.Sample? = await sample(in: host)
            samplesTaken += 1
            if sample == nil { failedSamples += 1 }
            last = sample ?? last
            let current: IdleWatch.Sample = sample ?? IdleWatch.Sample.unknown
            if current.busy == 0, previous?.activity == current.activity {
                if DispatchTime.now() >= quietSince + IdleWatch.quietWindow { return }
            } else {
                if previous != nil { quietResets += 1 }
                quietSince = DispatchTime.now()
            }
            previous = current
            guard DispatchTime.now() < deadline else { break }
            try? await Task.sleep(nanoseconds: Self.nanoseconds(Self.idleSampleInterval))
        }
        throw timeout(
            url: url,
            budget: budget,
            what: "never went quiet for --wait-for idle",
            detail: "Its last sample had \(last.busy) request(s) or image(s) outstanding "
                + "(\(samplesTaken) samples, \(quietResets) quiet-window resets, "
                + "\(failedSamples) unreadable, final activity count \(last.activity)).",
            nextMove: "Raise --budget, or wait for a selector or 'js:<expression>' — a page that polls is never idle.",
        )
    }

    /// One activity reading; `nil` when the page could not be sampled (the
    /// caller decides what an unreadable page means — see `settleIdle`).
    private func sample(in host: PageHost) async -> IdleWatch.Sample? {
        guard
            let text: String = try? await host.evaluate(IdleWatch.sampleBody, in: .page),
            let sample: IdleWatch.Sample = try? Self.decode(IdleWatch.Sample.self, from: text)
        else {
            return nil
        }
        return sample
    }
}
