import AppKit
import Foundation
import WebKit

/// `sleepy pdf` — a paginated, print-media PDF of the currently loaded page.
///
/// *Need:* print stylesheets and paginated artifacts (reports, invoices) are
/// rendering targets too; a PDF is a reviewable, attachable deliverable.
///
/// This is Safari's Save-as-PDF path, not `WKWebView.pdf(configuration:)`.
/// The latter renders **screen** media onto one sheet as tall as the document
/// — a 9,200px page came back as a single 1280×8533pt page with `.no-print`
/// elements still showing (`project/2026-08-24-first-agent-user-feedback.md`,
/// bug 3). `NSPrintOperation` instead asks WebKit to lay the page out for
/// paper: `@media print` applies, `@page` governs the margins, and the
/// content is broken across ``PaperSize`` sheets.
///
/// Three things about the AppKit path are load-bearing and were each measured
/// (`project/2026-08-28-offscreen-window-host.md`, "What printing needs"):
///
/// - **A window is required — to be modal *for*.** `runModal(for:…)` takes
///   one, so the host is asked for
///   ``PageHost/ensureOffscreenWindow(ordering:rendering:)``. The web view
///   itself does not need to be in it: `printOperation(with:)` paginates in
///   the web content process, and a windowless view printed modally for an
///   unrelated window produced byte-identical output. Nothing is ever
///   visible, and the app never activates.
/// - **The operation must be run document-modally**, with
///   `runModal(for:delegate:didRun:contextInfo:)` — see ``PrintRunner``.
///   Synchronous `run()` produced an unbounded run of empty pages in the
///   field (a 666 MB file before it was killed).
/// - **Margins belong to the page.** `NSPrintInfo`'s margins are set to zero
///   and the document's `@page { margin }` rule decides. Measured: a `@page`
///   rule overrides `NSPrintInfo` outright rather than adding to it, so the
///   rule is simply *the page decides* — and a page that says nothing prints
///   edge to edge, with no inset its stylesheet cannot see.
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

    /// The sheet to paginate onto.
    public let paper: PaperSize

    /// Creates a PDF operation.
    ///
    /// - Parameter paper: the sheet size; US Letter by default.
    public init(paper: PaperSize = .letter) {
        self.paper = paper
    }

    /// Renders the currently loaded page to a paginated, print-media PDF.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   print operation does not finish inside the host's budget — the one
    ///   thing forbidden is a hang — or
    ///   ``SleepyError/Kind/environment`` when AppKit reports the job failed
    ///   or wrote nothing.
    @MainActor
    public func execute(on host: PageHost) async throws -> Output {
        // Measured: every ordering and both rendering modes print the same
        // bytes, so this asks for the least intrusive pair — a window that
        // never enters the window list, and no rendering updates, which also
        // keeps `pdf` clear of the one piece of private API in the project.
        let offscreen = host.ensureOffscreenWindow(ordering: .unordered, rendering: .hidden)

        let destination: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-pdf-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: destination) }

        // `NSPrintOperation(view:)` is the wrong constructor here: the page
        // lives in another process, so AppKit's own drawing pass paginates
        // the right number of entirely blank sheets. `printOperation(with:)`
        // asks the web content process to lay itself out for paper.
        let operation = host.webView.printOperation(with: printInfo(savingTo: destination))
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        let finished: Bool = await PrintRunner.runModal(operation, in: offscreen.window, budget: host.budget)
        guard finished else {
            throw SleepyError(
                kind: .timeout,
                message: "The print operation did not finish within \(host.budget)s.",
                nextMove: "Raise the budget with --budget, or print a smaller page.",
            )
        }
        guard let data = try? Data(contentsOf: destination), !data.isEmpty else {
            throw SleepyError(
                kind: .environment,
                message: "The print operation finished but wrote no PDF.",
                nextMove: "Retry; if this persists, it is a seam bug against NSPrintOperation.",
            )
        }
        return Output(pdf: data)
    }

    /// The print job: this operation's paper, saved to `destination` rather
    /// than sent to a printer, with margins left to the document.
    ///
    /// Margins are zero here **on purpose**, and the behaviour was measured
    /// rather than assumed: a document's `@page { margin }` rule replaces
    /// whatever `NSPrintInfo` says (`@page` 1.25in gave a 90pt inset with
    /// `NSPrintInfo` at both 0pt and 72pt), while a document with no rule
    /// takes the `NSPrintInfo` value. So the only thing the number here
    /// decides is what an unstyled page gets — and zero is the answer that
    /// adds nothing the stylesheet author cannot see. A page that wants white
    /// space asks for it: `@page { margin: 0.5in }`.
    @MainActor
    private func printInfo(savingTo destination: URL) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = paper.points
        info.orientation = .portrait
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        return info
    }
}
