import Foundation
import WebKit

extension WKHTTPCookieStore: CookieStoreCalls {
    /// `getAllCookies`, which WebKit answers on the main thread.
    func readAll(_ answered: @escaping @MainActor ([HTTPCookie]) -> Void) {
        getAllCookies { cookies in answered(cookies) }
    }

    /// `setCookie`, which WebKit answers on the main thread.
    func write(_ cookie: HTTPCookie, _ answered: @escaping @MainActor () -> Void) {
        setCookie(cookie) { answered() }
    }
}
