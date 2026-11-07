import Foundation
import Testing
import TestSupport

/// `sleepy contrast`, `sleepy overflow` and the `window.sleepy` helpers as an
/// agent meets them: exit codes, JSON on stdout, the terse text form, and
/// `eval` reaching the helper library without a `--world` flag.
///
/// `.serialized` and `--budget 60000`: see ``CaptureGoldenTests`` — WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default.
@Suite(.serialized)
struct PageCheckGoldenTests {
    private func url(_ page: String, _ baseURL: URL) -> String {
        baseURL.appendingPathComponent(page).absoluteString
    }

    @Test func `eval reaches sleepy rect in the default world`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("helpers.html", baseURL),
                "--js", #"return sleepy.rect("h1")"#, "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            let printed = result.standardOutput
            #expect(printed.contains("\"width\":1280") || printed.contains("\"width\" : 1280"))
            #expect(printed.contains("\"height\":60") || printed.contains("\"height\" : 60"))
        }
    }

    @Test func `contrast exits 1 naming the SVG sub-label`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "contrast", url("contrast.html", baseURL), "--budget", "60000",
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput.contains("sub-label"))
            #expect(result.standardOutput.contains("Updated 3 minutes ago"))
        }
    }

    @Test func `contrast exits 0 once the sub-label is fixed`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "contrast", url("contrast-fixed.html", baseURL), "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
        }
    }

    @Test func `contrast text format names the unmeasured background`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "contrast", url("contrast.html", baseURL),
                "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput.contains("unknown (image)"))
            #expect(result.standardOutput.contains("wcag-aa"))
        }
    }

    @Test func `contrast --min takes a bare ratio`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "contrast", url("contrast.html", baseURL),
                "--min", "2", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
        }
    }

    @Test func `overflow exits 1 naming the spilling paragraph`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "overflow", url("overflow-spill.html", baseURL), "--budget", "60000",
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput.contains("token"))
        }
    }

    @Test func `overflow lists a scroll container and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "overflow", url("overflow-scroll.html", baseURL),
                "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("scroller"))
            #expect(!result.standardOutput.contains("wide-table"))
        }
    }

    @Test func `overflow honours --size`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "overflow", url("overflow-scroll.html", baseURL),
                "--size", "390x800", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("390"))
        }
    }

    @Test func `overflow checks every --size in one call and exits 1 if any spills`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "overflow", url("overflow-breakpoint.html", baseURL),
                "--size", "390x800", "--size", "1280x900", "--budget", "60000",
            ])
            #expect(result.exitCode == 1, "the hero spills at 390")
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
            )
            let sizes = try #require(object["sizes"] as? [[String: Any]])
            #expect(sizes.map { $0["width"] as? Int } == [390, 1280])
            #expect(sizes.map { $0["height"] as? Int } == [800, 900])
            let narrow = try #require(sizes.first?["report"] as? [String: Any])
            let wide = try #require(sizes.last?["report"] as? [String: Any])
            #expect((narrow["violations"] as? [Any])?.isEmpty == false)
            #expect((wide["violations"] as? [Any])?.isEmpty == true)
        }
    }

    @Test func `overflow at several sizes lists a scroll container per size and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "overflow", url("overflow-scroll.html", baseURL),
                "--size", "390x800", "--size", "1280x900", "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("390×800"))
            #expect(result.standardOutput.contains("1280×900"))
            #expect(result.standardOutput.components(separatedBy: "scroller").count - 1 == 2)
            #expect(!result.standardOutput.contains("wide-table"))
        }
    }

    @Test func `overflow still refuses a repeated --theme`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "overflow", url("overflow-scroll.html", baseURL),
                "--size", "390", "--size", "1280", "--theme", "light", "--theme", "dark", "--budget", "60000",
            ])
            #expect(result.exitCode == 2)
            #expect(result.standardError.contains("--theme"))
        }
    }

    @Test func `both verbs explain themselves`() async throws {
        let contrast = try await GoldenBinary.runOffPool(["contrast", "--help"])
        #expect(contrast.exitCode == 0)
        #expect(contrast.standardOutput.contains("wcag-aa"))
        #expect(contrast.standardOutput.contains("--selector"))

        let overflow = try await GoldenBinary.runOffPool(["overflow", "--help"])
        #expect(overflow.exitCode == 0)
        #expect(overflow.standardOutput.contains("--size"))
        #expect(overflow.standardOutput.contains("scroll"))
        #expect(overflow.standardOutput.contains("--size 390x800 --size 1280x900"))
    }

    @Test func `recipes routes legibility and spill questions to the two verbs`() async throws {
        let recipes = try await GoldenBinary.runOffPool(["recipes"])
        #expect(recipes.exitCode == 0)
        #expect(recipes.standardOutput.contains("sleepy contrast"))
        #expect(recipes.standardOutput.contains("sleepy overflow"))
        #expect(recipes.standardOutput.contains("--size 390x800 --size 1280x900"), "the spill question is per breakpoint")
    }
}
