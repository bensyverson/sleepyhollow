import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy overflow` — does anything on this page spill the viewport
/// sideways?
///
/// The answer is chiefly the exit code (0 the page holds its width, 1 at
/// least one element spills); the body names what spills and, separately,
/// what scrolls on purpose.
///
/// The viewport comes from `--size`, which is the shared loading flag — so
/// asking the question at another breakpoint is `--size 390x800`, the same
/// spelling every other loading verb uses. Repeating it asks at every
/// breakpoint in one call: ``OverflowSweep`` gives each size its own load and
/// the answer becomes an ``OverflowSweepReport``, one report per size.
struct OverflowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overflow",
        abstract: "Find elements that spill the viewport horizontally. Exit 1 if any do.",
        discussion: """
        Two things make this different from the loop it replaces. document.scrollWidth > clientWidth is silent on any page carrying overflow-x: hidden, so this measures element geometry against the viewport instead — and reports the document's own width beside it so the discrepancy is visible. And an element inside an overflow-x: auto or scroll ancestor is wide by design, so that ancestor ends the walk and is listed under scrollContainers rather than counted as a fault.

        A violation names a cause: 'box' is an element whose own border box ends past the viewport; 'content' is one whose box fits but whose content does not — the unbreakable string in a paragraph, which never widens the paragraph and so is invisible to a rect-only check. Box spills report the outermost element, content spills the innermost, so the report names a cause rather than a chain.

        Repeat --size to ask at every breakpoint in one call: each size gets its own load, and the JSON becomes {"sizes": [{"width", "height", "report"}]} — one entry per size in the order given, each report shaped exactly like the single-size output. Exit 1 if anything spills at any size. A --session page is already loaded at one size, so it takes no --size.

        Formats: json (default) — viewport, document width, violations, scrollContainers; text — one line each.

        Examples:
          sleepy overflow http://localhost:3000/report
          sleepy overflow http://localhost:3000/report --size 390x800 --format text
          sleepy overflow http://localhost:3000/report --size 390x800 --size 1280x900
          sleepy overflow --session app

        Exit codes: 0 nothing spills, 1 at least one element spills (at any size), 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    /// The formats `overflow` supports: the full report as JSON, or one line
    /// per finding.
    static let supportedFormats: Set<OutputFormat> = [.json, .text]

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .json,
            supporting: Self.supportedFormats,
            verb: "overflow",
        )
        let pageSource: PageSource = try source.resolve()
        let sweep = try OverflowSweep(sizes: flags.viewportSizes())
        // A session given several sizes takes the single path, whose session
        // seam refuses --size as a load-shaping flag.
        if sweep.isSweep, case let .url(url) = pageSource {
            let options: LoadOptions = try flags.resolveSizeSweepOptions(steps: PageExecution.actionSteps())
            let report: OverflowSweepReport = try await sweep.run(
                url,
                options: options,
                group: HostGroup(jar: flags.jar),
            )
            try write(report, as: resolvedFormat, text: Self.text(for: report))
            if !report.passes { Darwin.exit(ExitStatus.negative.rawValue) }
            return
        }
        let report: OverflowReport = try await PageExecution.run(
            OverflowOperation(),
            on: pageSource,
            flags: flags,
        )
        try write(report, as: resolvedFormat, text: Self.text(for: report))
        if !report.passes {
            Darwin.exit(ExitStatus.negative.rawValue)
        }
    }

    private func write(_ report: some Encodable, as format: OutputFormat, text: @autoclosure () -> String) throws {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try out.sink.write(encoder.encode(report))
        case .text:
            try out.sink.write(text())
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'overflow' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: json, text.",
            )
        }
    }

    /// The terse form: a headline carrying both widths, then one line per
    /// violation and per deliberate scroll container.
    static func text(for report: OverflowReport) -> String {
        var lines: [String] = [
            "\(count(report.violations.count, "violation"))"
                + " (viewport \(number(report.viewportWidth))px, document \(number(report.documentWidth))px)",
        ]
        for violation in report.violations {
            lines.append(
                "  \(violation.path)  right \(number(violation.right))px,"
                    + " over by \(number(violation.overflowBy))px  [\(violation.cause.rawValue)]",
            )
        }
        if !report.scrollContainers.isEmpty {
            lines.append(count(report.scrollContainers.count, "scroll container"))
            for container in report.scrollContainers {
                lines.append(
                    "  \(container.path)  scrolls \(number(container.scrollWidth))px"
                        + " in \(number(container.clientWidth))px",
                )
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The sweep's terse form: each size on a line of its own, with its
    /// single-size text indented beneath it.
    static func text(for sweep: OverflowSweepReport) -> String {
        sweep.sizes.map { entry in
            let body: String = text(for: entry.report)
                .split(separator: "\n")
                .map { "  \($0)\n" }
                .joined()
            return "\(entry.width)×\(entry.height)\n\(body)"
        }.joined()
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
