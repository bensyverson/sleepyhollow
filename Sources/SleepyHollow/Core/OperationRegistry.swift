import Foundation

/// Turns ``OperationEnvelope``s back into typed ``PageOperation``s.
///
/// Each verb family registers its operation types; the session host decodes
/// with the registry and never needs a shared enum of all verbs — which is
/// what lets families evolve without touching a common file.
public struct OperationRegistry: Sendable {
    private var decoders: [String: @Sendable (Data) throws -> any PageOperation] = [:]

    /// Creates an empty registry.
    public init() {}

    /// Registers `type` under its ``PageOperation/kind``. Registering the same
    /// kind twice replaces the earlier entry.
    public mutating func register<O: PageOperation>(_: O.Type) {
        decoders[O.kind] = { data in
            try JSONDecoder().decode(O.self, from: data)
        }
    }

    /// The kinds currently registered, sorted.
    public var registeredKinds: [String] {
        decoders.keys.sorted()
    }

    /// Decodes `envelope` into the registered operation type.
    ///
    /// - Throws: ``SleepyError`` (environment) when no type is registered for
    ///   the envelope's kind.
    public func decode(_ envelope: OperationEnvelope) throws -> any PageOperation {
        guard let decoder = decoders[envelope.kind] else {
            throw SleepyError(
                kind: .environment,
                message: "No operation registered for kind '\(envelope.kind)'.",
                nextMove: "Registered kinds: \(registeredKinds.joined(separator: ", ")).",
            )
        }
        return try decoder(envelope.payload)
    }
}
