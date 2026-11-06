import Foundation

/// Telling a real navigation from a same-document swap.
///
/// "Did the page reload?" cannot be answered from inside the page. A marker
/// the page stamps on `window` and the host reads back afterwards misses a
/// back or forward navigation outright: WebKit's back-forward cache restores
/// the earlier document *with its JavaScript heap*, marker and all
/// (2026-08-30 Woodcase report, item 5). The host can answer it, because
/// WebKit tells the navigation delegate every time a main-frame document
/// commits — including a document restored from that cache — and never for
/// a same-document change.
public extension PageHost {
    /// One main-frame navigation the host saw commit.
    struct Navigation: Friendly {
        /// Which navigation this was: the host's ``navigationCount`` right
        /// after it committed, so the first load is `1`.
        public var number: Int

        /// Where the page was when it committed, as WebKit reported it.
        public var url: URL?

        /// Records a navigation.
        ///
        /// - Parameter number: its place in the host's count.
        /// - Parameter url: where it committed.
        public init(number: Int, url: URL?) {
            self.number = number
            self.url = url
        }
    }

    /// How many main-frame documents have committed in this host since it was
    /// created — its own ``load(_:budget:)`` calls included.
    ///
    /// What counts is a *document change*: a load, a reload, a link or
    /// `location` navigation, a form submission, and a back or forward
    /// navigation — whether WebKit fetches it again or restores it from its
    /// back-forward cache. What does not count is a same-document change:
    /// `history.pushState`, `history.replaceState` and fragment (`#hash`)
    /// navigations move `webView.url` without a new document, which is how a
    /// single-page app routes. Subframe navigations do not count either. So
    /// "did that click reload the page?" is:
    ///
    /// ```swift
    /// let before = host.navigationCount
    /// try await host.execute(ClickOperation(selector: "a.next"))
    /// // … wait for the click's visible effect, then:
    /// let reloaded = host.navigationCount > before
    /// ```
    ///
    /// The count is the host's, fed by WebKit's navigation delegate on the
    /// main actor — a busy page cannot hide a navigation from it, and nothing
    /// in the page can forge one.
    var navigationCount: Int {
        delegate.navigations.count
    }

    /// Waits until the host has seen a navigation past `count`, and returns
    /// the most recent one.
    ///
    /// Read ``navigationCount`` *before* the action that should navigate and
    /// pass it here, so a navigation that commits before this call is not
    /// missed:
    ///
    /// ```swift
    /// let before = host.navigationCount
    /// try await host.evaluate("document.querySelector('form').submit(); return null;", in: .page)
    /// let landed = try await host.waitForNavigation(after: before)
    /// ```
    ///
    /// This waits for the *commit* — the new document exists and is the page
    /// — not for its load event; follow it with ``waitUntil(_:in:budget:)``
    /// for whatever the next step needs. A back navigation restored from the
    /// back-forward cache ends the wait like any other; a same-document change
    /// never does.
    ///
    /// - Parameter count: the ``navigationCount`` already seen.
    /// - Parameter budget: seconds to wait, or `nil` for the host's
    ///   ``budget``.
    /// - Returns: the latest navigation, at once when one past `count` has
    ///   already committed.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when no
    ///   navigation commits within the budget — the teaching names the
    ///   same-document case — and `CancellationError` when the caller is
    ///   cancelled first.
    @discardableResult
    func waitForNavigation(after count: Int, budget: TimeInterval? = nil) async throws -> Navigation {
        let applied: TimeInterval = budget ?? self.budget
        if let navigation = try await delegate.navigations.wait(after: count, budget: applied) {
            return navigation
        }
        let page: String = webView.url.map { " The page is still \($0.absoluteString)." } ?? ""
        throw SleepyError(
            kind: .timeout,
            message: "No navigation committed within \(applied)s after navigation #\(count).\(page)",
            nextMove: "Raise the budget if the page was slow to leave. A same-document change — "
                + "history.pushState, replaceState or a #hash — is not a navigation; wait for its effect "
                + "with waitUntil instead.",
        )
    }
}
