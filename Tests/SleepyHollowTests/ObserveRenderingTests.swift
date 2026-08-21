import Foundation
import SleepyHollow
import Testing

@Suite("Observe terse rendering")
struct ObserveRenderingTests {
    @Test func `console text is one labelled line per message`() {
        let log = ConsoleLog(
            messages: [
                ConsoleMessage(level: .log, origin: .console, text: "a log line", timeMilliseconds: 4),
                ConsoleMessage(level: .warn, origin: .console, text: "a warn line", timeMilliseconds: 5),
                ConsoleMessage(level: .error, origin: .uncaught, text: "TypeError: nope", timeMilliseconds: 6),
                ConsoleMessage(
                    level: .error,
                    origin: .unhandledRejection,
                    text: "Error: later",
                    timeMilliseconds: 7,
                ),
            ],
        )
        #expect(log.terseText == """
        log       a log line
        warn      a warn line
        uncaught  TypeError: nope
        rejection Error: later
        """)
    }

    @Test func `an empty console log renders as nothing`() {
        #expect(ConsoleLog().terseText.isEmpty)
    }

    @Test func `dropped messages are stated, not hidden`() {
        let log = ConsoleLog(
            messages: [ConsoleMessage(level: .log, origin: .console, text: "kept", timeMilliseconds: 1)],
            droppedMessages: 7,
        )
        #expect(log.terseText == """
        (7 earlier messages dropped)
        log       kept
        """)
    }

    @Test func `wire text is two labelled sections`() {
        let log = WireLog(
            inventory: [
                ResourceEntry(
                    url: "http://x/",
                    initiatorType: "navigation",
                    startTime: 0,
                    duration: 12.4,
                    httpStatus: 200,
                    transferSize: 345,
                ),
                ResourceEntry(
                    url: "http://x/script.js",
                    initiatorType: "script",
                    startTime: 5,
                    duration: 3,
                    transferSize: 120,
                ),
                ResourceEntry(
                    url: "http://other/pixel.png",
                    initiatorType: "img",
                    startTime: 6,
                    duration: 2,
                    isCrossOrigin: true,
                ),
            ],
            fetches: [
                FetchExchange(
                    id: 1,
                    method: "POST",
                    url: "http://x/submit",
                    status: 200,
                    responseBodyBytes: 25,
                    startedAtMilliseconds: 20,
                ),
                FetchExchange(
                    id: 2,
                    method: "GET",
                    url: "http://x/big",
                    status: 200,
                    responseBodyBytes: 4096,
                    truncated: .size,
                    startedAtMilliseconds: 30,
                ),
                FetchExchange(
                    id: 3,
                    method: "GET",
                    url: "http://x/gone",
                    startedAtMilliseconds: 40,
                    error: "TypeError: Load failed",
                ),
            ],
        )
        #expect(log.terseText == """
        inventory (3)
          navigation   200  http://x/  12ms  345B
          script       -    http://x/script.js  3ms  120B
          img          -    http://other/pixel.png  2ms
        fetches (3)
          POST   http://x/submit  200  25B
          GET    http://x/big  200  4096B  truncated:size
          GET    http://x/gone  error: TypeError: Load failed
        """)
    }

    @Test func `an empty wire log still names both layers`() {
        #expect(WireLog().terseText == """
        inventory (0)
        fetches (0)
        """)
    }
}
