import WebKit

@MainActor
public extension InjectedScript.World {
    /// The tool's private isolated world — one `WKContentWorld`, shared by
    /// every isolated script and message handler the host installs.
    ///
    /// Isolated worlds share the DOM with the page but not its JavaScript
    /// globals, which is what keeps instrumentation from colliding with page
    /// script — and equally why anything that must *observe* page globals
    /// (`console`, `fetch`) has to run in ``InjectedScript/World/page``.
    static let isolatedContentWorld: WKContentWorld = .world(name: "sleepy-hollow")

    /// The `WKContentWorld` this world maps onto.
    var contentWorld: WKContentWorld {
        switch self {
        case .isolated: Self.isolatedContentWorld
        case .page: WKContentWorld.page
        }
    }
}

extension InjectedScript.InjectionTime {
    /// The `WKUserScriptInjectionTime` this injection time maps onto.
    var userScriptInjectionTime: WKUserScriptInjectionTime {
        switch self {
        case .documentStart: .atDocumentStart
        case .documentEnd: .atDocumentEnd
        }
    }
}

@MainActor
extension InjectedScript {
    /// The `WKUserScript` that installs this script, main frame only.
    var userScript: WKUserScript {
        WKUserScript(
            source: source,
            injectionTime: injectAt.userScriptInjectionTime,
            forMainFrameOnly: true,
            in: world.contentWorld,
        )
    }
}
