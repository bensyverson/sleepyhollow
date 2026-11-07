import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `click` is a real click (leaf `v8Wtvb`): the host's window presses and
/// releases the button, WebKit hit-tests it the way it does a user's, and the
/// page sees `isTrusted` true and runs the click's default action — with or
/// without its scripts. Figures and decisions:
/// `project/2026-11-06-trusted-click.md`.
@Suite("Trusted click", .serialized)
struct TrustedClickTests {
    @MainActor
    private func host(_ base: URL, scripts: LoadOptions.PageScripts = .enabled, hosting: PageHost.Hosting = .live)
        async throws -> PageHost
    {
        let host = PageHost(options: LoadOptions(pageScripts: scripts), hosting: hosting)
        _ = try await host.load(URL(string: "click-trusted.html", relativeTo: base)!)
        return host
    }

    /// The events the page recorded since the last read, as `type@target`
    /// with `!` marking an untrusted one.
    @MainActor
    private func events(on host: PageHost) async throws -> [String] {
        try await host.evaluate(
            "const seen = window.sleepyEvents.map((e) => e.type + '@' + e.target + (e.isTrusted ? '' : '!'));"
                + "window.sleepyEvents = []; return seen;",
            as: [String].self,
            in: .page,
        )
    }

    /// The document-space centre of `id`'s box, as an agent reads it off
    /// `query`: transforms included.
    @MainActor
    private func centre(of id: String, on host: PageHost) async throws -> DocumentPoint {
        let parts: [Double] = try await host.evaluate(
            "const r = document.getElementById(id).getBoundingClientRect();"
                + "return [r.left + r.width / 2 + scrollX, r.top + r.height / 2 + scrollY];",
            as: [Double].self,
            arguments: ["id": id],
        )
        return DocumentPoint(x: parts[0], y: parts[1])
    }

    @Test
    @MainActor
    func `a click delivers the trusted pointer, mouse and click sequence a user's does`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            _ = try await host.execute(ClickOperation(selector: "#go"))
            #expect(try await events(on: host) == [
                "pointermove@go", "pointerdown@go", "mousedown@go", "pointerup@go", "mouseup@go", "click@go",
            ])
        }
    }

    @Test
    @MainActor
    func `a selector click on a button inside a rotated, scaled container reaches it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            _ = try await host.execute(ClickOperation(selector: "#spin"))
            #expect(try await events(on: host).contains("click@spin"))
        }
    }

    @Test
    @MainActor
    func `a selector click on a covered element is a clean negative naming what covers it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            do {
                _ = try await host.execute(ClickOperation(selector: "#under"))
                Issue.record("expected a clean negative")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.description.contains("#under"))
                #expect(error.description.contains("covered"))
                #expect(error.description.contains("<div>"))
            }
            #expect(try await events(on: host).isEmpty, "a refused click must send nothing")
        }
    }

    @Test
    @MainActor
    func `a click passes through what the pointer passes through`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            _ = try await host.execute(ClickOperation(selector: "#through"))
            #expect(try await events(on: host).contains("click@through"))
        }
    }

    @Test
    @MainActor
    func `a point click lands on whatever is on top there, and says so`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            let outcome = try await host.execute(ClickOperation(point: centre(of: "under", on: host)))
            #expect(outcome.hit?.id == "sheet")
            #expect(try await events(on: host).contains("click@sheet"))
        }
    }

    @Test
    @MainActor
    func `with the page's scripts off, a click still toggles a checkbox and follows a link`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await server.register(path: "/landing") { _ in
                FixtureResponse(status: 200, contentType: .html, body: Data("<title>Landed</title>".utf8))
            }
            let host = try await host(base, scripts: .disabled)
            _ = try await host.execute(ClickOperation(selector: "#agree"))
            let checked: Bool = try await host.evaluate("return document.getElementById('agree').checked;", as: Bool.self)
            #expect(checked)
            let outcome = try await host.execute(ClickOperation(selector: "#away"))
            #expect(outcome.startedNavigation)
        }
    }

    @Test
    @MainActor
    func `a click on a link reports the navigation it started`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await server.register(path: "/landing") { _ in
                FixtureResponse(status: 200, contentType: .html, body: Data("<title>Landed</title>".utf8))
            }
            let host = try await host(base)
            let outcome = try await host.execute(ClickOperation(selector: "#away"))
            #expect(outcome.startedNavigation)
        }
    }

    @Test
    @MainActor
    func `a windowless host refuses a click rather than fake one`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base, hosting: .windowless)
            do {
                _ = try await host.execute(ClickOperation(selector: "#go"))
                Issue.record("expected a usage error")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.description.contains("windowless"))
            }
            #expect(try await events(on: host).isEmpty, "a refused click must not fall back to a script click")
        }
    }
}
