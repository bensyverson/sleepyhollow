import Foundation
import Network

/// async/await bridges over `NWConnection`'s callback API, for the fixture
/// server's read-request/write-response loop.
extension NWConnection {
    /// Receives the next chunk of bytes.
    ///
    /// Returns `nil` when the peer finished sending (EOF); an empty `Data`
    /// means "nothing yet, keep reading".
    func receiveChunk(maximumLength: Int = 65536) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            self.receive(
                minimumIncompleteLength: 1,
                maximumLength: maximumLength,
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Sends bytes and waits until the network stack accepts them.
    func sendAll(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.send(
                content: data,
                completion: NWConnection.SendCompletion.contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                },
            )
        }
    }
}
