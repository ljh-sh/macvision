//
// macvision infer - CoreML 模型推理
//

import Foundation
import CoreML
import Vision
import AppKit
import CoreImage
import CoreImage
import CoreVideo

// Shell 执行
@discardableResult
func shell(_ cmd: String) -> Int32 {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", cmd]
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return 1
    }
    return task.terminationStatus
}

// ImageNet 类别标签
func imagenetLabels() -> [Int: String] {
    var labels: [Int: String] = [:]
    let pairs: [(Int, String)] = [
        (0, "tench"), (1, "goldfish"), (2, "great white shark"), (3, "tiger shark"),
        (5, "electric ray"), (10, "cock"), (11, "hen"), (20, "black grouse"),
        (23, "peacock"), (24, "quail"), (25, "partridge"),
        (27, "African elephant"), (28, "Indian elephant"), (29, "mammoth"),
        (30, "walrus"), (31, "hippopotamus"), (32, "ox"), (33, "water buffalo"),
        (70, "horse"), (71, "zebra"), (72, "donkey"), (73, "wild boar"),
        (76, "pig"), (80, "sheep"), (81, "impala"), (84, "llama"),
        (85, "weasel"), (86, "mink"), (87, "otter"), (88, "polecat"),
        (90, "badger"), (92, "sea lion"), (93, "chimpanzee"), (94, "gibbon"),
        (100, "proboscis monkey"), (101, "marmoset"), (102, "capuchin"),
        (106, "baboon"), (107, "cat"), (108, "dog"), (109, "wolf"),
        (151, "lion"), (152, "tiger"), (153, "leopard"), (154, "jaguar"),
        (207, "great grey owl"), (208, "owl"),
        (200, "drum"), (210, "banjo"), (220, "piano"), (230, "trumpet"),
        (250, "car"), (251, "taxi"), (254, "limousine"), (255, "minivan"),
        (258, "fire engine"), (259, "police van"), (261, "tow truck"),
        (262, "tractor"), (266, "forklift"), (269, "crane"),
        (281, "throne"), (282, "chair"), (286, "couch"), (290, "table"),
        (400, "laptop"), (401, "computer"), (403, "desk"), (409, "computer keyboard"),
        (410, "keyboard"), (411, "keypad"), (420, "monitor"), (425, "television"),
        (430, "cell phone"), (435, "telephone"), (440, "fax machine"), (450, "remote"),
        (500, "pot"), (502, "flower pot"), (504, "cup"), (508, "coffeepot"),
        (530, "espresso"), (620, "napkin"), (622, "menu"),
        (600, "vase"), (700, "teddy bear"), (714, "plate"),
        (769, "envelope"), (770, "wallet"), (780, "photocopier"),
        (800, "shower"), (850, "desk"), (900, "basket"), (905, "beach"),
        (950, "pillow"), (999, "toaster"),
    ]
    for (k, v) in pairs {
        labels[k] = v
    }
    return labels
}

