import Foundation

/// The on-disk directory of named cookie jars: where they live, what they
/// hold, and how they are listed, emptied and removed.
///
/// The layout is one directory per jar under the store root, mirroring
/// sessions so one `SLEEPYHOLLOW_HOME` explains the whole tool:
///
/// ```text
/// ~/.sleepyhollow/jars/<name>/cookies.json   the jar's CookieJarFile
/// ```
///
/// The root is overridable — by `SLEEPYHOLLOW_HOME` or by ``init(root:)`` — so
/// tests, and anyone sandboxing the tool, never touch the real home directory.
///
/// **Nothing here is reached unless a jar was named.** A bare invocation never
/// constructs a path under the root, which is what makes "ephemeral by
/// default" true by construction rather than by discipline.
///
/// Expired cookies are pruned on every read *and* every write, so a jar can
/// only shrink toward what a browser would still send.
public struct JarStore: Sendable {
    /// The jars directory's name inside the root.
    public static let jarsDirectoryName: String = "jars"

    /// The cookie file's name inside a jar's directory.
    public static let cookiesFileName: String = "cookies.json"

    /// Where this store looks for jars.
    public let root: URL

    /// Creates a store over `root`, defaulting to ``defaultRoot(environment:)``.
    public init(root: URL = JarStore.defaultRoot()) {
        self.root = root
    }

    /// The root `SLEEPYHOLLOW_HOME` names, or `~/.sleepyhollow` — the same
    /// home the session registry uses, deliberately: one variable relocates
    /// every named thing the tool owns.
    public static func defaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL {
        SessionRegistry.defaultRoot(environment: environment)
    }

    // MARK: - Layout

    /// The directory holding every jar's directory.
    public var jarsDirectory: URL {
        root.appendingPathComponent(Self.jarsDirectoryName)
    }

    /// Where `name`'s cookie file lives.
    public func directory(for name: JarName) -> URL {
        jarsDirectory.appendingPathComponent(name.rawValue)
    }

    /// The path of `name`'s cookie file.
    public func cookiesURL(for name: JarName) -> URL {
        directory(for: name).appendingPathComponent(Self.cookiesFileName)
    }

    /// Whether `name` has been created.
    public func exists(_ name: JarName) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: name).path)
    }

    // MARK: - Reading and writing

    /// The cookies `name` holds that have not expired by `instant`.
    ///
    /// A jar that was never created holds nothing — reading one is not an
    /// error, because attaching `--jar` to a fresh name is how a jar is made.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the file is there but cannot be read or decoded. A jar that silently
    ///   read as empty would look exactly like a logged-out one.
    public func cookies(in name: JarName, at instant: Date = Date()) throws -> [CookieRecord] {
        let url: URL = cookiesURL(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard
            let data: Data = try? Data(contentsOf: url),
            let file: CookieJarFile = try? Self.makeDecoder().decode(CookieJarFile.self, from: data)
        else {
            throw SleepyError(
                kind: .environment,
                message: "The cookie jar '\(name)' at \(url.path) could not be read.",
                nextMove: "Delete it with `sleepy jars rm \(name)` and mint it again.",
            )
        }
        return file.cookies.filter { !$0.isExpired(at: instant) }
    }

    /// Writes `cookies` to `name`, creating the jar if it is not there and
    /// dropping anything already expired by `instant`.
    ///
    /// The write is atomic: a jar is read by other invocations, and a
    /// half-written one would read as a logged-out session.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the jar's directory or file cannot be written.
    public func write(_ cookies: [CookieRecord], to name: JarName, at instant: Date = Date()) throws {
        let file = CookieJarFile(cookies: cookies.filter { !$0.isExpired(at: instant) }, updatedAt: instant)
        do {
            try FileManager.default.createDirectory(at: directory(for: name), withIntermediateDirectories: true)
            try Self.makeEncoder().encode(file).write(to: cookiesURL(for: name), options: .atomic)
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The cookie jar '\(name)' could not be written to \(cookiesURL(for: name).path): "
                    + error.localizedDescription,
                nextMove: "Check the directory is writable, or point \(SessionRegistry.homeEnvironmentVariable) elsewhere.",
            )
        }
    }

    // MARK: - Management

    /// Every jar in the store, by name, sorted.
    public func names() -> [JarName] {
        let contents: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: jarsDirectory,
            includingPropertiesForKeys: [URLResourceKey.isDirectoryKey],
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]).isDirectory) == true }
            .compactMap { JarName($0.lastPathComponent) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// A summary per jar, sorted by name. An unreadable jar is summarized as
    /// zero cookies rather than failing the whole listing — `list` is how you
    /// find the jar to remove.
    public func summaries() -> [JarSummary] {
        names().map { name in
            let file: CookieJarFile? = decodedFile(for: name)
            let live: [CookieRecord] = (file?.cookies ?? []).filter { !$0.isExpired(at: Date()) }
            return JarSummary(name: name, cookieCount: live.count, updatedAt: file?.updatedAt)
        }
    }

    /// Empties `name`'s cookies, keeping the jar itself.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   there is no such jar.
    public func clear(_ name: JarName) throws {
        try requireExists(name)
        try write([], to: name)
    }

    /// Deletes `name` and everything in it.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   there is no such jar.
    public func remove(_ name: JarName) throws {
        try requireExists(name)
        do {
            try FileManager.default.removeItem(at: directory(for: name))
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The cookie jar '\(name)' could not be removed: \(error.localizedDescription)",
                nextMove: "Check that \(directory(for: name).path) is writable.",
            )
        }
    }

    // MARK: - Support

    /// ISO 8601 dates, sorted keys, pretty-printed: a jar is a file a human
    /// may have to read, and a stable byte order makes diffs mean something.
    /// Built per use — `JSONEncoder` is a mutable class, so not `Sendable`.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func decodedFile(for name: JarName) -> CookieJarFile? {
        guard let data: Data = try? Data(contentsOf: cookiesURL(for: name)) else { return nil }
        return try? Self.makeDecoder().decode(CookieJarFile.self, from: data)
    }

    private func requireExists(_ name: JarName) throws {
        guard exists(name) else {
            throw SleepyError(
                kind: .environment,
                message: "No cookie jar named '\(name)'.",
                nextMove: "`sleepy jars list` shows the jars there are.",
            )
        }
    }
}
