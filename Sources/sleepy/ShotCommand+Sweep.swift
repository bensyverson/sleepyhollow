import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `shot`'s sweep: repeated `--size`, `--scale` and `--theme` crossed into one
/// capture per combination, plus the ``ShotVariantIndex`` that names them.
///
/// Split from the flags and the single capture so each file stays readable;
/// the entry point is ``ShotCommand/runSweep(_:)``, which
/// ``ShotCommand/run()`` hands over to the moment a plan has more than one
/// variant.
extension ShotCommand {
    /// One combination's captures, kept with the variant that produced them
    /// so the writer never has to re-derive which render it is holding.
    struct Render {
        let variant: ShotPlan.Variant
        let images: [ShotImage]
    }

    /// Renders every combination and writes them, suffixed, with the index on
    /// stdout — and, with `--sheet`, the mosaic at `--out` itself.
    @MainActor
    func runSweep(_ plan: ShotPlan) async throws {
        let base: String = try sweepDestination()
        try requireNoStrips()
        try requireSheetHasCells(plan)
        let region: ShotRegion = try region()
        let fit: ShotFit? = try maxSize.map { try ShotFit(maxSize: $0) }
        let grid: ShotGrid.Options? = try gridOptions()
        let renders: [Render] = try await capture(plan, region: region, fit: fit, grid: grid)
        try writeVariants(renders, base: base)
        if sheet { try writeSheet(renders, base: base) }
        try printIndex(plan, base: base)
    }

    /// Renders the plan, one page load per distinct viewport-and-theme pair.
    ///
    /// ``ShotPlan/loads`` is what makes that grouping safe: `--scale` changes
    /// only the raster, so every density of one size-and-theme pair comes off
    /// the same loaded page and a 2×2 size/scale sweep pays for two loads.
    ///
    /// The loads that remain all run through one ``HostGroup``, so every
    /// combination renders against one cookie store and one jar: `--jar` is
    /// imported once for the whole sweep rather than once per combination,
    /// and a session a first combination establishes is still there for the
    /// last. It does not share an HTTP cache — a non-persistent data store has
    /// none to share (``HostGroup`` carries the measurement) — so each
    /// combination still fetches the page's subresources for itself.
    @MainActor
    private func capture(
        _ plan: ShotPlan,
        region: ShotRegion,
        fit: ShotFit?,
        grid: ShotGrid.Options?,
    ) async throws -> [Render] {
        let steps: [ActionStep] = try PageExecution.actionSteps()
        let pageSource: PageSource = try source.resolve()
        let hosts = HostGroup(jar: flags.jar)
        var renders: [Render] = []
        for group in plan.loads {
            guard let first = group.first else { continue }
            let options: LoadOptions = try flags.resolveLoadOptions(steps: steps, size: first.size, theme: first.theme)
            let captured: [Render] = try await PageExecution.perform(
                on: pageSource,
                flags: flags,
                loadOptions: options,
                group: hosts,
                onPage: { host in
                    var captures: [Render] = []
                    for variant in group {
                        let output = try await host.execute(ShotOperation(
                            region: region,
                            scale: variant.scale,
                            fit: fit,
                            grid: grid,
                        ))
                        captures.append(Render(variant: variant, images: output.images))
                    }
                    return captures
                },
                onSession: { _ in throw Self.sweepNeedsAURL },
            )
            renders += captured
        }
        return renders
    }

    /// Writes each render to its suffixed file.
    private func writeVariants(_ renders: [Render], base: String) throws {
        for render in renders {
            try OutputSink(path: render.variant.file(base: base)).write(Self.only(render).png)
        }
    }

    /// Composes every render into the mosaic and writes it to `--out` itself.
    ///
    /// The full-size files keep the suffixes, so the sheet and its cells never
    /// claim the same path — which is also why `--sheet` insists on having
    /// more than one render to lay out.
    private func writeSheet(_ renders: [Render], base: String) throws {
        let cells: [ShotSheet.Cell] = try renders.map { render in
            try ShotSheet.Cell(capture: ShotCapture(decoding: Self.only(render)), label: render.variant.label)
        }
        let mosaic: ShotCapture = try ShotSheet.compose(cells, maxSize: maxSize ?? ShotSheet.defaultMaxSize)
        try OutputSink(path: base).write(mosaic.encoded().png)
    }

    /// Prints the JSON index that maps each file to the render it holds.
    private func printIndex(_ plan: ShotPlan, base: String) throws {
        let index = ShotVariantIndex(plan: plan, base: base)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try OutputSink(path: nil).write(encoder.encode(index))
    }

    /// A render's single image. `--tile` is refused inside a sweep, so every
    /// combination produces exactly one.
    private static func only(_ render: Render) throws -> ShotImage {
        guard let image = render.images.first else {
            throw SleepyError(
                kind: .environment,
                message: "The \(render.variant.label) render produced no image.",
                nextMove: "Retry; if this persists, it is a seam bug in ShotOperation.",
            )
        }
        return image
    }

    /// The `--out` path the suffixed files hang off.
    ///
    /// Checked before anything loads: N combinations have no single stdout to
    /// be written to, and finding that out after four renders wastes them.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage``.
    func sweepDestination() throws -> String {
        guard let base = out.out else {
            throw SleepyError(
                kind: .usage,
                message: "A sweep writes one PNG per combination, so it needs --out to name them.",
                nextMove: "Give it a base path: --size 480 --size 1280 --out header.png "
                    + "writes header-480.png and header-1280.png.",
            )
        }
        return base
    }

    /// Refuses `--tile` inside a sweep.
    ///
    /// Both flags claim the same two things — the `--out` stem and the JSON on
    /// stdout — and a directory of strips from four different renders scrambles
    /// exactly the reading order the tile index exists to preserve.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage``.
    func requireNoStrips() throws {
        guard tile == nil else {
            throw SleepyError(
                kind: .usage,
                message: "--tile cuts one capture into strips, and \(sheet ? "--sheet" : "a sweep") "
                    + "renders several captures; they would fight over the same file names and the same index.",
                nextMove: "Sweep first to find the render you want, then tile that one: "
                    + "drop --sheet and the repeated --size/--scale/--theme, and pass --tile.",
            )
        }
    }

    /// Refuses `--sheet` when there is only one render to lay out.
    ///
    /// A one-cell mosaic is a plain shot with a caption, and worse, the sheet
    /// and its single full-size file would both want the bare `--out` path —
    /// only a varying axis gives the full-size file a suffix of its own.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage``.
    func requireSheetHasCells(_ plan: ShotPlan) throws {
        guard !sheet || plan.isSweep else {
            throw SleepyError(
                kind: .usage,
                message: "--sheet lays several renders side by side, and this invocation renders one.",
                nextMove: "Repeat an axis to give it something to lay out: "
                    + "--size 390 --size 1280 --sheet --out sheet.png.",
            )
        }
    }

    /// The refusal a sweep earns on `--session`: a session holds one page,
    /// already loaded at one size and one theme.
    static var sweepNeedsAURL: SleepyError {
        SleepyError(
            kind: .usage,
            message: "A sweep re-renders the page for each combination, and --session names one page "
                + "a helper has already loaded.",
            nextMove: "Give a URL instead, so each combination gets its own load.",
        )
    }
}
