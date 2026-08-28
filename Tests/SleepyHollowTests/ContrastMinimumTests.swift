import Foundation
@testable import SleepyHollow
import Testing

/// `ContrastMinimum`: the named constants carry WCAG's *two* bars, a bare
/// ratio applies one bar to every size, and the spelling round-trips through
/// its single-string encoding.
@Suite("ContrastMinimum")
struct ContrastMinimumTests {
    @Test func `wcag-aa carries 4point5 normal and 3 large`() throws {
        let minimum: ContrastMinimum = try ContrastMinimum.parse("wcag-aa")
        #expect(minimum == .wcagAA)
        #expect(minimum.normalThreshold == 4.5)
        #expect(minimum.largeThreshold == 3.0)
    }

    @Test func `wcag-aaa carries 7 normal and 4point5 large`() throws {
        let minimum: ContrastMinimum = try ContrastMinimum.parse("wcag-aaa")
        #expect(minimum == .wcagAAA)
        #expect(minimum.normalThreshold == 7.0)
        #expect(minimum.largeThreshold == 4.5)
    }

    @Test func `a bare ratio applies to every size`() throws {
        let minimum: ContrastMinimum = try ContrastMinimum.parse("3.5")
        #expect(minimum == .ratio(3.5))
        #expect(minimum.normalThreshold == 3.5)
        #expect(minimum.largeThreshold == 3.5)
    }

    @Test func `the spelling is case-insensitive`() throws {
        #expect(try ContrastMinimum.parse("WCAG-AA") == .wcagAA)
    }

    @Test func `a ratio below 1 is a usage error`() {
        #expect(throws: SleepyError.self) {
            _ = try ContrastMinimum.parse("0.5")
        }
    }

    @Test func `a word that is neither a constant nor a number is a usage error`() {
        #expect(throws: SleepyError.self) {
            _ = try ContrastMinimum.parse("apca")
        }
    }

    @Test func `it encodes as one string and decodes back`() throws {
        for minimum in [ContrastMinimum.wcagAA, .wcagAAA, .ratio(3.25)] {
            let data: Data = try JSONEncoder().encode(minimum)
            #expect(String(data: data, encoding: .utf8) == "\"\(minimum.description)\"")
            #expect(try JSONDecoder().decode(ContrastMinimum.self, from: data) == minimum)
        }
    }

    @Test func `it describes itself the way it is typed`() {
        #expect(ContrastMinimum.wcagAA.description == "wcag-aa")
        #expect(ContrastMinimum.wcagAAA.description == "wcag-aaa")
        #expect(ContrastMinimum.ratio(3.25).description == "3.25")
    }
}
