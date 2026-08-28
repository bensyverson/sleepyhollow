import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotRegion")
struct ShotRegionTests {
    @Test func `a rect parses from x,y,w,h in CSS px`() throws {
        let region = try ShotRegion.rect(parsing: "0,850,1280,1285")
        #expect(region == .rect(CGRect(x: 0, y: 850, width: 1280, height: 1285)))
    }

    @Test func `a rect tolerates spaces and decimals`() throws {
        let region = try ShotRegion.rect(parsing: " 10.5, 20 ,30,40 ")
        #expect(region == .rect(CGRect(x: 10.5, y: 20, width: 30, height: 40)))
    }

    @Test(arguments: ["", "1,2,3", "1,2,3,4,5", "a,b,c,d", "0,0,-1,10", "0,0,10,0"])
    func `a malformed or empty rect is a usage error`(text: String) {
        #expect(throws: SleepyError.self) {
            _ = try ShotRegion.rect(parsing: text)
        }
        do {
            _ = try ShotRegion.rect(parsing: text)
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `regions are Friendly and round-trip through JSON`() throws {
        let regions: [ShotRegion] = [.viewport, .fullPage, .element("#a"), .rect(CGRect(x: 1, y: 2, width: 3, height: 4))]
        for region in regions {
            let data = try JSONEncoder().encode(region)
            let decoded = try JSONDecoder().decode(ShotRegion.self, from: data)
            #expect(decoded == region)
        }
    }
}
