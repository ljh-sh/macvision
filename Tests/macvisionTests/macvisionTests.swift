import XCTest
@testable import macvision

final class MacvisionTests: XCTestCase {

    // Geometry: Vision uses normalized bottom-left origin. The engine should
    // flip to top-left origin pixels and provide a normalized top-left box too.
    func testPixelBoxFlipsOrigin() {
        // Top-left quadrant of a 100x100 image. Vision normalized
        // (minX=0, minY=0.5, w=0.5, h=0.5) is the TOP-left quadrant because
        // Vision y grows upward.
        let big = makeImage(w: 100, h: 100)!
        let engine = VisionEngine(image: big, orientation: .up)
        let quad = engine.pixelBox(CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        XCTAssertEqual(quad, [0, 0, 50, 50])

        // Full normalized rect → whole image.
        let full = engine.pixelBox(CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(full, [0, 0, 100, 100])
    }

    func testNormBoxFlipsOrigin() {
        XCTAssertEqual(VisionEngine.normBox(CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
                       [0.0, 0.0, 0.5, 0.5])
    }

    func testSourceLabels() {
        XCTAssertEqual(ImageLoader.label(.file(URL(fileURLWithPath: "/tmp/x.png"))), "/tmp/x.png")
        XCTAssertEqual(ImageLoader.label(.stdin), "stdin")
        XCTAssertEqual(ImageLoader.label(.clipboard), "clipboard")
        XCTAssertEqual(ImageLoader.label(.screen), "screen")
    }

    func testDaemonEncodeProducesCompactJSON() {
        let s = daemonEncode(["ok": true, "count": 3, "name": "ocr"])
        XCTAssertTrue(s.contains("\"ok\":true"))
        XCTAssertTrue(s.contains("\"count\":3"))
        XCTAssertFalse(s.contains(" "), "compact JSON has no spaces")
    }

    func testDaemonRejectsMalformedRequest() {
        let s = daemonHandleRequest("not json at all")
        XCTAssertTrue(s.contains("\"ok\":false"))
        XCTAssertTrue(s.contains("error"))
    }

    func testDaemonRejectsMissingAction() {
        let s = daemonHandleRequest("{\"image\":\"/tmp/x.png\"}")
        XCTAssertTrue(s.contains("\"ok\":false"))
    }

    func testDoctorReportsEnvironment() {
        let d = runDoctor()
        XCTAssertEqual(d["ok"] as? Bool, true)
        XCTAssertNotNil(d["macos_version"])
        XCTAssertNotNil(d["architecture"])
        XCTAssertNotNil(d["capabilities"])
    }

    // MARK: - language resolution

    func testBuiltinLangPresets() {
        XCTAssertEqual(builtinLangPresets["all"]?.first, "zh-Hans")
        XCTAssertTrue(builtinLangPresets["cjk"]?.contains("ja-JP") ?? false)
    }

    func testExpandLangTokensMixesPresetAndCode() {
        // cjk preset + a raw code flatten in order.
        let r = expandLangTokens(["cjk", "en-US"])
        XCTAssertEqual(r, ["zh-Hans", "zh-Hant", "ja-JP", "ko-KR", "en-US"])
    }

    func testResolveLangsListDefaultsToAll() {
        XCTAssertEqual(resolveLangsList([]), builtinLangPresets["all"])
    }

    func testResolveLangsListExplicit() {
        XCTAssertEqual(resolveLangsList(["ja-JP"]), ["ja-JP"])
    }

    // MARK: - OCR integration (testdata/)

    private func testDataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // macvisionTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // macvision/ (repo root)
            .appendingPathComponent("testdata/\(name).png")
    }

    /// OCR `testdata/<name>.png` with `langs` and return the joined recognized text.
    private func ocrText(_ name: String, langs: [String]) throws -> String {
        let url = testDataURL(name)
        let img = try ImageLoader.load(.file(url))
        let engine = VisionEngine(image: img, orientation: .up)
        let r = try runOCR(engine: engine, src: .file(url), langs: langs,
                           level: .accurate, minConfidence: 0, top: 0,
                           usesLanguageCorrection: true)
        return (r["texts"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined(separator: " ") ?? ""
    }

    func testOcrReadsEnglish() throws {
        let t = try ocrText("en", langs: ["en-US"])
        XCTAssertTrue(t.contains("quick brown fox"), "en OCR: \(t)")
    }

    func testOcrReadsChinese() throws {
        let t = try ocrText("cn", langs: ["zh-Hans", "en-US"])
        XCTAssertTrue(t.contains("你好") || t.contains("视觉") || t.contains("中文"), "cn OCR: \(t)")
    }

    func testOcrReadsJapaneseExplicit() throws {
        // Vision prioritizes the FIRST CJK language; ja-JP must lead (or be alone)
        // or kana is starved by an earlier zh-Hans. See mneme auto-language doc.
        let t = try ocrText("ja", langs: ["ja-JP"])
        XCTAssertTrue(t.contains("テスト") || t.contains("こんにちは"), "ja OCR: \(t)")
    }

    func testOcrBroadDefaultReadsChinese() throws {
        // The broad 'all' default is zh-first, so Chinese reads fine.
        let t = try ocrText("cn", langs: builtinLangPresets["all"] ?? [])
        XCTAssertTrue(t.contains("你好") || t.contains("视觉"), "cn broad OCR: \(t)")
    }

    // MARK: - helpers

    private func makeImage(w: Int, h: Int) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
