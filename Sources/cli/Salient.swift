import Foundation
import Vision
import CoreImage
import CoreGraphics
import CoreVideo

/// Core saliency: produce a heatmap PNG for the most visually salient region.
///
/// `mode` is `"attention"` (what draws the eye, default) or `"objectness"`
/// (where whole objects likely are).
///
/// When `overlay=true`, instead of the raw mask we save a composite PNG:
/// the saliency mask is colored (red heatmap) and alpha-blended on top of
/// the original image, so you can SEE where the eye goes at a glance.
///
/// `overlayStyle` selects how the overlay is rendered:
/// - `"default"` (alias `--overlay`): grayscale background + blue→red jet-colormap mask
/// - `"strong"` (alias `--overlay1`): very dim original (color preserved) + vivid red/blue jet mask
func runSalient(engine: VisionEngine, src: ImageSource, mode: String, output: URL?, overlay: Bool, overlayStyle: String, crop: Bool, cropPadding: Double, cropSize: (width: Int, height: Int)?, ocr: Bool) throws -> [String: Any] {
    let obs: VNPixelBufferObservation?
    if mode == "objectness" {
        let r = VNGenerateObjectnessBasedSaliencyImageRequest()
        try engine.perform([r])
        obs = r.results?.first
    } else {
        let r = VNGenerateAttentionBasedSaliencyImageRequest()
        try engine.perform([r])
        obs = r.results?.first
    }
    guard let obs else {
        throw VisionError.requestFailed("saliency produced no output")
    }

    var result = baseResult(engine, src)
    result["mode"] = (mode == "objectness") ? "objectness" : "attention"
    result["mask_width"] = CVPixelBufferGetWidth(obs.pixelBuffer)
    result["mask_height"] = CVPixelBufferGetHeight(obs.pixelBuffer)

    if overlay {
        let originalCG = engine.image
        guard let maskCG = ciImageToCG(obs.pixelBuffer) else {
            throw VisionError.requestFailed("mask render failed")
        }
        let out: CGImage?
        switch overlayStyle {
        case "red":
            out = overlayStrong(mask: maskCG, on: originalCG)
        case "jet":
            out = overlayJet2(mask: maskCG, on: originalCG)
        case "bw":
            out = overlayHeatmap(mask: maskCG, on: originalCG)
        default:
            // 默认 = contour bands（最有用，显示显著性边界）
            out = overlayContour(mask: maskCG, on: originalCG)
        }
        guard let overlayCG = out else {
            throw VisionError.requestFailed("overlay rendering failed")
        }
        let outURL = output ?? defaultTempURL("saliency-\(overlayStyle)", "png")
        try savePNG(overlayCG, to: outURL)
        result["output"] = outURL.path
        result["saved"] = true
        result["overlay"] = true
        result["overlay_style"] = overlayStyle
    } else {
        // 原始 mask 输出 (单色 heatmap PNG)
        guard let cg = ciImageToCG(obs.pixelBuffer) else {
            throw VisionError.requestFailed("mask render failed")
        }
        let outURL = output ?? defaultTempURL("saliency", "png")
        try savePNG(cg, to: outURL)
        result["output"] = outURL.path
        result["saved"] = true
        result["overlay"] = false
        result["overlay_style"] = overlayStyle
    }

    // 2. (可选) 智能裁剪 — 找到高显著性区域的 bbox，把原图裁剪出来
    if crop {
        let maskW = CVPixelBufferGetWidth(obs.pixelBuffer)
        let maskH = CVPixelBufferGetHeight(obs.pixelBuffer)
        guard let maskBbox = computeSaliencyBBox(obs.pixelBuffer, padding: cropPadding) else {
            throw VisionError.requestFailed("could not compute saliency bbox")
        }
        // 把 mask 坐标换算到原图坐标
        let scaleX = Double(engine.width) / Double(maskW)
        let scaleY = Double(engine.height) / Double(maskH)
        let origBbox: [Int] = [
            Int(Double(maskBbox[0]) * scaleX),
            Int(Double(maskBbox[1]) * scaleY),
            Int(Double(maskBbox[2]) * scaleX),
            Int(Double(maskBbox[3]) * scaleY),
        ]
        result["saliency_bbox_mask"] = maskBbox       // mask 坐标（68x68）
        result["saliency_bbox"] = origBbox           // 原图坐标
        result["saliency_bbox_norm"] = [
            Double(origBbox[0]) / Double(engine.width),
            Double(origBbox[1]) / Double(engine.height),
            Double(origBbox[2]) / Double(engine.width),
            Double(origBbox[3]) / Double(engine.height),
        ]
        // 输出：--output 主文件是 heatmap/overlay，crop 用 crop-{output}.png
        let cropURL: URL
        if let o = output {
            let dir = o.deletingLastPathComponent()
            let stem = o.deletingPathExtension().lastPathComponent
            cropURL = dir.appendingPathComponent("\(stem)-crop.png")
        } else {
            cropURL = defaultTempURL("saliency-crop", "png")
        }
        result["crop_input_size"] = [engine.width, engine.height]
        result["crop_bbox_orig"] = origBbox
        if let cropped = cropImage(engine.image, with: origBbox, target: cropSize) {
            try savePNG(cropped, to: cropURL)
            result["crop"] = cropURL.path
            result["crop_size"] = [cropped.width, cropped.height]
            if let size = cropSize {
                result["crop_resize"] = [size.width, size.height]
            }
        } else {
            result["crop_error"] = "cropImage returned nil"
        }
    }

    // 3. (可选) OCR 后，只保留 bbox 与显著性 bbox 相交的文字（网页 dev 场景）
    if ocr {
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["en-US", "zh-Hans"]
        try engine.perform([req])
        var keptTexts: [[String: Any]] = []
        let textBoxes: [(bbox: [Int], text: String)] = (req.results ?? []).compactMap { o in
            guard let top = o.topCandidates(1).first else { return nil }
            return (engine.pixelBox(o.boundingBox), top.string)
        }
        // 没有 crop 情况下，saliency bbox 取整图
        let sb: [Int] = result["saliency_bbox"] as? [Int] ?? [0, 0, engine.width, engine.height]
        for tb in textBoxes {
            if boxesOverlap(tb.bbox, sb) {
                keptTexts.append([
                    "text": tb.text,
                    "bbox": tb.bbox,
                    "norm": [
                        Double(tb.bbox[0]) / Double(engine.width),
                        Double(tb.bbox[1]) / Double(engine.height),
                        Double(tb.bbox[2]) / Double(engine.width),
                        Double(tb.bbox[3]) / Double(engine.height),
                    ],
                ])
            }
        }
        result["texts_in_saliency"] = keptTexts
        result["ocr_count"] = keptTexts.count
    }

    return result
}

