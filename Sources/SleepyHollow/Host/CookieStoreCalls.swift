import Foundation

/// The two `WKHTTPCookieStore` calls ``CookieStoreBridge`` makes, in the
/// completion-handler shape WebKit answers them in.
///
/// A seam, not an abstraction: `WKHTTPCookieStore` is the only production
/// conformer. It exists because a real store cannot be made to stall on
/// demand, and the deadline around these calls needs a store that never
/// answers to be tested at all.
@MainActor
protocol CookieStoreCalls: AnyObject {
    /// Reads every cookie the store holds, answering on the main actor.
    func readAll(_ answered: @escaping @MainActor ([HTTPCookie]) -> Void)

    /// Stores `cookie`, replacing any cookie in the same slot, and answers
    /// on the main actor once it is stored.
    func write(_ cookie: HTTPCookie, _ answered: @escaping @MainActor () -> Void)
}
