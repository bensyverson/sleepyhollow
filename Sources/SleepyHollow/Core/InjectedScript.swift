/// A user script installed before a load (`WKUserScript` at the host layer).
///
/// Injection is a flag, not a verb, because user scripts must be in place
/// before the document starts — this is what retires the injecting-middleware
/// pattern.
public struct InjectedScript: Friendly {
    /// When the script runs relative to document parsing.
    public enum InjectionTime: String, Friendly {
        /// Before the document starts parsing.
        case documentStart
        /// After the document finishes parsing.
        case documentEnd
    }

    /// Which JavaScript world the script runs in.
    ///
    /// `CaseIterable` so the CLI's `--inject-world` can name both worlds when
    /// it refuses a third.
    public enum World: String, CaseIterable, Friendly {
        /// The tool's isolated world — instrumentation that cannot collide
        /// with page JS. The default.
        case isolated
        /// The page's own world, for when the page's state is the subject.
        case page
    }

    /// The script source.
    public var source: String

    /// When the script runs. Default ``InjectionTime/documentStart``.
    public var injectAt: InjectionTime

    /// Where the script runs. Default ``World/isolated``.
    public var world: World

    /// Creates an injected script.
    public init(source: String, injectAt: InjectionTime = .documentStart, world: World = .isolated) {
        self.source = source
        self.injectAt = injectAt
        self.world = world
    }
}
