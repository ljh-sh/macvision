import Foundation
import Vision
import CoreGraphics
import ImageIO

/// Core annotation: run OCR on the image, find candidate regions containing
/// any of the given keywords, draw red highlight boxes on the original image,
/// and report matches as JSON.
///
/// Two modes (`--precision`):
/// - `line` (default): single `VNRecognizeTextRequest`. Draws the box around the
///   entire OCR line that contains the keyword. Always works reliably.
/// - `character`: TWO Vision requests — `VNDetectTextRectanglesRequest` (per-char
///   boxes) + `VNRecognizeTextRequest` (text). Y-coords cluster + bbox center match
///   lines; then we take the char boxes that correspond to the matched substring.
///   More precise, but on cluttered pages (many lines) the alignment can be off, in
///   which case we fall back to the line bbox automatically.
///
/// Match modes (`--whole-word`):
/// - default: substring (case-insensitive). "X-CMD" matches "X-CMD, x-cmd", etc.
/// - `--whole-word`: regex `\bkw\b`. CJK ignores this (no token boundary in Chinese).
func runAnnotate(engine: VisionEngine, src: ImageSource, output: URL?, keywords: [String], wholeWord: Bool, precision: String, langs: [String]) throws -> [String: Any] {
    // 1. 跑 OCR（识别文字）
    let req = VNRecognizeTextRequest()
    req.recognitionLanguages = langs
    req.usesLanguageCorrection = true
    try engine.perform([req])

    // 2. (可选) 跑 detect text rectangles 拿字符 bbox
    var charRects: [VNRectangleObservation] = []
    if precision == "character" {
        let rectReq = VNDetectTextRectanglesRequest()
        rectReq.reportCharacterBoxes = true
        try engine.perform([rectReq])
        let observations = rectReq.results ?? []
        for case let o as VNTextObservation in observations {
            if let cb = o.characterBoxes {
                charRects.append(contentsOf: cb)
            }
        }
    }

    // 3. 找匹配
    var matches: [[String: Any]] = []
    let loweredKeywords = keywords.map { $0.lowercased() }
    let observations: [VNRecognizedTextObservation] = (req.results ?? [])
    for o in observations {
        guard let top = o.topCandidates(1).first else { continue }
        let text = top.string
        let lowText = text.lowercased()
        let hits = matchAllHits(text: text, lowText: lowText, keywords: loweredKeywords, wholeWord: wholeWord)
        if hits.isEmpty { continue }

        let lineBBox = engine.pixelBox(o.boundingBox)

        for hit in hits {
            // 决定精度：尝试字符级；不合理（>2 倍行高）的就 fallback
            var usedBox = lineBBox
            var usedPrecision = "line"

            if precision == "character" && !charRects.isEmpty {
                let lineCharRects = associateLineChars(
                    lineBBox: o.boundingBox,
                    lineText: text,
                    charRects: charRects
                )
                if let charBox = extractKeywordCharBbox(
                    text: text,
                    matchedText: hit.matched,
                    lineCharRects: lineCharRects
                ) {
                    let pixBox = denormalizeToPixel(charBox, engine: engine)
                    // sanity check: bbox 高度不应 > line bbox 高度 + 容差
                    let lineH = lineBBox[3]
                    if pixBox[3] <= max(lineH * 2, 30) {
                        usedBox = pixBox
                        usedPrecision = "character"
                    }
                }
            }

            let normArr: [Double] = [
                Double(usedBox[0]) / Double(engine.width),
                Double(usedBox[1]) / Double(engine.height),
                Double(usedBox[2]) / Double(engine.width),
                Double(usedBox[3]) / Double(engine.height),
            ]
            matches.append([
                "text": text,
                "keyword": hit.keyword,
                "match_text": hit.matched,
                "bbox": usedBox,
                "norm": normArr,
                "confidence": top.confidence,
                "precision": usedPrecision,
            ])
        }
    }

    var result = baseResult(engine, src)
    result["keywords"] = keywords
    result["whole_word"] = wholeWord
    result["count"] = matches.count
    result["matches"] = matches

    // 3. 画红框
    if !matches.isEmpty {
        let outURL = output ?? defaultTempURL("annotated", "png")
        if let annotated = drawRedBoxes(on: engine.image, matches: matches) {
            try savePNG(annotated, to: outURL)
            result["output"] = outURL.path
            result["saved"] = true
        }
    }

    return result
}

