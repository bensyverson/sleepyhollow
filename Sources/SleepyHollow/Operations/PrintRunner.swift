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
///
/// **A runner outlives its `await`.** `NSPrintOperation` does not retain the
/// object it sends `didRun:` to, and the operation goes on running on its
/// secondary thread after the deadline has already answered the caller — so a
/// runner released at that point is a dangling delegate AppKit will message
/// later. It did, three times on 2026-08-29: two aborts with
/// `doesNotRecognizeSelector` and one SIGSEGV in `objc_msgSend`, all reached
/// from `-[NSConcretePrintOperation _finishModalOperation]`. ``pending`` is
/// the strong reference that makes the callback safe.
@MainActor
final class PrintRunner: NSObject {
    /// Every runner AppKit may still call back into.
    ///
    /// A runner joins before `runModal` and leaves when `didRun:` arrives. One
    /// whose callback never comes stays here for the life of the process,
    /// deliberately: the only way to know AppKit is finished with the delegate
    /// is to be told, and freeing it on a guess is the crash this exists to
    /// stop. The leak is one small object per print that outlived its budget.
    private static var pending: Set<PrintRunner> = []

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
        await PrintRunner().run(operation, in: window, budget: budget)
    }

    /// The waiting caller, cleared by whichever of the callback or the
    /// deadline gets there first.
    private var continuation: CheckedContinuation<Bool, Never>?

    /// The deadline, cancelled as soon as the callback arrives.
    private var deadline: Task<Void, Never>?

    /// Starts the operation and waits for whichever of `didRun:` or the
    /// deadline arrives first.
    ///
    /// Not private: the lifetime this method takes on — the runner survives
    /// the return, because AppKit still holds it as a delegate — is what
    /// `PrintRunnerLifetimeTests` observes.
    func run(_ operation: NSPrintOperation, in window: NSWindow, budget: TimeInterval) async -> Bool {
        let finished: Bool = await withCheckedContinuation { continuation in
            self.continuation = continuation
            deadline = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, budget) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(false)
            }
            // Before `runModal`, not after: the operation can call back from
            // its own thread the moment it is under way.
            Self.pending.insert(self)
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
    ///
    /// Arriving here is also the one proof that AppKit is done with this
    /// delegate, so it is where the runner leaves ``pending``.
    @objc(printOperationDidRun:success:contextInfo:)
    private nonisolated func printOperationDidRun(
        _: NSPrintOperation,
        success: Bool,
        contextInfo _: UnsafeMutableRawPointer?,
    ) {
        Task { @MainActor in
            self.finish(success)
            PrintRunner.pending.remove(self)
        }
    }

    /// Resumes the waiting caller, at most once.
    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: success)
    }
}
