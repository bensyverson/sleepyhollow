import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotFit")
struct ShotFitTests {
    @Test func `a capture already inside the cap is left alone`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 400, height: 300))
        let fitted = try ShotFit(maxSize: 2000).applied(to: capture)
        #expect(fitted.pixelSize == CGSize(width: 400, height: 300))
        #expect(fitted.rect == capture.rect)
        #expect(fitted.pixelsPerCSSPixel == 1)
    }

    @Test func `a tall capture's longest side becomes exactly the cap`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 1280, height: 12982))
        let fitted = try ShotFit(maxSize: 2000).applied(to: capture)
        #expect(fitted.pixelSize == CGSize(width: 197, height: 2000))
    }

    @Test func `a wide capture caps its width instead`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 3000, height: 600))
        let fitted = try ShotFit(maxSize: 1500).applied(to: capture)
        #expect(fitted.pixelSize == CGSize(width: 1500, height: 300))
    }

    @Test func `fitting keeps the CSS rect and reports the thinned density`() throws {
        let rect = CGRect(x: 0, y: 850, width: 1280, height: 12982)
        let fitted = try ShotFit(maxSize: 2000).applied(to: syntheticCapture(rect: rect))
        #expect(fitted.rect == rect)
        #expect(fitted.scale == 1)
        #expect(abs(fitted.pixelsPerCSSPixel - 197.0 / 1280.0) < 0.0001)
    }

    @Test func `fitting a 2x render leaves the render scale alone`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 1000, height: 500), scale: 2)
        let fitted = try ShotFit(maxSize: 1000).applied(to: capture)
        #expect(fitted.pixelSize == CGSize(width: 1000, height: 500))
        #expect(fitted.scale == 2)
        #expect(fitted.pixelsPerCSSPixel == 1)
    }

    @Test func `the fitted image keeps the source's vertical order`() throws {
        // Bands 100 CSS px tall in a 1000px capture, halved: band 0 (red 0)
        // must still be on top, band 9 (red 153) at the bottom.
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 1000))
        let fitted = try ShotFit(maxSize: 500).applied(to: capture)
        #expect(redChannel(of: fitted.image, x: 50, y: 5) == 0)
        let bottom = try #require(redChannel(of: fitted.image, x: 50, y: 494))
        #expect(abs(Int(bottom) - 153) <= 2)
    }

    @Test(arguments: [0, -1]) func `a cap of zero or less is a usage error`(maxSize: Int) throws {
        do {
            _ = try ShotFit(maxSize: maxSize)
            Issue.record("expected a usage SleepyError")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.exitStatus == ExitStatus.usage)
        }
    }

    @Test func `the stage is Friendly and round-trips`() throws {
        let fit = try ShotFit(maxSize: 2000)
        let decoded = try JSONDecoder().decode(ShotFit.self, from: JSONEncoder().encode(fit))
        #expect(decoded == fit)
    }
}
