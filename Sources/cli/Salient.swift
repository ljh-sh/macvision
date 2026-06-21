import Foundation
import Vision
import CoreImage
import CoreGraphics
import CoreVideo

/// Core saliency: produce a heatmap PNG for the most visually salient region.
///
/// `mode` is `"attention"` (what draws the eye, default) or `"objectness"`
/// (where whole objects likely are).
func runSalient(engine: VisionEngine, src: ImageSource, mode: String, output: URL?) throws -> [String: Any] {
    let obs: VNPixelBufferObservation?
    if mode == "objectness" {
        let r = VNGenerateObjectnessBasedSaliencyImageRequest()
        try engine.perform([r])
        obs = r.results?.first
    } else {
        let r = VNGenerateAttentionBasedSaliencyImageRequest()
        try engine.perform([r])
        obs = r.results?.first
    }
    guard let obs else {
        throw VisionError.requestFailed("saliency produced no output")
    }

    let outURL = output ?? defaultTempURL("saliency", "png")
    var saved = false
    if let cg = ciImageToCG(obs.pixelBuffer) {
        try savePNG(cg, to: outURL)
        saved = true
    }

    var result = baseResult(engine, src)
    result["mode"] = (mode == "objectness") ? "objectness" : "attention"
    result["mask_width"] = CVPixelBufferGetWidth(obs.pixelBuffer)
    result["mask_height"] = CVPixelBufferGetHeight(obs.pixelBuffer)
    result["output"] = outURL.path
    result["saved"] = saved
    return result
}

/// Convert a luminance pixel buffer (the saliency mask) to a `CGImage`.
private func ciImageToCG(_ pb: CVPixelBuffer) -> CGImage? {
    let ci = CIImage(cvPixelBuffer: pb)
    return CIContext().createCGImage(ci, from: ci.extent)
}

/// Default output path under the system temp directory.
func defaultTempURL(_ prefix: String, _ ext: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("macvision-\(prefix)-\(ProcessInfo.processInfo.processIdentifier).\(ext)")
}

enum SalientCmd: Cmd {
    static let meta = CmdMeta(
        name: "salient",
        desc: "Produce a saliency heatmap (what the eye is drawn to)",
        opts: imageInputOpts + [
            OptMeta(name: "--mode", type: String.self, desc: "attention (default) | objectness"),
            OptMeta(name: "--output", type: String.self, desc: "Write the heatmap PNG here (default: a temp file)"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let mode = p.opt("--mode") as String? ?? "attention"
            let output = (p.opt("--output") as String?).map { URL(fileURLWithPath: $0) }
            printJson(try runSalient(engine: engine, src: src, mode: mode, output: output))
        }
    )
}