/// 返回所有命中的 (keyword, matchedText) 列表
private struct TextHit {
    let keyword: String
    let matched: String
}

private func matchAllHits(text: String, lowText: String, keywords: [String], wholeWord: Bool) -> [TextHit] {
    var hits: [TextHit] = []
    for kw in keywords where !kw.isEmpty {
        if wholeWord {
            if isCJKOnly(kw) {
                // 中文 substring
                var searchRange = lowText.startIndex..<lowText.endIndex
                while let r = lowText.range(of: kw, range: searchRange, locale: nil) {
                    let matched = String(text[r])
                    hits.append(TextHit(keyword: kw, matched: matched))
                    searchRange = r.upperBound..<lowText.endIndex
                }
            } else {
                // 英文 regex
                let pattern = "\\b\(escapeRegex(kw))\\b"
                if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(lowText.startIndex..., in: lowText)
                    re.enumerateMatches(in: lowText, options: [], range: range) { match, _, _ in
                        guard let m = match else { return }
                        if let swiftRange = Range(m.range, in: text) {
                            let matched = String(text[swiftRange])
                            hits.append(TextHit(keyword: kw, matched: matched))
                        }
                    }
                }
            }
        } else {
            // 默认 substring 全部命中位置
            var searchRange = lowText.startIndex..<lowText.endIndex
            while let r = lowText.range(of: kw, range: searchRange, locale: nil) {
                let matched = String(text[r])
                hits.append(TextHit(keyword: kw, matched: matched))
                searchRange = r.upperBound..<lowText.endIndex
            }
        }
    }
    return hits
}

/// (Legacy) 用 characterBoxes 计算关键词字符级 bbox
/// (Replaced by char-level mode using VNDetectTextRectanglesRequest.)
private func characterBBox(
    observation: VNRecognizedTextObservation,
    originalText: String,
    keyword: String,
    matchedText: String,
    engineWidth: Double,
    engineHeight: Double
) -> [Int]? {
    _ = originalText; _ = keyword; _ = matchedText; _ = engineWidth; _ = engineHeight
    return nil
}

/// 对一组 char boxes，找出属于该 line 的那些（按 y 中心距离 line bbox 中心 < 行高 1.5 倍，
/// 且 x 在行 bbox 范围内）。返回的 boxes 按 x 升序（与字符串顺序一致）。
private func associateLineChars(
    lineBBox: CGRect,
    lineText: String,
    charRects: [VNRectangleObservation]
) -> [VNRectangleObservation] {
    guard !charRects.isEmpty else { return [] }
    let lineCenterY = lineBBox.midY
    let maxDist = max(lineBBox.height, 0.02) * 1.5
    let lineMinX = lineBBox.minX
    let lineMaxX = lineBBox.maxX

    var matched: [VNRectangleObservation] = []
    for r in charRects {
        let b = r.boundingBox
        // y 中心接近
        if abs(b.midY - lineCenterY) > maxDist { continue }
        // x 与行 bbox 有重叠或很接近
        if b.maxX < lineMinX - 0.01 || b.minX > lineMaxX + 0.01 { continue }
        matched.append(r)
    }
    matched.sort { $0.boundingBox.minX < $1.boundingBox.minX }
    return matched
}

