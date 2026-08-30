import Foundation
import WebKit

/// The jar seam: the live cookie store, and the import/export either side of
/// a load.
///
/// The data store stays `nonPersistent()` even when a jar is named — WebKit's
/// own persistent stores are keyed by identifier only from macOS 14, and this
/// package's floor is 12 — so persistence is *ours*: the jar's cookies are
/// pushed into the ephemeral store before the first navigation, and whatever
/// the store holds afterwards is written back. The happy consequence is that
/// nothing under `~/.sleepyhollow` is ever touched unless
/// ``LoadOptions/jar`` names a jar.
///
/// In a ``HostGroup`` the same bracket runs one level up: the group's store is
/// the one every member reads and writes, so the import happens once for the
/// group and the export happens after any member's load. Everything here
/// delegates when ``PageHost/group`` is set, which is what keeps the two from
/// fighting over the same cookies.
public extension PageHost {
    /// The cookies the live page store currently holds.
    ///
    /// In a ``HostGroup`` that store is the group's, so this is every
    /// member's cookies, not this host's alone.
    func currentCookies() async -> [CookieRecord] {
        await CookieStoreBridge.allCookies(in: cookieStore)
    }

    /// Puts `record` in the live page store, replacing any cookie in the same
    /// slot (name, domain and path).
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when the
    ///   record is not one Foundation will accept as a cookie.
    func setCookie(_ record: CookieRecord) async throws {
        guard let cookie: HTTPCookie = record.httpCookie else {
            throw SleepyError(
                kind: .usage,
                message: "'\(record.name)' is not a cookie WebKit will accept for domain '\(record.domain)'.",
                nextMove: "Give a non-empty --name and a --domain the page can actually be sent to.",
            )
        }
        await CookieStoreBridge.set(cookie, in: cookieStore)
    }

    /// Writes the live store's cookies back to ``LoadOptions/jar`` — or, in a
    /// ``HostGroup``, to the group's jar.
    ///
    /// A no-op when no jar was named. Call this after mutating cookies past
    /// the end of a load — ``PageHost/load(_:budget:)`` already saves for itself.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar cannot be written.
    func saveJar() async throws {
        if let group {
            try await group.saveJar()
            return
        }
        guard let jar: JarName = options.jar else { return }
        try await jars.write(currentCookies(), to: jar)
    }
}

extension PageHost {
    /// The cookie store this host's reads and writes go through: its own web
    /// view's, which in a group is the group's shared store.
    var cookieStore: WKHTTPCookieStore {
        webView.configuration.websiteDataStore.httpCookieStore
    }

    /// Loads ``LoadOptions/jar``'s cookies into the live store, once per host
    /// — or, in a ``HostGroup``, once per group.
    ///
    /// Once, not per load: re-importing after the page has deleted a cookie
    /// would resurrect it, which is how a "log out" that did not stick starts.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar exists but cannot be read — an unreadable jar must not look
    ///   like a logged-out one.
    func importJarIfNeeded() async throws {
        if let group {
            try await group.importJarIfNeeded()
            return
        }
        guard let jar: JarName = options.jar, !hasImportedJar else { return }
        hasImportedJar = true
        try await CookieStoreBridge.load(jars.cookies(in: jar), into: cookieStore)
    }

    /// Saves the jar, swallowing a write failure.
    ///
    /// Used on ``PageHost/load(_:budget:)``'s failing paths: a login that redirected
    /// and then timed out has still minted its cookie, and the load's own
    /// error is the one worth reporting.
    func saveJarIgnoringFailure() async {
        try? await saveJar()
    }
}
