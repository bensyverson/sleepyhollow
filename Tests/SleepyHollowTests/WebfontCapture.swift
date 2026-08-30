import CoreGraphics
import Foundation
import SleepyHollow
import Testing

/// A viewport shot, decoded to pixels — the currency the two webfont suites
/// compare.
///
/// `ShotOperation.render(on:)` — the `CGImage` path — is internal and this
/// target imports the library rather than `@testable`, so the capture goes
/// through the public `execute` and comes back through `ShotCapture(decoding:)`.
/// That is a lossless PNG round trip on *both* sides of every comparison, and
/// the timing that matters — `takeSnapshot` itself — is identical either way.
/// When leaf `host-api` makes `render(on:)` public this can drop the decode.
///
@MainActor
func webfontCapture(on host: PageHost) async throws -> CGImage {
    let output = try await host.execute(ShotOperation())
    let image = try #require(output.images.first)
    return try ShotCapture(decoding: image).image
}

/// Runs one whole measurement, retrying it from scratch if the WebKit seam
/// *threw*.
///
/// On a Mac carrying several agents' suites at once — load average above 300,
/// measured 2026-08-29 — WebKit itself gives out: `callAsyncJavaScript` and
/// `takeSnapshot` fail with a bare `WKErrorDomain Code=1`, four runs in five,
/// in whichever test happened to be mid-call. That is a starved web content
/// process, not an answer about pixels, and `PageHost.evaluate` documents that
/// it passes WebKit's own error through rather than dressing it up.
///
/// Only a *throw* is retried, and the retry builds a fresh host and a fresh
/// page, so nothing is carried over from the failed attempt. A measurement
/// that completes is never retried, so no `#expect` here can be softened by
/// this: a paint regression is a pixel difference, and pixel differences do
/// not throw.
@MainActor
func retryingStarvedWebKit<T>(_ body: @MainActor () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch {
        return try await body()
    }
}

/// The mean absolute per-channel difference between two captures — 0 for
/// identical pixels, 9.9365 between the webfont fixture's fallback and its
/// bar glyphs.
func webfontDifference(_ first: CGImage, _ second: CGImage) throws -> Double {
    try #require(meanChannelDifference(first, second, width: first.width, height: first.height))
}
