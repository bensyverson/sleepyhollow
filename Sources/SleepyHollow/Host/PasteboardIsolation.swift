import AppKit
import Foundation
import ObjectiveC

/// Redirects the general pasteboard to one private to this process, so a
/// page's copy never reaches the clipboard of whoever runs `sleepy`, and a
/// page's paste never reads it.
///
/// A page that copies (`document.execCommand('copy')` after a click,
/// `navigator.clipboard.writeText`) writes to the *system* clipboard: WebKit's
/// web content process hard-codes `NSPasteboardNameGeneral`
/// (`Pasteboard::createForCopyAndPaste`) and the UI process, which is this
/// one, opens it with `+[NSPasteboard pasteboardWithName:]`
/// (`PlatformPasteboard::PlatformPasteboard`). Read in WebKit's source
/// 2026-11-06: no `WKWebView`, `WKWebViewConfiguration` or `WKPreferences`
/// property picks another name. Measured the same day: `sleepy dom <page>
/// --click '#b'` replaced a `pbpaste` sentinel with the page's text.
///
/// The one lever is in this process: replace the implementation of
/// `+[NSPasteboard pasteboardWithName:]` and `+[NSPasteboard generalPasteboard]`
/// so the general pasteboard resolves to a uniquely named one. Pages see an
/// ordinary clipboard — copy then paste inside the page works — that simply is
/// not the user's. Drag pasteboards and every other name pass through.
///
/// This replaces the implementation of **public** API at runtime. It is
/// installed by ``PageHost`` before its first web view exists, unless the
/// embedder chose ``ClipboardIsolation/shared`` through
/// ``PageHost/clipboardIsolation``, which also restores the originals live; when the methods cannot be found it is skipped,
/// ``isIsolated`` is `false`, and `sleepy doctor` fails its `pasteboard`
/// check — the fallback is loud, never silent. `PasteboardIsolationTests`
/// goes red if WebKit stops reaching the redirected methods.
@MainActor
enum PasteboardIsolation {
    /// What one installation leaves behind: the two replaced methods, the
    /// implementations to put back, and the pasteboards on either side.
    private struct Installation: @unchecked Sendable {
        /// The real general pasteboard, resolved through the original
        /// implementation.
        let user: NSPasteboard
        /// What pages copy into.
        let page: NSPasteboard
        /// `+pasteboardWithName:` and its original and redirecting
        /// implementations.
        let named: Method
        let originalNamed: IMP
        let redirectedNamed: IMP
        /// `+generalPasteboard` and its original and redirecting
        /// implementations.
        let general: Method
        let originalGeneral: IMP
        let redirectedGeneral: IMP
    }

    /// `nil` until the redirect has been installed, and `nil` afterward if it
    /// could not be.
    private static var installation: Installation?

    /// Whether the redirecting implementations are currently in place.
    private static var isRedirecting = false

    /// Whether ``install()`` has been tried in this process.
    private static var hasTriedInstall = false

    /// The user's real clipboard, for tests that must prove it was left
    /// alone. `nil` until the redirect has been installed once.
    static var userPasteboard: NSPasteboard? {
        installation?.user
    }

    /// The private pasteboard a page's copy lands in. `nil` until the
    /// redirect has been installed once.
    static var pagePasteboard: NSPasteboard? {
        installation?.page
    }

    /// Whether general-pasteboard lookups currently resolve to the private
    /// pasteboard — `false` when the AppKit methods could not be replaced, or
    /// when the embedder chose ``ClipboardIsolation/shared``.
    static var isIsolated: Bool {
        guard let installation else { return false }
        return NSPasteboard.general === installation.page
            && installation.user !== installation.page
    }

    /// Puts the process in the mode ``PageHost/clipboardIsolation`` names.
    /// ``PageHost`` calls this before it creates its web view; it is
    /// idempotent.
    static func ensureApplied() {
        apply(PageHost.clipboardIsolation)
    }

    /// Switches the process to `mode` now: installs the redirect the first
    /// time it is wanted, swaps the redirecting implementations in for
    /// ``ClipboardIsolation/isolated``, and the originals back for
    /// ``ClipboardIsolation/shared``.
    ///
    /// - Parameter mode: the isolation to have from this call on.
    static func apply(_ mode: ClipboardIsolation) {
        switch mode {
        case .isolated:
            if !hasTriedInstall {
                hasTriedInstall = true
                installation = install()
                isRedirecting = installation != nil
            } else if let installation, !isRedirecting {
                method_setImplementation(installation.named, installation.redirectedNamed)
                method_setImplementation(installation.general, installation.redirectedGeneral)
                isRedirecting = true
            }
        case .shared:
            guard let installation, isRedirecting else { return }
            method_setImplementation(installation.named, installation.originalNamed)
            method_setImplementation(installation.general, installation.originalGeneral)
            isRedirecting = false
        }
    }

    /// Replaces both class methods, or neither.
    private static func install() -> Installation? {
        guard let named = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("pasteboardWithName:")),
              let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))
        else { return nil }
        typealias Named = @convention(c) (AnyObject, Selector, NSPasteboard.Name) -> NSPasteboard?
        typealias General = @convention(c) (AnyObject, Selector) -> NSPasteboard
        let namedIMP: IMP = method_getImplementation(named)
        let generalIMP: IMP = method_getImplementation(general)
        let originalNamed = unsafeBitCast(namedIMP, to: Named.self)
        let originalGeneral = unsafeBitCast(generalIMP, to: General.self)
        let user: NSPasteboard = originalGeneral(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))
        let page = NSPasteboard.withUniqueName()
        let namedBlock: @convention(block) (AnyObject, NSPasteboard.Name) -> NSPasteboard? = { target, name in
            name == .general
                ? page
                : originalNamed(target, NSSelectorFromString("pasteboardWithName:"), name)
        }
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in page }
        let redirectedNamed: IMP = imp_implementationWithBlock(namedBlock)
        let redirectedGeneral: IMP = imp_implementationWithBlock(generalBlock)
        method_setImplementation(named, redirectedNamed)
        method_setImplementation(general, redirectedGeneral)
        return Installation(
            user: user,
            page: page,
            named: named,
            originalNamed: namedIMP,
            redirectedNamed: redirectedNamed,
            general: general,
            originalGeneral: generalIMP,
            redirectedGeneral: redirectedGeneral,
        )
    }
}
