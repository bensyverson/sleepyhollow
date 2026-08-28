import Foundation
import SleepyHollow
import Testing
import TestSupport

/// The four checks themselves, each proved once passing and once failing —
/// a diagnosis that cannot fail is not a diagnosis.
@Suite("Doctor")
struct DoctorTests {
    /// A throwaway registry root short enough to leave room for a socket path.
    private static func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dr\(String(UInt32.random(in: 0 ..< UInt32.max), radix: 16))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Binary and helper resolution

    @Test
    func `the binary check passes for the running executable and names it`() {
        let executable: URL = SessionLauncher.currentExecutable()
        let check: DoctorCheck = Doctor.checkBinary(executable: executable)
        #expect(check.name == .binary)
        #expect(check.status == .ok)
        #expect(check.detail.contains(executable.path))
        #expect(check.nextMove == nil)
    }

    @Test
    func `the binary check fails and teaches a rebuild when nothing executable is there`() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/sleepy")
        let check: DoctorCheck = Doctor.checkBinary(executable: missing)
        #expect(check.status == .failed)
        #expect(check.detail.contains(missing.path))
        let nextMove: String = try #require(check.nextMove)
        #expect(nextMove.contains("swift build"))
    }

    // MARK: - Sessions directory

    @Test
    func `the sessions check passes for a short root and names the socket path budget`() throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let check: DoctorCheck = Doctor.checkSessions(registry: SessionRegistry(root: root))
        #expect(check.name == .sessions)
        #expect(check.status == .ok)
        #expect(check.detail.contains(root.appendingPathComponent("sessions").path))
        #expect(check.detail.contains("103"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("sessions").path))
    }

    @Test
    func `the sessions check fails when the socket path exceeds what the kernel can address`() throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let deep: URL = root.appendingPathComponent(String(repeating: "d", count: 96))
        let check: DoctorCheck = Doctor.checkSessions(registry: SessionRegistry(root: deep))
        #expect(check.status == .failed)
        #expect(check.detail.contains("103"))
        let nextMove: String = try #require(check.nextMove)
        #expect(nextMove.contains(SessionRegistry.homeEnvironmentVariable))
    }

    @Test
    func `the sessions check fails and names the directory when it cannot be created`() throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // A regular file where the root's directory must go: creating
        // `<file>/sessions` fails on every machine, privileges included.
        let blocked: URL = root.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocked)
        let check: DoctorCheck = Doctor.checkSessions(registry: SessionRegistry(root: blocked))
        #expect(check.status == .failed)
        #expect(check.detail.contains(blocked.appendingPathComponent("sessions").path))
        #expect(check.nextMove != nil)
    }

    // MARK: - Temp directory

    @Test
    func `the temp check names the directory Foundation actually uses`() {
        #expect(Doctor.defaultTemporaryDirectory.path == FileManager.default.temporaryDirectory.path)
        let check: DoctorCheck = Doctor.checkTemporaryDirectory()
        #expect(check.name == .temporaryDirectory)
        #expect(check.status == .ok)
        #expect(check.detail.contains(Doctor.defaultTemporaryDirectory.path))
        #expect(check.nextMove == nil)
    }

    @Test
    func `the temp check leaves nothing behind`() throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(Doctor.checkTemporaryDirectory(root).status == .ok)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test
    func `the temp check fails and names the directory when it cannot be written`() throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked: URL = root.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocked)
        let check: DoctorCheck = Doctor.checkTemporaryDirectory(blocked)
        #expect(check.status == .failed)
        #expect(check.detail.contains(blocked.path))
        let nextMove: String = try #require(check.nextMove)
        // Never "set TMPDIR": Foundation ignores it (see Doctor's DocC), so
        // that would be a plausible instruction that changes nothing.
        #expect(nextMove.contains("sandbox"))
        #expect(!nextMove.hasPrefix("Set TMPDIR"))
    }

    // MARK: - WebKit, and the whole run

    @Test
    @MainActor
    func `the WebKit check passes when the content process can launch`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, _ in
            let check: DoctorCheck = await Doctor.checkWebKit()
            #expect(check.name == .webKit)
            #expect(check.status == .ok)
            #expect(check.nextMove == nil)
        }
    }

    @Test
    @MainActor
    func `a run reports one check per kind, in diagnosis order`() async throws {
        let root: URL = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await FixtureServer.withRunningOnMainActor { _, _ in
            let report: DoctorReport = await Doctor.run(registry: SessionRegistry(root: root))
            #expect(report.checks.map(\.name) == [.binary, .webKit, .sessions, .temporaryDirectory])
            #expect(report.status == .ok)
            #expect(report.error == nil)
        }
    }
}
