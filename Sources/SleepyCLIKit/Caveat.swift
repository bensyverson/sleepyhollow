import Foundation
import SleepyHollow

/// A one-line correctness caveat printed on **standard error** after a call
/// that succeeded but whose artifact is wrong in a way the tool can name.
///
/// The counterpart of ``Nudge``, and deliberately not one of its cases. A
/// tip says a cheaper path existed; a caveat says *this answer is not what
/// the page looks like*. The project's ruling is "never a plausible wrong
/// answer" (`project/2026-08-28-agent-feedback-synthesis.md` § Rulings): when
/// an artifact is known to be wrong, the call still succeeds — exit 0, file
/// written — but says so. So:
///
/// - **Never on standard output**, which carries the artifact or its index.
/// - **Never silenced.** ``emit(_:to:)`` takes no `quiet`: `--quiet`
///   silences advice, and this is not advice.
/// - **Once per render.** A tiled shot is one render cut into files; a sweep
///   is several renders, and each that earns a caveat names itself. A render
///   can earn two: the fallback renderer it was drawn by, then the CSS 3D
///   that renderer flattened.
public enum Caveat: Friendly {
    /// The shot drew CSS 3D flat (``FlattenedElement``): `count` elements in
    /// its area, the first few by path. `render` names the sweep combination,
    /// or is `nil` for a single shot.
    case flattened3D(count: Int, paths: [String], render: String?)

    /// The shot was drawn by `takeSnapshot` rather than the compositor
    /// (``ShotRenderer/snapshot(_:)``), for `fallback`'s reason. `render`
    /// names the sweep combination, or is `nil` for a single shot.
    case fallbackRenderer(ShotRenderer.Fallback, render: String?)

    /// How many paths a caveat lists before counting the rest.
    public static let listedPaths: Int = 3

    /// The caveat as it appears on standard error, without its newline.
    public var text: String {
        switch self {
        case let .flattened3D(count, paths, render):
            let subject: String = render.map { "the \($0) render" } ?? "this shot"
            let elements: String = count == 1 ? "1 element in it uses" : "\(count) elements in it use"
            let unlisted: Int = count - paths.count
            let named: String = paths.joined(separator: ", ") + (unlisted > 0 ? " and \(unlisted) more" : "")
            return "sleepy: \(subject) draws CSS 3D flat — \(elements) perspective, preserve-3d or "
                + "backface-visibility, which this renderer drops: \(named). "
                + "For a faithful render, capture it in Chrome."
        case let .fallbackRenderer(fallback, render):
            let subject: String = render.map { "the \($0) render" } ?? "this shot"
            return "sleepy: \(subject) was drawn by takeSnapshot, not the compositor, because "
                + "\(Self.reason(fallback)). takeSnapshot "
                + (fallback == .video ? "draws the video but " : "")
                + "flattens CSS 3D and drops backdrop-filter."
        }
    }

    /// Why the compositor could not draw the shot, as the clause after
    /// "because".
    private static func reason(_ fallback: ShotRenderer.Fallback) -> String {
        switch fallback {
        case .video: "its area holds a <video>, which the compositor draws blank"
        case .windowless: "the page has no live window for the compositor to draw"
        case .unavailable: "this Mac lacks a Metal device or WebKit's presentation-update hook"
        case .tooWide: "it is wider than one GPU texture (\(ShotRenderer.maximumWidth) px)"
        }
    }

    /// The caveat a shot's render earns, or `nil` when it drew faithfully.
    ///
    /// - Parameters:
    ///   - flattened3D: ``ShotOperation/Output/flattened3D``.
    ///   - render: the sweep combination's label, or `nil` for a single shot.
    public static func forShot(flattened3D: [FlattenedElement], render: String? = nil) -> Caveat? {
        guard !flattened3D.isEmpty else { return nil }
        return .flattened3D(
            count: flattened3D.count,
            paths: flattened3D.prefix(listedPaths).map(\.path),
            render: render,
        )
    }

    /// The caveat a shot's renderer earns: one for the `takeSnapshot`
    /// fallback, naming why, and `nil` for the compositor.
    ///
    /// - Parameters:
    ///   - renderer: ``ShotOperation/Output/renderer``.
    ///   - render: the sweep combination's label, or `nil` for a single shot.
    public static func forRenderer(_ renderer: ShotRenderer, render: String? = nil) -> Caveat? {
        guard let fallback = renderer.fallback else { return nil }
        return .fallbackRenderer(fallback, render: render)
    }

    /// Writes `caveat` to `handle` as one line, unless there is none.
    ///
    /// - Parameters:
    ///   - caveat: what the call's facts justified, or `nil`.
    ///   - handle: where the line goes; standard error, except in tests.
    public static func emit(_ caveat: Caveat?, to handle: FileHandle = .standardError) {
        guard let caveat else { return }
        handle.write(Data((caveat.text + "\n").utf8))
    }
}
