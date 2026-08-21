import Foundation

/// Reads the page's console log — `sleepy console`.
///
/// The log is read from the baseline capture every host installs, so no
/// preparation is needed: load a page and ask. It covers everything the page
/// said from document start through the moment the operation runs — every
/// `console` level, plus uncaught errors and unhandled rejections — which on a
/// one-shot load means "through settle".
///
/// ```swift
/// let host = PageHost()
/// _ = try await host.load(url)
/// let log = try await host.execute(ConsoleOperation())
/// ```
public struct ConsoleOperation: ExecutablePageOperation {
    /// The log this operation returns.
    public typealias Output = ConsoleLog

    /// The wire identifier.
    public static let kind: String = "console"

    /// Creates the operation.
    public init() {}

    /// Reads the capture's buffer out of the page.
    @MainActor
    public func execute(on host: PageHost) async throws -> ConsoleLog {
        let text: String = try await host.evaluate(ConsoleCapture.logExpression, in: .page)
        do {
            return try JSONDecoder().decode(ConsoleLog.self, from: Data(text.utf8))
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The page's console log could not be read: \(error.localizedDescription)",
                nextMove: "Reload the page; if it persists, the page may be overriding the console capture.",
            )
        }
    }
}
