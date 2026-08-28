import Foundation
import SleepyHollow
import Testing

/// The report's own arithmetic: what a check means, how a run rolls up, and
/// the two renderings an agent reads.
@Suite("Doctor checks and report")
struct DoctorCheckTests {
    private static func passing(_ name: DoctorCheck.Kind) -> DoctorCheck {
        DoctorCheck(name: name, status: .ok, detail: "\(name.rawValue) is fine.")
    }

    // MARK: - A single check

    @Test
    func `a passing check carries no failure`() {
        let check: DoctorCheck = Self.passing(.binary)
        #expect(check.status == .ok)
        #expect(check.nextMove == nil)
        #expect(check.error == nil)
    }

    @Test
    func `a failed check is an environment failure carrying its next move`() throws {
        let check = DoctorCheck(
            name: .webKit,
            status: .failed,
            detail: "WebKit could not start under this sandbox.",
            nextMove: "Run the command outside the sandbox.",
        )
        let error: SleepyError = try #require(check.error)
        #expect(error.kind == .environment)
        #expect(error.exitStatus == ExitStatus.environment)
        #expect(error.message == "WebKit could not start under this sandbox.")
        #expect(error.nextMove == "Run the command outside the sandbox.")
    }

    // MARK: - The report

    @Test
    func `a report of passing checks is ok, has no failure and exits zero`() {
        let report = DoctorReport(checks: [
            Self.passing(.binary),
            Self.passing(.webKit),
            Self.passing(.sessions),
            Self.passing(.temporaryDirectory),
        ])
        #expect(report.status == .ok)
        #expect(report.firstFailure == nil)
        #expect(report.error == nil)
        #expect(report.exitStatus == ExitStatus.success)
    }

    @Test
    func `a report with any failure reports the first one and exits five`() throws {
        let report = DoctorReport(checks: [
            Self.passing(.binary),
            DoctorCheck(name: .webKit, status: .failed, detail: "No content process.", nextMove: "Leave the sandbox."),
            DoctorCheck(name: .sessions, status: .failed, detail: "Not writable.", nextMove: "Point HOME elsewhere."),
        ])
        #expect(report.status == .failed)
        #expect(report.firstFailure?.name == .webKit)
        #expect(report.exitStatus == ExitStatus.environment)
        let error: SleepyError = try #require(report.error)
        #expect(error.message == "No content process.")
        #expect(error.nextMove == "Leave the sandbox.")
    }

    // MARK: - Renderings

    @Test
    func `the text rendering names every check with its status, detail and next move`() {
        let report = DoctorReport(checks: [
            Self.passing(.binary),
            DoctorCheck(name: .webKit, status: .failed, detail: "No content process.", nextMove: "Leave the sandbox."),
        ])
        let lines: [String] = report.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("ok"))
        #expect(lines[0].contains("binary"))
        #expect(lines[0].hasSuffix("binary is fine."))
        #expect(lines[1].hasPrefix("failed"))
        #expect(lines[1].contains("webkit"))
        #expect(lines[1].hasSuffix("No content process."))
        #expect(lines[2].hasSuffix("Leave the sandbox."))
        #expect(lines[2].hasPrefix(" "))
        #expect(!report.text.hasSuffix("\n"))
    }

    @Test
    func `the JSON shape names each check and round-trips`() throws {
        let report = DoctorReport(checks: [
            DoctorCheck(name: .webKit, status: .failed, detail: "No content process.", nextMove: "Leave the sandbox."),
            Self.passing(.temporaryDirectory),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data = try encoder.encode(report)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"name\":\"webkit\""))
        #expect(json.contains("\"name\":\"temp\""))
        #expect(json.contains("\"status\":\"failed\""))
        #expect(json.contains("\"nextMove\":\"Leave the sandbox.\""))
        #expect(try JSONDecoder().decode(DoctorReport.self, from: data) == report)
    }
}
