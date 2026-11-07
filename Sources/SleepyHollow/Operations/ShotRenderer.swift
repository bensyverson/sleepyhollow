import Foundation

/// Which renderer drew a shot — and, for the fallback, why.
///
/// `shot` renders through the compositor by default: `CARenderer` draws the
/// page's live Core Animation layer tree, so CSS 3D comes out as a browser
/// draws it (`project/2026-11-06-true-3d-shots.md` § Ruling on the capture
/// path). Where the compositor would draw something wrong — a `<video>`,
/// which is a remote-hosted layer it draws blank — or cannot run at all, the
/// shot falls back to WebKit's `takeSnapshot`, which paints CSS 3D flat.
/// Every shot names which it was, so a fallback is never silent.
///
/// On the wire it is an object with a `name` and, for the fallback, the
/// `fallback` reason: `{"name":"compositor"}`,
/// `{"name":"snapshot","fallback":"video"}`.
public enum ShotRenderer: Friendly {
    /// `CARenderer` over the page's composited layer tree: true 3D,
    /// `backdrop-filter`, and a flat page that matches `takeSnapshot` to
    /// anti-aliasing.
    case compositor

    /// `WKWebView.takeSnapshot`, WebKit's software repaint: draws video, but
    /// reduces every CSS 3D transform to 2D affine and drops
    /// `backdrop-filter`. The flat CSS 3D in its area is reported as
    /// ``ShotOperation/Output/flattened3D``.
    case snapshot(Fallback)

    /// Why a shot fell back to ``ShotRenderer/snapshot(_:)``.
    public enum Fallback: String, Friendly, CaseIterable {
        /// The shot area holds a rendered `<video>`, which the compositor
        /// draws blank without any error.
        case video
        /// The host has no live window, so WebKit commits no layer tree for
        /// the compositor to draw (``PageHost/Hosting/windowless``).
        case windowless
        /// This Mac lacks something the compositor needs: a Metal device, or
        /// WebKit's `_doAfterNextPresentationUpdate:`.
        case unavailable
        /// The shot is wider, in output pixels, than one Metal texture
        /// (``ShotRenderer/maximumWidth``).
        case tooWide
    }

    /// The widest shot, in output pixels, the compositor draws: Metal's
    /// largest texture side on every Mac GPU. A taller shot is drawn in
    /// strips; a wider one falls back (``Fallback/tooWide``).
    public static let maximumWidth: Int = 16384

    /// The renderer's wire name: `compositor` or `snapshot`.
    public var name: String {
        switch self {
        case .compositor: Self.compositorName
        case .snapshot: Self.snapshotName
        }
    }

    /// Why the shot fell back, or `nil` for a compositor shot.
    public var fallback: Fallback? {
        switch self {
        case .compositor: nil
        case let .snapshot(fallback): fallback
        }
    }

    private static let compositorName: String = "compositor"
    private static let snapshotName: String = "snapshot"

    private enum CodingKeys: String, CodingKey {
        case name
        case fallback
    }

    /// Decodes `{"name": …, "fallback": …}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name: String = try container.decode(String.self, forKey: .name)
        switch name {
        case Self.compositorName:
            self = .compositor
        case Self.snapshotName:
            self = try .snapshot(container.decode(Fallback.self, forKey: .fallback))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: container, debugDescription: "Unknown renderer '\(name)'.",
            )
        }
    }

    /// Encodes `{"name": …}`, plus `"fallback"` for a snapshot.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(fallback, forKey: .fallback)
    }
}
