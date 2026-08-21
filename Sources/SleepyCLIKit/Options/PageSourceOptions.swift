import ArgumentParser
import Foundation
import SleepyHollow

/// The shared "give me a page" arguments every page verb takes: a URL to
/// load ephemerally, or a live named session — the uniform grammar from the
/// vision doc's "The grammar" section.
///
/// Exactly one of the two must be given; both or neither is a usage error
/// that teaches the grammar.
public struct PageSourceOptions: ParsableArguments {
    @Argument(help: "A URL to load ephemerally (needs a scheme, e.g. http:// or file://).")
    public var url: String?

    @Option(name: .long, help: "Operate on this live session instead of a URL.")
    public var session: String?

    /// Creates an empty option group for ArgumentParser to populate.
    public init() {}

    /// Resolves the parsed arguments to Core's `PageSource`.
    ///
    /// Throws a teaching `SleepyError` when neither or both were given,
    /// the URL has no scheme, or the session name is invalid.
    public func resolve() throws -> PageSource {
        try Self.resolve(url: url, session: session)
    }

    /// The pure resolution logic behind ``resolve()``, exposed as a static
    /// function so it can be tested without invoking ArgumentParser.
    public static func resolve(url: String?, session: String?) throws -> PageSource {
        switch (url, session) {
        case let (.some(rawURL), .none):
            return try .url(resolveURL(rawURL))
        case let (.none, .some(rawSession)):
            return try .session(resolveSession(rawSession))
        case (.some, .some):
            throw SleepyError(
                kind: .usage,
                message: "Give a URL or --session, not both.",
                nextMove: "Drop the URL to act on the session, or drop --session to load fresh.",
            )
        case (.none, .none):
            throw SleepyError(
                kind: .usage,
                message: "A page source is required.",
                nextMove: "Give a URL (e.g. http://example.com) or --session <name>.",
            )
        }
    }

    // MARK: - The load verb's target

    /// What `sleepy load` was asked to do — the one verb that accepts a URL
    /// *and* `--session` at once.
    ///
    /// The vision doc gives `load` that privilege twice: §1 ("with
    /// `--session` it navigates an open session to a new URL") and §5's
    /// already-open error, which teaches `sleepy load --session login <url>`.
    /// Every other page verb keeps the two exclusive, because for a *read*
    /// they are two different pages.
    public enum LoadTarget: Friendly {
        /// Load this URL in a page that dies with the invocation.
        case ephemeral(URL)
        /// Act on a live session: navigate it to `navigatingTo`, or, when
        /// that is `nil`, report the page it is already on.
        case session(SessionName, navigatingTo: URL?)

        /// The page source this target executes against.
        public var pageSource: PageSource {
            switch self {
            case let .ephemeral(url): .url(url)
            case let .session(name, _): .session(name)
            }
        }

        /// Where to navigate, when this target navigates at all.
        public var navigationURL: URL? {
            switch self {
            case .ephemeral: nil
            case let .session(_, url): url
            }
        }
    }

    /// Resolves the parsed arguments to a ``LoadTarget``.
    public func resolveLoadTarget() throws -> LoadTarget {
        try Self.resolveLoadTarget(url: url, session: session)
    }

    /// The pure resolution logic behind ``resolveLoadTarget()``.
    public static func resolveLoadTarget(url: String?, session: String?) throws -> LoadTarget {
        switch (url, session) {
        case let (.some(rawURL), .none):
            return try .ephemeral(resolveURL(rawURL))
        case let (.none, .some(rawSession)):
            return try .session(resolveSession(rawSession), navigatingTo: nil)
        case let (.some(rawURL), .some(rawSession)):
            return try .session(resolveSession(rawSession), navigatingTo: resolveURL(rawURL))
        case (.none, .none):
            throw SleepyError(
                kind: .usage,
                message: "A page source is required.",
                nextMove: "Give a URL (e.g. http://example.com) or --session <name>.",
            )
        }
    }

    private static func resolveURL(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty else {
            throw SleepyError(
                kind: .usage,
                message: "'\(raw)' has no scheme.",
                nextMove: "Add http:// or file://, e.g. 'http://\(raw)'.",
            )
        }
        return url
    }

    private static func resolveSession(_ raw: String) throws -> SessionName {
        guard let name = SessionName(raw) else {
            throw SleepyError(
                kind: .usage,
                message: "'\(raw)' is not a valid session name.",
                nextMove: "Start with a letter or digit, then letters, digits, '.', '_', or '-'.",
            )
        }
        return name
    }
}
