/// One accessibility state on a node: a name and the value the page computed
/// for it.
///
/// States are only present when they *apply* — an element that cannot be
/// checked carries no `checked` state at all — and tri-state attributes keep
/// their third value rather than being flattened to a boolean.
public struct AXState: Friendly {
    /// The states the tool reports, in the order the outline sorts them
    /// (alphabetically, which is also this declaration order).
    public enum Name: String, Friendly, Comparable {
        /// The element is checked: `checkbox`, `radio`, `switch`, and the
        /// menu item variants. May be ``AXState/Value/token(_:)`` `"mixed"`.
        case checked
        /// `aria-current`: the element represents the current item in a set.
        case current
        /// The element is disabled — natively, through an ancestor
        /// `fieldset[disabled]`, or by `aria-disabled`.
        case disabled
        /// `aria-expanded`, or an open `details` for its `summary`.
        case expanded
        /// A heading's level.
        case level
        /// `aria-pressed` on a toggle button. May be `"mixed"`.
        case pressed
        /// The element is read-only, natively or by `aria-readonly`.
        case readonly
        /// The element is required, natively or by `aria-required`.
        case required
        /// `aria-selected`, or a selected `option`.
        case selected

        /// Alphabetical, which is the order states render in.
        public static func < (lhs: Name, rhs: Name) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// A state's value: a flag, a token such as `"mixed"`, or a number.
    ///
    /// It encodes as the bare JSON scalar — `true`, `"mixed"`, `1` — so the
    /// wire shape stays readable and a consumer needs no envelope.
    public enum Value: Friendly {
        /// A boolean state, reported both ways when the state applies.
        case flag(Bool)
        /// A token value, such as `"mixed"` or `aria-current`'s `"page"`.
        case token(String)
        /// A numeric value, such as a heading level.
        case number(Int)

        /// Decodes a bare JSON `true`/`false`, number, or string.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else if let number = try? container.decode(Int.self) {
                self = .number(number)
            } else {
                self = try .token(container.decode(String.self))
            }
        }

        /// Encodes as a bare JSON scalar.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .flag(flag): try container.encode(flag)
            case let .token(token): try container.encode(token)
            case let .number(number): try container.encode(number)
            }
        }
    }

    /// Which state this is.
    public let name: Name

    /// What the page computed for it.
    public let value: Value

    /// Creates a state.
    public init(name: Name, value: Value) {
        self.name = name
        self.value = value
    }

    /// The element is disabled.
    public static let disabled: AXState = .init(name: .disabled, value: .flag(true))

    /// The element is required.
    public static let required: AXState = .init(name: .required, value: .flag(true))

    /// The element is read-only.
    public static let readonly: AXState = .init(name: .readonly, value: .flag(true))
}