/// Convert a luminance pixel buffer (the saliency mask) to a `CGImage`.
private func ciImageToCG(_ pb: CVPixelBuffer) -> CGImage? {
    let ci = CIImage(cvPixelBuffer: pb)
    return CIContext().createCGImage(ci, from: ci.extent)
}

/// Find the bounding box of pixels above a threshold in the saliency mask.
/// Returns [x, y, w, h] in the *original image* pixel coordinates, with optional padding (fraction).
private func computeSaliencyBBox(_ pb: CVPixelBuffer, padding: Double = 0.0) -> [Int]? {
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    let width = CVPixelBufferGetWidth(pb)
    let height = CVPixelBufferGetHeight(pb)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }

    // Apple 把 saliency map 归一化到 0..1 (Float32)
    let fp = base.assumingMemoryBound(to: Float32.self)

    // 先扫一遍，找最大像素值，然后取 50% 作为阈值（自适应）
    var maxV: Float = 0
    for i in 0..<(width * height) { if fp[i] > maxV { maxV = fp[i] } }
    let threshold: Float = maxV * 0.5  // 取最大值的 50% 作为高显著性阈值
    var minX = width, minY = height, maxX = 0, maxY = 0
    var found = false
    for y in 0..<height {
        for x in 0..<width {
            let v = fp[y * width + x]
            if v > threshold {
                found = true
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x > maxX { maxX = x }
                if y > maxY { maxY = y }
            }
        }
    }
    if !found { return nil }

    // Vision mask 可能比原图小 (e.g. 68x68 vs 2142x1511)，按比例放大
    // 但 base address 是 mask 的，width/height 是 mask 的。
    // 我们让调用者拿到 mask bbox，再用 mask_size → original_size 比例放大。
    // 这里返回 4 元素（x, y, w, h 在 mask 坐标里），外层再 scale。
    let w = maxX - minX + 1
    let h = maxY - minY + 1
    // padding (fraction)
    let padX = Int(Double(w) * padding)
    let padY = Int(Double(h) * padding)
    let x1 = max(0, minX - padX)
    let y1 = max(0, minY - padY)
    let x2 = min(width - 1, maxX + padX)
    let y2 = min(height - 1, maxY + padY)
    return [x1, y1, x2 - x1 + 1, y2 - y1 + 1]
}

