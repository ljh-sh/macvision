import Foundation
import AppKit
import CoreGraphics
import ImageIO

/// Where an image comes from.
enum ImageSource {
    case file(URL)
    case stdin          // base64-encoded image bytes on stdin
    case clipboard      // image currently on the pasteboard
    case screen         // a fresh macOS screenshot
}

/// Resolve a CLI argument into an image source.
///
/// Special positional tokens:
/// - `-` / `stdin`     read base64-encoded bytes from stdin
/// - `clipboard`/`clip`/`paste`   read the image on the clipboard
/// - `screen`/`capture`           take a fresh screenshot
///
/// `--clipboard` and `--screen` flags take precedence over the positional token.
enum ImageLoader {
    static func resolve(arg: String?, clipboard: Bool, screen: Bool) -> ImageSource {
        if clipboard { return .clipboard }
        if screen { return .screen }
        guard let arg, !arg.isEmpty else {
            cmdError("image source required — pass a file path, '-' for stdin base64, or use --clipboard / --screen")
        }
        switch arg {
        case "-", "stdin": return .stdin
        case "clipboard", "clip", "paste": return .clipboard
        case "screen", "capture": return .screen
        default: return .file(URL(fileURLWithPath: arg))
        }
    }

    /// Human-readable label for the source, embedded in JSON output.
    static func label(_ src: ImageSource) -> String {
        switch src {
        case .file(let url): return url.path
        case .stdin: return "stdin"
        case .clipboard: return "clipboard"
        case .screen: return "screen"
        }
    }

    /// Decode the source into a `CGImage`.
    static func load(_ src: ImageSource) throws -> CGImage {
        switch src {
        case .file(let url):
            return try loadFile(url)
        case .stdin:
            return try loadStdin()
        case .clipboard:
            return try loadClipboard()
        case .screen:
            return try loadScreen()
        }
    }

    // MARK: - Loaders

    private static func loadFile(_ url: URL) throws -> CGImage {
        guard
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            throw VisionError.imageLoadFailed("cannot read image at \(url.path)")
        }
        return cg
    }

    private static func loadStdin() throws -> CGImage {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let decoded: Data
        if let raw = base64DecodeOrEmpty(data) {
            decoded = raw
        } else {
            // Not valid base64 — treat the bytes as a raw image.
            decoded = data
        }
        guard !decoded.isEmpty else {
            throw VisionError.imageLoadFailed("stdin is empty")
        }
        return try cgImage(from: decoded, hint: "stdin")
    }

    private static func loadClipboard() throws -> CGImage {
        ensureAppKit()
        guard let ns = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            throw VisionError.imageLoadFailed("no image on the clipboard")
        }
        guard let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionError.imageLoadFailed("clipboard image could not be decoded")
        }
        return cg
    }

    private static func loadScreen() throws -> CGImage {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("macvision-screen-\(ProcessInfo.processInfo.processIdentifier).png")
        // Silent capture of the main display (-x suppresses sound, no UI).
        let proc = Process()
        proc.launchPath = "/usr/sbin/screencapture"
        proc.arguments = ["-x", "-t", "png", tmp.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, FileManager.default.fileExists(atPath: tmp.path) else {
            throw VisionError.imageLoadFailed("screencapture failed (screen recording permission may be required)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try loadFile(tmp)
    }

    // MARK: - Helpers

    private static func cgImage(from data: Data, hint: String) throws -> CGImage {
        guard
            let src = CGImageSourceCreateWithData(data as CFData, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            throw VisionError.imageLoadFailed("\(hint) is not a decodable image")
        }
        return cg
    }

    private static func base64DecodeOrEmpty(_ data: Data) -> Data? {
        guard let s = String(data: data, encoding: .utf8),
              let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let out = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters])
        else { return nil }
        return out
    }

    /// Touching `NSApplication.shared` is enough for pasteboard access in a CLI;
    /// we never need to spin a run loop for Vision.
    private static func ensureAppKit() {
        _ = NSApplication.shared
    }
}
