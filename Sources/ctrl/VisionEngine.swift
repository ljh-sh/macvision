import Foundation
import CoreGraphics
import ImageIO
import Vision

enum VisionError: Error, LocalizedError {
    case imageLoadFailed(String)
    case requestFailed(String)
    case unsupportedOnThisMac(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let m): return "image load failed: \(m)"
        case .requestFailed(let m): return m
        case .unsupportedOnThisMac(let m): return "unsupported on this Mac: \(m)"
        }
    }
}

/// Thin wrapper around a decoded `CGImage` plus the helpers needed to translate
/// Vision's normalized (bottom-left origin) geometry into pixel (top-left origin)
/// coordinates that an agent can map directly onto the screen.
struct VisionEngine {
    let image: CGImage
    let orientation: CGImagePropertyOrientation

    var width: Int { image.width }
    var height: Int { image.height }

    /// Run one or more Vision requests against the image.
    func perform(_ requests: [VNRequest]) throws {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        do {
            try handler.perform(requests)
        } catch {
            throw VisionError.requestFailed(error.localizedDescription)
        }
    }

    // MARK: - Geometry helpers

    /// Convert a Vision normalized rect (origin bottom-left, values 0...1) into
    /// pixel `[x, y, w, h]` with origin at the top-left of the image.
    func pixelBox(_ norm: CGRect) -> [Int] {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let px = Int(round(norm.minX * w))
        let py = Int(round((1 - norm.minY - norm.height) * h))
        let pw = Int(round(norm.width * w))
        let ph = Int(round(norm.height * h))
        return [px, py, pw, ph]
    }

    /// Same rect, normalized but flipped to top-left origin `[x, y, w, h]` in 0...1.
    static func normBox(_ norm: CGRect) -> [Double] {
        return [
            norm.minX,
            1 - norm.minY - norm.height,
            norm.width,
            norm.height
        ]
    }

    /// Convert a Vision normalized point to pixel `[x, y]` (top-left origin).
    func pixelPoint(_ p: CGPoint) -> [Int] {
        [Int(round(p.x * CGFloat(width))), Int(round((1 - p.y) * CGFloat(height)))]
    }
}
