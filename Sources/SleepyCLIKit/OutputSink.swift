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
    ///
    /// A file destination's parent directories are created first, like
    /// `mkdir -p`: `--out runs/2026-08-28/home.png` into a tree that doesn't
    /// exist yet is an ordinary thing for an agent to ask for, and Foundation's
    /// own failure for it ("The file 'home.png' doesn't exist.") names the
    /// wrong thing entirely.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   naming the *directory* when it can't be created — the fact an agent
    ///   can act on.
    public func write(_ data: Data) throws {
        switch destination {
        case .standardOutput:
            FileHandle.standardOutput.write(data)
        case let .file(url):
            try Self.createParentDirectory(of: url)
            try data.write(to: url)
        }
    }

    /// Creates `url`'s parent directory and every level above it, and does
    /// nothing when it already exists.
    private static func createParentDirectory(of url: URL) throws {
        let directory: URL = url.deletingLastPathComponent()
        let manager: FileManager = .default

        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else { return }
            throw SleepyError(
                kind: .environment,
                message: "'\(directory.path)' is a file, so nothing can be written inside it.",
                nextMove: "Give --out a path whose parent is a directory, or remove that file first.",
            )
        }

        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "Could not create the directory '\(directory.path)' for --out: "
                    + "\(error.localizedDescription)",
                nextMove: "Check the path is writable, or write somewhere you own.",
            )
        }
    }
}
