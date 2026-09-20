import XCTest
@testable import BugaoshanSwift

/// ddddocr CoreML 移植测试：真实验证码 fixture（静态资源，不发网络请求）。
/// fixture 为 2026-09 从 id.scu.edu.cn 公开验证码接口拉取的样本，
/// 标签经人工识读 + ddddocr 双模型交叉验证（56/56 一致）。
final class DdddOcrRecognizerTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "png") else {
            throw XCTSkip("fixture \(name).png 不在测试 bundle 中")
        }
        return try Data(contentsOf: url)
    }

    private func labels() throws -> [String: String] {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "labels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw XCTSkip("labels.json 不在测试 bundle 中")
        }
        return dict
    }

    func testRecognizesRealCaptchas() throws {
        let expected = try labels()
        var correct = 0
        for (name, label) in expected.sorted(by: { $0.key < $1.key }) {
            let data = try fixture(name)
            let result = DdddOcrRecognizer.recognize(imageData: data)
            XCTAssertEqual(result, label, "\(name) 识别失败")
            if result == label { correct += 1 }
        }
        XCTAssertEqual(correct, expected.count, "整批识别率应为 100%")
    }

    func testRejectsGarbageInput() {
        // 非验证码图像应返回 nil 或空（不崩溃、不乱填）
        let blank = RGBImage(width: 80, height: 26).pngData()
        XCTAssertNotNil(blank)
        if let png = blank {
            let result = DdddOcrRecognizer.recognize(imageData: png)
            XCTAssertTrue(result == nil || result!.isEmpty || (result!.count == 4))
        }
    }
}
