import AppKit
import Foundation
import PDFKit
import SleepyHollow
import Testing
import TestSupport

@Suite("PDFOperation")
struct CapturePDFOperationTests {
    /// The banner `print-paginated.html` hides in print media; if it reaches
    /// the PDF, the render was a screen-media snapshot.
    private static let screenOnlyMarker: String = "SCREENONLYBANNER"

    @Test
    @MainActor
    func `pdf output starts with the PDF magic bytes and is non-trivial`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let output = try await host.execute(PDFOperation())
            #expect(output.pdf.count > 512)
            let header = output.pdf.prefix(5)
            #expect(header == Data("%PDF-".utf8))
        }
    }

    @Test
    @MainActor
    func `a print pass paginates onto several sheets and drops no-print elements`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "print-paginated.html", relativeTo: base)!)
            let output = try await host.execute(PDFOperation())
            let document = try #require(PDFDocument(data: output.pdf))
            #expect(document.pageCount >= 3)
            let text = try #require(document.string)
            #expect(text.contains("Paginated body paragraph"))
            #expect(!text.contains(Self.screenOnlyMarker))
        }
    }

    @Test
    @MainActor
    func `paper size picks the media box`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "print-paginated.html", relativeTo: base)!

            let letterHost = PageHost()
            _ = try await letterHost.load(url)
            let letter = try await letterHost.execute(PDFOperation(paper: .letter))
            let letterBox = try Self.mediaBox(of: letter.pdf)

            let a4Host = PageHost()
            _ = try await a4Host.load(url)
            let a4 = try await a4Host.execute(PDFOperation(paper: .a4))
            let a4Box = try Self.mediaBox(of: a4.pdf)

            print("[pdf] media box — letter: \(letterBox), a4: \(a4Box)")
            #expect(abs(Double(letterBox.width) - PaperSize.letter.points.width) < 2)
            #expect(abs(Double(letterBox.height) - PaperSize.letter.points.height) < 2)
            #expect(abs(Double(a4Box.width) - PaperSize.a4.points.width) < 2)
            #expect(abs(Double(a4Box.height) - PaperSize.a4.points.height) < 2)
            #expect(Double(a4Box.height) > Double(letterBox.height))
        }
    }

    @Test
    @MainActor
    func `printing opens no visible window and never activates the app`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "print-paginated.html", relativeTo: base)!)
            _ = try await host.execute(PDFOperation())
            // Non-vacuous: the print pass really did park the view in a
            // window, and that window is on no screen.
            let window = try #require(host.webView.window)
            #expect(window.screen == nil)
            #expect(window.isVisible == false)
            for screen in NSScreen.screens {
                #expect(!screen.frame.intersects(window.frame))
            }
            #expect(NSApp.isActive == false)
            #expect(NSApp.activationPolicy() == .prohibited)
            for visible in NSApp.windows where visible.isVisible {
                for screen in NSScreen.screens {
                    #expect(!screen.frame.intersects(visible.frame), "\(type(of: visible)) is on a screen")
                }
            }
        }
    }

    @Test
    @MainActor
    func `the page's @page margin governs the printed margin`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let plainHost = PageHost()
            _ = try await plainHost.load(URL(string: "print-paginated.html", relativeTo: base)!)
            let plain = try await plainHost.execute(PDFOperation())
            let plainInset = try Self.contentInset(of: plain.pdf)

            let ruledHost = PageHost()
            _ = try await ruledHost.load(URL(string: "print-page-margin.html", relativeTo: base)!)
            let ruled = try await ruledHost.execute(PDFOperation())
            let ruledInset = try Self.contentInset(of: ruled.pdf)

            print("[pdf] first-page content inset — no @page rule: \(plainInset), @page margin 1.25in: \(ruledInset)")
            // The documented ruling: NSPrintInfo adds nothing, so a page with
            // no rule prints edge to edge, and 1.25in of @page is 90pt of
            // inset on the sheet.
            #expect(plainInset.left < 2)
            #expect(abs(ruledInset.left - 90) < 2)
        }
    }

    @Test
    @MainActor
    func `a paper choice survives the wire`() throws {
        #expect(PDFOperation.kind == "pdf")
        let envelope = try OperationEnvelope(PDFOperation(paper: .a4))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == PDFOperation.kind)
        var registry = OperationRegistry()
        registry.register(PDFOperation.self)
        let operation = try registry.decode(decoded)
        let pdf = try #require(operation as? PDFOperation)
        #expect(pdf.paper == .a4)
    }

    @Test func `the operation is Friendly and round-trips through its envelope`() throws {
        #expect(PDFOperation.kind == "pdf")
        let envelope = try OperationEnvelope(PDFOperation())
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == PDFOperation.kind)
        var registry = OperationRegistry()
        registry.register(PDFOperation.self)
        let operation = try registry.decode(decoded)
        #expect(operation is PDFOperation)
    }

    /// The first page's media box.
    private static func mediaBox(of data: Data) throws -> CGRect {
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        return page.bounds(for: .mediaBox)
    }

    /// How far the first page's drawn text sits from the sheet's left and top
    /// edges, in points — the effective margin, measured rather than assumed.
    private static func contentInset(of data: Data) throws -> (left: Double, top: Double) {
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let selection = try #require(page.selection(for: box))
        let bounds = selection.bounds(for: page)
        return (left: Double(bounds.minX - box.minX), top: Double(box.maxY - bounds.maxY))
    }
}
