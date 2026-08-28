import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy pdf` — a paginated, print-media PDF of the page.
///
/// *Need:* print stylesheets and paginated artifacts (reports, invoices) are
/// rendering targets too; a PDF is a reviewable, attachable deliverable.
struct PdfCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdf",
        abstract: "Render a page to a paginated, print-media PDF.",
        discussion: """
        This is the Save-as-PDF path, not a screenshot: `@media print` rules apply, so `.no-print` elements are gone, and the content is broken across real sheets.

        Margins come from the page. A `@page { margin: … }` rule decides the margin on every sheet; a page with no such rule prints edge to edge, because nothing is added behind the stylesheet's back.

        Examples:
          sleepy pdf http://localhost:3000/ --out page.pdf
          sleepy pdf http://localhost:3000/report --paper a4 --out report.pdf
          sleepy pdf http://localhost:3000/report --theme dark --out report.pdf
          sleepy pdf --session app --out app.pdf

        Exit codes: 0 success, 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @Option(name: .long, help: "Sheet size: letter (8.5×11in) or a4 (210×297mm).")
    var paper: PaperSize = .letter

    @MainActor
    mutating func run() async throws {
        let output = try await PageExecution.run(
            PDFOperation(paper: paper),
            on: source.resolve(),
            flags: flags,
        )
        try out.sink.write(output.pdf)
    }
}
