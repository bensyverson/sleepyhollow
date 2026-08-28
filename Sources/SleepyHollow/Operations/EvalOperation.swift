import Foundation

/// `sleepy eval`: the universal escape hatch — run JavaScript against the page
/// and get its value back as JSON.
///
/// The script is an **async function body**, exactly as
/// `WKWebView.callAsyncJavaScript` defines one: it may `await`, and it must
/// `return` the value to transport. One shape is auto-wrapped, and only one:
/// a script with no `return` keyword and no *interior* `;` is a single
/// expression, so it becomes `return (<script>);` — a single trailing `;` is
/// dropped first, because `el.click();` is a call, not a statement list. That
/// is safe because an expression with no `return` and nothing after its one
/// `;` cannot be a statement list — there is nothing to guess. `el.click()`
/// then answers `null` honestly: that is the call's own value, not a guess.
/// Anything else without a `return` — an interior `;`, or a leading `const`,
/// `if` or `throw` that can only open a statement — could never answer
/// anything, so it is refused with a usage error naming the fix rather than
/// answered wrongly. See ``SourceShape``.
///
/// The value is stringified *page-side*, so what the page can serialize is
/// what crosses. A page-side failure — a thrown error or a syntax error —
/// comes back as a ``SleepyError`` carrying the page's own message, never a
/// WebKit stack trace.
///
/// Evaluation happens in the **page's own** ``InjectedScript/World`` by
/// default: an agent's question is almost always about the page's own state,
/// and an isolated world answers a different question in the same words —
/// page globals, page classes and the prototypes the page installed on
/// upgraded custom elements are all invisible there, while the DOM and
/// `customElements.get()` still answer, so the split is silent until it bites.
/// Pass ``InjectedScript/World/isolated`` for instrumentation that must not
/// collide with page script; Sleepy's own injected scripts keep their own
/// worlds regardless. (Ruling: `2026-08-28-agent-feedback-synthesis.md`.)
public struct EvalOperation: ExecutablePageOperation {
    /// What a script *is*, structurally — the one decision that separates a
    /// value the page can return from a body that could only answer `null`.
    ///
    /// Read lexically, from signals that are cheap and explainable in the
    /// error message: a `return` keyword in statement position, an *interior*
    /// `;`, and a leading keyword that can only open a statement.
    public enum SourceShape: Friendly {
        /// The script returns for itself: it contains a `return` keyword in
        /// statement position. It is evaluated exactly as written.
        case functionBody
        /// A single expression, with at most one trailing `;` — wrapped as
        /// `return (<script>);` so `document.title` answers the title and
        /// `el.click();` answers the call's own value.
        case expression
        /// Statements (or nothing at all) with no `return`: an interior `;`,
        /// or a leading `const`/`if`/`throw`-style keyword that cannot open
        /// an expression. There is no value to send back, so it is refused.
        case unreturnedStatements
    }

    /// Keywords that can only open a *statement*, never an expression.
    ///
    /// `const x = 1;` has the lexical shape of an expression with a trailing
    /// `;`, but wrapping it could only ever produce a syntax error — so it
    /// earns the teaching refusal instead. `function` and `class` are
    /// deliberately absent: `return (function () {})` is valid.
    private static let statementKeywords: Set<String> = [
        "const", "let", "var", "if", "for", "while", "do", "switch",
        "try", "throw", "break", "continue", "debugger",
    ]

    /// This operation's typed result: the value as JSON text.
    public typealias Output = String

    /// The wire identifier.
    public static let kind: String = "eval"

    /// The script, as the caller wrote it — an async function body, or a
    /// single expression this operation wraps. See ``SourceShape``.
    public var source: String

    /// A JSON **object** whose keys arrive in scope as named arguments;
    /// `nil` passes none. Kept as text so the operation stays `Friendly`.
    public var argumentsJSON: String?

    /// Which JavaScript world the body runs in. Default
    /// ``InjectedScript/World/page``.
    public var world: InjectedScript.World

    /// Creates the operation.
    public init(source: String, argumentsJSON: String? = nil, world: InjectedScript.World = .page) {
        self.source = source
        self.argumentsJSON = argumentsJSON
        self.world = world
    }

    /// Reads `source`'s ``SourceShape``.
    ///
    /// Pure, so the decision is testable without a page.
    ///
    /// The signals are read lexically, not parsed: this is deliberately a
    /// scanner, because the only wrong answer it can produce is a *refusal*
    /// (a `;` inside a string literal costs the caller an explicit `return`),
    /// never a silent `null`.
    public static func shape(of source: String) -> SourceShape {
        let trimmed: String = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsReturnStatement(trimmed) { return .functionBody }
        let body: String = expressionBody(in: trimmed)
        if body.isEmpty || body.contains(";") { return .unreturnedStatements }
        if statementKeywords.contains(leadingWord(of: body)) { return .unreturnedStatements }
        return .expression
    }

