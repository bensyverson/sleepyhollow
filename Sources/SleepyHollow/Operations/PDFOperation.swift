import Foundation
import WebKit

/// `sleepy pdf` — a paginated PDF of the currently loaded page
/// (`WKWebView.createPDF`).
///
/// *Need:* print stylesheets and paginated artifacts (reports, invoices) are
/// rendering targets too; a PDF is a reviewable, attachable deliverable.
public struct PDFOperation: ExecutablePageOperation {
    /// The PDF bytes a capture produced.
    public struct Output: Friendly {
        /// The encoded PDF document.
        public let pdf: Data

        /// Wraps encoded PDF bytes.
        public init(pdf: Data) {
            self.pdf = pdf
        }
    }

    /// The wire identifier.
    public static let kind: String = "pdf"

    /// Creates a PDF operation.
    public init() {}

    /// Renders the currently loaded page to a paginated PDF.
    ///
    /// `WKPDFConfiguration`'s default `rect` (the null rect) captures the
    /// whole page, so no explicit sizing is needed here.
    @MainActor
    public func execute(on host: PageHost) async throws -> Output {
        let data = try await host.webView.pdf(configuration: WKPDFConfiguration())
        return Output(pdf: data)
    }
}
