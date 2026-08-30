import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy resize <WxH>` — move an open session's viewport, without reopening
/// it.
///
/// A session verb by construction: an ephemeral page is opened at `--size` and
/// dies with the command, so resizing one would be a no-op with a return
/// value. On a live session it is the cheap way to check a second breakpoint —
/// the page relayouts, its media queries re-evaluate, and whatever it had been
/// clicked or filled into is still there.
///
/// The size takes exactly the shapes `--size` does, because breakpoints are
/// widths: `390x844`, or `390` for that width at the default height.
struct ResizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resize",
        abstract: "Move a live session's viewport, so the page relayouts at another breakpoint.",
        discussion: """
        The page is not reloaded: it relayouts at the new width, `matchMedia` and every CSS media query re-evaluate, and the next `shot --session` is taken at the new size. What the page did once, it does not do again — a script that read window.innerWidth at load time keeps its old answer, so a layout that must be built fresh at the new width wants `sleepy open` again instead.

        Prints the viewport the session now has, as JSON.

        Examples:
          sleepy resize --session app 390x844
          sleepy resize --session app 480               # 480 wide, default height
          sleepy shot --session app --out narrow.png

        Exit codes: 0 resized, 2 usage — including no --session, 5 no session by that name.
        """,
    )

    @Argument(help: "The new viewport: WxH, or a width alone taking the default height.")
    var size: String?

    @Option(name: .long, help: "The live session to resize.")
    var session: String?

    @OptionGroup var out: OutOption

    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let viewport: ViewportSize = try Self.resolveSize(size)
        let name: SessionName = try Self.resolveSession(session)
        let resized: ViewportSize = try await PageExecution.run(
            ResizeOperation(size: viewport),
            on: .session(name),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try out.sink.write(encoder.encode(resized))
    }

    /// The requested viewport, or a usage error naming both shapes.
    ///
    /// - Throws: `SleepyError` of kind `SleepyError.Kind.usage` when no size
    ///   was given, or it is neither `WxH` nor a width.
    static func resolveSize(_ raw: String?) throws -> ViewportSize {
        guard let raw else {
            throw SleepyError(
                kind: .usage,
                message: "`resize` needs the viewport to move to.",
                nextMove: "`sleepy resize --session <n> 390x844`, or a width alone — "
                    + "`390` means 390x\(ViewportSize.default.height).",
            )
        }
        return try LoadFlagOptions.viewportSize(parsing: raw, named: "resize")
    }

    /// The session to resize, or a usage error teaching the two ways to get a
    /// page at a given size.
    ///
    /// - Throws: `SleepyError` of kind `SleepyError.Kind.usage` when no
    ///   session was named, or the name is not a valid one.
    static func resolveSession(_ raw: String?) throws -> SessionName {
        guard let raw else {
            throw SleepyError(
                kind: .usage,
                message: "'resize' moves a live session's viewport: a page that exits with the command "
                    + "has nothing to resize.",
                nextMove: "Name one with --session <n>, or set the size where the load happens: "
                    + "`sleepy shot <url> --size 390x844`.",
            )
        }
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
