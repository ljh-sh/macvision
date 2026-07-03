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
            "Language shortcuts: `--en`, `--zh`, `--ja`, `--ko` each add a script to --lang at the position they appear — `--ja --en` is the same as `--lang ja-JP,en-US`. Lead with the script you want recognized (ja/ko before zh, so kana/Hangul isn't starved).",
            "Language presets: all (default), cjk, cn, latin, en. Mix freely: `--lang cjk,en-US`. Define your own set with $MACVISION_LANG_<NAME>=a,b,c then `--lang <name>`.",
            "Output is JSON; text is in `.texts[].text`. Bounding boxes are pixel `[x,y,w,h]` top-left (+ normalized `norm`).",
            "Narrow to a known script for speed/precision: `--lang en` (English only) is faster than the broad default.",
            "Vision prioritizes the FIRST CJK language. For pure Japanese or Korean, lead with it (`--lang ja-JP` / `ko-KR`) so kana/Hangul isn't starved by an earlier Chinese entry.",
        ],
        synopsis: [
            "macvision ocr <image>                       # auto: broad default languages",
            "macvision ocr <image> --lang cjk            # Chinese/Japanese/Korean preset",
            "macvision ocr <image> --lang zh-Hans,en-US  # specific languages",
            "macvision ocr <image> --ja --en             # shorthand: Japanese first, then English",
            "macvision ocr -                             # base64 image on stdin",
            "macvision ocr --clipboard                   # OCR the image on the clipboard",
        ],
        tldr: [
            ("Agent: read text from a screenshot directly to LLM (JSON positions)", "macvision ocr screenshot.png"),
            ("Agent: read text from clipboard (paste a screenshot)", "macvision ocr --clipboard"),
            ("Agent: read text as TSV (text, confidence, bbox, norm, center) for parsing", "macvision ocr screenshot.png"),
            ("Agent: read a multi-language screenshot, JSON", "macvision ocr scan.png --lang cjk"),
            ("Agent: just the words, one per line (--text)", "macvision ocr shot.png --text"),
            ("Agent: text grouped by visual lines (--lines)", "macvision ocr shot.png --lines"),
            ("Agent: choose the right script (Japanese first to avoid losing kana)", "macvision ocr shot.png --ja --en"),
            ("Agent: filter out OCR guesses below 0.5 confidence", "macvision ocr noisy.png --min-confidence 0.5 | jq '.texts'"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--lang", type: String.self, desc: "Recognition languages or presets, repeatable or comma-separated. Presets: all(default),cjk,cn,latin,en. Custom via $MACVISION_LANG_<NAME>", multiple: true),
        ] + langShortcutOpts + [
            OptMeta(name: "--level", type: String.self, desc: "Recognition level: accurate|fast (default: accurate)"),
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop results below this confidence (default: 0)"),
            OptMeta(name: "--top", type: Int.self, desc: "Keep at most N results (default: all)"),
            OptMeta(name: "--no-language-correction", type: Bool.self, desc: "Disable Vision language correction"),
            OptMeta(name: "--text", type: Bool.self, desc: "Output plain text (one per line)"),
            OptMeta(name: "--lines", type: Bool.self, desc: "Output text grouped by lines"),
            OptMeta(name: "--tsv", type: Bool.self, desc: "Output TSV format (x\\ty\\ttext)"),
            OptMeta(name: "--json", type: Bool.self, desc: "Output JSON format (default)"),
            OptMeta(name: "--tolerance", type: Int.self, desc: "Y-axis tolerance for line grouping (default: 10)"),
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
            let useText = p.opt("--text") as Bool? ?? false
            let useLines = p.opt("--lines") as Bool? ?? false
            let useJson = p.opt("--json") as Bool? ?? false
            // 默认 TSV，没有指定任何模式时用 TSV
            let useTsv = p.opt("--tsv") as Bool? ?? !(useText || useLines || useJson)
            let tolerance = p.opt("--tolerance") as Int? ?? 10
            let result = try runOCR(
                engine: engine, src: src, langs: langs, level: level,
                minConfidence: minConf, top: top, usesLanguageCorrection: correction
            )

            if useText || useLines || useTsv {
                // 按位置排序文本：先按 y 排序，再按 x 排序（左到右，上到下）
                let texts = result["texts"] as? [[String: Any]] ?? []
                let sorted = texts.sorted { a, b in
                    let aBox = a["bbox"] as? [Int] ?? [0,0,0,0]
                    let bBox = b["bbox"] as? [Int] ?? [0,0,0,0]
                    // 先按 y 排序（从上到下），再按 x 排序（从左到右）
                    if aBox[1] != bBox[1] { return aBox[1] < bBox[1] }
                    return aBox[0] < bBox[0]
                }

                if useTsv {
                    // TSV 格式：text\tconfidence\tbox\tnorm\tcenter\tcenter_norm（默认）
                    print("text\tconfidence\tbox\tnorm\tcenter\tcenter_norm")
                    for t in sorted {
                        let box = t["bbox"] as? [Int] ?? [0,0,0,0]
                        let boxStr = box.map { String($0) }.joined(separator: ",")
                        // 中心点坐标 (像素)
                        let cx = box.count >= 4 ? box[0] + box[2] / 2 : 0
                        let cy = box.count >= 4 ? box[1] + box[3] / 2 : 0
                        let centerStr = "\(cx),\(cy)"

                        // norm + 归一化中心点
                        let norm = t["norm"] as? [Double] ?? []
                        let normStr = norm.map { String(format: "%.4f", $0) }.joined(separator: ",")
                        let ncx: Double = norm.count >= 4 ? norm[0] + norm[2] / 2 : 0
                        let ncy: Double = norm.count >= 4 ? norm[1] + norm[3] / 2 : 0
                        let centerNormStr = String(format: "%.4f,%.4f", ncx, ncy)

                        let conf = t["confidence"] as? Double ?? (t["confidence"] as? Float).map { Double($0) } ?? 0.0
                        let text = t["text"] as? String ?? ""
                        print("\(text)\t\(conf)\t\(boxStr)\t\(normStr)\t\(centerStr)\t\(centerNormStr)")
                    }
                } else if useText {
                    // 纯文本模式：每行一个文本
                    for t in sorted {
                        print(t["text"] as? String ?? "")
                    }
                } else if useLines {
                    // lines 模式：按精确的 y 坐标分组（更严格）
                    var lines: [[String]] = []
                    var lastY: Int? = nil

                    for t in sorted {
                        guard let box = t["bbox"] as? [Int], box.count >= 2 else { continue }
                        let y = box[1]
                        if let prevY = lastY, y == prevY {
                            // 同一行（精确匹配 y）
                            lines[lines.count - 1].append(t["text"] as? String ?? "")
                        } else {
                            // 新行
                            lines.append([t["text"] as? String ?? ""])
                            lastY = y
                        }
                    }

                    // 输出每行
                    for line in lines {
                        print(line.joined(separator: " "))
                    }
                }
            } else {
                // JSON 模式
                printJson(result)
            }
        }
    )
}