/// Crop original image using bbox (already in original image coords), then resize to target (W, H).
/// If target is nil, keep the cropped dimensions. Composites alpha onto white so the output
/// looks the same as the user-visible preview.
private func cropImage(_ original: CGImage, with bbox: [Int], target: (width: Int, height: Int)? = nil) -> CGImage? {
    let origW = original.width
    let origH = original.height
    let x = bbox[0]
    let y = bbox[1]
    let w = bbox[2]
    let h = bbox[3]
    let safeX = max(0, min(x, origW - 1))
    let safeY = max(0, min(y, origH - 1))
    let safeW = max(1, min(w, origW - safeX))
    let safeH = max(1, min(h, origH - safeY))

    let rect = CGRect(x: safeX, y: safeY, width: safeW, height: safeH)
    guard let cropped = original.cropping(to: rect) else { return nil }
    guard let target = target else { return cropped }

    // 1. 在白底上合成裁剪（社交媒体需要不透明 PNG）
    let composed = compositeOnWhite(cropped) ?? cropped

    // 2. aspect-cover: 如果目标比例不同，再裁一次 sub rect
    let targetAspect = Double(target.width) / Double(target.height)
    let cropAspect = Double(composed.width) / Double(composed.height)

    var displayRect: CGRect
    if abs(cropAspect - targetAspect) < 0.001 {
        displayRect = CGRect(x: 0, y: 0, width: composed.width, height: composed.height)
    } else if cropAspect > targetAspect {
        // crop 比 target 更宽 — 高度相同，水平方向裁掉一些
        let displayW = Int(Double(composed.height) * targetAspect)
        let offsetX = (composed.width - displayW) / 2
        displayRect = CGRect(x: offsetX, y: 0, width: displayW, height: composed.height)
    } else {
        // crop 比 target 更窄 — 宽度相同，垂直方向补足
        let displayH = Int(Double(composed.width) / targetAspect)
        displayRect = CGRect(x: 0, y: 0, width: composed.width, height: displayH)
    }
    guard let display = composed.cropping(to: displayRect) else { return nil }

    // 3. resize 到 target（opaque，无 alpha）
    let ctx = CGContext(
        data: nil,
        width: target.width,
        height: target.height,
        bitsPerComponent: 8,
        bytesPerRow: target.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue).rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(display, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
    return ctx.makeImage()
}

/// Composite CGImage onto white background to remove alpha. Returns RGB (no alpha).
private func compositeOnWhite(_ image: CGImage) -> CGImage? {
    let w = image.width
    let h = image.height
    let ctx = CGContext(
        data: nil,
        width: w, height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue).rawValue
    )!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

/// Social media preset sizes (W x H), ordered by popularity.
private let socialMediaPresets: [(name: String, width: Int, height: Int, note: String)] = [
    ("square", 1080, 1080, "Instagram post, Facebook post, Twitter image"),
    ("story", 1080, 1920, "Instagram/TikTok/Snapchat story (9:16)"),
    ("reel", 1080, 1920, "TikTok/IG Reel (same as story)"),
    ("wide", 1200, 630, "Facebook share, Twitter card"),
    ("linkedin-cover", 1584, 396, "LinkedIn cover"),
    ("twitter-header", 1500, 500, "Twitter/X header (15:5)"),
    ("yt-thumb", 1280, 720, "YouTube thumbnail (16:9)"),
    ("ig-landscape", 1080, 566, "Instagram landscape (1.91:1)"),
    ("ig-portrait", 1080, 1350, "Instagram portrait (4:5)"),
    ("avatar", 400, 400, "Small avatar (Twitter/Discord)"),
    ("avatar-2x", 800, 800, "Large avatar"),
    ("pinterest", 1000, 1500, "Pinterest pin (2:3)"),
]

/// Parse --size value: preset name or WxH
func parseSocialSize(_ value: String) -> (width: Int, height: Int)? {
    if let preset = socialMediaPresets.first(where: { $0.name == value }) {
        return (preset.width, preset.height)
    }
    if let range = value.range(of: "x") {
        let wStr = String(value[..<range.lowerBound])
        let hStr = String(value[range.upperBound...])
        if let w = Int(wStr), let h = Int(hStr), w > 0, h > 0 {
            return (w, h)
        }
    }
    return nil
}

/// Two pixel boxes overlap?
private func boxesOverlap(_ a: [Int], _ b: [Int]) -> Bool {
    guard a.count >= 4, b.count >= 4 else { return false }
    let ax1 = a[0], ay1 = a[1], ax2 = a[0] + a[2], ay2 = a[1] + a[3]
    let bx1 = b[0], by1 = b[1], bx2 = b[0] + b[2], by2 = b[1] + b[3]
    return ax1 < bx2 && bx1 < ax2 && ay1 < by2 && by1 < ay2
}

/// "default" overlay: grayscale background + blue→red jet colormap mask.
private func overlayHeatmap(mask: CGImage, on original: CGImage) -> CGImage? {
    let origSize = original.width
    let origHeight = original.height

    // 1. 放大 mask 到原图尺寸
    let scaledMask: CGImage = {
        if mask.width == origSize && mask.height == origHeight {
            return mask
        }
        let ctx = CGContext(
            data: nil,
            width: origSize,
            height: origHeight,
            bitsPerComponent: 8,
            bytesPerRow: origSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: origSize, height: origHeight))
        return ctx.makeImage() ?? mask
    }()

    let ciMask = CIImage(cgImage: scaledMask)
    let outCtx = CIContext()

    // 2. 用 CIFalseColor 做"蓝→红"渐变（接近 Jet）
    guard let fcFilter = CIFilter(name: "CIFalseColor") else { return nil }
    fcFilter.setValue(ciMask, forKey: kCIInputImageKey)
    fcFilter.setValue(CIColor(red: 0.1, green: 0.0, blue: 0.8, alpha: 1.0),
                     forKey: "inputColor0")  // 冷：蓝紫
    fcFilter.setValue(CIColor(red: 1.0, green: 0.0, blue: 0.2, alpha: 1.0),
                     forKey: "inputColor1")  // 热：红
    guard let jet = fcFilter.outputImage else { return nil }

    // 3. 调 alpha mask 强度（让冷色更弱、热色更强）
    let alphaFilter = CIFilter(name: "CIColorMatrix")!
    alphaFilter.setValue(jet, forKey: kCIInputImageKey)
    // alpha = 原亮度 * 1.0（promoting mask brightness to alpha）
    alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputAVector")
    guard let colored = alphaFilter.outputImage else { return nil }

    // 4. 把原图转灰度 + 暗化（作为 heatmap 背景）
    let ciOriginal = CIImage(cgImage: original)
    let monoFilter = CIFilter(name: "CIPhotoEffectMono")
    monoFilter?.setValue(ciOriginal, forKey: kCIInputImageKey)
    let mono = monoFilter?.outputImage ?? ciOriginal

    let dimFilter = CIFilter(name: "CIColorControls")!
    dimFilter.setValue(mono, forKey: kCIInputImageKey)
    dimFilter.setValue(-0.15, forKey: kCIInputBrightnessKey)
    dimFilter.setValue(0.5, forKey: kCIInputSaturationKey)
    guard let dimmedMono = dimFilter.outputImage else { return nil }

    // 5. 叠加
    guard let composite = CIFilter(name: "CISourceOverCompositing") else { return nil }
    composite.setValue(colored, forKey: kCIInputImageKey)
    composite.setValue(dimmedMono, forKey: kCIInputBackgroundImageKey)

    guard let result = composite.outputImage else { return nil }
    return outCtx.createCGImage(result, from: result.extent)
}

