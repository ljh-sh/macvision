import Foundation
import Vision

/// Run VNDetectFaceLandmarksRequest — face rectangles + landmarks (eyes, nose, mouth).
func runFaceLandmarks(engine: VisionEngine, src: ImageSource, minConfidence: Double) throws -> [String: Any] {
    let req = VNDetectFaceLandmarksRequest()
    try engine.perform([req])

    let observations: [VNFaceObservation] = (req.results ?? [])
    let faces = observations.map { face -> [String: Any] in
        var d: [String: Any] = [
            "bbox": engine.pixelBox(face.boundingBox),
            "norm": VisionEngine.normBox(face.boundingBox),
        ]

        // 整体置信度
        d["confidence"] = face.confidence

        // 五个 landmark 组
        let regionKeys: [(VNFaceLandmarkRegion2D?, String)] = [
            (face.landmarks?.allPoints, "all"),
            (face.landmarks?.faceContour, "faceContour"),
            (face.landmarks?.leftEye, "leftEye"),
            (face.landmarks?.rightEye, "rightEye"),
            (face.landmarks?.leftEyebrow, "leftEyebrow"),
            (face.landmarks?.rightEyebrow, "rightEyebrow"),
            (face.landmarks?.nose, "nose"),
            (face.landmarks?.noseCrest, "noseCrest"),
            (face.landmarks?.medianLine, "medianLine"),
            (face.landmarks?.outerLips, "outerLips"),
            (face.landmarks?.innerLips, "innerLips"),
            (face.landmarks?.leftPupil, "leftPupil"),
            (face.landmarks?.rightPupil, "rightPupil"),
        ]
        var landmarks: [String: Any] = [:]
        for (region, key) in regionKeys {
            guard let region = region else { continue }
            let pts = region.normalizedPoints.map { p -> [String: Double] in
                ["x": Double(p.x), "y": Double(p.y)]
            }
            landmarks[key] = [
                "point_count": pts.count,
                "pixel_points": pts.map { p -> [String: Double] in
                    [
                        "x": p["x"]! * Double(engine.width),
                        "y": p["y"]! * Double(engine.height),
                    ]
                },
                "normalized_points": pts,
            ]
        }
        d["landmarks"] = landmarks
        d["landmark_regions"] = Array(landmarks.keys).sorted()
        return d
    }

    var result = baseResult(engine, src)
    result["count"] = faces.count
    result["faces"] = faces
    return result
}

enum FaceLandmarksCmd: Cmd {
    static let meta = CmdMeta(
        name: "face-landmarks",
        desc: "Detect faces and their landmarks (eyes, nose, mouth, etc.)",
        longDesc: "Uses VNDetectFaceLandmarksRequest. Returns each face's bounding box plus 13 landmark regions: allPoints, faceContour, leftEye, rightEye, leftEyebrow, rightEyebrow, nose, noseCrest, medianLine, outerLips, innerLips, leftPupil, rightPupil. Each region has both pixel and normalized point arrays.",
        tips: [
            "Landmarks come in two coordinate flavors: `pixel_points` (px, useful for drawing) and `normalized_points` (0-1, useful for analysis).",
            "Vision normalizes landmark points to 0-1 in the IMAGE coordinate space (origin bottom-left, Y up). We translate to top-left pixel coords too.",
            "Combine with `macvision detect --faces` (rectangles only) if you only need boxes — this command is heavier.",
        ],
        synopsis: [
            "macvision face-landmarks <image>",
            "macvision face-landmarks <image> --min-confidence 0.5",
        ],
        tldr: [
            ("Agent: detect faces + 13 landmark regions (eyes, nose, mouth)", "macvision face-landmarks group.jpg"),
            ("Agent: get eye positions for gaze / attention analysis", "macvision face-landmarks self.jpg | jq '.faces[].landmarks.leftEye'"),
            ("Agent: filter bad detections", "macvision face-landmarks crowd.jpg --min-confidence 0.5 | jq '.faces[].bbox'"),
            ("Agent: collect face contours for avatar / liveness work", "macvision face-landmarks portrait.jpg | jq '.faces[].landmarks.faceContour'"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop faces below this landmark confidence (default: 0)"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let minConf = p.opt("--min-confidence") as Double? ?? 0
            printJson(try runFaceLandmarks(engine: engine, src: src, minConfidence: minConf))
        }
    )
}