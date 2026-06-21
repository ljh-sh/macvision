import Foundation
import Vision

/// Core document segmentation: find the document outline (a quadrilateral) so
/// the caller can crop / deskew it.
func runDocument(engine: VisionEngine, src: ImageSource) throws -> [String: Any] {
    let r = VNDetectDocumentSegmentationRequest()
    try engine.perform([r])
    let docs = (r.results ?? [])
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
    var result = baseResult(engine, src)
    result["count"] = docs.count
    result["documents"] = docs
    return result
}

enum DocumentCmd: Cmd {
    static let meta = CmdMeta(
        name: "document",
        desc: "Find the document outline (for crop / deskew)",
        synopsis: [
            "macvision document <image>",
        ],
        tldr: [
            ("Get the document quad to crop/deskew a scan", "macvision document scan.jpg"),
        ],
        opts: imageInputOpts,
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            printJson(try runDocument(engine: engine, src: src))
        }
    )
}
