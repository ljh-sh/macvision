import Foundation
import CoreGraphics
import Vision

/// Image-input options shared by every vision subcommand.
let imageInputOpts: [OptMeta] = [
    OptMeta(name: "--clipboard", type: Bool.self, desc: "Read the image from the clipboard"),
    OptMeta(name: "--screen", type: Bool.self, desc: "Take a fresh screenshot first"),
    OptMeta(name: "--orientation", type: String.self, desc: "EXIF orientation: up|down|left|right|... (default: up)"),
]

func parseOrientation(_ s: String?) -> CGImagePropertyOrientation {
    guard let s else { return .up }
    switch s.lowercased() {
    case "up", "1": return .up
    case "down", "3": return .down
    case "left", "8": return .left
    case "right", "6": return .right
    case "upmirrored", "2": return .upMirrored
    case "downmirrored", "4": return .downMirrored
    case "leftmirrored", "5": return .leftMirrored
    case "rightmirrored", "7": return .rightMirrored
    default: return .up
    }
}

/// Resolve + load the image from a parsed command, returning the engine and source.
func loadEngine(_ p: ParsedCmd) throws -> (VisionEngine, ImageSource) {
    let clipboard = p.opt("--clipboard") as Bool? ?? false
    let screen = p.opt("--screen") as Bool? ?? false
    let src = ImageLoader.resolve(arg: p.arg(0), clipboard: clipboard, screen: screen)
    let img = try ImageLoader.load(src)
    let orient = parseOrientation(p.opt("--orientation") as String?)
    return (VisionEngine(image: img, orientation: orient), src)
}

/// Load an engine from a raw source token (used by the FIFO daemon).
func loadEngine(arg: String?) throws -> (VisionEngine, ImageSource) {
    let src = ImageLoader.resolve(arg: arg, clipboard: false, screen: false)
    let img = try ImageLoader.load(src)
    return (VisionEngine(image: img, orientation: .up), src)
}

/// Shared success header for every result.
func baseResult(_ engine: VisionEngine, _ src: ImageSource) -> [String: Any] {
    ["ok": true, "image": ImageLoader.label(src), "width": engine.width, "height": engine.height]
}

/// Optional value helper: read `key` from a daemon request dict as type T.
func reqVal<T>(_ dict: [String: Any], _ key: String, _ fallback: T) -> T {
    (dict[key] as? T) ?? fallback
}
