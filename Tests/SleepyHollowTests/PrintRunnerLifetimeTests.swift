import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// Who owns the print delegate after the budget runs out.
///
/// `NSPrintOperation` does not retain the object it sends `didRun:` to, and a
/// document-modal operation keeps running on its own `NSThread` after the
/// budget has already answered the caller. Three crash reports on 2026-08-29
/// caught the consequence: `-[NSConcretePrintOperation _finishModalOperation]`
/// messaging a freed `PrintRunner` — twice `doesNotRecognizeSelector` through
/// the forwarding path's `__retain_OA`, once a SIGSEGV in `objc_msgSend`.
@Suite("PrintRunner lifetime")
struct PrintRunnerLifetimeTests {
    @Test
    @MainActor
    func `a runner outlives a timed-out print, so AppKit's late callback has an object`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "print-paginated.html", relativeTo: base)))
            let offscreen = host.ensureOffscreenWindow(ordering: .unordered, rendering: .hidden)
            let destination: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sleepy-printrunner-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: destination) }
            let operation: NSPrintOperation = host.webView.printOperation(with: Self.printInfo(savingTo: destination))
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false

            weak var observed: PrintRunner?
            do {
                let runner = PrintRunner()
                observed = runner
                // A zero budget always wins the race: `runModal(for:…)` hands
                // the job to a secondary thread and returns, so the deadline
                // fires on the very next turn of the main actor while the
                // print is still in flight — the field case exactly.
                let finished: Bool = await runner.run(operation, in: offscreen.window, budget: 0)
                #expect(finished == false, "a zero budget must take the deadline path")
            }
            #expect(
                observed != nil,
                "AppKit will still send didRun: to this runner; releasing it is the 2026-08-29 crash",
            )
        }
    }

    /// A save-to-file print job, the shape `PDFOperation` uses.
    @MainActor
    private static func printInfo(savingTo destination: URL) -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = PaperSize.letter.points
        info.orientation = .portrait
        info.leftMargin = 0
        info.rightMargin = 0
        info.topMargin = 0
        info.bottomMargin = 0
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        return info
    }
}
