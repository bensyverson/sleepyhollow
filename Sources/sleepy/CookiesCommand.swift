import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// The formats `cookies get|set` support. File scope so the nested `Set`
/// subcommand does not shadow `Swift.Set` in its own declaration.
private let cookiesFormats: Set<OutputFormat> = [.text, .json]

/// `sleepy cookies get|set` — read or write cookies, against a named jar with
/// no page at all, or against a URL's live store.
///
/// Three shapes, and which one runs is decided by what was named:
///
/// - `--jar <name>` alone is pure file work: no browser starts, so minting a
///   session by hand costs nothing and `get` is a plain inspection.
/// - a URL loads the page and answers from `WKHTTPCookieStore`; add `--jar`
///   and the store is written back to the jar afterwards.
/// - `--session <name>` is the live helper's store, read and written in place.
///   A cookie written there needs an explicit `--domain`: the session's
///   current page is not this invocation's to guess.
struct CookiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cookies",
        abstract: "Read or write cookies, in a named jar or a page's live store.",
        discussion: """
        Examples:
          sleepy cookies get --jar login
          sleepy cookies get http://localhost:3000/ --name session
          sleepy cookies set --jar login --name session --value abc --domain localhost
          sleepy cookies set http://localhost:3000/ --jar login --name seen --value 1
        """,
        subcommands: [Get.self, Set.self],
    )

    /// `sleepy cookies get` — report cookies, optionally filtered by name.
    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get",
            abstract: "Report the cookies in a jar, or in a page's live store.",
            discussion: """
            --jar alone reads the file and starts no browser. A URL loads the page and reads WKHTTPCookieStore; --session reads the live helper's.

            Formats: text (default) — one line per cookie; json — the same records with ISO dates.

            Examples:
              sleepy cookies get --jar login
              sleepy cookies get --jar login --name session --format json
              sleepy cookies get http://localhost:3000/ --name session
              sleepy cookies get --session app

            Exit codes: 0 success — no cookies is an answer, not a failure, 2 usage, 3 budget ran out, 4 load failure, 5 no such jar or session.
            """,
        )

        @OptionGroup var source: PageSourceOptions

        @Option(name: .long, help: "Report only cookies with this name.")
        var name: String?

        @OptionGroup var flags: LoadFlagOptions
        @OptionGroup var format: FormatOption
        @OptionGroup var out: OutOption
        @OptionGroup var quiet: QuietOption

        @MainActor
        mutating func run() async throws {
            let options: LoadOptions = try flags.resolveLoadOptions(steps: [])
            let resolved: OutputFormat = try format.resolve(
                default: .text,
                supporting: cookiesFormats,
                verb: "cookies get",
            )
            let cookies: [CookieRecord] = try await read(options)
            try CookiesCommand.write(cookies, as: resolved, to: out.sink)
        }

        @MainActor
        private func read(_ options: LoadOptions) async throws -> [CookieRecord] {
            guard source.url != nil || source.session != nil else {
                let jar: JarName = try CookiesCommand.requireJar(options, verb: "get")
                let store = JarStore()
                try CookiesCommand.requireExists(jar, in: store)
                return try store.cookies(in: jar).filter { name == nil || $0.name == name }
            }
            return try await PageExecution.run(
                CookiesOperation(name: name),
                on: source.resolve(),
                flags: flags,
            )
        }
    }

    /// `sleepy cookies set` — write one cookie, then report it back.
    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Write one cookie into a jar, or into a page's live store.",
            discussion: """
            Writing straight into a jar mints a logged-in session by hand, with no browser and no login flow. A cookie written into a --session needs an explicit --domain.

            Examples:
              sleepy cookies set --jar login --name s --value abc --domain localhost
              sleepy cookies set --jar login --name s --value v --domain localhost --secure
              sleepy cookies set http://localhost:3000/ --jar login --name seen --value 1
              sleepy cookies set --session app --name seen --value 1 --domain localhost

            Exit codes: 0 written, 2 usage — including a missing --domain, 3 budget ran out, 4 load failure, 5 no such jar or session.
            """,
        )

        @OptionGroup var source: PageSourceOptions

        @Option(name: .long, help: "The cookie's name.")
        var name: String

        @Option(name: .long, help: "The cookie's value.")
        var value: String

        @Option(name: .long, help: "The domain to scope the cookie to. Defaults to the URL's host.")
        var domain: String?

        @Option(name: .long, help: "The path prefix the cookie is sent for. Default /.")
        var path: String = "/"

        @Flag(name: .long, help: "Send the cookie over TLS only.")
        var secure: Bool = false

        @Flag(name: .long, help: "Hide the cookie from page script.")
        var httpOnly: Bool = false

        @Option(name: .long, help: "Seconds until the cookie expires; omit for a session cookie.")
        var maxAge: Int?

        @OptionGroup var flags: LoadFlagOptions
        @OptionGroup var format: FormatOption
        @OptionGroup var out: OutOption
        @OptionGroup var quiet: QuietOption

        @MainActor
        mutating func run() async throws {
            let options: LoadOptions = try flags.resolveLoadOptions(steps: [])
            let resolved: OutputFormat = try format.resolve(
                default: .text,
                supporting: cookiesFormats,
                verb: "cookies set",
            )
            let cookies: [CookieRecord] = try await apply(options)
            try CookiesCommand.write(cookies, as: resolved, to: out.sink)
        }

        @MainActor
        private func apply(_ options: LoadOptions) async throws -> [CookieRecord] {
            guard source.url != nil || source.session != nil else {
                let jar: JarName = try CookiesCommand.requireJar(options, verb: "set")
                return try writeToJar(jar, domain: requireDomain())
            }
            let resolved: PageSource = try source.resolve()
            let cookie: CookieRecord = try record(domain: domain(for: resolved))
            return try await PageExecution.perform(
                on: resolved,
                flags: flags,
                onPage: { host in
                    let written: [CookieRecord] = try await host.execute(CookiesOperation(set: cookie))
                    // The load already saved the jar; this cookie arrived after it.
                    try await host.saveJar()
                    return written
                },
                onSession: { client in try await client.run(CookiesOperation(set: cookie)) },
            )
        }

        /// The cookie's domain: what `--domain` said, or the URL's own host.
        ///
        /// A session has no URL on this side of the socket, so `--domain` is
        /// required there — guessing a domain would write the cookie somewhere
        /// the page never sends it.
        private func domain(for source: PageSource) throws -> String {
            if let domain, !domain.isEmpty { return domain }
            switch source {
            case let .url(url):
                return url.host ?? ""
            case .session:
                throw SleepyError(
                    kind: .usage,
                    message: "A cookie written into a session needs a --domain.",
                    nextMove: "Add --domain <host>: the session's current page is not this invocation's to guess.",
                )
            }
        }

        /// Upserts the cookie into the jar file: same name, domain and path
        /// replaces, so setting twice does not accumulate duplicates.
        private func writeToJar(_ jar: JarName, domain: String) throws -> [CookieRecord] {
            let store = JarStore()
            let record: CookieRecord = record(domain: domain)
            var cookies: [CookieRecord] = try store.cookies(in: jar)
                .filter { !$0.occupiesSameSlot(as: record) }
            cookies.append(record)
            try store.write(cookies, to: jar)
            return [record]
        }

        private func record(domain: String) -> CookieRecord {
            CookieRecord(
                name: name,
                value: value,
                domain: domain,
                path: path,
                expiresAt: maxAge.map { Date().addingTimeInterval(TimeInterval($0)) },
                isSecure: secure,
                isHTTPOnly: httpOnly,
            )
        }

        private func requireDomain() throws -> String {
            guard let domain, !domain.isEmpty else {
                throw SleepyError(
                    kind: .usage,
                    message: "A cookie written straight into a jar needs a --domain.",
                    nextMove: "Add --domain <host>, or give a URL so the host can be taken from it.",
                )
            }
            return domain
        }
    }

    // MARK: - Shared

    /// The jar named on the invocation, or the usage error that teaches the
    /// three shapes apart.
    static func requireJar(_ options: LoadOptions, verb: String) throws -> JarName {
        guard let jar: JarName = options.jar else {
            throw SleepyError(
                kind: .usage,
                message: "`cookies \(verb)` needs somewhere to look.",
                nextMove: "Give --jar <name> to work on a jar, or a URL to work on a page's live store.",
            )
        }
        return jar
    }

    /// Refuses a jar that was never created. Attaching `--jar` to a loading
    /// verb creates one; naming an absent jar *here* is a typo, and an empty
    /// answer would read exactly like a logged-out one.
    static func requireExists(_ jar: JarName, in store: JarStore) throws {
        guard store.exists(jar) else {
            throw SleepyError(
                kind: .environment,
                message: "No cookie jar named '\(jar)'.",
                nextMove: "`sleepy jars list` shows the jars there are; `--jar \(jar)` on a loading verb makes this one.",
            )
        }
    }

    /// Renders cookies to the sink: one terse line each, or JSON.
    static func write(_ cookies: [CookieRecord], as format: OutputFormat, to sink: OutputSink) throws {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try sink.write(encoder.encode(cookies))
        default:
            let lines: [String] = cookies.map(\.terseLine)
            try sink.write(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
        }
    }
}