    /// `source` with a single trailing `;` removed — the form that is
    /// wrapped. One trailing `;` is punctuation an author's fingers add, not
    /// evidence of a statement list; a second `;` anywhere is.
    private static func expressionBody(in source: String) -> String {
        guard source.hasSuffix(";") else { return source }
        return String(source.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first identifier-shaped word of `source`, for the statement-keyword
    /// check. `constant.value` leads with `constant`, not `const`.
    private static func leadingWord(of source: String) -> String {
        String(source.prefix(while: isIdentifierCharacter))
    }

    /// The word `return` in statement position, rather than the tail of an
    /// identifier (`form.returnValue`) or a fragment of a selector
    /// (`'[data-return]'`) — both of which are expressions to wrap.
    ///
    /// Statement position means: nothing but spaces before it on its line, or
    /// a `;`, `{`, `}` or `)` immediately before it.
    private static func containsReturnStatement(_ source: String) -> Bool {
        let keyword: [Character] = Array("return")
        let characters: [Character] = Array(source)
        guard characters.count >= keyword.count else { return false }
        for start in 0 ... (characters.count - keyword.count) {
            guard Array(characters[start ..< (start + keyword.count)]) == keyword else { continue }
            let after: Int = start + keyword.count
            if after < characters.count, isIdentifierCharacter(characters[after]) { continue }
            if startsStatement(at: start, in: characters) { return true }
        }
        return false
    }

    /// Whether the token at `index` opens a statement: only spaces or tabs
    /// stand between it and the start of its line, or the previous
    /// significant character ends a statement or a block.
    private static func startsStatement(at index: Int, in characters: [Character]) -> Bool {
        var cursor: Int = index - 1
        while cursor >= 0, characters[cursor] == " " || characters[cursor] == "\t" {
            cursor -= 1
        }
        guard cursor >= 0 else { return true }
        return characters[cursor].isNewline || ";{})".contains(characters[cursor])
    }

    /// Whether `character` may continue a JavaScript identifier.
    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    /// The JavaScript actually handed to the page: ``source`` as written, or
    /// the wrapped form when it is a single expression.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when the
    ///   script is ``SourceShape/unreturnedStatements`` — it could only
    ///   answer `null`, and a plausible wrong answer is worse than an error.
    public func evaluatedSource() throws -> String {
        let trimmed: String = source.trimmingCharacters(in: .whitespacesAndNewlines)
        switch Self.shape(of: source) {
        case .functionBody:
            return source
        case .expression:
            return "return (\(Self.expressionBody(in: trimmed)));"
        case .unreturnedStatements:
            throw SleepyError(
                kind: .usage,
                message: "This script is a statement list with no 'return', so it could only ever answer null.",
                nextMove: "The body is an async function body — use 'return' to send a value back, "
                    + "e.g. 'return document.title;'. A single expression is wrapped for you, "
                    + "one trailing ';' and all.",
            )
        }
    }

    /// Evaluates ``source`` and returns its value as JSON text.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when the
    ///   script has no value to return, ``argumentsJSON`` is not a JSON
    ///   object, or the page reports a JavaScript failure, and
    ///   ``SleepyError/Kind/environment`` when WebKit could not run the
    ///   script at all.
    @MainActor
    public func execute(on host: PageHost) async throws -> String {
        let body: String = try evaluatedSource()
        let arguments: [String: Any] = try Self.arguments(from: argumentsJSON)
        do {
            return try await host.evaluate(body, arguments: arguments, in: world)
        } catch let error as SleepyError {
            throw error
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// Decodes the `--args` payload into named values for the page.
    static func arguments(from json: String?) throws -> [String: Any] {
        guard let json, !json.isEmpty else { return [:] }
        guard
            let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]),
            let object = parsed as? [String: Any]
        else {
            throw SleepyError(
                kind: .usage,
                message: "'--args' must be a JSON object; '\(json)' is not one.",
                nextMove: "Pass named values, e.g. --args '{\"count\": 3}'; each key arrives in scope by name.",
            )
        }
        return object
    }

    /// WebKit's userInfo key carrying the page's own exception message.
    private static let exceptionMessageKey: String = "WKJavaScriptExceptionMessage"

    /// Turns WebKit's error into a failure that states the page's complaint.
    private static func failure(from error: any Error) -> SleepyError {
        let details = error as NSError
        guard let message = details.userInfo[exceptionMessageKey] as? String, !message.isEmpty else {
            return SleepyError(
                kind: .environment,
                message: "The page could not run the script: \(details.localizedDescription)",
                nextMove: "Retry against a settled page — a frame that navigates mid-evaluation cannot answer.",
            )
        }
        return SleepyError(
            kind: .usage,
            message: "The page rejected the script: \(message)",
            nextMove: "The body is an async function body — use 'return' to send a value back, and 'await' for promises.",
        )
    }
}
