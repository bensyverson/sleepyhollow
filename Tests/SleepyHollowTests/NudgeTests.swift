import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// The typed success tips: which facts justify which tip, that at most one
/// is ever chosen, and that the writer honours `--quiet`.
struct NudgeTests {
    // MARK: - Which tip the facts justify

    @Test func `a capture taller than the vision budget asks for --max-size or --tile`() {
        let facts = Nudge.ShotFacts(captureHeight: 9200, wasCapped: false, wasTiled: false, wroteToFile: true)
        #expect(Nudge.forShot(facts) == .captureTallerThanVisionBudget(cssHeight: 9200))
    }

    @Test func `a capture exactly at the vision budget earns no tip`() {
        let facts = Nudge.ShotFacts(captureHeight: 2000, wasCapped: false, wasTiled: false, wroteToFile: true)
        #expect(Nudge.forShot(facts) == nil)
    }

    @Test func `--max-size already answers the tall capture`() {
        let facts = Nudge.ShotFacts(captureHeight: 9200, wasCapped: true, wasTiled: false, wroteToFile: true)
        #expect(Nudge.forShot(facts) == nil)
    }

    @Test func `--tile already answers it too`() {
        let facts = Nudge.ShotFacts(captureHeight: 9200, wasCapped: false, wasTiled: true, wroteToFile: true)
        #expect(Nudge.forShot(facts) == nil)
    }

    @Test func `a shot with no --out names peep compare`() {
        let facts = Nudge.ShotFacts(captureHeight: 800, wasCapped: false, wasTiled: false, wroteToFile: false)
        #expect(Nudge.forShot(facts) == .baselineComparisonIsImageWork)
    }

    @Test func `at most one tip is chosen when both apply`() {
        let facts = Nudge.ShotFacts(captureHeight: 9200, wasCapped: false, wasTiled: false, wroteToFile: false)
        #expect(Nudge.forShot(facts) == .captureTallerThanVisionBudget(cssHeight: 9200))
    }

    @Test func `a capped shot with no --out still names peep compare`() {
        let facts = Nudge.ShotFacts(captureHeight: 9200, wasCapped: true, wasTiled: false, wroteToFile: false)
        #expect(Nudge.forShot(facts) == .baselineComparisonIsImageWork)
    }

    // MARK: - What each tip says

    @Test func `the tall-capture tip names the height and both cheaper flags`() {
        let text: String = Nudge.captureTallerThanVisionBudget(cssHeight: 9200).text
        #expect(text == "Tip: a 9,200-px capture is more than a vision model reads well; "
            + "--max-size 2000 gives an overview, --tile strips at readable scale.")
    }

    @Test func `the baseline tip names peep compare and --out`() {
        let text: String = Nudge.baselineComparisonIsImageWork.text
        #expect(text.contains("peep compare"))
        #expect(text.contains("--out"))
    }

    @Test(arguments: [(1, "1"), (999, "999"), (1000, "1,000"), (12982, "12,982"), (1_234_567, "1,234,567")])
    func `a height is grouped in threes so a vision budget is legible`(height: Int, grouped: String) {
        #expect(Nudge.captureTallerThanVisionBudget(cssHeight: height).text.contains("a \(grouped)-px capture"))
    }

    // MARK: - The writer

    @Test func `emitting writes the tip as one line`() throws {
        let written: String = try Self.captureEmission(of: .baselineComparisonIsImageWork, quiet: false)
        #expect(written == Nudge.baselineComparisonIsImageWork.text + "\n")
    }

    @Test func `--quiet writes nothing`() throws {
        let written: String = try Self.captureEmission(of: .baselineComparisonIsImageWork, quiet: true)
        #expect(written.isEmpty)
    }

    @Test func `no tip writes nothing`() throws {
        let written: String = try Self.captureEmission(of: nil, quiet: false)
        #expect(written.isEmpty)
    }

    /// Runs ``Nudge/emit(_:quiet:to:)`` against a throwaway file and returns
    /// what landed in it.
    private static func captureEmission(of nudge: Nudge?, quiet: Bool) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }

        let handle = try FileHandle(forWritingTo: file)
        Nudge.emit(nudge, quiet: quiet, to: handle)
        try handle.close()

        return try String(contentsOf: file, encoding: .utf8)
    }
}
