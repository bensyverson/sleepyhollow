import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy pdf` — a paginated PDF of the page (`WKWebView.createPDF`).
///
/// *Need:* print stylesheets and paginated artifacts (reports, invoices) are
/// rendering targets too; a PDF is a reviewable, attachable deliverable.
struct PdfCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdf",
        abstract: "Render a page to a paginated PDF.",
        discussion: """
        Examples:
          sleepy pdf http://localhost:3000/ --out page.pdf
          sleepy pdf http://localhost:3000/report --theme dark --out report.pdf
          sleepy pdf --session app --out app.pdf

        Exit codes: 0 success, 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let output = try await PageExecution.run(PDFOperation(), on: source.resolve(), flags: flags)
        try out.sink.write(output.pdf)
    }
}
