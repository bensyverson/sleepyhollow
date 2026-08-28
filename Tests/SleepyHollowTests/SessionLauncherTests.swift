import Foundation
@testable import SleepyHollow
import Testing

/// How the launcher decides *which file* is `sleepy`.
///
/// The rule is pure — two inputs, one URL — so it can be exercised without a
/// subprocess; ``SessionLauncherPathGoldenTests`` proves the same fix through
/// a real `$PATH` invocation.
struct SessionLauncherTests {
    @Test func `a bare argv0 never decides the path when the image is known`() {
        let resolved: URL = SessionLauncher.resolveExecutable(
            bundleExecutable: URL(fileURLWithPath: "/opt/sleepy/bin/sleepy"),
            argument0: "sleepy",
        )
        #expect(resolved.path == "/opt/sleepy/bin/sleepy")
    }

    @Test func `a relative argv0 never decides the path either`() {
        let resolved: URL = SessionLauncher.resolveExecutable(
            bundleExecutable: URL(fileURLWithPath: "/opt/sleepy/bin/sleepy"),
            argument0: "./sleepy",
        )
        #expect(resolved.path == "/opt/sleepy/bin/sleepy")
    }

    @Test func `argv0 is the fallback when there is no running image to ask`() {
        let resolved: URL = SessionLauncher.resolveExecutable(
            bundleExecutable: nil,
            argument0: "/opt/sleepy/bin/sleepy",
        )
        #expect(resolved.path == "/opt/sleepy/bin/sleepy")
    }

    @Test func `the fallback still yields an absolute path`() {
        let resolved: URL = SessionLauncher.resolveExecutable(bundleExecutable: nil, argument0: "sleepy")
        #expect(resolved.path.hasPrefix("/"))
    }

    @Test func `the resolved executable is an absolute path to a real file`() {
        let executable: URL = SessionLauncher.currentExecutable()
        #expect(executable.path.hasPrefix("/"))
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
    }
}
