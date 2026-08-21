import Foundation

/// The framing on the session socket: a four-byte big-endian length, then that
/// many bytes of JSON.
///
/// A stream socket delivers bytes, not messages, so the protocol needs its own
/// message boundary. A length prefix is the smallest honest one — the reader
/// knows when a message is complete instead of guessing at delimiters, and a
/// truncated write is detectable rather than silently parsed as something else.
enum SessionFrame {
    /// The header's width in bytes.
    static let headerLength: Int = 4

    /// The largest payload a frame may carry (32 MiB).
    ///
    /// A ceiling exists so a corrupt or hostile length prefix cannot make the
    /// reader wait for gigabytes that will never arrive.
    static let maximumPayloadLength: Int = 32 * 1024 * 1024

    /// Encodes `value` as one frame.
    static func encode(_ value: some Encodable) throws -> Data {
        let payload: Data = try JSONEncoder().encode(value)
        guard payload.count <= maximumPayloadLength else {
            throw oversized(payload.count)
        }
        var frame = Data(capacity: headerLength + payload.count)
        let length = UInt32(payload.count)
        for shift: UInt32 in [24, 16, 8, 0] {
            frame.append(UInt8(truncatingIfNeeded: length >> shift))
        }
        frame.append(payload)
        return frame
    }

    /// Decodes the first complete frame in `buffer`, consuming it.
    ///
    /// - Returns: the decoded value, or `nil` when `buffer` does not hold a
    ///   whole frame yet — the caller reads more bytes and asks again.
    /// - Throws: ``SleepyError`` when the frame claims more than
    ///   ``maximumPayloadLength``, or when its JSON does not decode.
    static func decode<Value: Decodable>(_ type: Value.Type, from buffer: inout Data) throws -> Value? {
        guard buffer.count >= headerLength else { return nil }
        let header: Data = buffer.prefix(headerLength)
        let length = Int(header.reduce(UInt32(0)) { accumulated, byte in
            (accumulated << 8) | UInt32(byte)
        })
        guard length <= maximumPayloadLength else {
            throw oversized(length)
        }
        guard buffer.count >= headerLength + length else { return nil }
        let start: Data.Index = buffer.index(buffer.startIndex, offsetBy: headerLength)
        let end: Data.Index = buffer.index(start, offsetBy: length)
        let payload = Data(buffer[start ..< end])
        buffer = Data(buffer[end...])
        do {
            return try JSONDecoder().decode(type, from: payload)
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The session socket carried a frame this build can't read: \(error).",
                nextMove: "Close the session and reopen it — the helper is from a different build.",
            )
        }
    }

    private static func oversized(_ length: Int) -> SleepyError {
        SleepyError(
            kind: .environment,
            message: "A session frame of \(length) bytes exceeds the \(maximumPayloadLength)-byte ceiling.",
            nextMove: "Ask for less in one operation, or close and reopen the session if this is corruption.",
        )
    }
}
