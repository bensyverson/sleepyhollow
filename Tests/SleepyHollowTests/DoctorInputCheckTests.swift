import Foundation
import SleepyHollow
import Testing

/// `sleepy doctor`'s `input` check: the WebKit SPI real keyboard and pointer
/// input rest on is present (leaf `XerXuw`; Ben's approval of the SPI came
/// with the requirement that doctor checks it, as it checks the accent pin).
struct DoctorInputCheckTests {
    @Test func `the input check passes on this WebKit`() {
        let check = Doctor.checkInput()
        #expect(check.name == .input)
        #expect(check.status == .ok)
    }

    @Test func `the input check names a selector this WebKit lacks, and teaches`() {
        let check = Doctor.checkInput(selectors: ["_doAfterProcessingAllPendingKeyEvents:", "_sleepyNoSuchSelector:"])
        #expect(check.name == .input)
        #expect(check.status == .failed)
        #expect(check.detail.contains("_sleepyNoSuchSelector:"))
        #expect(!check.detail.contains("_doAfterProcessingAllPendingKeyEvents:"))
        #expect(check.nextMove?.isEmpty == false)
    }

    @Test func `the default selectors are the ones real input uses`() {
        #expect(Doctor.inputSelectors.sorted() == [
            "_doAfterProcessingAllPendingKeyEvents:",
            "_doAfterProcessingAllPendingMouseEvents:",
            "_simulateMouseMove:",
        ])
    }
}
