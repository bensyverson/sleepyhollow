import Foundation
import QuartzCore
@testable import SleepyHollow
import Testing
import TestSupport

/// What each of `shot`'s renderers costs: the compositor against the
/// `takeSnapshot` fallback, at 1× and 2×, on one live 1280×800 page.
///
/// Off unless `SLEEPY_MEASURE` is set, because it is not a test — it asserts
/// nothing. Run it through `scripts/measure-shot-renderers.sh`, which sets
/// that variable and names the knobs (`SLEEPY_MEASURE_CAPTURES`,
/// `SLEEPY_MEASURE_ORDER`).
///
/// Three arms, each after one throwaway warm-up of every arm (the first
/// compositor render in a process cold-starts Metal and Core Animation's
/// renderer):
///
/// - `compositor image`: wait for the presentation update, render, read back
///   (``PageHost/compositorImage(of:scale:)``);
/// - `compositor stage`: ``ShotOperation/render(on:)`` as `shot` runs it,
///   adding the renderer choice (the `<video>` check) to the above;
/// - `snapshot stage`: the fallback's render stage, `takeSnapshot` plus the
///   flattened-3D check and the re-rasterize to the exact pixel size.
@Suite(
    "Shot renderer measurement",
    .enabled(if: ProcessInfo.processInfo.environment["SLEEPY_MEASURE"] != nil),
    .serialized,
)
struct ShotRendererMeasurementTests {
    private var captures: Int {
        ProcessInfo.processInfo.environment["SLEEPY_MEASURE_CAPTURES"].flatMap { Int($0) } ?? 20
    }

    private var snapshotFirst: Bool {
        ProcessInfo.processInfo.environment["SLEEPY_MEASURE_ORDER"] == "snapshot"
    }

    @Test(arguments: [1, 2])
    @MainActor
    func `print the cost of each renderer`(scale: Int) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
            _ = try await host.load(#require(URL(string: "compositor-t3d.html", relativeTo: base)))
            let viewport = CGRect(x: 0, y: 0, width: 1280, height: 800)
            let operation = try ShotOperation(scale: ShotScale(factor: scale))
            let arms: [(String, @MainActor () async throws -> Void)] = [
                ("compositor image", { _ = try await host.compositorImage(of: viewport, scale: scale) }),
                ("compositor stage", { _ = try await operation.render(on: host) }),
                ("snapshot stage", { _ = try await operation.snapshotCapture(of: viewport, on: host, because: .unavailable) }),
            ]
            let ordered = snapshotFirst ? arms.reversed() : arms
            for (_, arm) in ordered {
                try await arm()
            }
            for (name, arm) in ordered {
                var times: [Double] = []
                for _ in 0 ..< captures {
                    let start = CACurrentMediaTime()
                    try await arm()
                    times.append((CACurrentMediaTime() - start) * 1000)
                }
                times.sort()
                let median = times[times.count / 2]
                let p90 = times[min(times.count - 1, times.count * 9 / 10)]
                print(String(format: "[shot-renderers] %d× %@: median %.1f ms, p90 %.1f ms (n=%d)", scale, name, median, p90, captures))
            }
        }
    }
}
