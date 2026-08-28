import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy shot` — render at a given `--size`, write a PNG.
///
/// *Need:* the baseline act of seeing. `--element` crops to one element's
/// rect — the thing under test is rarely the whole page — and `--full-page`
/// captures the entire scroll height instead of the viewport.
///
/// Exit 1 is `--element`'s clean negative: the selector matched nothing, or
/// matched something with no rendered area — either way there is no crop to
/// take, so no PNG is written. Every other failure follows the shared scheme
/// (2 usage, 4 load failure, 5 environment).
struct ShotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shot",
        abstract: "Screenshot a page: the viewport, one element, a document rect, or the full scrollable page.",
        discussion: """
        Examples:
          sleepy shot http://localhost:3000/ --out shot.png
          sleepy shot http://localhost:3000/ --element '#save-button' --out button.png
          sleepy shot http://localhost:3000/ --full-page --theme dark --out page.png
          sleepy shot http://localhost:3000/ --rect 0,850,1280,600 --out band.png
          sleepy shot --session app --element '.toast' -o toast.png

        Exit codes: 0 success, 1 --element matched nothing or matched an element with no rendered area (no PNG written; the reason and the element's rect are on stderr), 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @Option(name: .long, help: "Crop the screenshot to this CSS selector's rect. Exits 1 if nothing matches.")
    var element: String?

    @Option(name: .long, help: "Crop to x,y,width,height in CSS document px — the values query or a tile index report.")
    var rect: String?

    /// `--full` is the same flag: it is what a typist reaches for first, and
    /// without it the parser's nearest match is `--fill` — a real `shot`
    /// flag that does something else entirely.
    @Flag(
        name: [.long, .customLong("full")],
        help: "Capture the full scrollable page instead of the viewport (--full is the same flag).",
    )
    var fullPage: Bool = false

    /// The one region the flags name; more than one is a usage error rather
    /// than a silent precedence rule.
    func region() throws -> ShotRegion {
        var regions: [ShotRegion] = []
        if let element { regions.append(.element(element)) }
        if let rect { try regions.append(ShotRegion.rect(parsing: rect)) }
        if fullPage { regions.append(.fullPage) }
        guard regions.count <= 1 else {
            throw SleepyError(
                kind: .usage,
                message: "--element, --rect and --full-page name different regions; pick one.",
                nextMove: "Drop all but one of them. To crop a full-page capture, use --rect with document coordinates.",
            )
        }
        return regions.first ?? .viewport
    }

    @MainActor
    mutating func run() async throws {
        let region: ShotRegion = try region()
        let output = try await PageExecution.run(
            ShotOperation(region: region),
            on: source.resolve(),
            flags: flags,
        )
        guard let image = output.images.first else {
            throw SleepyError(
                kind: .environment,
                message: "The shot produced no image.",
                nextMove: "Retry; if this persists, it is a seam bug in ShotOperation.",
            )
        }
        try out.sink.write(image.png)
    }
}
