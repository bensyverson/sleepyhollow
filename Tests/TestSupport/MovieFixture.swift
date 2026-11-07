import AVFoundation
import CoreVideo
import Foundation

/// A real, playable movie for tests that need a `<video>` with a decoded
/// frame, written at test time so no binary lives in the repo.
public enum MovieFixture {
    /// The movie's one color, in sRGB: every frame is solid magenta, so a
    /// capture finds the video by counting pixels of it.
    public static let color: (red: UInt8, green: UInt8, blue: UInt8) = (255, 0, 255)

    /// Writes a two-second, 30 fps, 320×192 H.264 movie of solid
    /// ``color`` to `url`, replacing any file there.
    ///
    /// - Throws: AVFoundation's error when the writer cannot start or finish.
    public static func writeMagenta(to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = 320
        let height = 192
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< 60 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let buffer = magentaFrame(width: width, height: height) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    /// One solid-``color`` BGRA frame.
    private static func magentaFrame(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let pixel = base + row * rowBytes + column * 4
                pixel[0] = color.blue
                pixel[1] = color.green
                pixel[2] = color.red
                pixel[3] = 255
            }
        }
        return buffer
    }
}
