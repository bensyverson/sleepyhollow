import ArgumentParser
import SleepyHollow

/// Lets `--min` accept `wcag-aa`, `wcag-aaa` or a bare ratio directly as a
/// ``ContrastMinimum``.
///
/// `allValueStrings` names only the two constants: they are what an agent
/// should reach for, because each carries WCAG's *two* thresholds, and a
/// bare ratio — which applies one bar to text of every size — is documented
/// in the flag's help instead of offered as a completion.
extension ContrastMinimum: ExpressibleByArgument {
    /// Reads the argument, answering `nil` for anything
    /// ``ContrastMinimum/parse(_:)`` refuses.
    public init?(argument: String) {
        guard let parsed = try? ContrastMinimum.parse(argument) else { return nil }
        self = parsed
    }

    /// How the value is spelled back in help and error text.
    public var defaultValueDescription: String {
        description
    }

    /// The two named levels; a ratio is free-form.
    public static var allValueStrings: [String] {
        [wcagAAName, wcagAAAName]
    }
}
