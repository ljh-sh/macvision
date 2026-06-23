// Render small text images for the macvision OCR test dataset.
// Uses NSFont.systemFont so CoreText cascades to CJK fallback fonts — every
// script renders. Regenerate with:  swift testdata/render.swift
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import AppKit

func render(_ text: String, _ outFile: String) {
    let W = 1100, H = 260
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // System font cascades to CJK fallbacks, so all scripts render.
    let font = NSFont.systemFont(ofSize: 48)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let attr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = CGPoint(x: 40, y: 100)
    CTLineDraw(line, ctx)

    guard let img = ctx.makeImage() else { exit(1) }
    let url = URL(fileURLWithPath: outFile)
    guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
    print("wrote", outFile)
}

render("The quick brown fox jumps over the lazy dog. macvision 2026.", "testdata/en.png")
render("macvision 视觉识别测试。你好，世界！中文 OCR 验证。", "testdata/cn.png")
render("macvision OCRテスト。こんにちは、世界！日本語の文字認識。", "testdata/ja.png")
render("macvision OCR 测试 / 你好世界 / Hello World 2026", "testdata/mixed.png")
