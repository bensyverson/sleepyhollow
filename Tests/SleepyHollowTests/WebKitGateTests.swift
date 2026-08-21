import Foundation
import Testing
import TestSupport

@Suite("WebKit concurrency gate")
struct WebKitGateTests {
    /// Tracks how many tasks hold a slot at once.
    private actor PeakCounter {
        private(set) var active = 0
        private(set) var peak = 0
        private(set) var completed = 0

        func enter() {
            active += 1
            peak = max(peak, active)
        }

        func exit() {
            active -= 1
            completed += 1
        }
    }

    @Test
    func `no more than width tasks hold the gate at once`() async {
        let gate = WebKitGate(width: 2)
        let counter = PeakCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 12 {
                group.addTask {
                    await gate.acquire()
                    await counter.enter()
                    // A real suspension, so overlapping holders would be seen.
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    await counter.exit()
                    await gate.release()
                }
            }
        }
        #expect(await counter.peak <= 2, "the gate must bound concurrent holders to its width")
        #expect(await counter.peak == 2, "the gate must not serialize below its width")
        #expect(await counter.completed == 12, "every waiter must eventually pass through")
    }

    @Test
    func `a released slot wakes a waiter`() async throws {
        let gate = WebKitGate(width: 1)
        await gate.acquire()
        let counter = PeakCounter()
        let waiter = Task {
            await gate.acquire()
            await counter.enter()
            await gate.release()
        }
        // The waiter must be blocked: give it a real chance to run wrongly.
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await counter.active == 0, "a full gate must make acquirers wait")
        await gate.release()
        await waiter.value
        #expect(await counter.peak == 1, "release must hand the slot to the waiter")
    }
}
