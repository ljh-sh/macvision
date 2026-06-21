import Foundation
import Vision

/// Core OCR: run `VNRecognizeTextRequest` and build the result dict.
///
/// Shared by the `ocr` subcommand and the FIFO daemon.
func runOCR(
    engine: VisionEngine,
    src: ImageSource,
    langs: [String],
    level: VNRequestTextRecognitionLevel,
    minConfidence: Double,
    top: Int,
    usesLanguageCorrection: Bool
) throws -> [String: Any] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = level
    req.recognitionLanguages = langs
    req.usesLanguageCorrection = usesLanguageCorrection
    try engine.perform([req])

    // Flatten to (observation, top candidate, all candidates), dropping any
    // observation that produced no candidate.
    let obs = (req.results ?? []).compactMap { o -> (o: VNRecognizedTextObservation, top: VNRecognizedText, cands: [VNRecognizedText])? in
        let cands = o.topCandidates(10)
        guard let top = cands.first else { return nil }
        return (o, top, cands)
    }
    .filter { Double($0.top.confidence) >= minConfidence }
    .sorted { $0.top.confidence > $1.top.confidence }
    let limited = top > 0 ? Array(obs.prefix(top)) : obs

    var result = baseResult(engine, src)
    result["languages"] = langs
    result["count"] = limited.count
    result["texts"] = limited.map { item -> [String: Any] in
        var t: [String: Any] = [
            "text": item.top.string,
            "confidence": item.top.confidence,
            "bbox": engine.pixelBox(item.o.boundingBox),
            "norm": VisionEngine.normBox(item.o.boundingBox),
        ]
        if item.cands.count > 1 {
            t["candidates"] = item.cands.dropFirst().map { $0.string }
        }
        return t
    }
    return result
}

enum OcrCmd: Cmd {
    static let meta = CmdMeta(
        name: "ocr",
        desc: "Extract text (OCR) from an image",
        opts: imageInputOpts + [
            OptMeta(name: "--lang", type: [String].self, desc: "Recognition languages, comma-separated (default: en-US). zh-Hans / zh-Hant for Chinese"),
            OptMeta(name: "--level", type: String.self, desc: "Recognition level: accurate|fast (default: accurate)"),
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop results below this confidence (default: 0)"),
            OptMeta(name: "--top", type: Int.self, desc: "Keep at most N results (default: all)"),
            OptMeta(name: "--no-language-correction", type: Bool.self, desc: "Disable Vision language correction"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let langs = p.opt("--lang") as [String]? ?? ["en-US"]
            let level: VNRequestTextRecognitionLevel =
                (p.opt("--level") as String? ?? "accurate") == "fast" ? .fast : .accurate
            let minConf = p.opt("--min-confidence") as Double? ?? 0.0
            let top = p.opt("--top") as Int? ?? 0
            let correction = !(p.opt("--no-language-correction") as Bool? ?? false)
            printJson(try runOCR(
                engine: engine, src: src, langs: langs, level: level,
                minConfidence: minConf, top: top, usesLanguageCorrection: correction
            ))
        }
    )
}
