import Foundation
import Vision

/// Run VNDetectHumanBodyPoseRequest — body bounding boxes + 18 keypoint joints per body.
func runPose(engine: VisionEngine, src: ImageSource, minConfidence: Double) throws -> [String: Any] {
    let req = VNDetectHumanBodyPoseRequest()
    try engine.perform([req])

    let observations: [VNHumanBodyPoseObservation] = (req.results ?? [])
    let bodies = observations.map { body -> [String: Any] in
        var d: [String: Any] = [
            "confidence": body.confidence,
        ]

        // 18 个关键点
        if let allPoints = try? body.recognizedPoints(.all) {
            var joints: [String: Any] = [:]
            var minX: Double = 1, maxX: Double = 0, minY: Double = 1, maxY: Double = 0

            for (name, point) in allPoints {
                guard Float(point.confidence) > Float(minConfidence) else { continue }
                joints[name.rawValue.rawValue] = [
                    "x": Double(point.location.x),
                    "y": Double(point.location.y),
                    "pixel_x": Double(point.location.x) * Double(engine.width),
                    "pixel_y": (1.0 - Double(point.location.y)) * Double(engine.height),
                    "confidence": Double(point.confidence),
                ]
                if Float(point.confidence) > 0 {
                    let px = Double(point.location.x)
                    let py = Double(point.location.y)
                    minX = Swift.min(minX, px); maxX = Swift.max(maxX, px)
                    minY = Swift.min(minY, py); maxY = Swift.max(maxY, py)
                }
            }
            d["joints"] = joints
            d["joint_count"] = joints.count

            // 从 joints 计算包围框（Vision 没有直接提供）
            if minX < maxX {
                let w = maxX - minX
                let h = maxY - minY
                let pixX = minX * Double(engine.width)
                let pixY = (1 - maxY) * Double(engine.height)
                d["bbox"] = [Int(pixX), Int(pixY), Int(w * Double(engine.width)), Int(h * Double(engine.height))]
                d["norm"] = [minX, 1 - maxY, w, h]
            }
        }

        return d
    }

    var result = baseResult(engine, src)
    result["count"] = bodies.count
    result["bodies"] = bodies
    return result
}

enum PoseCmd: Cmd {
    static let meta = CmdMeta(
        name: "pose",
        desc: "Detect human body pose (18 keypoint joints per body)",
        longDesc: "Uses VNDetectHumanBodyPoseRequest. Returns each detected body with its bounding box and 18 joint keypoints (head, neck, shoulders, elbows, wrists, hips, knees, ankles, etc.). Each joint has both normalized (0-1) and pixel coordinates plus a confidence score.",
        tips: [
            "Vision uses 0-1 normalized coords with Y pointing UP (Vision convention). We give you both raw `x,y` (Vision) and `pixel_x,pixel_y` (top-left origin, Y down) for plotting.",
            "Filter noise: pass `--min-confidence 0.3` to drop joints Vision isn't sure about. Useful for stick-figure rendering.",
            "Joint names: nose, neck, leftEye, rightEye, leftEar, rightEar, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle.",
        ],
        synopsis: [
            "macvision pose <image>",
            "macvision pose <image> --min-confidence 0.3",
        ],
        tldr: [
            ("Agent: detect body pose (18 joint keypoints) — fitness / dance / sports", "macvision pose runner.jpg"),
            ("Agent: get the wrist positions for a workout tracker", "macvision pose workout.jpg --min-confidence 0.5 | jq '.bodies[].joints.leftWrist'"),
            ("Agent: list all 18 joints (nose, neck, shoulders, elbows, wrists, hips, knees, ankles, eyes, ears)", "macvision pose dance.jpg | jq '.bodies[0].joints | keys'"),
            ("Agent: filter noise for cleaner stick figures", "macvision pose sway.jpg --min-confidence 0.3"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--min-confidence", type: Double.self, desc: "Drop joints below this confidence (0-1, default: 0)"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let minConf = p.opt("--min-confidence") as Double? ?? 0
            printJson(try runPose(engine: engine, src: src, minConfidence: minConf))
        }
    )
}