import Foundation
import WebKit

/// The seam verb families build on: install instrumentation, run JavaScript,
/// receive what the page posts back.
public extension PageHost {
    /// Installs a user script. Must happen before the load it should affect —
    /// a document-start script cannot be added to a document already parsing.
    func install(_ script: InjectedScript) {
        webView.configuration.userContentController.addUserScript(script.userScript)
    }

    /// Runs `body` as an async JavaScript function body and returns its
    /// completion value as JSON text — or throws once `budget` seconds pass
    /// without an answer.
    ///
    /// The value is stringified *page-side* (`JSON.stringify`), which is the
    /// honest transport: what the page can serialize is what crosses, and
    /// nothing is re-interpreted host-side. `undefined` and values
    /// `JSON.stringify` cannot represent come back as `"null"`.
    ///
    /// The deadline is the host's, not WebKit's: `callAsyncJavaScript` has
    /// none, so a body that awaits a promise the page never settles would
    /// otherwise suspend its caller for good. Past the deadline the call is
    /// abandoned — the caller gets a timeout, the page may still be running
    /// the body, and the host records it in ``abandonedCall``. Cancelling the
    /// caller's task abandons the call the same way.
    ///
    /// - Parameter body: an async function body: it may `await`, and must
    ///   `return` the value to transport.
    /// - Parameter arguments: values put in scope under their keys; each must
    ///   be JSON-serializable.
    /// - Parameter world: ``InjectedScript/World/isolated`` by default, so
    ///   instrumentation cannot collide with page script. Pass
    ///   ``InjectedScript/World/page`` when the page's own globals are the
    ///   subject.
    /// - Parameter budget: seconds to wait for the answer, or `nil` for the
    ///   host's ``callBudget``.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` naming
    ///   the body's first line when the budget runs out, `CancellationError`
    ///   when the caller is cancelled first, and WebKit's own error when the
    ///   page throws or the frame is gone — the eval verb shapes that into a
    ///   structured failure; the host does not pretend it was something else.
    @discardableResult
    func evaluate(
        _ body: String,
        arguments: [String: Any] = [:],
        in world: InjectedScript.World = .isolated,
        budget: TimeInterval? = nil,
    ) async throws -> String {
        try await evaluate(
            body,
            arguments: arguments,
            in: world,
            within: budget ?? callBudget,
            naming: Self.describing(evaluation: body),
        )
    }

    /// ``evaluate(_:arguments:in:budget:)`` with the call named by the
    /// caller, for the host's own evaluations, whose bodies would read as
    /// noise in a timeout.
    internal func evaluate(
        _ body: String,
        arguments: [String: Any],
        in world: InjectedScript.World,
        within budget: TimeInterval,
        naming call: String,
    ) async throws -> String {
        try await answer(call, within: budget) { answered in
            webView.callAsyncJavaScript(
                Self.stringifying(body),
                arguments: arguments,
                in: nil,
                in: world.contentWorld,
            ) { result in
                answered(result.flatMap { value in
                    guard let text = value as? String else {
                        return .failure(SleepyError(
                            kind: .environment,
                            message: "The page returned a value that could not be transported as JSON text.",
                            nextMove: "Return a JSON-serializable value from the evaluated body.",
                        ))
                    }
                    return .success(text)
                })
            }
        }
    }

    /// A stream of everything the page posts to the script-message handler
    /// called `name`, as text.
    ///
    /// The handler is registered on first call — so call this **before** the
    /// load whose messages you want — and stays registered for the host's
    /// life. Streams are keyed by name: registering one name in both worlds
    /// merges into one stream. String bodies arrive verbatim (post JSON text,
    /// as the console capture does); other bodies are JSON-encoded, and
    /// anything that cannot be is described.
    func messages(named name: String, in world: InjectedScript.World = .isolated) -> AsyncStream<String> {
        register(messageName: name, in: world)
        return AsyncStream { continuation in
            nextMessageSinkID += 1
            let id: Int = nextMessageSinkID
            messageSinks[name, default: []].append(MessageSink(id: id, continuation: continuation))
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.removeSink(id: id, named: name)
                }
            }
        }
    }

    /// Registers the script-message handler for `name` in `world`, once.
    internal func register(messageName name: String, in world: InjectedScript.World) {
        let key = "\(world.rawValue):\(name)"
        guard !registeredMessageNames.contains(key) else { return }
        registeredMessageNames.insert(key)
        webView.configuration.userContentController.add(
            delegate,
            contentWorld: world.contentWorld,
            name: name,
        )
    }

    /// Hands a received script message to every sink on that name.
    internal func deliver(message body: Any, named name: String) {
        guard let sinks = messageSinks[name] else { return }
        let text: String = Self.text(from: body)
        for sink in sinks {
            sink.continuation.yield(text)
        }
    }

    private func removeSink(id: Int, named name: String) {
        messageSinks[name]?.removeAll { $0.id == id }
    }

    private static func text(from body: Any) -> String {
        if let string = body as? String { return string }
        if JSONSerialization.isValidJSONObject(body),
           let data: Data = try? JSONSerialization.data(withJSONObject: body),
           let text = String(data: data, encoding: .utf8)
        {
            return text
        }
        return String(describing: body)
    }

    /// Wraps `body` so the page, not the host, turns the value into JSON.
    ///
    /// The arrow function captures lexically, so the named arguments WebKit
    /// puts in scope stay visible inside `body`, and `await` still works.
    private static func stringifying(_ body: String) -> String {
        """
        const __sleepyValue = await (async () => {
        \(body)
        })();
        const __sleepyText = JSON.stringify(__sleepyValue);
        return __sleepyText === undefined ? "null" : __sleepyText;
        """
    }
}
