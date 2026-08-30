import Foundation
import WebKit

/// The jar seam: the bridge to `WKHTTPCookieStore`, and the import/export
/// either side of a load.
///
/// The data store stays `nonPersistent()` even when a jar is named — WebKit's
/// own persistent stores are keyed by identifier only from macOS 14, and this
/// package's floor is 12 — so persistence is *ours*: the jar's cookies are
/// pushed into the ephemeral store before the first navigation, and whatever
/// the store holds afterwards is written back. The happy consequence is that
/// nothing under `~/.sleepyhollow` is ever touched unless
/// ``LoadOptions/jar`` names a jar.
public extension PageHost {
    /// The cookies the live page store currently holds.
    func currentCookies() async -> [CookieRecord] {
        await Self.allCookies(in: webView.configuration.websiteDataStore.httpCookieStore)
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
        await Self.set(cookie, in: webView.configuration.websiteDataStore.httpCookieStore)
    }

    /// Writes the live store's cookies back to ``LoadOptions/jar``.
    ///
    /// A no-op when no jar was named. Call this after mutating cookies past
    /// the end of a load — ``PageHost/load(_:budget:)`` already saves for itself.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar cannot be written.
    func saveJar() async throws {
        guard let jar: JarName = options.jar else { return }
        try await jars.write(currentCookies(), to: jar)
    }
}

extension PageHost {
    /// Loads ``LoadOptions/jar``'s cookies into the live store, once per host.
    ///
    /// Once, not per load: re-importing after the page has deleted a cookie
    /// would resurrect it, which is how a "log out" that did not stick starts.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar exists but cannot be read — an unreadable jar must not look
    ///   like a logged-out one.
    func importJarIfNeeded() async throws {
        guard let jar: JarName = options.jar, !hasImportedJar else { return }
        hasImportedJar = true
        let store: WKHTTPCookieStore = webView.configuration.websiteDataStore.httpCookieStore
        for record in try jars.cookies(in: jar) {
            guard let cookie: HTTPCookie = record.httpCookie else { continue }
            await Self.set(cookie, in: store)
        }
        // One round-trip through the store after the sets: it is what forces
        // WebKit to hand the cookies to its networking process before the
        // first request goes out.
        _ = await Self.allCookies(in: store)
    }

    /// Saves the jar, swallowing a write failure.
    ///
    /// Used on ``PageHost/load(_:budget:)``'s failing paths: a login that redirected
    /// and then timed out has still minted its cookie, and the load's own
    /// error is the one worth reporting.
    func saveJarIgnoringFailure() async {
        try? await saveJar()
    }

    // MARK: - The WKHTTPCookieStore bridge

    /// `WKHTTPCookieStore`'s reads and writes are completion-handler APIs with
    /// optional handlers, so Swift generates no `async` overloads for them;
    /// these two wrappers are the whole bridge. Both map to ``CookieRecord``
    /// or take an already-built `HTTPCookie` so nothing non-`Sendable` crosses
    /// a continuation.
    @MainActor
    private static func allCookies(in store: WKHTTPCookieStore) async -> [CookieRecord] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[CookieRecord], Never>) in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies.map(CookieRecord.init))
            }
        }
    }

    @MainActor
    private static func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }
}
