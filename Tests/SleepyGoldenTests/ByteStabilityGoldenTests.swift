import Foundation
import Testing
import TestSupport

/// The determinism contract as tests, for the page **read** verbs: `load`,
/// `dom`, `query`, `style`, `find`, `ax` and `eval`.
///
/// The vision doc's philosophy rule 1 says "the same invocation emits the same
/// bytes" and rule 5 says the tool is "deterministic by construction — fixed
/// window size, named theme, no ambient state". Stated as an executable claim:
/// run one argument vector twice, in two fresh subprocesses, against the same
/// fixture page, with `--size` and `--theme` pinned — and the two outputs must
/// be byte-identical. Each test also asserts the *shape* of what came back, so
/// a verb that went silent could not pass by emitting nothing twice.
///
/// Every verb here is byte-stable in both of its formats; the verbs that are
/// not (`console`, `wire`, `pdf`) live in ``ArtifactDeterminismGoldenTests``
/// with the violation pinned instead of the bytes.
///
/// `.serialized`: each test shells out to real `sleepy` subprocesses through
/// ``GoldenBinary``'s blocking `Process.waitUntilExit()`. Serializing keeps
/// this suite's contribution to the number in flight bounded — the same
/// concern every golden suite carries (see ``DomGoldenTests``).
@Suite(.serialized)
struct ByteStabilityGoldenTests {
    // MARK: - load

    @Test func `load's facts are the same bytes twice`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let pair = try await GoldenDeterminism.twice(["load", url] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(pair)
            let facts = try #require(
                try JSONSerialization.jsonObject(with: Data(pair.0.standardOutput.utf8)) as? [String: Any],
            )
            #expect(facts["finalURL"] as? String == url)
            #expect(facts["httpStatus"] as? Int == 200)
            #expect(facts["consoleErrorCount"] as? Int == 0)
            #expect((facts["dialogs"] as? [Any])?.isEmpty == true)
        }
    }

    // MARK: - dom

    @Test func `dom's HTML and its JSON tree are each the same bytes twice`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString

            let html = try await GoldenDeterminism.twice(["dom", url] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(html)
            #expect(html.0.standardOutput.hasPrefix("<!DOCTYPE html>"))
            #expect(html.0.standardOutput.contains("<h1>Sleepy Hollow static fixture</h1>"))

            let json = try await GoldenDeterminism.twice(["dom", url, "--format", "json"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(json)
            let root = try #require(
                try JSONSerialization.jsonObject(with: Data(json.0.standardOutput.utf8)) as? [String: Any],
            )
            #expect(root["kind"] as? String == "element")
            #expect(root["tag"] as? String == "html")
            #expect(root["children"] is [Any])
        }
    }

    // MARK: - query

    @Test func `query's facts and terse lines are each the same bytes twice`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("form.html").absoluteString

            let json = try await GoldenDeterminism.twice(["query", url, "--selector", "#publish"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(json)
            let elements = try #require(
                try JSONSerialization.jsonObject(with: Data(json.0.standardOutput.utf8)) as? [[String: Any]],
            )
            let element = try #require(elements.first)
            #expect(element["tagName"] as? String == "button")
            #expect(element["text"] as? String == "Publish")
            #expect(element["visible"] as? Bool == true)
            // Geometry is the field most at risk from a moving viewport: it is
            // stable only because --size is pinned.
            let geometry = try #require(element["geometry"] as? [String: Any])
            #expect(geometry["width"] is Double)

            let text = try await GoldenDeterminism.twice(["query", url, "--selector", "#publish", "--format", "text"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(text)
            #expect(text.0.standardOutput.hasPrefix("button \"Publish\" visible=true x="))
        }
    }

    // MARK: - style

    @Test func `style's computed values are the same bytes twice in both formats`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let selector: [String] = ["--selector", "h1", "--property", "display", "--property", "color"]

            let json = try await GoldenDeterminism.twice(["style", url] + selector + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(json)
            let result = try #require(
                try JSONSerialization.jsonObject(with: Data(json.0.standardOutput.utf8)) as? [String: Any],
            )
            #expect(result["matched"] as? Bool == true)
            let values = try #require(result["values"] as? [String: String])
            #expect(values["display"] == "block")
            #expect(values["color"] == "rgb(0, 0, 0)")

            let text = try await GoldenDeterminism.twice(["style", url] + selector + ["--format", "text"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(text)
            #expect(text.0.standardOutput == "display: block\ncolor: rgb(0, 0, 0)\n")
        }
    }

    /// The named theme is an *input* to determinism, not a decoration: the
    /// same page under `--theme dark` must answer the dark value, and answer
    /// it identically twice.
    @Test func `a named theme fixes the rendering and stays fixed`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("theme.html").absoluteString
            let pair = try await GoldenDeterminism.twice([
                "style", url,
                "--selector", "body",
                "--property", "background-color",
                "--format", "text",
                "--size", "1280x800",
                "--theme", "dark",
                "--budget", "60000",
            ])
            GoldenDeterminism.expectStable(pair)
            #expect(pair.0.standardOutput == "background-color: rgb(17, 17, 17)\n")
        }
    }

    // MARK: - find

    @Test func `find's verdict is the same bytes twice in both formats`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString

            let text = try await GoldenDeterminism.twice(["find", url, "--text", "quick brown"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(text)
            #expect(text.0.standardOutput == "matched\n")

            let json = try await GoldenDeterminism.twice(["find", url, "--text", "quick brown", "--format", "json"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(json)
            #expect(json.0.standardOutput == "true")
        }
    }

    // MARK: - ax

    @Test func `ax's outline and its JSON tree are each the same bytes twice`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("form.html").absoluteString

            let outline = try await GoldenDeterminism.twice(["ax", url] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(outline)
            #expect(outline.0.standardOutput.hasPrefix("document \"Form fixture\"\n"))
            #expect(outline.0.standardOutput.contains("button \"Publish\" (disabled)"))

            let json = try await GoldenDeterminism.twice(["ax", url, "--format", "json"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(json)
            let root = try #require(
                try JSONSerialization.jsonObject(with: Data(json.0.standardOutput.utf8)) as? [String: Any],
            )
            #expect(root["role"] as? String == "document")
            #expect(root["name"] as? String == "Form fixture")
            #expect(root["children"] is [Any])
        }
    }

    // MARK: - eval

    @Test func `eval's value is the same bytes twice in both formats`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let script: [String] = ["--js", "return document.title;"]

            let json = try await GoldenDeterminism.twice(["eval", url] + script + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(json)
            #expect(json.0.standardOutput == "\"Static fixture\"\n")

            let text = try await GoldenDeterminism.twice(["eval", url] + script + ["--format", "text"] + GoldenDeterminism.rendering)
            GoldenDeterminism.expectStable(text)
            #expect(text.0.standardOutput == "Static fixture\n")
        }
    }
}
