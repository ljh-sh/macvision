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

    // Aggregate confidence so a caller (e.g. an agent deciding whether to retry
    // with a different language set) can judge without recomputing. count is the
    // stronger signal for "wrong language" (0 texts), confidence gauges quality.
    let avgConfidence: Double = limited.isEmpty
        ? 0
        : limited.map { Double($0.top.confidence) }.reduce(0, +) / Double(limited.count)

    var result = baseResult(engine, src)
    result["languages"] = langs
    result["count"] = limited.count
    result["confidence"] = avgConfidence
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
        desc: "Read text out of an image (OCR)",
        longDesc: "Uses VNRecognizeTextRequest, which is natively multi-language — pass a list and one request reads every script. With no --lang it auto-detects against a broad default set (all: zh / en / ja / ko / fr / de / es / pt / it / ru).",
        tips: [
            "Language presets: all (default), cjk, cn, latin, en. Mix freely: `--lang cjk,en-US`. Define your own set with $MACVISION_LANG_<NAME>=a,b,c then `--lang <name>`.",
            "Output is JSON; text is in `.texts[].text`. Bounding boxes are pixel `[x,y,w,h]` top-left (+ normalized `norm`).",
            "Narrow to a known script for speed/precision: `--lang en` (English only) is faster than the broad default.",
            "Vision prioritizes the FIRST CJK language. For pure Japanese or Korean, lead with it (`--lang ja-JP` / `ko-KR`) so kana/Hangul isn't starved by an earlier Chinese entry.",
        ],
        synopsis: [
            "macvision ocr <image>                       # auto: broad default languages",
            "macvision ocr <image> --lang cjk            # Chinese/Japanese/Korean preset",
            "macvision ocr <image> --lang zh-Hans,en-US  # specific languages",
            "macvision ocr -                             # base64 image on stdin",
            "macvision ocr --clipboard                   # OCR the image on the clipboard",
        ],
        tldr: [
            ("Read all text in an image (language auto-detected)", "macvision ocr screenshot.png"),
            ("Hand just the recognized text to another tool", "macvision ocr screenshot.png | jq -r '.texts[].text'"),
            ("OCR a Chinese/Japanese/Korean scan", "macvision ocr scan.png --lang cjk"),
            ("OCR the image currently on the clipboard", "macvision ocr --clipboard"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--lang", type: String.self, desc: "Recognition languages or presets, repeatable or comma-separated. Presets: all(default),cjk,cn,latin,en. Custom via $MACVISION_LANG_<NAME>", multiple: true),
            OptMeta(name: "--level", type: String.self, desc: "Recognition level: accurate|fast (default: accurate)"),
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop results below this confidence (default: 0)"),
            OptMeta(name: "--top", type: Int.self, desc: "Keep at most N results (default: all)"),
            OptMeta(name: "--no-language-correction", type: Bool.self, desc: "Disable Vision language correction"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let langs = resolveLangs(p)
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
