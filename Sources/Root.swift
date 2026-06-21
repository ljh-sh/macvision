import Foundation

enum MacvisionRoot: Cmd {
    static let meta = CmdMeta(
        name: "macvision",
        desc: "macOS vision CLI — local OCR, classification, and detection",
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
