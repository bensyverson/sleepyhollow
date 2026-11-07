import AppKit
import Foundation
import WebKit

/// The compositor capture, as a call on a host: wait for the frame, then
/// render its layer tree.
extension PageHost {
    /// Why this host cannot render through the compositor, or `nil` when it
    /// can.
    ///
    /// The compositor draws the layer tree WebKit commits to the UI process,
    /// and WebKit only commits for a page it considers visible — a host
    /// parked live in its ``OffscreenWindow``. A windowless host, or one
    /// parked with ``OffscreenWindow/Rendering/hidden``, has no current tree
    /// to draw.
    var compositorUnavailability: ShotRenderer.Fallback? {
        guard let offscreenWindow, offscreenWindow.isLive, webView.window != nil else { return .windowless }
        guard CompositorSPI.supportsPresentationUpdate(webView), CompositorRenderer.gpu != nil else {
            return .unavailable
        }
        return nil
    }

    /// Waits until the UI process has applied a layer-tree commit that holds
    /// everything the page did before this call (``CompositorSPI``), inside
    /// the host's ``callBudget``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when no
    ///   update lands within the budget, and of kind
    ///   ``SleepyError/Kind/environment`` when WebKit no longer offers the
    ///   hook.
    func waitForPresentationUpdate() async throws {
        try await answer("presentation update", within: callBudget) { answered in
            let asked = CompositorSPI.afterNextPresentationUpdate(of: webView) {
                answered(.success(()))
            }
            if !asked {
                answered(.failure(SleepyError(
                    kind: .environment,
                    message: "This WebKit no longer offers _doAfterNextPresentationUpdate:.",
                    nextMove: "Shots fall back to takeSnapshot on this macOS; report the version.",
                )))
            }
        }
    }

    /// The web view's backing layer, in its window's layer tree — the layer
    /// the compositor renders and must put back.
    ///
    /// AppKit only builds the window's own layers on the window's first
    /// display pass, so a view parked a moment ago has a backing layer with
    /// no superlayer (measured 2026-11-06: `nil` straight after parking and
    /// after `layoutSubtreeIfNeeded()`, present after `displayIfNeeded()` or
    /// any run-loop turn that displays). This asks for that pass when it has
    /// not happened yet.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when the view has no layer, or no window to place it in.
    func compositedLayer() throws -> CALayer {
        if webView.layer?.superlayer == nil {
            webView.window?.displayIfNeeded()
        }
        guard let layer = webView.layer, layer.superlayer != nil else {
            throw SleepyError(
                kind: .environment,
                message: "The web view's layer is not in a window's layer tree, so the compositor cannot render it.",
                nextMove: "Retry; if this persists, it is a seam bug in the compositor path.",
            )
        }
        return layer
    }

    /// Renders `rect` of the page — view coordinates, top-left origin — at
    /// `scale` pixels per CSS px through the compositor, once the current
    /// frame has been presented.
    ///
    /// - Throws: what ``waitForPresentationUpdate()`` throws, and
    ///   ``SleepyError`` of kind ``SleepyError/Kind/environment`` when the
    ///   render itself fails (no GPU, a texture Metal refuses).
    func compositorImage(of rect: CGRect, scale: Int) async throws -> CGImage {
        try await waitForPresentationUpdate()
        let layer: CALayer = try compositedLayer()
        do {
            return try CompositorRenderer.render(layer, rect: rect, scale: CGFloat(scale))
        } catch let failure as CompositorRenderer.Failure {
            throw SleepyError(
                kind: .environment,
                message: "The compositor could not render this shot (\(failure)).",
                nextMove: "Retry; if this persists, it is a seam bug in the compositor path.",
            )
        }
    }
}
