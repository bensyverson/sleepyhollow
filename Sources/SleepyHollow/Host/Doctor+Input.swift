import Foundation
import WebKit

public extension Doctor {
    /// The `WKWebView` selectors ``checkInput(selectors:)`` asks for by
    /// default: the SPI behind `press`, `--type`, `--press` and `--hover`.
    static var inputSelectors: [String] {
        InputSPI.all
    }

    /// Whether this WebKit has the private selectors real keyboard and
    /// pointer input rest on (see `TrustedInput`).
    ///
    /// Without them `press` and the `--hover` step refuse with an environment
    /// error rather than fall back to untrusted events, so this names the
    /// missing selectors before an agent meets that refusal.
    ///
    /// - Parameter selectors: the selectors to look for; the default is
    ///   ``inputSelectors``. A test passes a bogus one to prove the failure.
    /// - Returns: ok when every selector is present; failed naming the
    ///   missing ones.
    static func checkInput(selectors: [String] = inputSelectors) -> DoctorCheck {
        let missing: [String] = selectors.filter { !WKWebView.instancesRespond(to: NSSelectorFromString($0)) }
        guard missing.isEmpty else {
            return .failed(
                .input,
                "This WebKit has no -[WKWebView \(missing.joined(separator: ", "))], so `press`, --type, --press "
                    + "and --hover cannot deliver real keystrokes or pointer moves, and refuse.",
                nextMove: "Use the synthesized act verbs (click, fill, submit), which say they are untrusted, "
                    + "and report this macOS version as a seam bug.",
            )
        }
        return .passed(.input, "Real keyboard and pointer input is available (WebKit's input SPI is present).")
    }
}
