import Foundation
import CoreGraphics
import ImageIO

/// Write a `CGImage` to disk as PNG.
func savePNG(_ cg: CGImage, to url: URL) throws {
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw VisionError.requestFailed("cannot create PNG at \(url.path)")
    }
    CGImageDestinationAddImage(dst, cg, nil)
    guard CGImageDestinationFinalize(dst) else {
        throw VisionError.requestFailed("cannot write PNG at \(url.path)")
    }
}
