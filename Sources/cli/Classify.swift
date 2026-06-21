import Foundation
import Vision

/// Core classification: scene labels via `VNClassifyImageRequest`, or animal
/// species via `VNRecognizeAnimalsRequest` when `animals` is true.
func runClassify(
    engine: VisionEngine,
    src: ImageSource,
    top: Int,
    minConfidence: Double,
    animals: Bool
) throws -> [String: Any] {
    let labels: [(String, Float)]
    let mode: String
    if animals {
        let req = VNRecognizeAnimalsRequest()
        try engine.perform([req])
        mode = "animals"
        // VNRecognizeAnimalsRequest returns [VNRecognizedObjectObservation];
        // each carries `.labels` ([VNClassificationObservation]).
        labels = (req.results ?? [])
            .compactMap { $0.labels.first }
            .sorted { $0.confidence > $1.confidence }
            .filter { Double($0.confidence) >= minConfidence }
            .map { ($0.identifier, $0.confidence) }
    } else {
        let req = VNClassifyImageRequest()
        try engine.perform([req])
        mode = "scene"
        labels = (req.results ?? [])
            .sorted { $0.confidence > $1.confidence }
            .filter { Double($0.confidence) >= minConfidence }
            .map { ($0.identifier, $0.confidence) }
    }
    let limited = Array(labels.prefix(top))

    var result = baseResult(engine, src)
    result["mode"] = mode
    result["count"] = limited.count
    result["labels"] = limited.map { ["name": $0.0, "confidence": $0.1] }
    return result
}

enum ClassifyCmd: Cmd {
    static let meta = CmdMeta(
        name: "classify",
        desc: "Classify an image's scene/objects (or animal species with --animals)",
        synopsis: [
            "macvision classify <image> [--top N] [--min-confidence 0.2]",
            "macvision classify <image> --animals   # recognize animal species",
        ],
        tldr: [
            ("Top 5 scene/object labels", "macvision classify photo.jpg --top 5"),
            ("What animal is in this photo", "macvision classify pet.jpg --animals"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--top", type: Int.self, desc: "Keep top N labels (default: 10)"),
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop labels below this confidence (default: 0)"),
            OptMeta(name: "--animals", type: Bool.self, desc: "Recognize animal species instead of scene"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let top = p.opt("--top") as Int? ?? 10
            let minConf = p.opt("--min-confidence") as Double? ?? 0.0
            let animals = p.opt("--animals") as Bool? ?? false
            printJson(try runClassify(
                engine: engine, src: src, top: top, minConfidence: minConf, animals: animals
            ))
        }
    )
}
