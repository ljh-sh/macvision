import Foundation

enum MacvisionRoot: Cmd {
    static let meta = CmdMeta(
        name: "macvision",
        desc: "turn any image into agent-friendly JSON — local OCR & vision on macOS",
        longDesc: "Wraps Apple's Vision framework in a tiny Swift binary. Reads text, classifies scenes, detects faces/body/pose, extracts image embeddings, and more — entirely on-device. No model to download, nothing uploaded, tiny footprint. Designed to give AI agents EYES on macOS: every subcommand outputs JSON that pipelines straight into an LLM.",
        tips: [
            "Designed for AI agents: every command outputs compact JSON (with `ok` flag and confidence scores), so output pipes cleanly into `jq` and then into any LLM.",
            "Bounding boxes are pixel [x, y, w, h] with a TOP-LEFT origin (screen coordinates). A normalized [0,1] copy is in `norm`.",
            "Image input: a file path, `-` for base64 on stdin, `--clipboard`, or `--screen` (take a fresh screenshot).",
            "OCR outputs 4 flavors: `--tsv` (default: text, confidence, box, norm, center, center_norm), `--json`, `--text`, `--lines`.",
            "For agent pipelines: `macvision <cmd> img.jpg | jq '<query>'` gives clean structured output for downstream tools.",
            "Private by design: images are processed on-device by Apple's Vision framework; nothing is uploaded.",
            "All Vision requests are on macOS 13+; some prefer Apple Silicon. Run `macvision doctor` to see what your Mac supports.",
        ],
        synopsis: [
            "macvision ocr <image> [--lang zh-Hans,en-US]",
            "macvision classify <image> [--top N] [--animals]",
            "macvision detect <image> [--ocr [--lang ...]]",
            "macvision face-landmarks <image>",
            "macvision pose <image>",
            "macvision humans <image>",
            "macvision document <image>",
            "macvision salient <image> [--output heat.png]",
            "macvision feature <image> [--compare <other>]",
            "macvision annotate <image> \"key1,key2\" [--output out.png]",
            "macvision daemon [--req <path> --res <path>]",
            "macvision doctor",
        ],
        tldr: [
            ("Agent: 'what does this screenshot say?' → OCR with positions", "macvision ocr shot.png --tsv"),
            ("Agent: 'what's in this photo?' → top 5 scene labels", "macvision classify photo.jpg --top 5"),
            ("Agent: full screenshot dump (faces+barcodes+text+OCR)", "macvision detect img.png --ocr --lang zh-Hans,en-US"),
            ("Agent: 'what's on my clipboard right now?'", "macvision ocr --clipboard"),
            ("Agent: read a QR / barcode", "macvision detect qr.png --barcodes"),
            ("Agent: face landmarks (eyes, nose, mouth) for one face", "macvision face-landmarks portrait.jpg"),
            ("Agent: 18-joint body pose (fitness, dance, gesture)", "macvision pose runner.jpg"),
            ("Agent: count people, get person bboxes", "macvision humans photo.jpg | jq .count"),
            ("Agent: detect document quad to crop/deskew", "macvision document scan.jpg"),
            ("Agent: smart crop (where the eye goes)", "macvision salient photo.jpg --output heat.png"),
            ("Agent: dedup / compare two images (0 = same)", "macvision feature a.jpg --compare b.jpg"),
            ("Agent: highlight every 'X-CMD' / 'TODO' / brand mention with red boxes", "macvision annotate doc.png X-CMD --output marked.png"),
            ("Agent: pick the right Apple Vision features", "macvision doctor"),
            ("Agent: trial a fine-tuned CoreML model", "macvision infer squeezenet1-1 photo.jpg"),
        ],
        subcmds: [
            "ocr": OcrCmd.self,
            "classify": ClassifyCmd.self,
            "detect": DetectCmd.self,
            "face-landmarks": FaceLandmarksCmd.self,
            "pose": PoseCmd.self,
            "humans": HumansCmd.self,
            "salient": SalientCmd.self,
            "document": DocumentCmd.self,
            "feature": FeatureCmd.self,
            "annotate": AnnotateCmd.self,
            "daemon": DaemonCmd.self,
            "doctor": DoctorCmd.self,
            "infer": Infer.self,
        ],
        run: { p in
            guard let sub = p.arg(0) else {
                printCmdHelp(MacvisionRoot.self)
                return
            }
            var subArgs = p
            if !subArgs.args.isEmpty {
                subArgs.args.removeFirst()
            }
            switch sub {
            case "ocr":             try await OcrCmd.meta.run?(subArgs)
            case "classify":        try await ClassifyCmd.meta.run?(subArgs)
            case "detect":          try await DetectCmd.meta.run?(subArgs)
            case "face-landmarks":  try await FaceLandmarksCmd.meta.run?(subArgs)
            case "pose":            try await PoseCmd.meta.run?(subArgs)
            case "humans":          try await HumansCmd.meta.run?(subArgs)
            case "salient":         try await SalientCmd.meta.run?(subArgs)
            case "document":        try await DocumentCmd.meta.run?(subArgs)
            case "feature":         try await FeatureCmd.meta.run?(subArgs)
            case "annotate":        try await AnnotateCmd.meta.run?(subArgs)
            case "daemon":          try await DaemonCmd.meta.run?(subArgs)
            case "doctor":          try await DoctorCmd.meta.run?(subArgs)
            case "infer":           try await Infer.meta.run?(subArgs)
            default:                cmdError("unknown subcommand: \(sub)")
            }
        }
    )
}
