import AppKit
import Foundation

/// Runs an `NSPrintOperation` document-modally and reports, once, whether it
/// finished — turning AppKit's `didRun:` callback into an `await` with a
/// deadline on it.
///
/// Two reasons this exists rather than a call to `NSPrintOperation.run()`:
///
/// - **`run()` is not usable here.** Driven synchronously against a hosted
///   `WKWebView` it produced an unbounded run of empty pages in the field —
///   a 666 MB PDF before the process was killed
///   (`project/2026-08-24-first-agent-user-feedback.md`, bug 3). The
///   document-modal form paginates correctly.
/// - **Nothing may hang.** AppKit gives no guarantee that `didRun:` ever
///   arrives; the budget makes a runaway print a reportable timeout instead
///   of a wedged verb.
///
/// The callback and the deadline race, and the first one wins: ``finish(_:)``
/// resumes at most once, so a late `didRun:` after a timeout is dropped.
@MainActor
final class PrintRunner: NSObject {
    /// Waits for `operation` to finish printing, or for `budget` to run out.
    ///
    /// - Parameters:
    ///   - operation: the configured operation; its panels should already be
    ///     off.
    ///   - window: the window the operation runs document-modally for —
    ///     `NSPrintOperation` refuses a view that has none.
    ///   - budget: how long, in seconds, to wait for `didRun:`.
    /// - Returns: `true` when AppKit reported success, `false` when it
    ///   reported failure or the budget ran out first.
    static func runModal(_ operation: NSPrintOperation, in window: NSWindow, budget: TimeInterval) async -> Bool {
        let runner = PrintRunner()
        return await runner.run(operation, in: window, budget: budget)
    }

    /// The waiting caller, cleared by whichever of the callback or the
    /// deadline gets there first.
    private var continuation: CheckedContinuation<Bool, Never>?

    /// The deadline, cancelled as soon as the callback arrives.
    private var deadline: Task<Void, Never>?

    /// Starts the operation and waits for whichever of `didRun:` or the
    /// deadline arrives first.
    private func run(_ operation: NSPrintOperation, in window: NSWindow, budget: TimeInterval) async -> Bool {
        let finished: Bool = await withCheckedContinuation { continuation in
            self.continuation = continuation
            deadline = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, budget) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(false)
            }
            operation.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil,
            )
        }
        deadline?.cancel()
        deadline = nil
        return finished
    }

    /// AppKit's completion callback.
    ///
    /// Two things about it are exact and were both learned by crashing:
    ///
    /// - The signature is the SDK's `printOperationDidRun:success:contextInfo:`
    ///   to the letter; anything else compiles and is simply never called.
    /// - **It arrives on a background thread.** A document-modal print
    ///   operation finishes on a secondary `NSThread`
    ///   (`-[NSConcretePrintOperation _continueModalOperationToTheEnd:]`), so
    ///   an `@objc` method inherited into `@MainActor` isolation traps in
    ///   `swift_task_checkIsolated` the moment AppKit calls it. Hence
    ///   `nonisolated`, and the hop back.
    ///
    /// The selector is spelled out in the `@objc` attribute so no later
    /// rename — the formatter's `unusedArguments` rule included — can move it
    /// out from under AppKit.
    @objc(printOperationDidRun:success:contextInfo:)
    private nonisolated func printOperationDidRun(
        _: NSPrintOperation,
        success: Bool,
        contextInfo _: UnsafeMutableRawPointer?,
    ) {
        Task { @MainActor in self.finish(success) }
    }

    /// Resumes the waiting caller, at most once.
    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: success)
    }
}
