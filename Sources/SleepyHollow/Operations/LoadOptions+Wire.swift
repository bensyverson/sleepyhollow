public extension LoadOptions {
    /// A copy of these options with the fetch recorder installed.
    ///
    /// The recorder has to be a document-start user script — a wrapper added
    /// after parsing begins misses the first inline script's request — so it
    /// cannot be installed by ``WireOperation``, which runs against a page
    /// that has already loaded. `sleepy wire` asks for it here, before the
    /// host exists; a session that wants `wire` must be opened the same way.
    ///
    /// - Parameter byteCap: how many response-body bytes the recorder reads
    ///   per exchange before reporting ``FetchExchange/Truncation/size``.
    func recordingWire(byteCap: Int = WireRecorder.defaultByteCap) -> LoadOptions {
        var copy: LoadOptions = self
        copy.scripts.append(WireRecorder.script(byteCap: byteCap))
        return copy
    }
}