/// "strong" overlay: VERY dim original (color preserved) + vivid blue→red jet mask on top.
/// Difference from default: keeps hue (not monochrome), dims harder, heatmap colors are more saturated.
private func overlayStrong(mask: CGImage, on original: CGImage) -> CGImage? {
    let origSize = original.width
    let origHeight = original.height

    // 1. 放大 mask 到原图尺寸
    let scaledMask: CGImage = {
        if mask.width == origSize && mask.height == origHeight {
            return mask
        }
        let ctx = CGContext(
            data: nil,
            width: origSize,
            height: origHeight,
            bitsPerComponent: 8,
            bytesPerRow: origSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: origSize, height: origHeight))
        return ctx.makeImage() ?? mask
    }()

    let ciMask = CIImage(cgImage: scaledMask)
    let outCtx = CIContext()

    // 2. mask 转为红色 heatmap：R = mask亮度*2，alpha = mask亮度*1.5
    //    G、B 都设 0，mask 灰度被映射成纯红
    guard let redFilter = CIFilter(name: "CIColorMatrix") else { return nil }
    redFilter.setValue(ciMask, forKey: kCIInputImageKey)
    redFilter.setValue(CIVector(x: 2.0, y: 0, z: 0, w: 0), forKey: "inputRVector")  // R = maskR * 2 (clip 0-1)
    redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")  // G = 0
    redFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")  // B = 0
    redFilter.setValue(CIVector(x: 1.5, y: 0, z: 0, w: -0.1), forKey: "inputAVector") // alpha = maskR*1.5 - 0.1
    guard let redHeatmap = redFilter.outputImage else { return nil }

    // 3. 底片 = 原图"亮化淡化" — 提高亮度、降低饱和，让原图褪色变浅，
    //    红色 heatmap 在褪色底上更突出。
    let ciOriginal = CIImage(cgImage: original)
    let dimFilter = CIFilter(name: "CIColorControls")!
    dimFilter.setValue(ciOriginal, forKey: kCIInputImageKey)
    dimFilter.setValue(0.25, forKey: kCIInputBrightnessKey)   // +0.25 让原图变亮
    dimFilter.setValue(0.35, forKey: kCIInputSaturationKey)    // 0.35 显著降饱和（褪色）
    dimFilter.setValue(0.85, forKey: kCIInputContrastKey)      // 降低对比度让褪色更均匀
    guard let fadedOriginal = dimFilter.outputImage else { return nil }

    // 4. 把红色 heatmap 叠加在变暗的原图上
    guard let composite = CIFilter(name: "CISourceOverCompositing") else { return nil }
    composite.setValue(redHeatmap, forKey: kCIInputImageKey)
    composite.setValue(fadedOriginal, forKey: kCIInputBackgroundImageKey)

    guard let result = composite.outputImage else { return nil }
    return outCtx.createCGImage(result, from: result.extent)
}

