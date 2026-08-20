/// The condition that ends a load's settle phase.
///
/// Waiting is a primitive of the tool, not a polling loop in the agent: the
/// agent states the condition, the host owns the clock, and exhausting the
/// budget is an exit code with the page's last state attached — never a hang.
public enum WaitCondition: Friendly {
    /// A CSS selector that must match at least one element.
    case selector(String)
    /// A JavaScript expression that must evaluate truthy.
    case predicate(String)
    /// Network and script activity has gone quiet.
    case idle
    /// The navigation's load event alone.
    case load
}
