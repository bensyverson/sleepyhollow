import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// The correctness caveats: which findings earn one, what the line says, and
/// that nothing — `--quiet` included — has a switch to silence it.
struct CaveatTests {
    private static func element(_ path: String) -> FlattenedElement {
        FlattenedElement(path: path, reasons: [.perspectiveAncestor], rect: DocumentRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func `a shot with no flattened 3D earns no caveat`() {
        #expect(Caveat.forShot(flattened3D: []) == nil)
    }

    @Test func `one element is named, singular, with where to get a faithful render`() throws {
        let caveat = try #require(Caveat.forShot(flattened3D: [Self.element("div#card")]))
        #expect(caveat.text.hasPrefix("sleepy: this shot draws CSS 3D flat"))
        #expect(caveat.text.contains("1 element "))
        #expect(caveat.text.contains("div#card"))
        #expect(caveat.text.contains("Chrome"))
        #expect(!caveat.text.contains("\n"))
    }

    @Test func `past three elements, the rest are counted, not listed`() throws {
        let paths = ["div#a", "div#b", "div#c", "div#d", "div#e"]
        let caveat = try #require(Caveat.forShot(flattened3D: paths.map(Self.element)))
        #expect(caveat.text.contains("5 elements"))
        #expect(caveat.text.contains("div#a, div#b, div#c and 2 more"))
        #expect(!caveat.text.contains("div#d"))
    }

    @Test func `a sweep's caveat names the render it belongs to`() throws {
        let caveat = try #require(Caveat.forShot(flattened3D: [Self.element("div#card")], render: "480@2x"))
        #expect(caveat.text.hasPrefix("sleepy: the 480@2x render draws CSS 3D flat"))
    }

    @Test func `emit writes one line and takes no quiet switch`() throws {
        let pipe = Pipe()
        Caveat.emit(Caveat.forShot(flattened3D: [Self.element("div#card")]), to: pipe.fileHandleForWriting)
        Caveat.emit(nil, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()
        let written = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(written.hasSuffix("\n"))
        #expect(written.split(separator: "\n").count == 1)
    }
}
