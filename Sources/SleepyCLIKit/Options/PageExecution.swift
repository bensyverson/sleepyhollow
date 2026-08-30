import ArgumentParser
import Foundation
import SleepyHollow

/// The one seam every page verb executes through: a URL loads an ephemeral
/// page here, a `--session` ships the identical operation to a helper.
///
/// A verb states *what* it wants — one `ExecutablePageOperation` — and this
/// decides *where* it runs. That is why adding a verb costs no session code:
/// the operation is the same value either way (see `PageOperation`), so the
/// two page sources differ only in who executes it.
///
/// ```swift
/// let result: DOMResult = try await PageExecution.run(DOMOperation(), on: source, flags: flags)
/// ```
///
/// ## Flags a session refuses
///
/// Loading options — `--size`, `--theme`, `--jar`, `--inject`,
/// `--inject-world`, `--wait-for`, the dialog flags, the one-shot action
/// flags — shape a *load*. A session's
/// page host was built from the options its `sleepy open` carried, and its
/// wait engine is fixed at construction, so honouring them later is not
/// possible: they are refused with a usage error naming `sleepy open` rather
/// than accepted and quietly ignored. `--budget` is the exception, because it
/// has an honest meaning on this side — it bounds how long the client waits
/// for the helper to answer, connection and reply alike.
public enum PageExecution {
    /// Every load-shaping flag, in the order ``loadShapingFlags(_:)`` reports
    /// them: the order they appear in ``LoadFlagOptions``.
    public static let loadShapingFlagNames: [String] = [
        "--size", "--theme", "--transparent", "--jar", "--file-root", "--inject", "--inject-world", "--wait-for",
        "--confirm", "--prompt-text", "--click", "--fill", "--submit",
    ]

    /// Which load-shaping flags `flags` actually carries.
    ///
    /// Pure, so the routing decision is testable without a page or a helper.
    /// `nil` is the act verbs, which declare no loading flags at all.
    ///
    /// - Important: the argument must be a *parsed* option group. An
    ///   `@Option` property wrapper that ArgumentParser never filled traps
    ///   when it is read, so this is never called on a fresh
    ///   `LoadFlagOptions()`.
    public static func loadShapingFlags(_ flags: LoadFlagOptions?) -> [String] {
        guard let flags else { return [] }
        let given: [Bool] = [
            !flags.size.isEmpty,
            !flags.theme.isEmpty,
            flags.transparent,
            flags.jar != nil,
            flags.fileRoot != nil,
            !flags.inject.isEmpty,
            flags.injectWorld != nil,
            flags.waitFor != nil,
            flags.confirm != nil,
            flags.promptText != nil,
            !flags.click.isEmpty,
            !flags.fill.isEmpty,
            !flags.submit.isEmpty,
        ]
        return zip(loadShapingFlagNames, given).compactMap { name, wasGiven in wasGiven ? name : nil }
    }

    /// Refuses a `--session` invocation that carries load-shaping flags.
    ///
    /// - Throws: `SleepyError` of kind `SleepyError.Kind.usage` naming
    ///   every offending flag and where it belongs instead.
    public static func requireSessionCompatible(_ flags: LoadFlagOptions?) throws {
        let offenders: [String] = loadShapingFlags(flags)
        guard let first: String = offenders.first else { return }
        let list: String = offenders.joined(separator: ", ")
        let verb: String = offenders.count == 1 ? "shapes" : "shape"
        throw SleepyError(
            kind: .usage,
            message: "\(list) \(verb) a load, and --session names a page a helper has already loaded.",
            nextMove: "Set it where the load happens — `sleepy open <url> --name <n> \(first) …` — "
                + "or drop --session to load the page fresh.",
        )
    }

    /// The client for `name`, bounded by `flags`' budget when one was given.
    ///
    /// `--budget` is the invocation's ceiling everywhere else, so it is the
    /// ceiling here too: it bounds the connection *and*, since 2026-08-29, the
    /// wait for the reply — see ``SleepyHollow/SessionClient/deadline``. The
    /// helper keeps its own clock on the work, because it is the only process
    /// that knows when its page gave up; this side keeps the promise that
    /// nothing hangs when the helper's clock stops running.
    public static func client(
        for name: SessionName,
        flags: LoadFlagOptions? = nil,
        registry: SessionRegistry = SessionRegistry(),
    ) throws -> SessionClient {
        try requireSessionCompatible(flags)
        guard let milliseconds: Int = flags?.budget else {
            return SessionClient(name: name, registry: registry)
        }
        let budget = TimeInterval(milliseconds) / 1000
        return SessionClient(
            name: name,
            registry: registry,
            budget: budget,
            connectTimeout: budget,
        )
    }

