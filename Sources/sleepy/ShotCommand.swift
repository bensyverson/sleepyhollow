import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy shot` — render at a given `--size`, write a PNG.
///
/// *Need:* the baseline act of seeing. `--selector` crops to one element's
/// rect — the thing under test is rarely the whole page — and `--full-page`
/// captures the entire scroll height instead of the viewport.
///
/// `--max-size` and `--tile` are the readout half: an image an agent can
/// actually read. The first caps the output's longest side (the page is
/// unchanged — only the pixels thin), the second cuts the capture into
/// overlapping strips written as `<out>-01.png`, `<out>-02.png` … with a
/// ``ShotIndex`` on stdout saying which document rows each file holds.
///
/// Exit 1 is `--selector`'s clean negative: the selector matched nothing, or
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
          sleepy shot http://localhost:3000/ --selector '#save-button' --out button.png
          sleepy shot http://localhost:3000/ --full-page --theme dark --out page.png
          sleepy shot http://localhost:3000/ --rect 0,850,1280,600 --out band.png
          sleepy shot http://localhost:3000/ --full-page --max-size 2000 --out overview.png
          sleepy shot http://localhost:3000/ --full-page --max-size 2000 --tile --out strips.png
          sleepy shot http://localhost:3000/ --full-page --max-size 2000 --grid lines --out map.png
          sleepy shot --session app --selector '.toast' -o toast.png

        --tile writes strips-01.png, strips-02.png … next to --out and prints a JSON index on stdout: each entry's x, y, width and height are CSS document px, so a strip worth a closer look is --rect x,y,width,height with no arithmetic. Adjacent strips share 40 CSS px, and 'scale' is how many pixels of the file stand for one CSS px.

        Exit codes: 0 success, 1 --selector matched nothing or matched an element with no rendered area (no PNG written; the reason and the element's rect are on stderr), 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    /// `--element` is the same flag: `shot` shipped with that spelling while
    /// `click`, `fill` and `submit` said `--selector`, and an agent that
    /// learned one guessed wrong on the next
    /// (2026-08-24-first-agent-user-feedback.md). `--selector` is now the one
    /// name; the old spelling keeps working.
    @Option(
        name: [.long, .customLong("element")],
        help: "Crop the screenshot to this CSS selector's rect (--element is the same flag). Exits 1 if nothing matches.",
    )
    var selector: String?

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

    @Option(
        name: .long,
        help: "Cap the longest side of the output PNG at this many pixels. The page renders unchanged; only the image is downsampled.",
    )
    var maxSize: Int?

    /// Bare `--tile` is the common case — an agent knows it wants strips
    /// before it knows how tall they should be — so this is ArgumentParser's
    /// `defaultAsFlag` option rather than a flag plus a second option. The
    /// `.next` strategy is deliberate: the default, `.scanningForValue`,
    /// reads *ahead* past other options, so `--tile --out shot.png` would
    /// quietly take `shot.png` as the tile height.
    @Option(
        name: .long,
        defaultAsFlag: ShotTile.Height.automatic,
        parsing: .next,
        help: ArgumentHelp(
            "Cut the capture into horizontal strips this many CSS px tall, sharing 40px. "
                + "Bare --tile takes its height from --max-size, else the viewport. Needs --out.",
            valueName: "css-px",
        ),
    )
    var tile: ShotTile.Height?

    @Option(
        name: .long,
        help: "Draw coordinate rulers in a gutter, labeled in CSS document px: 'lines' also lays faint guides across the page, 'rulers' leaves the page pixels untouched. Drawn after --max-size, so the gutter adds ~\(ShotGrid.minimumGutter)px beyond the cap.",
    )
    var grid: String?

    @Option(name: .long, help: "Spacing between grid ticks and labels, in CSS px.")
    var gridStep: Int = 100

    /// The grid the flags ask for, or `nil` when `--grid` was not passed.
    func gridOptions() throws -> ShotGrid.Options? {
        guard let grid else { return nil }
        return try ShotGrid.Options(mode: ShotGrid.Mode(parsing: grid), step: gridStep)
    }

    /// The one region the flags name; more than one is a usage error rather
    /// than a silent precedence rule.
    func region() throws -> ShotRegion {
        var regions: [ShotRegion] = []
        if let selector { regions.append(.element(selector)) }
        if let rect { try regions.append(ShotRegion.rect(parsing: rect)) }
        if fullPage { regions.append(.fullPage) }
        guard regions.count <= 1 else {
            throw SleepyError(
                kind: .usage,
                message: "--selector, --rect and --full-page name different regions; pick one.",
                nextMove: "Drop all but one of them. To crop a full-page capture, use --rect with document coordinates.",
            )
        }
        return regions.first ?? .viewport
    }

    /// A checked `--tile`: the strip height, and the `--out` path the
    /// numbered files hang off.
    ///
    /// One value for two facts that are only ever true together — asking for
    /// strips means asking for files — so no later step has to handle a
    /// "tiling, but nowhere to write" state that parsing already ruled out.
    private struct StripRequest {
        let height: ShotTile.Height
        let base: String
    }

    @MainActor
    mutating func run() async throws {
        let region: ShotRegion = try region()
        let fit: ShotFit? = try maxSize.map { try ShotFit(maxSize: $0) }
        let strips: StripRequest? = try stripRequest()
        let output = try await PageExecution.run(
            ShotOperation(region: region, fit: fit, tile: strips?.height, grid: gridOptions()),
            on: source.resolve(),
            flags: flags,
        )
        guard let first = output.images.first else {
            throw SleepyError(
                kind: .environment,
                message: "The shot produced no image.",
                nextMove: "Retry; if this persists, it is a seam bug in ShotOperation.",
            )
        }
        if let strips {
            try writeStrips(output.images, named: strips.base)
        } else {
            try out.sink.write(first.png)
        }
        Nudge.emit(
            Nudge.forShot(Nudge.ShotFacts(
                captureHeight: Double(first.rect.height),
                wasCapped: fit != nil,
                wasTiled: strips != nil,
                wroteToFile: out.out != nil,
            )),
            quiet: quiet.quiet,
        )
    }

    /// The checked `--tile` request, or `nil` when `--tile` wasn't asked for.
    ///
    /// Both checks happen before the page loads: a height the 40px overlap
    /// would swallow, and the missing `--out` — N strips have no single
    /// stdout to be written to, and discovering that after a render wastes
    /// the render.
    private func stripRequest() throws -> StripRequest? {
        guard let tile else { return nil }
        guard let base = out.out else {
            throw SleepyError(
                kind: .usage,
                message: "--tile writes one PNG per strip, so it needs --out to name them.",
                nextMove: "Give it a base path: --tile --out strips.png writes strips-01.png, strips-02.png ….",
            )
        }
        return try StripRequest(height: tile.validated(), base: base)
    }

    /// Writes the strips as `<out>-01.png`, `<out>-02.png` … and prints the
    /// JSON index that says which document rows each one holds.
    ///
    /// Numbered files and an index appear whenever `--tile` was asked for,
    /// even for a page that fits in a single strip: what a caller has to
    /// parse should follow from the flags it passed, not from how tall the
    /// page turned out to be.
    private func writeStrips(_ images: [ShotImage], named base: String) throws {
        let files: [String] = images.indices.map { Self.numbered(base, strip: $0 + 1) }
        for (image, file) in zip(images, files) {
            try OutputSink(path: file).write(image.png)
        }
        let index = ShotIndex(tiles: zip(files, images).map(ShotIndex.Tile.init(file:image:)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try OutputSink(path: nil).write(encoder.encode(index))
    }

    /// `strips.png` and strip 2 make `strips-02.png`; a path with no
    /// extension keeps none.
    private static func numbered(_ base: String, strip: Int) -> String {
        let url = URL(fileURLWithPath: base)
        let stem: String = url.deletingPathExtension().path + String(format: "-%02d", strip)
        return url.pathExtension.isEmpty ? stem : stem + "." + url.pathExtension
    }
}