/// 在 matched text 对应的字符索引范围内取 char boxes，合并为 union CGRect
private func extractKeywordCharBbox(
    text: String,
    matchedText: String,
    lineCharRects: [VNRectangleObservation]
) -> CGRect? {
    // 1. 在 text 中找 matchedText 的所有位置
    var ranges: [Range<String.Index>] = []
    var searchRange = text.startIndex..<text.endIndex
    while let r = text.range(of: matchedText, range: searchRange, locale: nil) {
        ranges.append(r)
        searchRange = r.upperBound..<text.endIndex
    }
    guard !ranges.isEmpty else { return nil }

    // 2. 把 matched ranges 映射到 char 索引
    // 方法：估算每个字符的 index 范围（按 grapheme cluster）
    // 然后匹配哪个 char rect 落在这个 index 范围
    var charIndexes: [Range<Int>] = []
    var idx = 0
    for ch in text {
        let len = Array(String(ch)).count  // grapheme cluster length
        charIndexes.append(idx..<(idx + len))
        idx += len
    }

    // 3. 对每个 matched range，找出其字符对应的 char rect 索引
    var unionRect: CGRect?
    for range in ranges {
        let startIdx = text.distance(from: text.startIndex, to: range.lowerBound)
        let endIdx = text.distance(from: text.startIndex, to: range.upperBound)
        // 注意：distance 是 UTF-16 units 还是 graphemes？我们用 array of chars
        // 此处做一个近似：distance 在 Swift 是 Character 计数（即 grapheme cluster）
        for (i, cr) in lineCharRects.enumerated() {
            // 这个 char rect 大约对应 text 的第 i 个字符
            // （前提: detect_rectangles 给的字符顺序 = 字符串顺序）
            if i >= charIndexes.count { break }
            let ci = charIndexes[i]
            // 重叠检查：(ci ∩ [startIdx, endIdx)) ≠ ∅
            if ci.lowerBound < endIdx && ci.upperBound > startIdx {
                let rect = cr.boundingBox
                if let u = unionRect {
                    unionRect = u.union(rect)
                } else {
                    unionRect = rect
                }
            }
        }
    }
    return unionRect
}

/// normalized CGRect → pixel [x,y,w,h] (top-left origin)
private func denormalizeToPixel(_ rect: CGRect, engine: VisionEngine) -> [Int] {
    let w = Double(engine.width)
    let h = Double(engine.height)
    let px = Int(round(rect.minX * w))
    let py = Int(round((1 - rect.minY - rect.height) * h))
    let pw = Int(round(rect.width * w))
    let ph = Int(round(rect.height * h))
    return [px, py, max(1, pw), max(1, ph)]
}

private func isCJKOnly(_ s: String) -> Bool {
    let cjk: ClosedRange<UInt32> = 0x4E00...0x9FFF
    let hira: ClosedRange<UInt32> = 0x3040...0x309F
    let kata: ClosedRange<UInt32> = 0x30A0...0x30FF
    let hang: ClosedRange<UInt32> = 0xAC00...0xD7AF
    if s.isEmpty { return false }
    for u in s.unicodeScalars {
        let v = u.value
        if cjk.contains(v) || hira.contains(v) || kata.contains(v) || hang.contains(v) {
            continue
        }
        return false
    }
    return true
}

private func escapeRegex(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: ".",  with: "\\.")
     .replacingOccurrences(of: "+",  with: "\\+")
     .replacingOccurrences(of: "*",  with: "\\*")
     .replacingOccurrences(of: "?",  with: "\\?")
     .replacingOccurrences(of: "(",  with: "\\(")
     .replacingOccurrences(of: ")",  with: "\\)")
     .replacingOccurrences(of: "[",  with: "\\[")
     .replacingOccurrences(of: "]",  with: "\\]")
     .replacingOccurrences(of: "{",  with: "\\{")
     .replacingOccurrences(of: "}",  with: "\\}")
     .replacingOccurrences(of: "^",  with: "\\^")
     .replacingOccurrences(of: "$",  with: "\\$")
}

