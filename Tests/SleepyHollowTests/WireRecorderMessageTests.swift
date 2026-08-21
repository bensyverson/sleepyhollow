import Foundation
import SleepyHollow
import Testing
import TestSupport

/// Collects script messages off a stream while a load runs.
private actor MessageCollector {
    private var received: [String] = []

    func append(_ message: String) {
        received.append(message)
    }

    func all() -> [String] {
        received
    }
}

@Suite("Wire recorder messages")
struct WireRecorderMessageTests {
    @Test
    @MainActor
    func `each exchange posts request, response and body, correlated by id`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            let stream: AsyncStream<String> = host.messages(named: WireRecorder.messageName, in: .page)
            let collector = MessageCollector()
            let pump = Task {
                for await message in stream {
                    await collector.append(message)
                }
            }
            _ = try await host.load(URL(string: "fetch.html", relativeTo: base)!)
            _ = try await host.execute(WireOperation())

            // Delivery is asynchronous by nature: the exchanges are complete,
            // but the subscriber still has to be scheduled. Wait for the six
            // messages the fixture's two fetches owe, then stop.
            var messages: [String] = []
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                messages = await collector.all()
                if messages.count >= 6 { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            pump.cancel()

            let decoded: [[String: Any]] = messages.compactMap { text in
                let object: Any? = try? JSONSerialization.jsonObject(with: Data(text.utf8))
                return object as? [String: Any]
            }
            for id in [1, 2] {
                let exchange: [[String: Any]] = decoded.filter { ($0["id"] as? Int) == id }
                #expect(exchange.compactMap { $0["kind"] as? String } == ["request", "response", "body"])
            }
            let post: [String: Any] = try #require(decoded.first {
                ($0["kind"] as? String) == "request" && ($0["method"] as? String) == "POST"
            })
            #expect((post["requestBody"] as? String) == "field=starlight")
        }
    }
}
