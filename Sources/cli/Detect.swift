import Foundation
import Vision

/// Which detections to run, plus tuning knobs.
struct DetectOptions {
    var faces: Bool = false
    var rects: Bool = false
    var barcodes: Bool = false
    var textRegions: Bool = false
    var horizon: Bool = false
    var ocr: Bool = false
    var ocrLang: [String] = ["en-US"]
    var symbologies: [VNBarcodeSymbology]? = nil
    var minSize: Double = 0.2
    var minConfidence: Double = 0

    /// A "narrow" detector flag selects ONLY that detector. `--ocr` is NOT narrow —
    /// it adds text recognition on top of whatever else runs.
    var anyNarrow: Bool { faces || rects || barcodes || textRegions || horizon }

    mutating func applyDefaults() {
        // No narrow flag → run the broad, cheap set. OCR adds on top if requested.
        if !anyNarrow {
            faces = true; barcodes = true; textRegions = true; horizon = true
        }
    }
}

func parseSymbologies(_ list: [String]?) -> [VNBarcodeSymbology]? {
    guard let list, !list.isEmpty else { return nil }
    return list.compactMap { name in
        switch name.lowercased() {
        case "qr": return .qr
        case "ean13", "ean-13": return .ean13
        case "ean8", "ean-8": return .ean8
        case "upce", "upc-e": return .upce
        case "upca", "upc-a": return .upce
        case "code128", "code-128": return .code128
        case "code39", "code-39": return .code39
        case "code93", "code-93": return .code93
        case "dataMatrix", "datamatrix": return .dataMatrix
        case "pdf417", "pdf-417": return .pdf417
        case "aztec": return .aztec
        case "itf14", "itf-14": return .itf14
        default: return nil
        }
    }
}

/// Core detection: run the requested Vision detectors in a single pass.
func runDetect(engine: VisionEngine, src: ImageSource, opts: DetectOptions) throws -> [String: Any] {
    var requests: [VNRequest] = []
    var faceReq: VNDetectFaceRectanglesRequest?
    var rectReq: VNDetectRectanglesRequest?
    var barcodeReq: VNDetectBarcodesRequest?
    var textReq: VNDetectTextRectanglesRequest?
    var horizonReq: VNDetectHorizonRequest?
    var ocrReq: VNRecognizeTextRequest?

    if opts.faces {
        let r = VNDetectFaceRectanglesRequest(); faceReq = r; requests.append(r)
    }
    if opts.rects {
        let r = VNDetectRectanglesRequest()
        r.minimumSize = Float(opts.minSize)
        r.minimumConfidence = Float(opts.minConfidence)
        rectReq = r; requests.append(r)
    }
    if opts.barcodes {
        let r = VNDetectBarcodesRequest()
        if let sym = opts.symbologies { r.symbologies = sym }
        barcodeReq = r; requests.append(r)
    }
    if opts.textRegions {
        let r = VNDetectTextRectanglesRequest(); textReq = r; requests.append(r)
    }
    if opts.horizon {
        let r = VNDetectHorizonRequest(); horizonReq = r; requests.append(r)
    }
    if opts.ocr {
        let r = VNRecognizeTextRequest()
        r.recognitionLanguages = opts.ocrLang
        r.usesLanguageCorrection = true
        ocrReq = r; requests.append(r)
    }

    try engine.perform(requests)

    var detections: [String: Any] = [:]
    var total = 0

    if let req = faceReq {
        let faces = (req.results ?? []).map { o -> [String: Any] in
            [
                "bbox": engine.pixelBox(o.boundingBox),
                "norm": VisionEngine.normBox(o.boundingBox),
            ]
        }
        detections["faces"] = faces
        detections["face_count"] = faces.count
        total += faces.count
    }
    if let req = rectReq {
        let rects = (req.results ?? [])
            .filter { Double($0.confidence) >= opts.minConfidence }
            .sorted { $0.confidence > $1.confidence }
            .map { o -> [String: Any] in
                [
                    "bbox": engine.pixelBox(o.boundingBox),
                    "norm": VisionEngine.normBox(o.boundingBox),
                    "corners": [
                        engine.pixelPoint(o.topLeft),
                        engine.pixelPoint(o.topRight),
                        engine.pixelPoint(o.bottomRight),
                        engine.pixelPoint(o.bottomLeft),
                    ],
                    "confidence": o.confidence,
                ]
            }
        detections["rectangles"] = rects
        detections["rectangle_count"] = rects.count
        total += rects.count
    }
    if let req = barcodeReq {
        let codes = (req.results ?? []).compactMap { o -> [String: Any]? in
            guard let payload = o.payloadStringValue else { return nil }
            return [
                "payload": payload,
                "symbology": symbologyName(o.symbology),
                "bbox": engine.pixelBox(o.boundingBox),
                "norm": VisionEngine.normBox(o.boundingBox),
            ] as [String: Any]
        }
        detections["barcodes"] = codes
        detections["barcode_count"] = codes.count
        total += codes.count
    }
    if let req = textReq {
        let regions = (req.results ?? []).map { o -> [String: Any] in
            var d: [String: Any] = [
                "bbox": engine.pixelBox(o.boundingBox),
                "norm": VisionEngine.normBox(o.boundingBox),
            ]
            if let chars = o.characterBoxes, !chars.isEmpty {
                d["character_count"] = chars.count
            }
            return d
        }
        detections["text_regions"] = regions
        detections["text_region_count"] = regions.count
        total += regions.count
    }
    if let req = horizonReq, let h = req.results?.first {
        detections["horizon"] = ["angle": h.angle]
    }
    if let req = ocrReq {
        let texts = (req.results ?? []).compactMap { o -> [String: Any]? in
            guard let top = o.topCandidates(1).first else { return nil }
            return [
                "text": top.string,
                "confidence": top.confidence,
                "bbox": engine.pixelBox(o.boundingBox),
                "norm": VisionEngine.normBox(o.boundingBox),
            ]
        }
        detections["texts"] = texts
        detections["text_count"] = texts.count
        total += texts.count
    }

    var result = baseResult(engine, src)
    result["count"] = total
    result["detections"] = detections
    return result
}

