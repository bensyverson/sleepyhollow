import Foundation
@testable import SleepyHollow
import Testing

/// The on-disk jar directory: layout, the `SLEEPYHOLLOW_HOME` override,
/// round-tripping cookies, pruning expiry, and list/clear/rm.
@Suite("JarStore")
struct JarStoreTests {
    private func withStore(_ body: (JarStore) throws -> Void) throws {
        let root: URL = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        try body(JarStore(root: root))
    }

    private func record(name: String, expiresAt: Date? = nil) -> CookieRecord {
        CookieRecord(name: name, value: "v-\(name)", domain: "127.0.0.1", path: "/", expiresAt: expiresAt)
    }

    private var login: JarName {
        JarName("login-flow")!
    }

    // MARK: - Layout

    @Test func `jars live under the root's jars directory, one directory each`() {
        let root = URL(fileURLWithPath: "/tmp/sh-example")
        let store = JarStore(root: root)
        #expect(store.jarsDirectory.path == "/tmp/sh-example/jars")
        #expect(store.directory(for: login).path == "/tmp/sh-example/jars/login-flow")
        #expect(store.cookiesURL(for: login).lastPathComponent == "cookies.json")
    }

    @Test func `SLEEPYHOLLOW_HOME overrides the default root`() {
        let overridden: URL = JarStore.defaultRoot(environment: ["SLEEPYHOLLOW_HOME": "/tmp/elsewhere"])
        #expect(overridden.path == "/tmp/elsewhere")
        let fallback: URL = JarStore.defaultRoot(environment: [:])
        #expect(fallback.lastPathComponent == ".sleepyhollow")
    }

    @Test func `an empty override falls back to the home directory`() {
        let fallback: URL = JarStore.defaultRoot(environment: ["SLEEPYHOLLOW_HOME": ""])
        #expect(fallback.lastPathComponent == ".sleepyhollow")
    }

    // MARK: - Reading and writing

    @Test func `writing then reading a jar round-trips its cookies`() throws {
        try withStore { store in
            try store.write([record(name: "sid"), record(name: "csrf")], to: login)
            let read: [CookieRecord] = try store.cookies(in: login)
            #expect(read.map(\.name).sorted() == ["csrf", "sid"])
        }
    }

    @Test func `writing a jar creates it, so naming is creating`() throws {
        try withStore { store in
            #expect(!store.exists(login))
            try store.write([], to: login)
            #expect(store.exists(login))
            try #expect(store.cookies(in: login).isEmpty)
        }
    }

    @Test func `reading an absent jar yields no cookies rather than failing`() throws {
        try withStore { store in
            try #expect(store.cookies(in: login).isEmpty)
        }
    }

    @Test func `expired cookies are pruned on read`() throws {
        try withStore { store in
            let stale: CookieRecord = record(name: "stale", expiresAt: Date(timeIntervalSince1970: 1000))
            let fresh: CookieRecord = record(name: "fresh", expiresAt: Date(timeIntervalSince1970: 4_102_444_800))
            try store.write([stale, fresh], to: login, at: Date(timeIntervalSince1970: 500))
            let read: [CookieRecord] = try store.cookies(in: login, at: Date(timeIntervalSince1970: 2000))
            #expect(read.map(\.name) == ["fresh"])
        }
    }

    @Test func `expired cookies are pruned on write`() throws {
        try withStore { store in
            let stale: CookieRecord = record(name: "stale", expiresAt: Date(timeIntervalSince1970: 1000))
            try store.write([stale, record(name: "sid")], to: login, at: Date(timeIntervalSince1970: 2000))
            let read: [CookieRecord] = try store.cookies(in: login, at: Date(timeIntervalSince1970: 2000))
            #expect(read.map(\.name) == ["sid"])
        }
    }

    @Test func `a corrupt jar file is an environment error naming the jar`() throws {
        try withStore { store in
            try store.write([], to: login)
            try Data("not json".utf8).write(to: store.cookiesURL(for: login))
            let error: SleepyError? = #expect(throws: SleepyError.self) {
                _ = try store.cookies(in: login)
            }
            #expect(error?.kind == .environment)
            #expect(error?.message.contains("login-flow") == true)
        }
    }

    // MARK: - Management

    @Test func `listing reports every jar, sorted, with its cookie count`() throws {
        try withStore { store in
            try store.write([record(name: "sid")], to: login)
            try store.write([], to: JarName("admin")!)
            let summaries: [JarSummary] = store.summaries()
            #expect(summaries.map(\.name.rawValue) == ["admin", "login-flow"])
            #expect(summaries.map(\.cookieCount) == [0, 1])
        }
    }

    @Test func `listing an untouched root reports no jars`() throws {
        try withStore { store in
            #expect(store.summaries().isEmpty)
        }
    }

    @Test func `clearing empties a jar's cookies but keeps the jar`() throws {
        try withStore { store in
            try store.write([record(name: "sid")], to: login)
            try store.clear(login)
            #expect(store.exists(login))
            try #expect(store.cookies(in: login).isEmpty)
        }
    }

    @Test func `removing deletes the jar entirely`() throws {
        try withStore { store in
            try store.write([record(name: "sid")], to: login)
            try store.remove(login)
            #expect(!store.exists(login))
            #expect(store.summaries().isEmpty)
        }
    }

    @Test func `clearing an unknown jar is an environment error that teaches list`() throws {
        try withStore { store in
            let error: SleepyError? = #expect(throws: SleepyError.self) {
                try store.clear(login)
            }
            #expect(error?.kind == .environment)
            #expect(error?.exitStatus == .environment)
            #expect(error?.nextMove?.contains("sleepy jars list") == true)
        }
    }

    @Test func `removing an unknown jar is an environment error`() throws {
        try withStore { store in
            let error: SleepyError? = #expect(throws: SleepyError.self) {
                try store.remove(login)
            }
            #expect(error?.kind == .environment)
        }
    }

    @Test func `a jar file that is not a directory is ignored by listing`() throws {
        try withStore { store in
            try FileManager.default.createDirectory(at: store.jarsDirectory, withIntermediateDirectories: true)
            try Data("stray".utf8).write(to: store.jarsDirectory.appendingPathComponent(".DS_Store"))
            #expect(store.summaries().isEmpty)
        }
    }
}
