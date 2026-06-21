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
