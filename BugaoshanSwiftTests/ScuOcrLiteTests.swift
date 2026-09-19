import XCTest
@testable import BugaoshanSwift

/// ScuOcrLite 移植测试：模型解析、分割管线、图像编解码回环。
final class ScuOcrLiteTests: XCTestCase {

    private func bundledModel() throws -> ScuOcrLite.Model {
        let url = Bundle(for: type(of: self)).url(forResource: "model", withExtension: "scuocr")
            ?? Bundle.main.url(forResource: "model", withExtension: "scuocr")
        // 测试 bundle 没有该资源时退回主 bundle（host app）
        guard let url, let bytes = try? [UInt8](Data(contentsOf: url)),
              let model = ScuOcrLite.Model(bytes: bytes) else {
            throw XCTSkip("model.scuocr 不在测试可及的 bundle 中")
        }
        return model
    }

    // MARK: - 模型解析

    func testModelParsing() throws {
        let model = try bundledModel()
        XCTAssertEqual(model.numClasses, 36)
        XCTAssertEqual(model.stride, 49)
        XCTAssertEqual(model.centroids.count, 36 * 49)
    }

    func testModelRejectsBadMagic() {
        XCTAssertNil(ScuOcrLite.Model(bytes: [0, 0, 0, 0, 1, 0, 36, 49]))
        XCTAssertNil(ScuOcrLite.Model(bytes: []))
    }

    // MARK: - 识别

    func testRecognizeWrongPatchCountReturnsEmpty() throws {
        let model = try bundledModel()
        let patch = ScuOcrLite.CharacterPatch(
            image: [[Double]](repeating: [Double](repeating: 0, count: 6), count: 8),
            aspectRatio: 1, xCenter: 0)
        XCTAssertEqual(model.recognize([patch]), "")
        XCTAssertEqual(model.recognize([]), "")
    }

    func testRecognizeFourPatchesProducesFourChars() throws {
        let model = try bundledModel()
        let patches = (0..<4).map { i in
            ScuOcrLite.CharacterPatch(
                image: [[Double]](repeating: [Double](repeating: Double(i % 2), count: 6), count: 8),
                aspectRatio: 1, xCenter: i * 10)
        }
        let result = model.recognize(patches)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.allSatisfy { ScuOcrLite.charset.contains($0) })
    }

    // MARK: - 分割管线（合成验证码）

    /// 合成 80×26 图：白底、4 个不同颜色的实心色块 + 灰色干扰线
    private func syntheticCaptcha() -> RGBImage {
        var image = RGBImage(width: 80, height: 26)
        let colors: [(UInt8, UInt8, UInt8)] = [
            (200, 30, 30),    // 红
            (30, 160, 40),    // 绿
            (40, 60, 200),    // 蓝
            (170, 140, 20),   // 黄
        ]
        for (i, color) in colors.enumerated() {
            let x0 = 6 + i * 18
            for y in 6..<20 {
                for x in x0..<(x0 + 10) {
                    image[x, y] = color
                }
            }
        }
        // 干扰线：接近 (111,110,112) 的灰
        for x in 0..<80 {
            image[x, x % 26] = (110, 111, 113)
        }
        return image
    }

    func testSegmentCharactersFindsFour() {
        let chars = ScuOcrLite.segmentCharacters(syntheticCaptcha())
        XCTAssertEqual(chars.count, 4)
        // 按 x 升序
        XCTAssertTrue(zip(chars, chars.dropFirst()).allSatisfy { $0.xCenter < $1.xCenter })
        // 实心 10×14 色块的宽高比
        XCTAssertEqual(chars[0].aspectRatio, 10.0 / 14.0, accuracy: 0.001)
    }

    func testFullPipelineOnSyntheticImage() throws {
        let model = try bundledModel()
        let image = syntheticCaptcha()
        let result = ScuOcrLite.recognize(pixels: image, model: model)
        XCTAssertEqual(result.count, 4)
    }

    func testGrayLineRemoved() {
        // 纯干扰线图（无字符）应分割为空
        var image = RGBImage(width: 80, height: 26)
        for x in 0..<80 {
            for y in 0..<26 {
                image[x, y] = (110, 111, 113)
            }
        }
        XCTAssertTrue(ScuOcrLite.segmentCharacters(image).isEmpty)
    }

    // MARK: - 图像编解码回环

    func testPNGRoundTrip() throws {
        let image = syntheticCaptcha()
        guard let png = image.pngData() else {
            return XCTFail("PNG 编码失败")
        }
        let decoded = try RGBImage.decode(png)
        XCTAssertEqual(decoded.width, 80)
        XCTAssertEqual(decoded.height, 26)
        // 内容一致（解码回环保持像素）
        XCTAssertEqual(decoded.pixels, image.pixels)
    }

    func testDecodeFromRecognizeEntry() throws {
        let model = try bundledModel()
        let image = syntheticCaptcha()
        guard let png = image.pngData() else {
            return XCTFail("PNG 编码失败")
        }
        let viaData = try ScuOcrLite.recognize(imageData: png, model: model)
        let viaPixels = ScuOcrLite.recognize(pixels: image, model: model)
        XCTAssertEqual(viaData, viaPixels)
    }
}
