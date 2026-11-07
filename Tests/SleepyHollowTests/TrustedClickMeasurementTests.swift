import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The measurement behind making `click` trusted
/// (`project/2026-11-06-trusted-click.md`): what a real click through the
/// host's window delivers, next to the synthesized one it replaced, on the
/// cases an existing user could see change.
///
/// Off unless `SLEEPY_MEASURE` is set: it prints rather than asserts. Run
/// `SLEEPY_MEASURE=1 swift test --filter TrustedClickMeasurement`.
@Suite(
    "Trusted click measurement",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SLEEPY_MEASURE"] != nil),
)
struct TrustedClickMeasurementTests {
    @MainActor
    private func json(_ host: PageHost, _ source: String) async throws -> String {
        try await host.evaluate(source, in: host.options.pageScripts == .disabled ? .isolated : .page)
    }

    /// The viewport centre of `id`'s box, transforms included.
    @MainActor
    private func centre(of id: String, on host: PageHost) async throws -> CGPoint {
        let parts: [Double] = try await host.evaluate(
            "const r = document.getElementById(id).getBoundingClientRect();"
                + "return [r.left + r.width / 2, r.top + r.height / 2];",
            as: [Double].self,
            arguments: ["id": id],
        )
        return CGPoint(x: parts[0], y: parts[1])
    }

    @MainActor
    private func report(_ label: String, _ host: PageHost) async throws {
        let events: String = try await json(host, "const e = window.sleepyEvents || []; window.sleepyEvents = []; return e;")
        let state: String = try await json(host, """
        return {
          active: document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : null,
          hovered: Array.from(document.querySelectorAll(':hover')).map((e) => e.id || e.tagName).join('>'),
          agree: document.getElementById('agree') ? document.getElementById('agree').checked : null,
          url: location.pathname,
        };
        """)
        print("== \(label)\n   events: \(events)\n   state: \(state)")
    }

    @Test
    @MainActor
    func `what a trusted click delivers`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await server.register(path: "/landing") { _ in
                FixtureResponse(status: 200, contentType: .html, body: Data("<title>Landed</title>".utf8))
            }
            let page = URL(string: "click-trusted.html", relativeTo: base)!
            let host = PageHost()
            _ = try await host.load(page)
            let input = try TrustedInput(for: host, action: "click")

            for id in ["go", "spin", "under", "through", "agree"] {
                let point = try await centre(of: id, on: host)
                let started = Date()
                try await input.click(atViewport: point)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                try await report("trusted click #\(id) at \(point) (\(ms) ms)", host)
            }

            try await input.click(atViewport: CGPoint(x: 100.75, y: 40.25))
            try await report("trusted click at fractional 100.75, 40.25", host)

            let goPoint = try await centre(of: "go", on: host)
            try await input.click(atViewport: goPoint)
            try await input.click(atViewport: goPoint)
            try await report("two trusted clicks on #go back to back", host)

            let started = Date()
            _ = try await host.execute(EvalOperation(
                source: "document.getElementById('go').click(); return 1;",
                world: .isolated,
            ))
            try await report(
                "for comparison: one isolated-world element.click() (\(Int(Date().timeIntervalSince(started) * 1000)) ms)",
                host,
            )

            let requests = host.navigationRequestCount
            try await input.click(atViewport: centre(of: "away", on: host))
            let navigating = await host.navigationStarted(sinceRequests: requests)
            print("== trusted click on the link: navigationStarted=\(navigating)")

            let noJS = PageHost(options: LoadOptions(pageScripts: .disabled))
            _ = try await noJS.load(page)
            let noJSInput = try TrustedInput(for: noJS, action: "click")
            try await noJSInput.click(atViewport: centre(of: "agree", on: noJS))
            let checked: String = try await json(noJS, "return document.getElementById('agree').checked;")
            print("== no-js trusted click on the checkbox: checked=\(checked)")
            let noJSRequests = noJS.navigationRequestCount
            try await noJSInput.click(atViewport: centre(of: "away", on: noJS))
            let noJSNavigating = await noJS.navigationStarted(sinceRequests: noJSRequests)
            print("== no-js trusted click on the link: navigationStarted=\(noJSNavigating)")
        }
    }
}
