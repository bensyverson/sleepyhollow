import Foundation

/// Reads the page's accessibility tree: roles, names, states and structure,
/// with presentation stripped away.
///
/// The computation happens in the page, in the isolated world, from the
/// library's own script (`AXScript`) — see `project/2026-08-20-ax-spike.md`
/// for why the native macOS accessibility path is closed to a headless CLI.
/// What comes back is the page's semantics *per WAI-ARIA and AccName*, which
/// is the contract pages are written against.
///
/// ```swift
/// let tree = try await host.execute(AXOperation())
/// let publish = tree.flattened.first { $0.role == .button && $0.name == "Publish" }
/// ```
public struct AXOperation: ExecutablePageOperation {
    /// The tree's root: the document node.
    public typealias Output = AXNode

    /// The wire identifier.
    public static let kind: String = "ax"

    /// Creates the operation. It has no parameters: the tree is the tree.
    public init() {}

    /// Computes the tree in `host`'s current page.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the page cannot run the computation (a frame that went away mid-read)
    ///   or answers with something this build cannot decode.
    @MainActor
    public func execute(on host: PageHost) async throws -> AXNode {
        let json: String
        do {
            json = try await host.evaluate(AXScript.source)
        } catch let error as SleepyError {
            throw error
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The page could not compute its accessibility tree: \(error.localizedDescription)",
                nextMove: "Reload the page and try again; if it persists, the page may be navigating while being read.",
            )
        }
        do {
            return try JSONDecoder().decode(AXNode.self, from: Data(json.utf8))
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The accessibility computation answered with a tree this build can't read.",
                nextMove: "This is a bug in SleepyHollow — please report the page that caused it.",
            )
        }
    }
}