/// 在原图上画红色矩形框（半透明填充 + 4px 边框），返回新的 CGImage
///
/// 坐标：JSON 中 bbox 是 top-left origin (PNG convention)。
/// CGContext 在 macOS 上是 bottom-left origin — 我们需要在画之前翻转 y。
private func drawRedBoxes(on image: CGImage, matches: [[String: Any]]) -> CGImage? {
    let w = image.width
    let h = image.height
    let bytesPerRow = w * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                              space: colorSpace, bitmapInfo: info) else { return nil }
    // 翻转 y 轴，使 CGContext 用 top-left origin 接收
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)

    // 画原图（翻转坐标系下，原图也已上下翻转）
    // 但我们想保留原图：先画原图（未翻转），再恢复。
    // 简单办法：用 save/restoreState
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.restoreGState()

    // 画红色 rect（top-left origin）
    for m in matches {
        guard let bbox = m["bbox"] as? [Int], bbox.count >= 4 else { continue }
        let x = CGFloat(bbox[0])
        let y = CGFloat(bbox[1])
        let bw = CGFloat(bbox[2])
        let bh = CGFloat(bbox[3])
        let rect = CGRect(x: x, y: y, width: bw, height: bh)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.25))
        ctx.fill(rect)
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(4)
        ctx.stroke(rect)
    }
    return ctx.makeImage()
}

enum AnnotateCmd: Cmd {
    static let meta = CmdMeta(
        name: "annotate",
        desc: "Highlight OCR text containing keywords with red boxes (smart-annotate)",
        longDesc: "Run OCR on the image, find lines containing any of the given keywords, and draw red rectangles on the original. Outputs the annotated image + a JSON list of matches (text, keyword, bbox). Default match is substring (case-insensitive); pass --whole-word for token-boundary match.",
        tips: [
            "Default match is case-insensitive substring: \"X-CMD\" matches both \"X-CMD\" and \"x-cmd\".",
            "Pass `--whole-word` to require token boundaries (good for English, where \"Apple\" shouldn't match \"Pineapple\").",
            "Chinese keywords always use substring match (Chinese has no whitespace token boundaries).",
            "Apple Vision does NOT expose per-character bounding boxes in public Swift API — the red box covers the entire OCR line that contains the keyword (not just the matched characters).",
            "Use `--lang` to OCR in another script: `--lang en`, `--lang zh-Hans`, etc.",
        ],
        synopsis: [
            "macvision annotate <image> <keyword[,keyword,...]> --output out.png",
            "macvision annotate <image> X-CMD --output out.png          # one keyword",
            "macvision annotate <image> X-CMD,Claude --whole-word      # token match",
        ],
        tldr: [
            ("Agent: highlight all occurrences of a brand mention with red boxes", "macvision annotate screenshot.png X-CMD --output out.png"),
            ("Agent: mark all TODO/urgent keywords for review", "macvision annotate doc.png TODO,urgent --output marked.png"),
            ("Agent: find every \"Apple\" word (avoid \"Pineapple\")", "macvision annotate doc.png Apple --whole-word --output out.png"),
            ("Agent: count matches in a document", "macvision annotate doc.png X-CMD | jq '.matches | length'"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--output", type: String.self, desc: "Write annotated PNG here (default: a temp file)"),
            OptMeta(name: "--whole-word", type: Bool.self, desc: "Match token boundary (English keyword only — avoid e.g. 'Apple' matching 'Pineapple')"),
            OptMeta(name: "--precision", type: String.self, desc: "Box precision: 'line' (default, one line bbox per match) or 'character' (precise char bbox via second Vision request)"),
        ] + langShortcutOpts + [
            OptMeta(name: "--lang", type: String.self, desc: "OCR languages/presets (presets: all,cjk,cn,latin,en). Repeatable or comma-separated", multiple: true),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen"),
               ArgMeta(name: "keywords", desc: "Comma-separated keywords to highlight (e.g. X-CMD,Claude)"),
        ],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let output = (p.opt("--output") as String?).map { URL(fileURLWithPath: $0) }
            let wholeWord = p.opt("--whole-word") as Bool? ?? false
            let precision = p.opt("--precision") as String? ?? "line"
            let positional = p.arg(1) ?? ""
            let rawKeywords: String = positional
            let flagKeywords = (p.opt("--keywords") as [String]?) ?? []
            let allRaw: String = flagKeywords.isEmpty ? rawKeywords : flagKeywords.joined(separator: ",")
            let keywords = allRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let langs = resolveLangs(p)
            printJson(try runAnnotate(engine: engine, src: src, output: output, keywords: keywords, wholeWord: wholeWord, precision: precision, langs: langs))
        }
    )
}