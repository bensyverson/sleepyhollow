import Foundation
import Testing
import TestSupport

/// A one-shot verb's page is hosted live, so animation time advances, end to
/// end through the real binary.
///
/// Job issue `ND4YmR` (frozen rAF, transitions and Web Animations), fixed by
/// leaf `GzK3Rl`; the ruling is `project/2026-11-06-true-3d-shots.md`
/// § Ruling on the capture path.
@Suite(.serialized)
struct LiveHostingGoldenTests {
    /// What `animation-end-state.html` reports after one second on its clock.
    private struct AnimationReport: Decodable {
        let rafFrames: Int
        let transitionTransform: String
        let waapiPlayState: String
        let waapiCurrentTime: Double?
    }

    @Test func `rAF runs and a transition and a Web Animation reach their end state`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("animation-end-state.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "eval", url,
                "--js", "return JSON.parse(document.getElementById('report').textContent);",
                "--wait-for", "body[data-done]",
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let report = try JSONDecoder().decode(AnimationReport.self, from: Data(result.standardOutput.utf8))
            // Chrome draws 60 in that second; a loaded machine draws fewer,
            // and a frozen host draws none. Any steady chain clears this.
            #expect(report.rafFrames >= 5, "rAF frames in 1 s: \(report.rafFrames)")
            #expect(report.transitionTransform == "matrix(1, 0, 0, 1, 200, 0)")
            #expect(report.waapiPlayState == "finished")
            #expect(report.waapiCurrentTime == 300)
        }
    }
}
