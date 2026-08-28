import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy contrast` — is every label on this page readable against what it
/// sits on?
///
/// The answer is chiefly the exit code (0 nothing failing, 1 at least one
/// failure); the body lists what failed and what could not be measured.
/// Text over a `background-image` is reported as `unknown (image)` rather
/// than given a ratio, and does **not** make the verb exit 1 — a gap is not
/// a proven fault, and inventing a number would be worse than either.
///
/// `--selector` and `--min` are flags, not positionals — see
/// ``QueryCommand``'s discussion for why (the shared page-source group's
/// optional URL positional silently steals a same-position verb argument
/// when `--session` is used).
struct ContrastCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contrast",
        abstract: "Check every rendered text node's WCAG contrast against its real background. Exit 1 on any failure.",
        discussion: """
        The background is the part worth a verb: it walks ancestors compositing translucent layers, stops at the first background-image or gradient and reports 'unknown (image)' rather than a ratio, and for SVG <text> uses the fill of the topmost shape underneath — none of which getComputedStyle answers on its own.

        --min takes a named level or a bare ratio. wcag-aa (the default) is 4.5:1, or 3:1 for large text; wcag-aaa is 7:1, or 4.5:1 large. A bare ratio like 3.5 applies to every size — prefer the names, which carry both bars. Large text is WCAG's own rule: 24px or larger, or 18.66px or larger when bold.

        Text hidden by display, visibility or opacity, or with no rendered area, is skipped and counted.

        Formats: json (default) — minimum, counts, failures, unmeasured; text — one line per finding.

        Examples:
          sleepy contrast http://localhost:3000/report
          sleepy contrast http://localhost:3000/report --min wcag-aaa --format text
          sleepy contrast http://localhost:3000/report --selector '#summary-card'
          sleepy contrast --session app --min 3

        Exit codes: 0 nothing failing (unmeasured text is still listed), 1 at least one failure, 2 usage — including a --selector that matches nothing, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    /// The formats `contrast` supports: the full report as JSON, or one line
    /// per finding.
    static let supportedFormats: Set<OutputFormat> = [.json, .text]

    @OptionGroup var source: PageSourceOptions

    @Option(
        name: .long,
        help: "Minimum contrast: wcag-aa (default), wcag-aaa, or a bare ratio like 3.5 applied to every size.",
    )
    var min: ContrastMinimum?

    @Option(name: .long, help: "CSS selector; only text inside the matched elements is measured.")
    var selector: String?

    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .json,
            supporting: Self.supportedFormats,
            verb: "contrast",
        )
        let report: ContrastReport = try await PageExecution.run(
            ContrastOperation(minimum: min ?? .wcagAA, selector: selector),
            on: source.resolve(),
            flags: flags,
        )
        try write(report, as: resolvedFormat)
        if !report.passes {
            Darwin.exit(ExitStatus.negative.rawValue)
        }
    }

    private func write(_ report: ContrastReport, as format: OutputFormat) throws {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try out.sink.write(encoder.encode(report))
        case .text:
            try out.sink.write(Self.text(for: report))
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'contrast' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: json, text.",
            )
        }
    }

    /// The terse form: a headline, then one line per failure and per
    /// unmeasured node, then the counts.
    static func text(for report: ContrastReport) -> String {
        var lines = ["\(count(report.failures.count, "failure")) (\(report.minimum))"]
        for failure in report.failures {
            lines.append("  " + line(for: failure))
        }
        if !report.unmeasured.isEmpty {
            lines.append("\(count(report.unmeasured.count, "node")) over an image, unmeasured")
            for node in report.unmeasured {
                lines.append("  " + line(for: node))
            }
        }
        lines.append("\(report.checked) checked, \(report.skipped) skipped")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func line(for finding: ContrastReport.Finding) -> String {
        let size: String = finding.isLargeText ? "large" : "normal"
        let measured = if let ratio = finding.ratio, let background = finding.background {
            "\(ratio):1 needs \(finding.required):1  \(finding.foreground) on \(background)"
        } else {
            "no ratio  \(finding.foreground) on unknown (\(finding.reason ?? "unknown"))"
        }
        return "\(finding.path)  \(measured)  [\(size)]  \"\(finding.text)\""
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
