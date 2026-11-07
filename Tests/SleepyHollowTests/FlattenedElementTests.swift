import CoreGraphics
import Foundation
import SleepyHollow
import Testing

/// ``FlattenedElement`` as an embedder holds it: a `Friendly` wire value
/// whose reasons decode from the page's spelling, and a fact the readout
/// stages keep attached to the pixels it describes.
@Suite("FlattenedElement")
struct FlattenedElementTests {
    private static let back = FlattenedElement(
        path: "div#back",
        reasons: [.hiddenBackface],
        rect: DocumentRect(x: 775, y: 75, width: 200, height: 100),
    )

    private static let deep = FlattenedElement(
        path: "div#deep",
        reasons: [.perspectiveAncestor],
        rect: DocumentRect(x: 25, y: 1600, width: 200, height: 100),
    )

    @Test func `it round-trips through JSON`() throws {
        let decoded = try JSONDecoder().decode(FlattenedElement.self, from: JSONEncoder().encode(Self.back))
        #expect(decoded == Self.back)
    }

    @Test func `the reasons decode from the page's own spelling`() throws {
        let json = #"["perspectiveFunction","perspectiveAncestor","preserve3D","hiddenBackface"]"#
        let reasons = try JSONDecoder().decode([FlattenedElement.Reason].self, from: Data(json.utf8))
        #expect(reasons == [.perspectiveFunction, .perspectiveAncestor, .preserve3D, .hiddenBackface])
    }

    @Test func `a shot's output carries the finding across the wire`() throws {
        let output = ShotOperation.Output(images: [], renderer: .snapshot(.video), flattened3D: [Self.back])
        let decoded = try JSONDecoder().decode(ShotOperation.Output.self, from: JSONEncoder().encode(output))
        #expect(decoded.flattened3D == [Self.back])
        #expect(decoded.renderer == .snapshot(.video))
    }

    @Test func `fitting and gridding keep the finding, since the rect is unchanged`() throws {
        let capture = Self.flagged(syntheticCapture(rect: CGRect(x: 0, y: 0, width: 1280, height: 3000)))
        let fitted = try ShotFit(maxSize: 500).applied(to: capture)
        #expect(fitted.flattened3D == capture.flattened3D)
        let gridded = try ShotGrid.draw(
            ShotGrid.Options(mode: .rulers, step: 100),
            on: capture,
            pixelsPerCSSPixel: capture.pixelsPerCSSPixel,
        )
        #expect(gridded.flattened3D == capture.flattened3D)
    }

    @Test func `each strip keeps only the elements its rows show`() throws {
        let capture = Self.flagged(syntheticCapture(rect: CGRect(x: 0, y: 0, width: 1280, height: 2000)))
        let strips = try ShotTile(height: 1000).applied(to: capture)
        // Strips: 0–1000, 960–1960, 1920–2000.
        #expect(strips.map(\.flattened3D) == [[Self.back], [Self.deep], []])
    }

    private static func flagged(_ capture: ShotCapture) -> ShotCapture {
        ShotCapture(image: capture.image, rect: capture.rect, scale: capture.scale, flattened3D: [back, deep])
    }
}
