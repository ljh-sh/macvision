import Foundation
import Vision

/// Parse one NDJSON request line and return one NDJSON response line.
func daemonHandleRequest(_ line: String) -> String {
    guard let data = line.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let action = (dict["action"] as? String) ?? (dict["cmd"] as? String)
    else {
        return daemonEncode(["ok": false, "error": "request must be a JSON object with an 'action' field"])
    }
    do {
        let result = try daemonDispatch(action: action, request: dict)
        return daemonEncode(result)
    } catch {
        return daemonEncode(["ok": false, "error": error.localizedDescription])
    }
}

/// Route a daemon request to the shared core functions used by the CLI.
func daemonDispatch(action: String, request: [String: Any]) throws -> [String: Any] {
    switch action {
    case "doctor":
        return runDoctor()

    case "ocr":
        let (engine, src) = try loadEngine(arg: request["image"] as? String)
        let langs = (request["lang"] as? [String])
            ?? (request["languages"] as? [String])
            ?? ["en-US"]
        let level: VNRequestTextRecognitionLevel = (request["level"] as? String) == "fast" ? .fast : .accurate
        return try runOCR(
            engine: engine, src: src, langs: langs, level: level,
            minConfidence: reqDouble(request, "min_confidence", 0.0),
            top: reqInt(request, "top", 0),
            usesLanguageCorrection: reqBool(request, "use_correction", true)
        )

    case "classify":
        let (engine, src) = try loadEngine(arg: request["image"] as? String)
        return try runClassify(
            engine: engine, src: src,
            top: reqInt(request, "top", 10),
            minConfidence: reqDouble(request, "min_confidence", 0.0),
            animals: reqBool(request, "animals", false)
        )

    case "detect":
        let (engine, src) = try loadEngine(arg: request["image"] as? String)
        var opts = DetectOptions()
        opts.faces = reqBool(request, "faces", false)
        opts.rects = reqBool(request, "rects", false)
        opts.barcodes = reqBool(request, "barcodes", false)
        opts.textRegions = reqBool(request, "text_regions", false)
        opts.horizon = reqBool(request, "horizon", false)
        opts.ocr = reqBool(request, "ocr", false)
        opts.ocrLang = (request["lang"] as? [String]) ?? ["en-US"]
        opts.symbologies = parseSymbologies(request["symbologies"] as? [String])
        opts.minSize = reqDouble(request, "min_size", 0.2)
        opts.minConfidence = reqDouble(request, "min_confidence", 0.0)
        opts.applyDefaults()
        return try runDetect(engine: engine, src: src, opts: opts)

    case "feature":
        let (engine, src) = try loadEngine(arg: request["image"] as? String)
        let revision2 = reqInt(request, "level", 1) >= 2
        if let cmp = request["compare"] as? String {
            let (engine2, src2) = try loadEngine(arg: cmp)
            return try runFeatureCompare(engineA: engine, srcA: src, engineB: engine2, srcB: src2, revision2: revision2)
        }
        return try runFeatureSingle(engine: engine, src: src, revision2: revision2)

    case "salient":
        let (engine, src) = try loadEngine(arg: request["image"] as? String)
        let mode = reqString(request, "mode", "attention")
        let out = (request["output"] as? String).map { URL(fileURLWithPath: $0) }
        return try runSalient(engine: engine, src: src, mode: mode, output: out)

    case "document":
        let (engine, src) = try loadEngine(arg: request["image"] as? String)
        return try runDocument(engine: engine, src: src)

    default:
        throw VisionError.requestFailed("unknown action: \(action)")
    }
}

func daemonEncode(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
          let s = String(data: data, encoding: .utf8)
    else {
        return "{\"ok\":false,\"error\":\"encode failed\"}"
    }
    return s
}

// MARK: - Typed request-field readers (JSON numbers arrive as NSNumber)

func reqDouble(_ d: [String: Any], _ k: String, _ fallback: Double) -> Double {
    if let v = d[k] as? Double { return v }
    if let v = d[k] as? Int { return Double(v) }
    return fallback
}

func reqInt(_ d: [String: Any], _ k: String, _ fallback: Int) -> Int {
    if let v = d[k] as? Int { return v }
    if let v = d[k] as? Double { return Int(v) }
    return fallback
}

func reqBool(_ d: [String: Any], _ k: String, _ fallback: Bool) -> Bool {
    (d[k] as? Bool) ?? fallback
}

func reqString(_ d: [String: Any], _ k: String, _ fallback: String) -> String {
    (d[k] as? String) ?? fallback
}

enum DaemonCmd: Cmd {
    static let meta = CmdMeta(
        name: "daemon",
        desc: "Run a long-lived FIFO daemon (NDJSON over named pipes) for IPC",
        longDesc: "Reads NDJSON requests from the request FIFO and writes one NDJSON response per request to the response FIFO. Each request is a JSON object with an `action` (ocr, classify, detect, feature, salient, document, doctor) plus that action's fields — output matches the matching CLI command.",
        synopsis: [
            "macvision daemon [--req <path> --res <path>]",
        ],
        tldr: [
            ("Start the daemon on the default FIFOs", "macvision daemon &"),
            ("Send an OCR request over the FIFO", "echo '{\"action\":\"ocr\",\"image\":\"/tmp/s.png\",\"lang\":[\"zh-Hans\",\"en-US\"]}' > /tmp/macvision.req"),
            ("Read the response line", "cat /tmp/macvision.res"),
        ],
        opts: [
            OptMeta(name: "--req", type: String.self, desc: "Request FIFO path (default: /tmp/macvision.req)"),
            OptMeta(name: "--res", type: String.self, desc: "Response FIFO path (default: /tmp/macvision.res)"),
        ],
        run: { p in
            let req = p.opt("--req") as String? ?? "/tmp/macvision.req"
            let res = p.opt("--res") as String? ?? "/tmp/macvision.res"
            try await DaemonCtrl.run(.init(reqPath: req, resPath: res))
        }
    )
}
