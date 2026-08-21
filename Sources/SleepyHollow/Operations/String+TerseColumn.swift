extension String {
    /// The string padded with spaces to `width`, never truncated: terse output
    /// lines up where it can and stays honest where it cannot.
    func paddedToColumn(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
