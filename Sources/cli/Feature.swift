import Foundation
import Vision

/// Compute a single image feature-print (image fingerprint) as a base64 vector.
///
/// `revision2` selects the higher-precision macOS 14+ model when available.
func runFeatureSingle(engine: VisionEngine, src: ImageSource, revision2: Bool) throws -> [String: Any] {
    let obs = try featurePrint(engine: engine, revision2: revision2)
    var result = baseResult(engine, src)
    result["level"] = revision2 ? 2 : 1
    result["element_count"] = obs.elementCount
    result["element_type"] = elementTypeString(obs.elementType)
    result["bytes"] = obs.data.count
    result["data"] = base64Bytes(obs.data)
    return result
}

/// Compute the distance between two images' feature-prints (0 = identical).
func runFeatureCompare(
    engineA: VisionEngine, srcA: ImageSource,
    engineB: VisionEngine, srcB: ImageSource,
    revision2: Bool
) throws -> [String: Any] {
    let a = try featurePrint(engine: engineA, revision2: revision2)
    let b = try featurePrint(engine: engineB, revision2: revision2)
    var distance: Float = 0
    try a.computeDistance(&distance, to: b)
    var result = baseResult(engineA, srcA)
    result["compare"] = ImageLoader.label(srcB)
    result["level"] = revision2 ? 2 : 1
    result["distance"] = distance
    // 0 = identical. A loose "same image" cutoff; callers should pick their own threshold.
    result["same"] = distance < 0.5
    return result
}

func featurePrint(engine: VisionEngine, revision2: Bool) throws -> VNFeaturePrintObservation {
    let r = VNGenerateImageFeaturePrintRequest()
    if revision2, #available(macOS 14, *) {
        r.revision = VNGenerateImageFeaturePrintRequestRevision2
    }
    try engine.perform([r])
    guard let obs = r.results?.first else {
        throw VisionError.requestFailed("featureprint produced no output")
    }
    return obs
}

private func elementTypeString(_ t: VNElementType) -> String {
    switch t {
    case .float: return "float"
    case .double: return "double"
    case .unknown: return "unknown"
    @unknown default: return "unknown"
    }
}

enum FeatureCmd: Cmd {
    static let meta = CmdMeta(
        name: "feature",
        desc: "Image fingerprint (feature-print vector), or compare two images",
        synopsis: [
            "macvision feature <image>                    # fingerprint vector (base64)",
            "macvision feature <image> --compare <other>  # distance (0 = identical)",
            "macvision feature <image> --level 2          # more precise (macOS 14+)",
        ],
        tldr: [
            ("Get an image fingerprint", "macvision feature a.jpg"),
            ("Are two images the same? (distance ~0)", "macvision feature a.jpg --compare b.jpg"),
            ("Near-duplicate check (pick your own threshold)", "macvision feature a.jpg --compare b.jpg | jq .distance"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--compare", type: String.self, desc: "Second image path; prints the distance between the two instead of a vector"),
            OptMeta(name: "--level", type: Int.self, desc: "Featureprint revision: 1 (default) or 2 (more precise, macOS 14+)"),
        ],
        args: [ArgMeta(name: "image", desc: "First image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let revision2 = (p.opt("--level") as Int? ?? 1) >= 2
            if let cmp = (p.opt("--compare") as String?) {
                let (engine2, src2) = try loadEngine(arg: cmp)
                printJson(try runFeatureCompare(engineA: engine, srcA: src, engineB: engine2, srcB: src2, revision2: revision2))
            } else {
                printJson(try runFeatureSingle(engine: engine, src: src, revision2: revision2))
            }
        }
    )
}
