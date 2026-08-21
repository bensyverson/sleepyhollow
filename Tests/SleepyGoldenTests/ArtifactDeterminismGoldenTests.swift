import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import SleepyHollow
import Testing
import TestSupport

/// The determinism contract for the verbs whose output is not plain text, or
/// not fully stable: the observe verbs (`console`, `wire`), the artifact verbs
/// (`shot`, `pdf`, `archive`) through their `--out` files, and the state verbs
/// (`jars list`, `cookies get`).
///
/// ``ByteStabilityGoldenTests`` states the plain claim — same invocation, same
/// bytes — for every verb that keeps it. Three here do not, and each is a
/// **finding**, pinned as the strongest honest assertion rather than softened
/// away. Measured 2026-08-20 by repeating each invocation eight times against
/// a `python3 -m http.server` copy of these fixtures, `sleepy` built debug at
/// `--size 1280x800 --theme light --budget 60000`:
///
/// - **`console --format json`** repeats itself except for
///   `timeMilliseconds`, the page's own `performance.now()` reading — 7 or 8
///   across eight runs of `console-errors.html`. The terse format, which
///   never prints the timing, *is* byte-stable.
/// - **`wire`** repeats itself except for `startTime`, `duration` and the
///   whole `timing` block — and the block's *membership* moves too, because
///   a phase WebKit reports as `0` is dropped as absent, so a reused
///   connection loses `connectStart`/`connectEnd` entirely. Both formats
///   carry it: the terse line prints the duration as `Nms`, seen as 7ms and
///   8ms across eight runs of `static.html`.
/// - **`pdf`** emits `/CreationDate`, `/ModDate` and a content-plus-date
///   `/ID` into the trailer. Two runs of `pdf static.html` differed in 66
///   bytes of 24286, all inside those three values; the byte *length*, the
///   page count and the page's text and media box were identical.
///
/// The two timing ones are **intermittent**: on an idle machine consecutive
/// runs often quantize to the same millisecond, so a plain byte-equality
/// assertion would pass most of the time and fail under load. That is a worse
/// test than this one, not a better one — a latent flake that would be read as
/// contention rather than as the contract being broken.
///
/// Whether a timing belongs in the default output at all is a data question,
/// not a rendering one, so it is not decided here — see this leaf's `job`
/// notes and the report.
///
/// The pinned invocation and the run-it-twice apparatus are
/// ``ByteStabilityGoldenTests``'s, borrowed rather than copied so the two
/// halves of one contract cannot drift apart. Splitting them across two
/// suites is a wall-clock decision: Swift Testing runs suites in parallel,
/// and these ~33 subprocess page loads cost about half as much that way.
///
/// `.serialized`: the same subprocess-contention concern every golden suite
/// carries (see ``DomGoldenTests``).
@Suite(.serialized)
struct ArtifactDeterminismGoldenTests {
    // MARK: - console

