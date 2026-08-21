import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy wire` — what the page asked for, and what came back.
///
/// Two layers in one answer: the inventory of every request the page made, and
/// the full exchange for every `window.fetch` call. The recorder that makes
/// the second layer possible is installed here, before the load, because a
/// document-start user script is the only place it can go.
struct WireCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wire",
        abstract: "Report the page's request log: the resource inventory and the full fetch exchanges.",
        discussion: """
        Two layers, and their honest limits:

          inventory  every request the page made — URL, type, timing, and sizes
                     for same-origin resources. No methods, no headers, no
                     bodies, and no HTTP status except the main frame's: WebKit
                     has never shipped PerformanceResourceTiming.responseStatus,
                     so a subresource's status is unknowable here.
          fetches    method, headers, request and response bodies and status for
                     every window.fetch call in the main frame. Response bodies
                     are capped at 256 KiB and flagged when truncated. XHR,
                     workers, service workers, beacons, EventSource and
                     WebSockets appear in the inventory only.

        After the page loads, wire keeps watching for up to 2s until the page
        stops fetching, so requests made from a load handler are included.

        Against --session the inventory always works, but the fetch log needs the
        recorder installed before the session's first load: open it with
        `sleepy open <url> --name <n> --record-wire`.

        Formats: json (default), text — one line per entry under each layer.

        Examples:
          sleepy wire http://localhost:3000/app
          sleepy wire http://localhost:3000/app --format text
          sleepy wire http://localhost:3000/app --wait-for '.saved' --out wire.json
          sleepy wire --session app --format text

        Exit codes: 0 success, 2 usage, 3 budget ran out, 4 load failure,
        5 no such session, or a session opened without --record-wire.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let chosen: OutputFormat = try format.resolve(
            default: .json,
            supporting: [.json, .text],
            verb: "wire",
        )
        let log: WireLog = try await PageExecution.run(
            WireOperation(),
            on: source.resolve(),
            flags: flags,
            preparing: { $0.recordingWire() },
        )
        let rendered: Data = try ObserveRendering.render(log, text: log.terseText, as: chosen, verb: "wire")
        try out.sink.write(rendered)
    }
}