    /// The ordered one-shot action steps this invocation carried.
    ///
    /// Read from the raw argument vector rather than from the parsed option
    /// group, because ArgumentParser loses the interleave order across
    /// separate array options. A verb that assembles its own `LoadOptions` —
    /// `shot`'s size/scale/theme sweep — needs the same steps this seam would
    /// have resolved for it.
    public static func actionSteps() throws -> [ActionStep] {
        try ActionStepParser.parse(CommandLine.arguments)
    }

    /// The `LoadOptions` the ephemeral path uses when the caller did not
    /// supply its own: `flags` resolved, or the deterministic defaults for the
    /// act verbs, which declare no loading flags at all.
    public static func defaultLoadOptions(_ flags: LoadFlagOptions?) throws -> LoadOptions {
        let steps: [ActionStep] = try actionSteps()
        return try flags?.resolveLoadOptions(steps: steps)
            ?? LoadFlagOptions.resolve(
                size: nil, theme: nil, jar: nil, injectPaths: [], injectWorld: nil, waitFor: nil,
                budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: steps,
            )
    }

    /// Runs `operation` against `source` and returns its output.
    ///
    /// - Parameters:
    ///   - operation: what to do to the page.
    ///   - source: the resolved page source the verb was given.
    ///   - flags: the verb's loading flags, used for the ephemeral load and
    ///     checked for compatibility on the session path.
    ///   - preparing: a last chance to shape the ephemeral load's options —
    ///     `sleepy wire` installs its recorder here.
    ///   - registry: where a named session is looked up.
    ///
    /// - Note: the ordered action steps come from the raw argument vector,
    ///   because ArgumentParser loses the interleave order across separate
    ///   array options — see ``LoadFlagOptions``.
    @MainActor
    public static func run<Operation: ExecutablePageOperation>(
        _ operation: Operation,
        on source: PageSource,
        flags: LoadFlagOptions? = nil,
        preparing: (LoadOptions) -> LoadOptions = { $0 },
        registry: SessionRegistry = SessionRegistry(),
    ) async throws -> Operation.Output {
        try await perform(
            on: source,
            flags: flags,
            preparing: preparing,
            registry: registry,
            onPage: { host in try await host.execute(operation) },
            onSession: { client in try await client.run(operation) },
        )
    }

    /// The general form: hands the verb a loaded page host or a live session
    /// client, whichever the source named.
    ///
    /// Verbs that need more than one operation, or the host itself — `cookies
    /// set` writes the jar back after the write — use this; everything else
    /// uses ``run(_:on:flags:preparing:registry:)``.
    ///
    /// Passing a `group` makes the ephemeral host a member of it, so a verb
    /// that loads the same page several times — `shot`'s sweep — pays for its
    /// subresources once. It changes nothing on the session path: a session
    /// already is one long-lived browser.
    @MainActor
    public static func perform<Value>(
        on source: PageSource,
        flags: LoadFlagOptions? = nil,
        loadOptions: LoadOptions? = nil,
        group: HostGroup? = nil,
        preparing: (LoadOptions) -> LoadOptions = { $0 },
        registry: SessionRegistry = SessionRegistry(),
        onPage: (PageHost) async throws -> Value,
        onSession: (SessionClient) async throws -> Value,
    ) async throws -> Value {
        switch source {
        case let .url(url):
            let resolved: LoadOptions = try loadOptions ?? defaultLoadOptions(flags)
            let options: LoadOptions = preparing(resolved)
            let host: PageHost = try group.map { try PageHost.member(of: $0, options: options) }
                ?? PageHost(options: options)
            _ = try await host.load(url)
            return try await onPage(host)
        case let .session(name):
            let session: SessionClient = try client(for: name, flags: flags, registry: registry)
            return try await onSession(session)
        }
    }
}
