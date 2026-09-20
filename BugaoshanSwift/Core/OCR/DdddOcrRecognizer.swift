import Foundation
import CoreML
import CoreGraphics

/// ddddocr（MIT，github.com/sml2h3/ddddocr）common CRNN 模型的 CoreML 移植。
/// 模型由 ONNX float 版手工移植至 PyTorch（数值对齐 onnxruntime）后经 coremltools 转换，
/// 在 356 张真机验证码样本上与源模型 100% 一致。
///
/// 管线（与 ddddocr 预处理一致）：
/// 去灰色干扰线 → 等比缩放至 64×196（高质量插值）→ ITU-R 601-2 灰度 → /255
/// → CoreML 推理（25 时间步 × 8210 类 logits）→ CTC 解码（去连续重复、去 blank）
/// → 结果必须为 4 位 [0-9a-z]，否则返回 nil（上层回退旧模型 / 重试）。
enum DdddOcrRecognizer {

    static let inputH = 64
    static let inputW = 196
    static let seqlen = 25

    /// 模型单例（线程安全懒加载；MLModel 本身线程安全）
    private static let model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "DdddOcr", withExtension: "mlmodelc") else {
            return nil
        }
        let conf = MLModelConfiguration()
        conf.computeUnits = .all
        return try? MLModel(contentsOf: url, configuration: conf)
    }()

    /// 字符集（8210 项，索引即类别；索引 0 为 CTC blank）
    private static let charset: [String] = {
        guard let url = Bundle.main.url(forResource: "ddddocr_charset", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data),
              list.count > 1 else {
            return []
        }
        return list
    }()

    /// 识别验证码图片数据（PNG/JPEG），失败或低可信时返回 nil
    static func recognize(imageData: Data) -> String? {
        guard let model else { return nil }
        let provider: MLDictionaryFeatureProvider
        do {
            provider = makeProvider(imageData: imageData)
        } catch {
            #if DEBUG
            print("[DdddOcr] provider 构造失败: \(error)")
            #endif
            return nil
        }
        let features: MLFeatureProvider
        do {
            features = try model.prediction(from: provider)
        } catch {
            #if DEBUG
            print("[DdddOcr] 推理失败: \(error)")
            #endif
            return nil
        }
        guard let outputName = model.modelDescription.outputDescriptionsByName.keys.first,
              let out = features.featureValue(for: outputName)?.multiArrayValue else {
            return nil
        }
        return ctcDecode(out)
    }

    // MARK: - 预处理

    private static func makeProvider(imageData: Data) -> MLDictionaryFeatureProvider {
        // 布局 [1, 1, H, W]，行优先
        var pixels = [Float32](repeating: 0, count: inputH * inputW)
        if let image = try? RGBImage.decode(imageData) {
            preprocess(image: image, into: &pixels)
        }
        let arr = try! MLMultiArray(shape: [1, 1, NSNumber(value: inputH), NSNumber(value: inputW)],
                                    dataType: .float32)
        for (i, v) in pixels.enumerated() { arr[i] = NSNumber(value: v) }
        let inputName = model?.modelDescription.inputDescriptionsByName.keys.first ?? "x"
        return try! MLDictionaryFeatureProvider(dictionary: [inputName: arr])
    }

    /// 去灰线 → Lanczos3 缩放 64×196（纯浮点实现，跨平台像素完全一致）→ 灰度归一化
    /// 注：不能用 CG 插值——macOS/iOS 的缩放核不同，而模型对插值敏感（已实测）
    private static func preprocess(image: RGBImage, into pixels: inout [Float32]) {
        // 1) 去灰色干扰线（#6f6e70 ± 10）
        let cleaned = removeGrayLine(image)

        // 2) 分离式 Lanczos3：先纵后横，逐轴钳位+舍入（与验证过的参考实现一致）
        let mid = lanczosAxis(cleaned, outCount: inputH, vertical: true)
        let rgb2 = lanczosAxis(RGBImage(width: image.width, height: inputH, pixels: mid),
                               outCount: inputW, vertical: false)

        // 3) ITU-R 601-2 灰度 + /255（浮点，不再舍入）
        for y in 0..<inputH {
            for x in 0..<inputW {
                let o = (y * inputW + x) * 3
                let gray = 0.299 * Double(rgb2[o]) + 0.587 * Double(rgb2[o + 1]) + 0.114 * Double(rgb2[o + 2])
                pixels[y * inputW + x] = Float32(gray / 255.0)
            }
        }
    }

    private static func removeGrayLine(_ image: RGBImage) -> RGBImage {
        var cleaned = image
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = image[x, y]
                if abs(Int(p.r) - 111) <= 10, abs(Int(p.g) - 110) <= 10, abs(Int(p.b) - 112) <= 10 {
                    cleaned[x, y] = (255, 255, 255)
                }
            }
        }
        return cleaned
    }

    /// 单轴 Lanczos3 重采样，输入输出均为 RGB 三字节交错；返回钳位舍入后的 RGB
    private static func lanczosAxis(_ src: RGBImage, outCount: Int, vertical: Bool) -> [UInt8] {
        let inCount = vertical ? src.height : src.width
        let fixed = vertical ? src.width : src.height
        guard inCount != outCount else { return src.pixels }

        func sinc(_ x: Double) -> Double { x == 0 ? 1 : sin(.pi * x) / (.pi * x) }
        func kernel(_ x: Double) -> Double { abs(x) >= 3 ? 0 : sinc(x) * sinc(x / 3) }

        var out = [UInt8](repeating: 0, count: fixed * outCount * 3)
        for o in 0..<outCount {
            let center = (Double(o) + 0.5) * Double(inCount) / Double(outCount)
            let xmin = Int(floor(center - 3)), xmax = Int(ceil(center + 3))
            var weights: [Double] = []
            var indices: [Int] = []
            for i in xmin...xmax {
                let ii = min(max(i, 0), inCount - 1)
                weights.append(kernel(Double(i) + 0.5 - center))
                indices.append(ii)
            }
            let sum = weights.reduce(0, +)
            guard sum != 0 else { continue }

            var acc = [Double](repeating: 0, count: fixed * 3)
            for (k, ii) in indices.enumerated() {
                let w = weights[k] / sum
                for f in 0..<fixed {
                    let srcOff = vertical ? (ii * fixed + f) * 3 : (f * src.width + ii) * 3
                    acc[f * 3] += w * Double(src.pixels[srcOff])
                    acc[f * 3 + 1] += w * Double(src.pixels[srcOff + 1])
                    acc[f * 3 + 2] += w * Double(src.pixels[srcOff + 2])
                }
            }
            for idx in 0..<(fixed * 3) {
                let c = idx / 3, k = idx % 3
                let v = min(max((acc[idx] + 0.5).rounded(.down), 0), 255)
                let dstOff = vertical ? (o * fixed + c) * 3 + k : (c * outCount + o) * 3 + k
                out[dstOff] = UInt8(v)
            }
        }
        return out
    }

    // MARK: - CTC 解码

    /// 输出 (25, 1, 8210)：逐时间步 argmax → 去连续重复 → 去 blank(0) → 查字符集；
    /// 必须恰好 4 个 [0-9a-z] 字符才认为可信
    private static func ctcDecode(_ out: MLMultiArray) -> String? {
        guard !charset.isEmpty else { return nil }
        let count = seqlen
        var indices: [Int] = []
        indices.reserveCapacity(count)

        // 通用形状解析：按 stride 找最后一维（类别维）
        let shape = out.shape.map { $0.intValue }
        let classDim = shape.last ?? 0
        guard classDim == charset.count, shape.count >= 2 else { return nil }
        let seqLen = shape.count >= 3 ? shape[shape.count - 3] : shape[0]
        // MLMultiArray 线性下标：假定 (S, 1, C) 行主序
        for s in 0..<min(seqLen, count) {
            var best = 0
            var bestVal = -Double.infinity
            let base = s * classDim
            for c in 0..<classDim {
                let v = out[base + c].doubleValue
                if v > bestVal {
                    bestVal = v
                    best = c
                }
            }
            indices.append(best)
        }

        var chars: [Character] = []
        var prev = -1
        for idx in indices {
            defer { prev = idx }
            guard idx != prev, idx != 0, idx < charset.count else { continue }
            let s = charset[idx]
            guard s.count == 1, let ch = s.first else { continue }
            chars.append(ch)
        }
        let text = String(chars).lowercased()
        guard text.count == 4,
              text.allSatisfy({ c in (c >= "0" && c <= "9") || (c >= "a" && c <= "z") }) else {
            return nil
        }
        return text
    }
}
