import Foundation

enum MacvisionRoot: Cmd {
    static let meta = CmdMeta(
        name: "macvision",
        desc: "turn any image into agent-friendly JSON — local OCR & vision on macOS",
        longDesc: "Wraps Apple's Vision framework in a tiny Swift binary. Reads text, classifies scenes, and detects faces/barcodes/documents out of any image — entirely on-device. No model to download, nothing uploaded, tiny footprint.",
        tips: [
            "All output is compact JSON. Check the `ok` field: true on success; on failure it is false with an `error` field.",
            "Bounding boxes are pixel [x, y, w, h] with a TOP-LEFT origin (screen coordinates). A normalized [0,1] copy is in `norm`.",
            "Image input: a file path, `-` for base64 on stdin, `--clipboard`, or `--screen` (take a fresh screenshot).",
            "Private by design: images are processed on-device by Apple's Vision framework; nothing is uploaded.",
        ],
        synopsis: [
            "macvision ocr <image> [--lang zh-Hans,en-US]",
            "macvision classify <image> [--top N] [--animals]",
            "macvision detect <image> [--ocr [--lang ...]]",
            "macvision document <image>",
            "macvision salient <image> [--output heat.png]",
            "macvision feature <image> [--compare <other>]",
            "macvision daemon [--req <path> --res <path>]",
            "macvision doctor",
        ],
        tldr: [
            ("Read text from a screenshot (Chinese + English)", "macvision ocr shot.png --lang zh-Hans,en-US"),
            ("What's in this photo (top scene labels)", "macvision classify photo.jpg --top 5"),
            ("Everything in an image, including the text", "macvision detect img.png --ocr --lang zh-Hans,en-US"),
            ("Read the image on the clipboard", "macvision ocr --clipboard"),
            ("Find QR / barcodes", "macvision detect qr.png --barcodes"),
            ("Compare two images (0 = identical)", "macvision feature a.jpg --compare b.jpg"),
            ("Check what this Mac supports", "macvision doctor"),
        ],
        subcmds: [
            "ocr": OcrCmd.self,
            "classify": ClassifyCmd.self,
            "detect": DetectCmd.self,
            "salient": SalientCmd.self,
            "document": DocumentCmd.self,
            "feature": FeatureCmd.self,
            "daemon": DaemonCmd.self,
            "doctor": DoctorCmd.self,
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
            case "ocr":       try await OcrCmd.meta.run?(subArgs)
            case "classify":  try await ClassifyCmd.meta.run?(subArgs)
            case "detect":    try await DetectCmd.meta.run?(subArgs)
            case "salient":   try await SalientCmd.meta.run?(subArgs)
            case "document":  try await DocumentCmd.meta.run?(subArgs)
            case "feature":   try await FeatureCmd.meta.run?(subArgs)
            case "daemon":    try await DaemonCmd.meta.run?(subArgs)
            case "doctor":    try await DoctorCmd.meta.run?(subArgs)
            default:          cmdError("unknown subcommand: \(sub)")
            }
        }
    )
}
