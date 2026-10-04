import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import ViewportProtocol

public protocol ThumbnailProviding: Sendable {
    func thumbnails(displayIDs: [UInt32], maxWidth: Int) async -> [ThumbnailPacket]
}

/// T2-NAT-04: small JPEGs of each display for the client's picker (Screen Recording TCC).
public struct SCKThumbnailProvider: ThumbnailProviding {
    public init() {}

    public func thumbnails(displayIDs: [UInt32], maxWidth: Int) async -> [ThumbnailPacket] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return []
        }
        var out: [ThumbnailPacket] = []
        for id in displayIDs {
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let config = SCStreamConfiguration()
            let width = min(maxWidth, display.width * 2)
            config.width = width
            config.height = max(1, width * display.height / max(display.width, 1))
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  let jpeg = Self.jpeg(image)
            else { continue }
            out.append(ThumbnailPacket(displayID: id, jpeg: jpeg))
        }
        return out
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.6) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}

/// Fixed thumbnails for tests.
public struct StaticThumbnailProvider: ThumbnailProviding {
    public init() {}

    public func thumbnails(displayIDs: [UInt32], maxWidth: Int) async -> [ThumbnailPacket] {
        displayIDs.map { ThumbnailPacket(displayID: $0, jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9])) }
    }
}
