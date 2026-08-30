import Foundation
@testable import SleepyHollow
import Testing

/// A helper can only run what it can decode: every operation a page verb ships
/// must be registered, or `--session` silently loses that verb.
struct SessionOperationsRegistryTests {
    /// The wire kind of every operation a 1.0 verb sends to a session.
    static let requiredKinds: [String] = [
        ArchiveOperation.kind,
        AXOperation.kind,
        ClickOperation.kind,
        ConsoleOperation.kind,
        ContrastOperation.kind,
        CookiesOperation.kind,
        DOMOperation.kind,
        EvalOperation.kind,
        FillOperation.kind,
        FindOperation.kind,
        NavigateOperation.kind,
        OverflowOperation.kind,
        PDFOperation.kind,
        QueryOperation.kind,
        ResizeOperation.kind,
        ShotOperation.kind,
        StyleOperation.kind,
        SubmitOperation.kind,
        WireOperation.kind,
    ]

    @Test func `every verb's operation is registered with the helper`() {
        let registered: Set<String> = Set(SessionOperations.registry.registeredKinds)
        for kind in Self.requiredKinds {
            #expect(registered.contains(kind), "'\(kind)' is not registered: --session would refuse that verb")
        }
    }

    @Test func `a registered kind round-trips through an envelope`() throws {
        let envelope = try OperationEnvelope(QueryOperation(selector: "p"))
        let decoded = try SessionOperations.registry.decode(envelope)
        #expect(type(of: decoded).kind == QueryOperation.kind)
    }

    @Test func `navigate carries an optional URL: nil means read the facts`() throws {
        let none = NavigateOperation(url: nil)
        #expect(none.url == nil)
        let url: URL = try #require(URL(string: "http://example.com/next"))
        let envelope = try OperationEnvelope(NavigateOperation(url: url))
        let decoded = try SessionOperations.registry.decode(envelope)
        #expect((decoded as? NavigateOperation)?.url == url)
    }
}