private func symbologyName(_ s: VNBarcodeSymbology) -> String {
    String(describing: s)
}

enum DetectCmd: Cmd {
    static let meta = CmdMeta(
        name: "detect",
        desc: "Detect faces, barcodes, text, and more in an image",
        longDesc: "Runs one or more Vision detectors in a single pass. With no detector flag it runs the broad, cheap set: faces, barcodes, text regions, and horizon. Pass a flag to run ONLY that detector (a focused, faster subset). Rectangles and OCR are opt-in.",
        tips: [
            "Why flags? `detect img.png` already runs faces+barcodes+text-regions+horizon. A flag like `--faces` NARROWS to just faces (faster, less noise) — it does not add on top.",
            "text-regions gives the BOUNDING BOXES of text only. To READ the actual words, add `--ocr` (or use the dedicated `ocr` command).",
        ],
        synopsis: [
            "macvision detect <image>                         # broad: faces, barcodes, text regions, horizon",
            "macvision detect <image> --ocr --lang zh-Hans,en-US   # broad + read the text",
            "macvision detect <image> --faces                 # only faces",
            "macvision detect <image> --barcodes --symbologies qr   # only QR codes",
            "macvision detect <image> --rects                 # document/card rectangles (opt-in)",
        ],
        tldr: [
            ("Everything in a screenshot (including the text)", "macvision detect shot.png --ocr --lang zh-Hans,en-US"),
            ("Only the QR/barcodes", "macvision detect qr.png --barcodes"),
            ("Only faces", "macvision detect group.jpg --faces"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--faces", type: Bool.self, desc: "Detect faces"),
            OptMeta(name: "--rects", type: Bool.self, desc: "Detect document/card rectangles (opt-in; tuned for cards)"),
            OptMeta(name: "--barcodes", type: Bool.self, desc: "Detect barcodes / QR codes"),
            OptMeta(name: "--text-regions", type: Bool.self, desc: "Detect text region bounding boxes (no content)"),
            OptMeta(name: "--ocr", type: Bool.self, desc: "Recognize the actual text (add to read words, not just boxes)"),
            OptMeta(name: "--lang", type: [String].self, desc: "OCR recognition languages with --ocr (default: en-US). zh-Hans / zh-Hant for Chinese"),
            OptMeta(name: "--horizon", type: Bool.self, desc: "Detect horizon angle"),
            OptMeta(name: "--symbologies", type: [String].self, desc: "Barcode symbologies, comma-separated (e.g. qr,ean13). Default: Vision's built-in set"),
            OptMeta(name: "--min-size", type: Double.self, desc: "Minimum rectangle size for --rects (0-1, default: 0.2)"),
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop detections below this confidence (default: 0)"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            var opts = DetectOptions()
            opts.faces = p.opt("--faces") as Bool? ?? false
            opts.rects = p.opt("--rects") as Bool? ?? false
            opts.barcodes = p.opt("--barcodes") as Bool? ?? false
            opts.textRegions = p.opt("--text-regions") as Bool? ?? false
            opts.horizon = p.opt("--horizon") as Bool? ?? false
            opts.ocr = p.opt("--ocr") as Bool? ?? false
            opts.ocrLang = p.opt("--lang") as [String]? ?? ["en-US"]
            opts.symbologies = parseSymbologies(p.opt("--symbologies") as [String]?)
            opts.minSize = p.opt("--min-size") as Double? ?? 0.2
            opts.minConfidence = p.opt("--min-confidence") as Double? ?? 0
            opts.applyDefaults()
            printJson(try runDetect(engine: engine, src: src, opts: opts))
        }
    )
}
