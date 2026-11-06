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
///   is several renders, and each that earns a caveat names itself.
public enum Caveat: Friendly {
    /// The shot drew CSS 3D flat (``FlattenedElement``): `count` elements in
    /// its area, the first few by path. `render` names the sweep combination,
    /// or is `nil` for a single shot.
    case flattened3D(count: Int, paths: [String], render: String?)

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
