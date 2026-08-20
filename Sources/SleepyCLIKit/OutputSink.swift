import Foundation
import SleepyHollow

/// Where a verb's output goes: standard output, or a file named by `--out`.
///
/// Centralizes the "write bytes or text somewhere" concern so every verb's
/// artifact output (a PNG, a PDF, serialized JSON, …) goes through one path.
public struct OutputSink: Friendly {
    /// The concrete destination.
    public enum Destination: Friendly {
        /// Write to the process's standard output.
        case standardOutput
        /// Write to this file, replacing its contents.
        case file(URL)
    }

    /// The resolved destination.
    public let destination: Destination

    /// Creates a sink writing to `path`, or standard output when `path` is
    /// `nil` — the shape `--out <file>` resolves to.
    public init(path: String?) {
        if let path {
            destination = .file(URL(fileURLWithPath: path))
        } else {
            destination = .standardOutput
        }
    }

    /// Writes `text`, encoded as UTF-8, to the resolved destination.
    public func write(_ text: String) throws {
        try write(Data(text.utf8))
    }

    /// Writes `data` to the resolved destination.
    public func write(_ data: Data) throws {
        switch destination {
        case .standardOutput:
            FileHandle.standardOutput.write(data)
        case let .file(url):
            try data.write(to: url)
        }
    }
}
