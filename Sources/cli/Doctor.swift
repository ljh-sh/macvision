import Foundation

/// Environment + capability report. Pure function so the daemon can serve it too.
func runDoctor() -> [String: Any] {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let osStr = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    let arch = machineArch()
    let appleSilicon = arch.hasPrefix("arm64")

    var checks: [[String: Any]] = []
    checks.append(["name": "macos_version", "value": osStr, "ok": os.majorVersion >= 13, "requirement": ">= 13"])
    checks.append(["name": "architecture", "value": arch, "ok": true])
    checks.append(["name": "apple_silicon", "value": appleSilicon, "ok": appleSilicon, "note": "Intel Macs support OCR/classify/detect; some requests prefer Apple Silicon"])

    // Capability matrix. All requests below require macOS 13+, which is the build floor.
    let caps: [(String, Bool, String)] = [
        ("ocr",            true,  "VNRecognizeTextRequest"),
        ("classify",       true,  "VNClassifyImageRequest"),
        ("classify_animals", true, "VNRecognizeAnimalsRequest"),
        ("detect_faces",   true,  "VNDetectFaceRectanglesRequest"),
        ("detect_barcodes", true, "VNDetectBarcodesRequest"),
        ("detect_rects",   true,  "VNDetectRectanglesRequest"),
        ("detect_text_regions", true, "VNDetectTextRectanglesRequest"),
        ("detect_horizon", true,  "VNDetectHorizonRequest"),
        ("salient",        true,  "VNGenerateAttentionBasedSaliencyImageRequest"),
        ("document",       true,  "VNDetectDocumentSegmentationRequest"),
        ("feature",        true,  "VNGenerateImageFeaturePrintRequest"),
    ]
    var capabilities: [[String: Any]] = []
    for (name, ok, api) in caps {
        capabilities.append(["name": name, "ok": ok, "api": api])
    }

    let usable = os.majorVersion >= 13
    return [
        "ok": usable,
        "macos_version": osStr,
        "architecture": arch,
        "apple_silicon": appleSilicon,
        "checks": checks,
        "capabilities": capabilities,
    ]
}

func machineArch() -> String {
    var sysinfo = utsname()
    if uname(&sysinfo) == 0 {
        let mirror = Mirror(reflecting: sysinfo.machine)
        var bytes: [UInt8] = []
        for child in mirror.children {
            guard let v = child.value as? Int8, v != 0 else { break }
            bytes.append(UInt8(bitPattern: v))
        }
        if let s = String(bytes: bytes, encoding: .utf8), !s.isEmpty {
            return s
        }
    }
    #if arch(arm64)
    return "arm64"
    #else
    return "x86_64"
    #endif
}

enum DoctorCmd: Cmd {
    static let meta = CmdMeta(
        name: "doctor",
        desc: "Check the environment and report Vision capabilities",
        synopsis: [
            "macvision doctor",
        ],
        tldr: [
            ("Check macOS version, arch, and supported Vision requests", "macvision doctor"),
        ],
        run: { _ in
            printJson(runDoctor())
        }
    )
}
