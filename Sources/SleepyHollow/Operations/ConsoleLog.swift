/// Everything the page said during this document's life: the output of
/// `sleepy console`.
///
/// The log covers the current document only — a navigation starts a fresh one,
/// because the capture lives in the page and the page is replaced.
public struct ConsoleLog: Friendly {
    /// The messages, in the order the page produced them.
    public var messages: [ConsoleMessage]

    /// How many older messages the page-side buffer dropped to stay bounded.
    /// Stated rather than hidden, so a truncated log is never mistaken for a
    /// complete one.
    public var droppedMessages: Int

    /// Creates a console log.
    public init(messages: [ConsoleMessage] = [], droppedMessages: Int = 0) {
        self.messages = messages
        self.droppedMessages = droppedMessages
    }

    /// The terse form: one labelled line per message, preceded by a line
    /// stating any drops. An empty log renders as nothing at all.
    public var terseText: String {
        var lines: [String] = []
        if droppedMessages > 0 {
            lines.append("(\(droppedMessages) earlier messages dropped)")
        }
        lines.append(contentsOf: messages.map(\.terseLine))
        return lines.joined(separator: "\n")
    }
}
