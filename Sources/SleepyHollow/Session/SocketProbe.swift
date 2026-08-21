import Darwin
import Foundation

/// Answers one question about a Unix domain socket path: is anything
/// listening there right now?
///
/// Deliberately BSD sockets rather than `Network.framework`: a `connect(2)` to
/// a local socket answers immediately and synchronously — accepted into the
/// listener's backlog, or `ECONNREFUSED` — while an `NWConnection` to a dead
/// socket enters `.waiting` and retries forever, which is a hang wearing a
/// probe's clothes.
enum SocketProbe {
    /// The longest socket path the kernel can address, from `sockaddr_un`'s
    /// `sun_path` (104 bytes, one reserved for the terminator).
    ///
    /// Not a style limit: `NWConnection(to: .unix(path:))` **crashes** on a
    /// longer path, and `bind` silently truncates, so the registry refuses
    /// such a path with a teaching error before either can happen.
    static let maximumPathLength: Int = 103

    /// Whether a listener accepts a connection at `path`.
    ///
    /// `false` for a missing path, a stale socket file nobody owns, a regular
    /// file, or a path the kernel cannot address.
    static func isListening(atPath path: String) -> Bool {
        let bytes: [UInt8] = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumPathLength else { return false }

        let descriptor: Int32 = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let capacity: Int = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { path in
            path.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (offset, byte) in bytes.enumerated() {
                    destination[offset] = CChar(bitPattern: byte)
                }
                destination[bytes.count] = 0
            }
        }
        let outcome: Int32 = withUnsafePointer(to: &address) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return outcome == 0
    }
}
