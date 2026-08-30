import Foundation
import WebKit

/// Several ``PageHost``s that are one browser: one non-persistent
/// `WKWebsiteDataStore` — so one cookie store — and one cookie jar.
///
/// An ungrouped host builds its own data store, which is the right default for
/// a one-shot verb — nothing it touches outlives it. It is the wrong shape for
/// a harness that logs in once and then renders a dozen pages: each host would
/// have to import the jar again, and a cookie an earlier page deleted would
/// come back.
///
/// ```swift
/// let group = HostGroup(jar: JarName("login")!)
/// for size in sizes {
///     var options = LoadOptions()
///     options.size = size
///     let host = try PageHost.member(of: group, options: options)
///     _ = try await host.load(url)      // signed in, from the first load on
/// }
/// ```
///
/// ## What a group does *not* share: the HTTP cache
///
/// A group was asked for to make repeated loads cheaper — the first library
/// embedding measured 142 ms per load on a page carrying 3.4 MB of scripts,
/// re-fetched every time (`project/2026-08-29-woodcase-harness-feedback.md`,
/// finding 9) — on the premise that one `WKWebsiteDataStore` holds one cache.
/// **It does not, when the store is ephemeral.** Measured 2026-08-29 with
/// `scripts/measure-host-group.sh` (load average 17–30, so the absolute
/// milliseconds are an upper bound):
///
/// - two members loading one page: the script is fetched **twice**; adding a
///   shared `WKProcessPool` changes nothing (it is deprecated at this
///   package's own floor and is inert);
/// - one host loading the same page twice: fetched **once** — the cache is
///   real, it just lives in the web view's content process;
/// - two views on the *persistent* default store: fetched **once**;
/// - six loads at 3.4 MB, fresh hosts against one group: 285/205 ms per load
///   one way round and 204/260 ms the other — whichever arm runs second wins,
///   so grouping is worth no measurable time.
///
/// So a group is a shared *identity*, not a shared cache. What would deliver
/// the cache — an isolated persistent store (macOS 14) or re-using one web
/// view — is in `project/backlog.md`; the whole measurement is
/// `project/2026-08-29-host-group-cache.md`.
///
/// ## Why the group owns the jar
///
/// WebKit keeps cookies and the HTTP cache in the *same* `WKWebsiteDataStore`,
/// so a shared cache is necessarily a shared cookie store — there is no
/// arrangement in which members share a cache but not their cookies. That
/// makes the per-host jar bracket wrong inside a group: it would import the
/// jar again for each member (resurrecting a cookie an earlier member's page
/// had deleted, which is how a logout that did not stick starts) and export
/// the shared store to whichever jar each member happened to name. So the jar
/// is the group's: imported once, before any member's first navigation, and
/// exported after every member's load. A member whose ``LoadOptions/jar``
/// disagrees is refused at construction — see
/// ``PageHost/member(of:options:)``.
///
/// The store stays `nonPersistent()` for the same reason a host's does:
/// `WKWebsiteDataStore(forIdentifier:)` is macOS 14 and this package's floor
/// is 12, so persistence is ours — the import and export around a load.
///
/// - Note: a group is not a lifetime manager. It holds no reference to its
///   members; a host lives exactly as long as whoever made it keeps it.
@MainActor
public final class HostGroup {
    /// The jar every member reads from and writes back to; `nil` when the
    /// group keeps no cookies past its own lifetime.
    public let jar: JarName?

    /// The one data store every member's web view is configured with — the
    /// shared cookie store (and, being ephemeral, no shared cache; see above).
    ///
    /// Exposed for the same reason ``PageHost/webView`` is: an embedder that
    /// wants `WKWebsiteDataStore`'s own API (removing records, listing data
    /// types) should not need a wrapper method per call.
    public let dataStore: WKWebsiteDataStore

    /// Where ``jar`` is read and written. Members use this store, not one of
    /// their own — which is why ``PageHost/member(of:options:)`` takes no
    /// `jars` argument.
    let jars: JarStore

    /// Whether the jar has already been pulled into the shared cookie store.
    private var hasImportedJar = false

    /// Creates a group: a fresh non-persistent data store, optionally
    /// attached to a jar.
    ///
    /// - Parameter jar: the jar every member shares, or `nil` for a group
    ///   whose cookies die with it.
    /// - Parameter jars: where that jar is read and written; the default store
    ///   honours `SLEEPYHOLLOW_HOME`, and tests inject a throwaway root.
    public init(jar: JarName? = nil, jars: JarStore = JarStore()) {
        self.jar = jar
        self.jars = jars
        dataStore = WKWebsiteDataStore.nonPersistent()
    }

    /// The cookies the shared page store currently holds.
    public func currentCookies() async -> [CookieRecord] {
        await CookieStoreBridge.allCookies(in: dataStore.httpCookieStore)
    }

    /// Writes the shared store's cookies back to ``jar``.
    ///
    /// A no-op when the group has no jar. Every member's load calls this, so
    /// a cookie minted by any of them lands; call it directly only after
    /// mutating cookies past the end of a load.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar cannot be written.
    public func saveJar() async throws {
        guard let jar else { return }
        try await jars.write(currentCookies(), to: jar)
    }

    /// Loads ``jar``'s cookies into the shared store, once for the whole group.
    ///
    /// Once, not per member and not per load: re-importing after a page has
    /// deleted a cookie would resurrect it.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar exists but cannot be read — an unreadable jar must not look
    ///   like a logged-out one.
    func importJarIfNeeded() async throws {
        guard let jar, !hasImportedJar else { return }
        hasImportedJar = true
        try await CookieStoreBridge.load(jars.cookies(in: jar), into: dataStore.httpCookieStore)
    }

    /// Saves the jar, swallowing a write failure — the shape a failing load
    /// needs, where the load's own error is the one worth reporting.
    func saveJarIgnoringFailure() async {
        try? await saveJar()
    }

    /// Points `configuration` at the shared data store — the whole of what a
    /// member shares.
    ///
    /// There is deliberately no shared `WKProcessPool` here. It is the API
    /// that used to decide which web views share a content process, and it was
    /// deprecated *at this package's own floor*: "Creating and using multiple
    /// instances of WKProcessPool no longer has any effect" (`WKProcessPool.h`,
    /// `API_DEPRECATED(… macos(10.10, 12.0))`). Modern WebKit decides process
    /// sharing from the data store and the site, so the store is both the
    /// mechanism and the whole of it; a pool would be a property that holds no
    /// decision.
    func configure(_ configuration: WKWebViewConfiguration) {
        configuration.websiteDataStore = dataStore
    }

    /// Refuses a member whose own jar is not this group's.
    ///
    /// `nil` is agreement, not disagreement: a member that names no jar
    /// inherits the group's. Anything else — a different name, or a name where
    /// the group has none — would export the *shared* store, cookies from
    /// every other member included, to a jar of its own.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage``.
    func requireJarAgrees(with candidate: JarName?) throws {
        guard let candidate, candidate != jar else { return }
        let mine: String = jar.map { "the group's jar '\($0.rawValue)'" } ?? "no jar at all"
        throw SleepyError(
            kind: .usage,
            message: "This host asks for jar '\(candidate.rawValue)', and its group has \(mine). "
                + "A group is one browser: its members share one cookie store, so they cannot keep separate jars.",
            nextMove: jar == nil
                ? "Pass the jar to HostGroup(jar:) instead, and leave it off the member."
                : "Drop the member's jar so it inherits the group's, or give it a group of its own.",
        )
    }
}
