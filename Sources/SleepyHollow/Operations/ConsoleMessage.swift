/// One thing the page said: a `console` call, an uncaught error, or an
/// unhandled promise rejection.
///
/// The text is what the page's own arguments stringify to — strings verbatim,
/// objects as JSON where they serialize — joined by spaces, exactly as a
/// browser console would show them.
public struct ConsoleMessage: Friendly {
    /// The console level a message came in at. Errors and rejections report
    /// ``error``.
    public enum Level: String, Friendly {
        /// `console.debug`.
        case debug
        /// `console.log`.
        case log
        /// `console.info`.
        case info
        /// `console.warn`.
        case warn
        /// `console.error`, an uncaught error, or an unhandled rejection.
        case error
    }

    /// Where the message came from — the distinction a level alone loses.
    public enum Origin: String, Friendly {
        /// An explicit `console.*` call.
        case console
        /// An uncaught exception, via `window.onerror`.
        case uncaught
        /// A promise rejected with no handler.
        case unhandledRejection
    }

    /// The level.
    public var level: Level

    /// What produced the message.
    public var origin: Origin

    /// The stringified arguments, or the error's message.
    public var text: String

    /// When the page said it, in milliseconds since the document started —
    /// `performance.now()`, so the ordering is the page's own.
    public var timeMilliseconds: Double

    /// The script an uncaught error came from, when the page reported one.
    public var sourceURL: String?

    /// The line an uncaught error came from, when the page reported one.
    public var line: Int?

    /// Creates a console message.
    public init(
        level: Level,
        origin: Origin,
        text: String,
        timeMilliseconds: Double,
        sourceURL: String? = nil,
        line: Int? = nil,
    ) {
        self.level = level
        self.origin = origin
        self.text = text
        self.timeMilliseconds = timeMilliseconds
        self.sourceURL = sourceURL
        self.line = line
    }

    /// The label the terse format prints: the level for console calls, the
    /// origin for the things a level cannot describe.
    public var label: String {
        switch origin {
        case .console: level.rawValue
        case .uncaught: "uncaught"
        case .unhandledRejection: "rejection"
        }
    }

    /// One terse line: the label, padded into a column, then the text.
    public var terseLine: String {
        label.paddedToColumn(9) + " " + text
    }
}