/// "jet2" overlay: 学术标准 5 段 Jet colormap（蓝→青→绿→黄→红），
/// 通过 CPU 查表直接生成 RGBA 像素图，叠加在褪色底片上。
private func overlayJet2(mask: CGImage, on original: CGImage) -> CGImage? {
    let origSize = original.width
    let origHeight = original.height

    // 1. 放大 mask 到原图尺寸
    let scaledMask: CGImage = {
        if mask.width == origSize && mask.height == origHeight {
            return mask
        }
        let ctx = CGContext(
            data: nil,
            width: origSize,
            height: origHeight,
            bitsPerComponent: 8,
            bytesPerRow: origSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: origSize, height: origHeight))
        return ctx.makeImage() ?? mask
    }()

    let outCtx = CIContext()

    // 2. CPU 上生成 Jet RGBA 像素图（完全 jet colormap，无 CIFilter 限制）
    let width = origSize
    let height = origHeight
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    guard let maskData = scaledMask.dataProvider?.data else { return nil }
    guard let maskBytesPtr = CFDataGetBytePtr(maskData) else { return nil }
    let maskBytesPerRow = scaledMask.bytesPerRow
    let maskBytesPerPixel = scaledMask.bitsPerPixel / 8

    for y in 0..<height {
        // mask 在 y 方向的源像素（bilinear 简化只用 nearest）
        let my = (y * scaledMask.height) / max(height, 1)
        let maskRowStart = my * maskBytesPerRow
        let dstRowStart = y * bytesPerRow

        for x in 0..<width {
            let mx = (x * scaledMask.width) / max(width, 1)
            let maskVal = Float(maskBytesPtr[maskRowStart + mx * maskBytesPerPixel]) / 255.0
            let (r, g, b) = jetRGB(maskVal)
            let i = dstRowStart + x * 4
            pixels[i + 0] = r
            pixels[i + 1] = g
            pixels[i + 2] = b
            pixels[i + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let ctx = CGContext(data: &pixels,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: info.rawValue),
          let jetImage = ctx.makeImage() else {
        return nil
    }

    // 3. alpha = mask 亮度 — 低 mask 区显示褪色底片，高 mask 区全色显示
    let ciJet = CIImage(cgImage: jetImage)
    guard let alphaFilter = CIFilter(name: "CIColorMatrix") else { return nil }
    alphaFilter.setValue(ciJet, forKey: kCIInputImageKey)
    alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
    alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
    alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
    alphaFilter.setValue(CIVector(x: 1.4, y: 0, z: 0, w: 0), forKey: "inputAVector")
    guard let jetAlpha = alphaFilter.outputImage else { return nil }

    // 4. 底片 = 原图褪色（亮化 + 降低饱和度）
    let ciOriginal = CIImage(cgImage: original)
    guard let dimFilter = CIFilter(name: "CIColorControls") else { return nil }
    dimFilter.setValue(ciOriginal, forKey: kCIInputImageKey)
    dimFilter.setValue(0.25, forKey: kCIInputBrightnessKey)
    dimFilter.setValue(0.4, forKey: kCIInputSaturationKey)
    guard let fadedOriginal = dimFilter.outputImage else { return nil }

    // 5. 叠加
    guard let composite = CIFilter(name: "CISourceOverCompositing") else { return nil }
    composite.setValue(jetAlpha, forKey: kCIInputImageKey)
    composite.setValue(fadedOriginal, forKey: kCIInputBackgroundImageKey)

    guard let result = composite.outputImage else { return nil }
    return outCtx.createCGImage(result, from: result.extent)
}

/// "contour" overlay: 把显著性 mask 量化成多个等级（类似地图等高线），
/// 每个等级涂不同颜色（蓝→青→绿→黄→红），叠加在褪色底片上。
/// 比 overlay2 更清晰看出显著性"边界"，适合 agent 解析。
private func overlayContour(mask: CGImage, on original: CGImage) -> CGImage? {
    let origSize = original.width
    let origHeight = original.height

    // 1. 放大 mask
    let scaledMask: CGImage = {
        if mask.width == origSize && mask.height == origHeight {
            return mask
        }
        let ctx = CGContext(
            data: nil,
            width: origSize,
            height: origHeight,
            bitsPerComponent: 8,
            bytesPerRow: origSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: origSize, height: origHeight))
        return ctx.makeImage() ?? mask
    }()

    // 2. CPU 上绘制"等高带"
    let width = origSize
    let height = origHeight
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    guard let maskData = scaledMask.dataProvider?.data else { return nil }
    guard let maskBytesPtr = CFDataGetBytePtr(maskData) else { return nil }
    let maskBytesPerRow = scaledMask.bytesPerRow
    let maskBytesPerPixel = scaledMask.bitsPerPixel / 8

    // 5 个显著性等级：20%, 40%, 60%, 80%, 100%
    let levels: [(threshold: Float, color: (UInt8, UInt8, UInt8))] = [
        (0.20, (0,   0,   200)),
        (0.40, (0,   200, 220)),
        (0.60, (0,   200, 0)),
        (0.80, (240, 200, 0)),
        (1.00, (220, 0,   0)),
    ]

    for y in 0..<height {
        let my = (y * scaledMask.height) / max(height, 1)
        let maskRowStart = my * maskBytesPerRow
        let dstRowStart = y * bytesPerRow

        for x in 0..<width {
            let mx = (x * scaledMask.width) / max(width, 1)
            let maskVal = Float(maskBytesPtr[maskRowStart + mx * maskBytesPerPixel]) / 255.0

            // 找最大等级 (mask 落到哪个 band)
            var color: (UInt8, UInt8, UInt8)? = nil
            for lvl in levels {
                if maskVal >= lvl.threshold {
                    color = lvl.color
                }
            }
            // alpha = mask 亮度（让低显著性区透明，显示褪色底）
            let alpha = max(0, min(255, Int(maskVal * 255 * 1.4)))

            let i = dstRowStart + x * 4
            if let c = color {
                pixels[i + 0] = c.0
                pixels[i + 1] = c.1
                pixels[i + 2] = c.2
                pixels[i + 3] = UInt8(alpha)
            } else {
                pixels[i + 0] = 0
                pixels[i + 1] = 0
                pixels[i + 2] = 0
                pixels[i + 3] = 0
            }
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let ctx = CGContext(data: &pixels,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: info.rawValue),
          let contourImage = ctx.makeImage() else {
        return nil
    }

    // 3. 底片 = 原图褪色
    let ciOriginal = CIImage(cgImage: original)
    guard let dimFilter = CIFilter(name: "CIColorControls") else { return nil }
    dimFilter.setValue(ciOriginal, forKey: kCIInputImageKey)
    dimFilter.setValue(0.25, forKey: kCIInputBrightnessKey)
    dimFilter.setValue(0.4, forKey: kCIInputSaturationKey)
    guard let fadedOriginal = dimFilter.outputImage else { return nil }

    // 4. 叠加
    let ciContour = CIImage(cgImage: contourImage)
    guard let composite = CIFilter(name: "CISourceOverCompositing") else { return nil }
    composite.setValue(ciContour, forKey: kCIInputImageKey)
    composite.setValue(fadedOriginal, forKey: kCIInputBackgroundImageKey)

    guard let result = composite.outputImage else { return nil }
    let outCtx = CIContext()
    return outCtx.createCGImage(result, from: result.extent)
}

/// Jet colormap: t in 0..1 → (R, G, B) 5 段标准学术 colormap
private func jetRGB(_ t: Float) -> (UInt8, UInt8, UInt8) {
    let tt = max(0, min(1, t))  // clamp
    var r: Float = 0
    var g: Float = 0
    var b: Float = 0
    if tt < 0.125 {
        // navy → blue
        r = 0; g = 0; b = 0.5 + 4 * (tt + 0.125)
        b = min(b, 1)
    } else if tt < 0.375 {
        // blue → cyan
        r = 0; g = 4 * (tt - 0.125); b = 1
    } else if tt < 0.625 {
        // cyan → green (近似用 cyan→yellow split)
        r = 4 * (tt - 0.375); g = 1; b = 1 - 4 * (tt - 0.375)
    } else if tt < 0.875 {
        // green → yellow
        r = 1; g = 1 - 4 * (tt - 0.625); b = 0
    } else {
        r = 1; g = 0; b = 0
    }
    let ri = UInt8(min(max(r * 255, 0), 255))
    let gi = UInt8(min(max(g * 255, 0), 255))
    let bi = UInt8(min(max(b * 255, 0), 255))
    return (ri, gi, bi)
}

/// Build a 256x1 RGB lookup strip for the Jet colormap (blue → cyan → green → yellow → red).
private func makeJetColormapCGImage() -> CGImage {
    let width = 256
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow)

    for x in 0..<width {
        let t = Float(x) / Float(width - 1)
        let r: Float
        let g: Float
        let b: Float

        if t < 0.25 {
            b = 1; r = 0; g = 4 * t
        } else if t < 0.5 {
            r = 4 * (t - 0.25); g = 1; b = 1 - 4 * (t - 0.25)
        } else if t < 0.75 {
            r = 1; g = 1 - 4 * (t - 0.5); b = 0
        } else {
            r = 1; g = 0; b = 0
        }

        let i = x * 4
        pixels[i + 0] = UInt8(min(max(r * 255, 0), 255))
        pixels[i + 1] = UInt8(min(max(g * 255, 0), 255))
        pixels[i + 2] = UInt8(min(max(b * 255, 0), 255))
        pixels[i + 3] = 255
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let ctx = CGContext(data: &pixels,
                        width: width,
                        height: 1,
                        bitsPerComponent: 8,
                        bytesPerRow: bytesPerRow,
                        space: colorSpace,
                        bitmapInfo: info.rawValue)!
    return ctx.makeImage()!
}

/// Default output path under the system temp directory.
func defaultTempURL(_ prefix: String, _ ext: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("macvision-\(prefix)-\(ProcessInfo.processInfo.processIdentifier).\(ext)")
}

enum SalientCmd: Cmd {
    static let meta = CmdMeta(
        name: "salient",
        desc: "Produce a saliency heatmap (what the eye is drawn to)",
        longDesc: "Apple Vision produces a per-pixel saliency map (mask ~68×68 for big images). By default we save the raw mask as a grayscale PNG. With `--overlay` we render the heatmap on top of the image. Four styles: `--overlay` (default: 5-level topographic contour bands, clearest for boundary detection), `--overlay-red` (red-only, eye-grabbing), `--overlay-jet` (full Jet colormap: blue→cyan→green→yellow→red, academic standard), `--overlay-bw` (grayscale background + blue→red colormap, classic paper look).",
        tips: [
            "Pick `--overlay` (default) for the cleanest band contours — best for finding the 'edge' of where attention goes.",
            "Pick `--overlay-red` if you want the original colors slightly faded and the heatmap to dominate (eye-grabbing for users).",
            "Pick `--overlay-jet` for the full academic standard 5-segment Jet colormap (blue→cyan→green→yellow→red).",
            "Pick `--overlay-bw` for B&W background (classic saliency paper look).",
            "`--mode attention` (default) tells you where the eye is drawn. `--mode objectness` predicts where whole objects are likely to be.",
            "Use the overlay as a smart-crop candidate: crop to where red is densest.",
        ],
        synopsis: [
            "macvision salient <image> [--mode attention|objectness] [--output heat.png]",
            "macvision salient <image> --overlay --output cnt.png        # 5-band contour (default)",
            "macvision salient <image> --overlay-red --output hot.png   # red mask on faded bg",
            "macvision salient <image> --overlay-jet --output jet.png   # full Jet colormap",
            "macvision salient <image> --overlay-bw  --output bw.png    # B&W bg + blue→red",
        ],
        tldr: [
            ("Agent: get the raw grayscale heatmap PNG", "macvision salient photo.jpg --output heat.png"),
            ("Agent: get 5-level topographic contour bands (--overlay, default)", "macvision salient photo.jpg --overlay --output contour.png"),
            ("Agent: get faded original + red mask (--overlay-red, eye-grabbing)", "macvision salient photo.jpg --overlay-red --output hot.png"),
            ("Agent: get full Jet colormap blue→cyan→green→yellow→red (--overlay-jet, academic)", "macvision salient photo.jpg --overlay-jet --output jet.png"),
            ("Agent: get B&W background with blue→red mask (--overlay-bw, paper-style)", "macvision salient photo.jpg --overlay-bw --output bw.png"),
            ("Agent: smart crop candidate (use contour to find edges)", "macvision salient photo.jpg --overlay | jq .output"),
            ("Agent: where whole objects likely are (--mode objectness + --overlay-jet)", "macvision salient photo.jpg --mode objectness --overlay-jet"),
        ],
        opts: imageInputOpts + [
            OptMeta(name: "--mode", type: String.self, desc: "attention (default) | objectness"),
            OptMeta(name: "--output", type: String.self, desc: "Write the heatmap PNG here (default: a temp file)"),
            OptMeta(name: "--overlay", type: Bool.self, desc: "Render the heatmap on top of the image (default style: 5-level contour bands, like a topographic map)"),
            OptMeta(name: "--overlay-red", type: Bool.self, desc: "Red-only heatmap on faded original (eye-grabbing)"),
            OptMeta(name: "--overlay-jet", type: Bool.self, desc: "Full Jet colormap (blue→cyan→green→yellow→red) on faded original (academic standard heatmap)"),
            OptMeta(name: "--overlay-bw", type: Bool.self, desc: "Grayscale background + blue→red colormap (paper-style)"),
            OptMeta(name: "--crop", type: Bool.self, desc: "Smart-crop the original to the saliency bbox (smart-thumb) and report bbox in JSON"),
            OptMeta(name: "--padding", type: Double.self, desc: "Padding around crop bbox (0..1, default 0.05)"),
            OptMeta(name: "--size", type: String.self, desc: "Resize crop output: preset (square|story|reel|wide|linkedin-cover|twitter-header|yt-thumb|ig-landscape|ig-portrait|avatar|avatar-2x|pinterest) or WxH (e.g. 1080x1080)"),
            OptMeta(name: "--ocr", type: Bool.self, desc: "Run OCR and only return texts inside the saliency region (webpage dev: extract text from the salient area)"),
        ],
        args: [ArgMeta(name: "image", desc: "Image path, '-' for stdin base64, or use --clipboard/--screen")],
        run: { p in
            let (engine, src) = try loadEngine(p)
            let mode = p.opt("--mode") as String? ?? "attention"
            let output = (p.opt("--output") as String?).map { URL(fileURLWithPath: $0) }
            let red = p.opt("--overlay-red") as Bool? ?? false
            let jet = p.opt("--overlay-jet") as Bool? ?? false
            let bw = p.opt("--overlay-bw") as Bool? ?? false
            let default_ = p.opt("--overlay") as Bool? ?? false
            let crop = p.opt("--crop") as Bool? ?? false
            let padding = p.opt("--padding") as Double? ?? 0.05
            let sizeStr = p.opt("--size") as String?
            let cropSize = sizeStr.flatMap { parseSocialSize($0) }
            let ocr = p.opt("--ocr") as Bool? ?? false
            let overlay = red || jet || bw || default_
            let style: String = red ? "red" : (jet ? "jet" : (bw ? "bw" : "contour"))
            printJson(try runSalient(engine: engine, src: src, mode: mode, output: output, overlay: overlay, overlayStyle: style, crop: crop, cropPadding: padding, cropSize: cropSize, ocr: ocr))
        }
    )
}