    @Test func `console's terse log is the same bytes twice`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("console-errors.html").absoluteString
            let pair = try await GoldenDeterminism.twice(
                ["console", url, "--format", "text"] + GoldenDeterminism.rendering,
            )
            GoldenDeterminism.expectStable(pair)
            let lines: [Substring] = pair.0.standardOutput.split(separator: "\n")
            #expect(lines.count == 4)
            #expect(lines.first?.hasPrefix("log ") == true)
            #expect(pair.0.standardOutput.contains("error     first error"))
            #expect(pair.0.standardOutput.contains("uncaught  TypeError"))
        }
    }

    /// `console --format json` is stable in everything but the page's own
    /// clock — the finding this suite's DocC records.
    @Test func `console's JSON log repeats everything but its timings`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("console-errors.html").absoluteString
            let pair = try await GoldenDeterminism.twice(
                ["console", url] + GoldenDeterminism.rendering,
            )
            #expect(pair.0.exitCode == 0)
            #expect(pair.1.exitCode == 0)

            let first: Data = try Self.pruning(["timeMilliseconds"], fromJSON: pair.0.standardOutput)
            let second: Data = try Self.pruning(["timeMilliseconds"], fromJSON: pair.1.standardOutput)
            // The pruning has to have bitten, or the comparison below proves
            // nothing: the timings are in the raw output and gone from this one.
            #expect(pair.0.standardOutput.contains("timeMilliseconds"))
            #expect(!String(decoding: first, as: UTF8.self).contains("timeMilliseconds"))
            #expect(first == second)

            let log = try #require(
                try JSONSerialization.jsonObject(with: Data(pair.0.standardOutput.utf8)) as? [String: Any],
            )
            #expect(log["droppedMessages"] as? Int == 0)
            let messages = try #require(log["messages"] as? [[String: Any]])
            #expect(messages.count == 4)
            #expect(messages.first?["level"] as? String == "log")
            #expect(messages.last?["origin"] as? String == "uncaught")
            #expect(messages.allSatisfy { $0["timeMilliseconds"] is Double })
        }
    }

    // MARK: - wire

    /// `wire --format json` is stable in everything but the measured times —
    /// the second finding this suite's DocC records.
    @Test func `wire's JSON log repeats everything but its measured times`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let pair = try await GoldenDeterminism.twice(["wire", url] + GoldenDeterminism.rendering)
            #expect(pair.0.exitCode == 0)
            #expect(pair.1.exitCode == 0)

            let first: Data = try Self.pruning(Self.wireTimingKeys, fromJSON: pair.0.standardOutput)
            let second: Data = try Self.pruning(Self.wireTimingKeys, fromJSON: pair.1.standardOutput)
            // The pruning has to have bitten — see the console test above.
            #expect(pair.0.standardOutput.contains("\"duration\""))
            #expect(!String(decoding: first, as: UTF8.self).contains("\"duration\""))
            #expect(first == second)

            let log = try #require(
                try JSONSerialization.jsonObject(with: Data(pair.0.standardOutput.utf8)) as? [String: Any],
            )
            #expect((log["fetches"] as? [Any])?.isEmpty == true)
            let inventory = try #require(log["inventory"] as? [[String: Any]])
            let navigation = try #require(inventory.first)
            #expect(navigation["url"] as? String == url)
            #expect(navigation["initiatorType"] as? String == "navigation")
            #expect(navigation["httpStatus"] as? Int == 200)
            #expect(navigation["isCrossOrigin"] as? Bool == false)
        }
    }

    @Test func `wire's terse log repeats everything but its durations`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let pair = try await GoldenDeterminism.twice(
                ["wire", url, "--format", "text"] + GoldenDeterminism.rendering,
            )
            #expect(pair.0.exitCode == 0)
            #expect(pair.1.exitCode == 0)
            let blanked: String = Self.blankingDurations(pair.0.standardOutput)
            // The blanking has to have bitten — see the console test above.
            #expect(blanked.contains("<ms>"))
            #expect(blanked == Self.blankingDurations(pair.1.standardOutput))

            let lines: [Substring] = pair.0.standardOutput.split(separator: "\n")
            try #require(lines.count == 3)
            #expect(lines[0] == "inventory (1)")
            #expect(lines[1].contains("navigation"))
            #expect(lines[1].contains(url))
            #expect(lines[2] == "fetches (0)")
        }
    }

    // MARK: - shot

    @Test func `shot's PNG is the same bytes twice, at the size --size named`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let arguments: [String] = ["shot", url] + GoldenDeterminism.rendering
            let (first, second) = try await Self.twiceWritingFile(arguments, extension: "png")

            #expect(first.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
            let dimensions = try #require(Self.pixelDimensions(ofPNG: first))
            #expect(dimensions.width == 1280)
            #expect(dimensions.height == 800)
            #expect(first == second)
        }
    }

    // MARK: - pdf

    /// `pdf` cannot claim byte-identity: `WKWebView.createPDF` stamps the
    /// trailer with the wall clock. What *is* stable is asserted instead.
    @Test func `pdf repeats its pages and its byte length, not its bytes`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let arguments: [String] = ["pdf", url] + GoldenDeterminism.rendering
            let (first, second) = try await Self.twiceWritingFile(arguments, extension: "pdf")

            #expect(first.prefix(5) == Data("%PDF-".utf8))
            #expect(first.count == second.count)

            let firstDocument = try #require(PDFDocument(data: first))
            let secondDocument = try #require(PDFDocument(data: second))
            #expect(firstDocument.pageCount == 1)
            #expect(firstDocument.pageCount == secondDocument.pageCount)
            let firstPage = try #require(firstDocument.page(at: 0))
            let secondPage = try #require(secondDocument.page(at: 0))
            #expect(firstPage.string == secondPage.string)
            #expect(firstPage.bounds(for: .mediaBox) == secondPage.bounds(for: .mediaBox))
            #expect(firstPage.string?.contains("Sleepy Hollow static fixture") == true)
        }
    }

    // MARK: - archive

    @Test func `archive's webarchive is the same bytes twice and stays loadable`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url: String = baseURL.appendingPathComponent("static.html").absoluteString
            let arguments: [String] = ["archive", url] + GoldenDeterminism.rendering
            let (first, second) = try await Self.twiceWritingFile(arguments, extension: "webarchive")

            #expect(first.prefix(8) == Data("bplist00".utf8))
            let plist = try #require(
                try PropertyListSerialization.propertyList(from: first, format: nil) as? [String: Any],
            )
            let main = try #require(plist["WebMainResource"] as? [String: Any])
            #expect(main["WebResourceURL"] as? String == url)
            #expect(first == second)
        }
    }

    // MARK: - the state verbs

    @Test func `jars list is the same bytes twice in both formats`() async throws {
        try await Self.withMintedJar { environment in
            let text = try await Self.twice(["jars", "list"], environment: environment)
            GoldenDeterminism.expectStable(text)
            #expect(text.0.standardOutput.hasPrefix("login  1 cookie  "))

            let json = try await Self.twice(["jars", "list", "--format", "json"], environment: environment)
            GoldenDeterminism.expectStable(json)
            let summaries = try #require(
                try JSONSerialization.jsonObject(with: Data(json.0.standardOutput.utf8)) as? [[String: Any]],
            )
            #expect(summaries.count == 1)
            #expect(summaries.first?["name"] as? String == "login")
            #expect(summaries.first?["cookieCount"] as? Int == 1)
            #expect(summaries.first?["updatedAt"] is String)
        }
    }

    @Test func `cookies get is the same bytes twice in both formats`() async throws {
        try await Self.withMintedJar { environment in
            let text = try await Self.twice(["cookies", "get", "--jar", "login"], environment: environment)
            GoldenDeterminism.expectStable(text)
            #expect(text.0.standardOutput == "sleepy=hollow; Domain=127.0.0.1; Path=/\n")

            let json = try await Self.twice(
                ["cookies", "get", "--jar", "login", "--format", "json"],
                environment: environment,
            )
            GoldenDeterminism.expectStable(json)
            let cookies = try #require(
                try JSONSerialization.jsonObject(with: Data(json.0.standardOutput.utf8)) as? [[String: Any]],
            )
            #expect(cookies.count == 1)
            #expect(cookies.first?["name"] as? String == "sleepy")
            #expect(cookies.first?["value"] as? String == "hollow")
            #expect(cookies.first?["domain"] as? String == "127.0.0.1")
        }
    }

    // MARK: - Apparatus

    /// The keys `wire` fills from a clock, at any depth: the two the entry
    /// carries directly, the whole phase-timing block (whose *membership*
    /// moves, not only its numbers), and the fetch layer's two.
    private static let wireTimingKeys: Set<String> = [
        "startTime",
        "duration",
        "timing",
        "elapsedMilliseconds",
        "startedAtMilliseconds",
    ]

    /// Runs one argument vector twice under `environment`, each in its own
    /// fresh subprocess.
    private static func twice(
        _ arguments: [String],
        environment: [String: String],
    ) async throws -> (CliInvocation, CliInvocation) {
        let first: CliInvocation = try await GoldenBinary.runOffPool(arguments, environment: environment)
        let second: CliInvocation = try await GoldenBinary.runOffPool(arguments, environment: environment)
        return (first, second)
    }

    /// Runs one argument vector twice, each writing to its own fresh `--out`
    /// file, and returns what the two runs wrote.
    private static func twiceWritingFile(
        _ arguments: [String],
        extension fileExtension: String,
    ) async throws -> (Data, Data) {
        var written: [Data] = []
        for _ in 0 ..< 2 {
            let out: URL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            defer { try? FileManager.default.removeItem(at: out) }
            let result: CliInvocation = try await GoldenBinary.runOffPool(arguments + ["--out", out.path])
            #expect(result.exitCode == 0)
            #expect(result.standardError.isEmpty)
            try written.append(Data(contentsOf: out))
        }
        return (written[0], written[1])
    }

    /// Runs `body` against a throwaway `SLEEPYHOLLOW_HOME` holding one jar
    /// with one cookie, minted without starting a browser.
    private static func withMintedJar(_ body: ([String: String]) async throws -> Void) async throws {
        let root: URL = try SessionHelperProcess.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let environment: [String: String] = [SessionRegistry.homeEnvironmentVariable: root.path]
        let minted: CliInvocation = try await GoldenBinary.runOffPool(
            ["cookies", "set", "--jar", "login", "--name", "sleepy", "--value", "hollow", "--domain", "127.0.0.1"],
            environment: environment,
        )
        #expect(minted.exitCode == 0)
        try await body(environment)
    }

    /// `text` re-encoded with every key in `keys` dropped at any depth, so two
    /// answers that differ only in those keys compare byte for byte.
    ///
    /// Re-encoding rather than deleting lines is deliberate: a dropped key can
    /// change the *shape* of the JSON around it (a trailing comma, an object
    /// that empties), and a line-wise strip would report that as a difference.
    private static func pruning(_ keys: Set<String>, fromJSON text: String) throws -> Data {
        let object: Any = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try JSONSerialization.data(
            withJSONObject: pruned(object, removing: keys),
            options: [.sortedKeys],
        )
    }

    private static func pruned(_ value: Any, removing keys: Set<String>) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, element) in dictionary where !keys.contains(key) {
                result[key] = pruned(element, removing: keys)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { pruned($0, removing: keys) }
        }
        return value
    }

    /// `text` with every `<digits>ms` token replaced, so `wire --format text`
    /// can be compared on everything but the durations it measures.
    private static func blankingDurations(_ text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { token in
                let digits: Substring = token.dropLast(2)
                let isDuration: Bool = token.hasSuffix("ms") && !digits.isEmpty && digits.allSatisfy(\.isNumber)
                return isDuration ? "<ms>" : String(token)
            }
            .joined(separator: " ")
    }

    private static func pixelDimensions(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height)
    }
}
