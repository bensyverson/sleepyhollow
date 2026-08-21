import Foundation
import Network

/// Answering clients: one framed conversation per connection, one operation at
/// a time, every answer a ``SessionReply``.
extension SessionHost {
    /// Takes on a connection the listener accepted.
    func adopt(_ connection: NWConnection) {
        guard !isStopped else {
            connection.cancel()
            return
        }
        let framed = SessionConnection(adopting: connection)
        Task { @MainActor [weak self] in
            await self?.serve(framed)
            await framed.close()
        }
    }

    /// Reads requests until the peer goes away or the host stops.
    ///
    /// Serving waits for the host to be ready first: a client that connects
    /// while the session's first page is still loading gets its answer late
    /// rather than getting an answer about a blank page.
    private func serve(_ connection: SessionConnection) async {
        await waitUntilReady()
        while !isStopped {
            let request: SessionRequest?
            do {
                request = try await connection.receive(SessionRequest.self)
            } catch {
                return
            }
            guard let request, !isStopped else { return }
            noteActivity()
            let reply: SessionReply = await answer(request)
            try? await connection.send(reply)
            noteActivity()
            if case .shutdown = request {
                await stop()
                return
            }
        }
    }

    /// Carries out one request. Failures become ``SessionReply/failure(_:)``
    /// rather than a dropped connection, so a session failure teaches exactly
    /// as much as a one-shot failure does.
    private func answer(_ request: SessionRequest) async -> SessionReply {
        switch request {
        case .shutdown:
            return .acknowledged
        case let .operation(envelope):
            do {
                let decoded: any PageOperation = try operations.decode(envelope)
                guard let executable = decoded as? any ExecutablePageOperation else {
                    throw SleepyError(
                        kind: .environment,
                        message: "Operation '\(envelope.kind)' has no way to run against a page.",
                        nextMove: "This is a bug in the verb that sent it — report the kind.",
                    )
                }
                let payload: Data = try await encodedOutput(of: executable)
                return .output(payload)
            } catch let error as SleepyError {
                return .failure(error)
            } catch {
                return .failure(SleepyError(
                    kind: .environment,
                    message: "Operation '\(envelope.kind)' failed in the session helper: \(error).",
                    nextMove: "Try the same verb without --session to see whether the page or the session is at fault.",
                ))
            }
        }
    }

    /// Runs an operation whose type is only known dynamically, by opening the
    /// existential into a generic context where its `Output` has a name again.
    private func encodedOutput(of operation: any ExecutablePageOperation) async throws -> Data {
        try await encodedOutput(ofTyped: operation)
    }

    private func encodedOutput(ofTyped operation: some ExecutablePageOperation) async throws -> Data {
        try await JSONEncoder().encode(operation.execute(on: page))
    }
}