enum Infer: Cmd {
    static let meta = CmdMeta(
        name: "infer",
        desc: "CoreML model inference with on-demand download",
        synopsis: [
            "macvision infer <model> <image>",
        ],
        tldr: [
            ("Agent: run a CoreML classification model (downloads on first use)", "macvision infer squeezenet1-1 photo.jpg"),
            ("Agent: try a fine-tuned YOLO detection model", "macvision infer yolov8n photo.jpg"),
            ("Agent: many models available — pass any name published at github.com/ljh-sh/coreml-model", "macvision infer mobilenet-v3-small photo.jpg"),
        ],
        args: [
            ArgMeta(name: "model", desc: "Model name (e.g., yolov8n, resnet50)"),
            ArgMeta(name: "image", desc: "Image path"),
        ],
        run: { p in
            let modelName = p.arg(0) ?? ""
            let imagePath = p.arg(1) ?? ""

            guard !modelName.isEmpty else {
                cmdError("Usage: macvision infer <model> <image>")
            }
            guard !imagePath.isEmpty else {
                cmdError("Usage: macvision infer <model> <image>")
            }

            // 下载模型（如果需要）
            let modelURL = try await downloadModel(modelName)

            // 加载模型
            let compiledURL = try await MLModel.compileModel(at: modelURL)
            let mlModel = try MLModel(contentsOf: compiledURL)

            // 检查输入类型 - 只看 inputs 部分
            let modelDesc = mlModel.description
            let inputsMatch = modelDesc.range(of: "inputs:", options: .caseInsensitive)
            let hasImageInput: Bool
            if let start = inputsMatch?.lowerBound {
                let rest = modelDesc[start...]
                hasImageInput = rest.contains("Image")
            } else {
                hasImageInput = false
            }
            let isImageInput = hasImageInput

            // 已知输入名称
            let inputName = "input"

            // 加载图像
            guard let image = NSImage(contentsOfFile: imagePath) else {
                cmdError("Cannot load image: \(imagePath)")
            }
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                cmdError("Cannot convert image")
            }

            if isImageInput {
                // VNCoreMLRequest for image input models
                let vnnModel = try VNCoreMLModel(for: mlModel)
                let request = VNCoreMLRequest(model: vnnModel) { request, error in
                    if let error = error {
                        print("[error] \(error)")
                        return
                    }

                    // Classification results
                    if let results = request.results as? [VNClassificationObservation] {
                        let top5 = results.prefix(5)
                        print("[result] Classification Top 5:")
                        for (i, r) in top5.enumerated() {
                            print("  \(i+1). \(r.identifier): \(String(format: "%.2f", r.confidence * 100))%")
                        }
                    }

                    // Detection results
                    if let results = request.results as? [VNRecognizedObjectObservation], !results.isEmpty {
                        print("[result] Detected objects:")
                        for (i, r) in results.prefix(10).enumerated() {
                            let conf = String(format: "%.2f", r.confidence * 100)
                            if let label = r.labels.first {
                                print("  \(i+1). \(label.identifier): \(conf)%")
                            }
                        }
                    }

                    // YOLOv8 produces raw output, show count
                    let count = request.results?.count ?? 0
                    if count > 0 && !(request.results is [VNClassificationObservation]) && !(request.results is [VNRecognizedObjectObservation]) {
                        print("[info] Model ran but output format not supported")
                    }
                }

                let handler = VNImageRequestHandler(cgImage: cg)
                try handler.perform([request])
            } else {
                // MultiArray 输入模型
                print("[info] MultiArray input model - using MLFeatureValue")

                // 创建 MultiArray (1x3x224x224)
                let width = 224
                let height = 224
                let channels = 3

                // 使用 MLFeatureValue 从 MultiArray
                guard let inputMultiArray = try? MLMultiArray(shape: [1, channels, height, width] as [NSNumber], dataType: .float32) else {
                    cmdError("Failed to create MultiArray")
                }

                // 缩放图像到 224x224
                let ciImage = CIImage(cgImage: cg)
                let scaleX = CGFloat(width) / CGFloat(cg.width)
                let scaleY = CGFloat(height) / CGFloat(cg.height)
                let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

                let context = CIContext()
                guard let scaledCG = context.createCGImage(scaled, from: scaled.extent) else {
                    cmdError("Failed to scale image")
                }

                // 提取像素 (BGRA)
                var pixelData = [UInt8](repeating: 0, count: width * height * 4)
                guard let ctx = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    cmdError("Failed to create context")
                }

                ctx.draw(scaledCG, in: CGRect(x: 0, y: 0, width: width, height: height))

                // 填充 MultiArray (CHW 格式，ImageNet 标准化)
                for y in 0..<height {
                    for x in 0..<width {
                        let srcIdx = (y * width + x) * 4
                        let r = Float(pixelData[srcIdx]) / 255.0
                        let g = Float(pixelData[srcIdx + 1]) / 255.0
                        let b = Float(pixelData[srcIdx + 2]) / 255.0

                        // ImageNet 标准化
                        let rNorm = (r - 0.485) / 0.229
                        let gNorm = (g - 0.456) / 0.224
                        let bNorm = (b - 0.406) / 0.225

                        inputMultiArray[[0, 0, y, x] as [NSNumber]] = NSNumber(value: rNorm)
                        inputMultiArray[[0, 1, y, x] as [NSNumber]] = NSNumber(value: gNorm)
                        inputMultiArray[[0, 2, y, x] as [NSNumber]] = NSNumber(value: bNorm)
                    }
                }

                // 创建特征值
                let inputFeature = try MLFeatureValue(multiArray: inputMultiArray)

                // 使用 FeatureProvider
                let featureProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputFeature])

                // 推理
                let output = try mlModel.prediction(from: featureProvider)

                // 解析输出 - 尝试 var_293 或其他常见输出名
                var outputMultiArray: MLMultiArray?

                if let outFeat = output.featureValue(for: "var_293"),
                   let outArr = outFeat.multiArrayValue {
                    outputMultiArray = outArr
                } else if let outFeat = output.featureValue(for: "output"),
                          let outArr = outFeat.multiArrayValue {
                    outputMultiArray = outArr
                } else {
                    // 尝试找到第一个 MultiArray 输出
                    for name in output.featureNames {
                        if let feat = output.featureValue(for: name),
                           let arr = feat.multiArrayValue {
                            outputMultiArray = arr
                            break
                        }
                    }
                }

                guard let outArr = outputMultiArray else {
                    cmdError("Failed to get output")
                }

                // 获取 Top 5 - 输出是原始 logits，需要 softmax
                var probs = [(Int, Float)]()
                for i in 0..<min(1000, outArr.count) {
                    let idx = [0, i] as [NSNumber]
                    if let val = outArr[idx] as? NSNumber {
                        probs.append((i, val.floatValue))
                    }
                }

                // 计算 softmax
                let maxLogit = probs.map { $0.1 }.max() ?? 0
                var expSum: Float = 0
                for i in 0..<probs.count {
                    let expVal = exp(probs[i].1 - maxLogit)
                    expSum += expVal
                }

                // 计算概率并排序
                var softmaxProbs = [(Int, Float)]()
                for i in 0..<probs.count {
                    let expVal = exp(probs[i].1 - maxLogit)
                    let prob = expVal / expSum
                    softmaxProbs.append((probs[i].0, prob))
                }

                softmaxProbs.sort { $0.1 > $1.1 }
                let top5 = softmaxProbs.prefix(5)

                // ImageNet 类别映射
                let labels = imagenetLabels()
                print("[result] Classification Top 5:")
                for (i, (classIdx, prob)) in top5.enumerated() {
                    let label = labels[classIdx] ?? "class_\(classIdx)"
                    print("  \(i+1). \(label): \(String(format: "%.2f", prob * 100))%")
                }
            }

            print("[done]")
        }
    )

    // 下载模型
    static func downloadModel(_ name: String) async throws -> URL {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ljh-sh/coreml-model")
        let modelPath = cacheDir.appendingPathComponent("\(name).mlpackage")

        // 检查缓存
        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath
        }

        print("[download] Downloading \(name)...")

        // 下载
        let url = URL(string: "https://api.github.com/repos/edwinjhlee/coreml-model/releases/tags/v2026.06.27")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let assets = json["assets"] as! [[String: Any]]

        // 优先 .gz，备选 .xz
        var assetURL: String?
        var isGz = false
        for asset in assets {
            let assetName = asset["name"] as! String
            if assetName.hasPrefix(name) && assetName.hasSuffix(".mlpackage.gz") {
                assetURL = "https://github.com/edwinjhlee/coreml-model/releases/download/v2026.06.27/\(assetName)"
                isGz = true
                break
            }
        }
        if assetURL == nil {
            for asset in assets {
                let assetName = asset["name"] as! String
                if assetName.hasPrefix(name) && assetName.hasSuffix(".mlpackage.xz") {
                    assetURL = "https://github.com/edwinjhlee/coreml-model/releases/download/v2026.06.27/\(assetName)"
                    break
                }
            }
        }

        guard let downloadURL = assetURL else {
            cmdError("Model not found: \(name)")
        }

        // 下载压缩文件
        let (tempURL, _) = try await URLSession.shared.download(from: URL(string: downloadURL)!)

        // 创建缓存目录
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // 解压
        if isGz {
            let gzPath = cacheDir.appendingPathComponent("\(name).mlpackage.gz")
            if FileManager.default.fileExists(atPath: gzPath.path) {
                try FileManager.default.removeItem(at: gzPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: gzPath)

            // gunzip 解压 + tar 解包 - 使用 shell
            let extractDir = cacheDir.appendingPathComponent("\(name).mlpackage")
            let extractCmd = "cd \(cacheDir.path) && /usr/bin/gunzip -c \(gzPath.path) | /usr/bin/tar -xf - -C \(cacheDir.path)"
            let result = shell(extractCmd)
            guard result == 0 else {
                throw NSError(domain: "Infer", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Failed to extract model"])
            }

            // 找到解压后的目录
            var extractedDir: URL?
            let contents = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for item in contents {
                let itemName = item.lastPathComponent
                // 可能是 xxx.mlpackage 或 xxx.mlpackage.dir
                if itemName.hasPrefix(name) && itemName.contains(".mlpackage") && item.hasDirectoryPath {
                    extractedDir = item
                    break
                }
            }

            guard let srcDir = extractedDir else {
                throw NSError(domain: "Infer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Extracted model directory not found"])
            }

            // 检查是否有嵌套的 mlpackage 目录 (结构: xxx.mlpackage.dir/xxx.mlpackage/)
            let nestedPath = srcDir.appendingPathComponent("\(name).mlpackage")
            if FileManager.default.fileExists(atPath: nestedPath.path) {
                // 嵌套结构: 把内部的 mlpackage 移到 cacheDir 根目录
                let targetPath = cacheDir.appendingPathComponent("\(name).mlpackage")
                if FileManager.default.fileExists(atPath: targetPath.path) {
                    try FileManager.default.removeItem(at: targetPath)
                }
                try FileManager.default.moveItem(at: nestedPath, to: targetPath)
                // 删除外层目录
                try FileManager.default.removeItem(at: srcDir)
            } else {
                // 直接移动
                if FileManager.default.fileExists(atPath: modelPath.path) {
                    try FileManager.default.removeItem(at: modelPath)
                }
                try FileManager.default.moveItem(at: srcDir, to: modelPath)
            }

            try FileManager.default.removeItem(at: gzPath)
        } else {
            let xzPath = cacheDir.appendingPathComponent("\(name).mlpackage.xz")
            if FileManager.default.fileExists(atPath: xzPath.path) {
                try FileManager.default.removeItem(at: xzPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: xzPath)

            let xzProcess = Process()
            xzProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/xz")
            xzProcess.arguments = ["-d", "-k", xzPath.path, "-o", modelPath.path]
            try xzProcess.run()
            xzProcess.waitUntilExit()

            try FileManager.default.removeItem(at: xzPath)
        }

        print("[ready] \(name)")
        return modelPath
    }

    // 创建像素缓冲区
    static func createPixelBuffer(from cgImage: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "Infer", code: Int(status), userInfo: nil)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw NSError(domain: "Infer", code: -1, userInfo: nil)
        }

        // 调整图像大小
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(cgImage, in: rect)

        return buffer
    }
}