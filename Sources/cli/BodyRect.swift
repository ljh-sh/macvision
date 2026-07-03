import Foundation
import Vision

/// Run VNDetectHumanRectanglesRequest — full-body human bounding boxes only.
func runHumans(engine: VisionEngine, src: ImageSource) throws -> [String: Any] {
    let req = VNDetectHumanRectanglesRequest()
    try engine.perform([req])

    let humans = (req.results ?? []).map { o -> [String: Any] in
        [
            "bbox": engine.pixelBox(o.boundingBox),
            "norm": VisionEngine.normBox(o.boundingBox),
            "confidence": o.confidence,
        ]
    }

    var result = baseResult(engine, src)
    result["count"] = humans.count
    result["humans"] = humans
    return result
}

enum HumansCmd: Cmd {
    static let meta = CmdMeta(
        name: "humans",
        desc: "Detect human bodies (rectangles, no landmarks/pose)",
        longDesc: "Uses VNDetectHumanRectanglesRequest. Lighter than `pose` — gives you bounding boxes around visible bodies without joint extraction. Use this when you only need 'how many people are here' or want to crop each person.",
        tips: [
            "Want joints too? Use `pose` instead. This command is just boxes.",
            "Combine with `macvision detect --faces` to get both people and faces in one pass (different APIs though).",
        ],
        synopsis: [
            "macvision humans <image>",
        ],
        tldr: [
            ("Agent: count people in a photo", "macvision humans crowd.jpg | jq .count"),
            ("Agent: get person bounding boxes to crop or pass downstream", "macvision humans meeting.jpg | jq '.humans[].bbox'"),
            ("Agent: lighter alternative to face-landmarks when you only need boxes", "macvision humans photo.jpg"),
        ],
        opts: imageInputOpts,
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            printJson(try runHumans(engine: engine, src: src))
        }
    )
}