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

        Exit codes: 0 success, 2 usage, 4 load failure, 5 environment.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let steps: [ActionStep] = try ActionStepParser.parse(CommandLine.arguments)
        let options: LoadOptions = try flags.resolveLoadOptions(steps: steps)
        switch try source.resolve() {
        case .session:
            throw SleepyError(
                kind: .environment,
                message: "Sessions are not available yet.",
                nextMove: "Give a URL to load ephemerally; sessions arrive with the session leaves.",
            )
        case let .url(url):
            let host = PageHost(options: options)
            _ = try await host.load(url)
            let output = try await host.execute(PDFOperation())
            try out.sink.write(output.pdf)
        }
    }
}
