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
    /// completion value as JSON text.
    ///
    /// The value is stringified *page-side* (`JSON.stringify`), which is the
    /// honest transport: what the page can serialize is what crosses, and
    /// nothing is re-interpreted host-side. `undefined` and values
    /// `JSON.stringify` cannot represent come back as `"null"`.
    ///
    /// - Parameter body: an async function body: it may `await`, and must
    ///   `return` the value to transport.
    /// - Parameter arguments: values put in scope under their keys; each must
    ///   be JSON-serializable.
    /// - Parameter world: ``InjectedScript/World/isolated`` by default, so
    ///   instrumentation cannot collide with page script. Pass
    ///   ``InjectedScript/World/page`` when the page's own globals are the
    ///   subject.
    /// - Throws: WebKit's own error when the page throws or the frame is gone
    ///   — the eval verb shapes it into a structured failure; the host does
    ///   not pretend it was something else.
    @discardableResult
    func evaluate(
        _ body: String,
        arguments: [String: Any] = [:],
        in world: InjectedScript.World = .isolated,
    ) async throws -> String {
        let value: Any? = try await webView.callAsyncJavaScript(
            Self.stringifying(body),
            arguments: arguments,
            in: nil,
            contentWorld: world.contentWorld,
        )
        guard let text = value as? String else {
            throw SleepyError(
                kind: .environment,
                message: "The page returned a value that could not be transported as JSON text.",
                nextMove: "Return a JSON-serializable value from the evaluated body.",
            )
        }
        return text
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
