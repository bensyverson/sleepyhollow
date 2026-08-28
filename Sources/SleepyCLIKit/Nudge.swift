import Foundation
import SleepyHollow

/// A one-line tip printed on **standard error** after a call that *succeeded*
/// but had a cheaper path — the success half of the teaching layer.
///
/// The field reports' most expensive misses were not failures: a 9,000-px PNG
/// no vision model can read, a render nobody could diff against a baseline
/// because it never became a file (2026-08-24-first-agent-user-feedback.md,
/// 2026-08-28-agent-feedback-synthesis.md § "Agents re-guess every time"). An
/// error can't teach those, because nothing went wrong.
///
/// Four rules hold the shape, and every one of them is why this is a type
/// rather than a `FileHandle.standardError.write` at a call site:
///
/// - **Never on standard output.** A `--format json` consumer must see exactly
///   the bytes it asked for, and a bare `shot` writes a PNG there.
/// - **At most one per call.** ``forShot(_:)`` picks; it never appends.
/// - **Never after a failure.** The call site sits at the end of a successful
///   `run()`, past every `throw`.
/// - **Silenced by `--quiet`.** ``QuietOption`` carries the flag;
///   ``emit(_:quiet:to:)`` is the only writer that reads it.
///
/// A future tip is a new case plus a line in whichever `for…` selector owns
/// its verb — not a new stderr call in a command.
public enum Nudge: Friendly {
    /// A capture taller than a vision model reads well, with neither
    /// `--max-size` nor `--tile` asked for. The height is the capture's own,
    /// in CSS px.
    case captureTallerThanVisionBudget(cssHeight: Int)

    /// A render that went to standard output, so there is no file for
    /// `peep compare` to diff against a baseline.
    case baselineComparisonIsImageWork

    /// The tallest capture a vision model reads well, in CSS px — the figure
    /// every field report converged on (2026-08-28-agent-readout-and-checks.md).
    public static let visionBudgetCSSPixels: Int = 2000

    /// The tip as it appears on standard error, without its newline.
    public var text: String {
        switch self {
        case let .captureTallerThanVisionBudget(cssHeight):
            "Tip: a \(Self.grouped(cssHeight))-px capture is more than a vision model reads well; "
                + "--max-size \(Self.visionBudgetCSSPixels) gives an overview, --tile strips at readable scale."
        case .baselineComparisonIsImageWork:
            "Tip: comparing a render against a saved baseline is image work, not page work — "
                + "write this one with --out, then `peep compare` (PixelPeeper) diffs the two."
        }
    }

    // MARK: - Choosing a tip

    /// What a finished `shot` knows about itself: the facts that decide
    /// whether a cheaper path existed.
    ///
    /// A struct rather than four arguments so the command hands over
    /// *observations*, and every rule about which tip they justify stays here.
    public struct ShotFacts: Friendly {
        /// The capture's height in CSS px — `ShotImage.rect.height`, the page
        /// measurement, never the pixel count.
        public let captureHeight: Double

        /// Whether `--max-size` already thinned the output.
        public let wasCapped: Bool

        /// Whether `--tile` already cut it into readable strips.
        public let wasTiled: Bool

        /// Whether the bytes landed in a file rather than on standard output.
        public let wroteToFile: Bool

        /// Creates the facts a `shot` call ended with.
        public init(captureHeight: Double, wasCapped: Bool, wasTiled: Bool, wroteToFile: Bool) {
            self.captureHeight = captureHeight
            self.wasCapped = wasCapped
            self.wasTiled = wasTiled
            self.wroteToFile = wroteToFile
        }
    }

    /// The one tip a successful `shot` earns, or `nil` when it earned none.
    ///
    /// Order is priority, and it is deliberate: an unreadable image is a
    /// wasted call, while a missing baseline is only a missed convenience, so
    /// the readout tip wins when both apply.
    public static func forShot(_ facts: ShotFacts) -> Nudge? {
        if !facts.wasCapped, !facts.wasTiled, facts.captureHeight > Double(visionBudgetCSSPixels) {
            return .captureTallerThanVisionBudget(cssHeight: Int(facts.captureHeight.rounded()))
        }
        if !facts.wroteToFile {
            return .baselineComparisonIsImageWork
        }
        return nil
    }

    // MARK: - Writing

    /// Writes `nudge` to `handle` as one line, unless there is nothing to say
    /// or `quiet` silences it.
    ///
    /// The only writer: a tip that isn't emitted here isn't a tip.
    ///
    /// - Parameters:
    ///   - nudge: the tip a verb's facts justified, or `nil` for none.
    ///   - quiet: `--quiet`, from ``QuietOption``.
    ///   - handle: where the line goes; standard error, except in tests.
    public static func emit(_ nudge: Nudge?, quiet: Bool, to handle: FileHandle = .standardError) {
        guard !quiet, let nudge else { return }
        handle.write(Data((nudge.text + "\n").utf8))
    }

    /// `12982` as `"12,982"`.
    ///
    /// Hand-rolled rather than `NumberFormatter`: the grouping separator a
    /// formatter picks depends on the host's locale, and a tip whose text
    /// changes with the machine that printed it is not determinism by
    /// construction (vision doc §5).
    private static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }
}
