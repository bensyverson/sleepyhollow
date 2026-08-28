import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import TestSupport

/// `sleepy shot`, `sleepy pdf`, `sleepy archive` end to end: the capture
/// family against the real binary and real fixtures.
struct CaptureGoldenTests {
    @Test func `shot writes a decodable PNG sized to the viewport and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile(extension: "png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["shot", url, "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0)
            #expect(result.standardError.isEmpty)
            let data = try Data(contentsOf: out)
            let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
            #expect(dimensions.width == 1280)
            #expect(dimensions.height == 800)
        }
    }

    @Test func `shot --full-page writes a PNG taller than the viewport`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile(extension: "png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["shot", url, "--full-page", "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0)
            let data = try Data(contentsOf: out)
            let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
            #expect(dimensions.height > 800)
        }
    }

    @Test func `shot --element crops to the element and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile(extension: "png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["shot", url, "--element", "#target", "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0)
            let data = try Data(contentsOf: out)
            let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
            #expect(abs(dimensions.width - 200) <= 2)
            #expect(abs(dimensions.height - 150) <= 2)
        }
    }

    @Test func `shot --element with no match exits 1 and writes nothing`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile(extension: "png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--element", "#does-not-exist", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 1)
            #expect(!result.standardError.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: out.path))
        }
    }

    @Test func `shot --session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }

    @Test func `pdf writes a valid PDF via --out and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile(extension: "pdf")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["pdf", url, "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0)
            let data = try Data(contentsOf: out)
            #expect(data.count > 512)
            #expect(data.prefix(5) == Data("%PDF-".utf8))
        }
    }

    @Test func `pdf paginates print media onto the sheet --paper names`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("print-paginated.html").absoluteString
            let out = Self.temporaryFile(extension: "pdf")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(
                ["pdf", url, "--paper", "a4", "--budget", "60000", "--out", out.path],
            )
            #expect(result.exitCode == 0, "\(result.standardError)")
            let document = try #require(try PDFDocument(data: Data(contentsOf: out)))
            #expect(document.pageCount >= 3)
            let text = try #require(document.string)
            #expect(text.contains("Paginated body paragraph"))
            #expect(!text.contains("SCREENONLYBANNER"))
            let box = try #require(document.page(at: 0)).bounds(for: .mediaBox)
            #expect(abs(Double(box.width) - 595.28) < 2)
            #expect(abs(Double(box.height) - 841.89) < 2)
        }
    }

    @Test func `archive writes a parseable webarchive via --out and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile(extension: "webarchive")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["archive", url, "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0)
            let data = try Data(contentsOf: out)
            let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            #expect(plist["WebMainResource"] != nil)
        }
    }

    private static func temporaryFile(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    private static func pixelDimensions(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height)
    }
}
