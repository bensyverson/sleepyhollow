/// Reads the host's current ``PageFacts`` — the smallest possible
/// ``ExecutablePageOperation``, and the proof that the seam closes.
///
/// It exists so the Host layer exercises ``ExecutablePageOperation`` without
/// owning a real verb: the `load` verb's operation belongs to the CLI leaf,
/// and every other operation to its family. Deliberately internal, so nothing
/// builds on it by accident.
struct ReadFactsOperation: ExecutablePageOperation {
    /// The facts this operation returns.
    typealias Output = PageFacts

    /// The wire identifier.
    static let kind: String = "readFacts"

    /// Creates the operation.
    init() {}

    /// Returns the host's current facts.
    @MainActor
    func execute(on host: PageHost) async throws -> PageFacts {
        host.facts
    }
}
