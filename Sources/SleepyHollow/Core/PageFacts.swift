import Foundation

/// The facts a load reports: the base output of `sleepy load` and the
/// last-state attachment on timeouts.
public struct PageFacts: Friendly {
    /// Where navigation ended, redirects included.
    public var finalURL: URL?

    /// The main resource's HTTP status, when the navigation was HTTP.
    public var httpStatus: Int?

    /// How many console errors the page emitted.
    public var consoleErrorCount: Int

    /// Every dialog raised, with the answers the policy gave.
    public var dialogs: [DialogRecord]

    /// Creates page facts.
    public init(
        finalURL: URL? = nil,
        httpStatus: Int? = nil,
        consoleErrorCount: Int = 0,
        dialogs: [DialogRecord] = [],
    ) {
        self.finalURL = finalURL
        self.httpStatus = httpStatus
        self.consoleErrorCount = consoleErrorCount
        self.dialogs = dialogs
    }
}
