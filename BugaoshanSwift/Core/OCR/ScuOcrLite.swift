import Foundation
import CoreGraphics
import ImageIO

/// SCU 统一身份认证验证码识别（scu_ocr_lite Dart 包移植）。
/// 算法：去灰色干扰线 → 量化颜色聚类分割 4 字符 → 亮度阈值二值化 →
/// 6×8 最近邻缩放 → 与 36 类质心（48 像素 + 1 宽高比加权）做最近邻匹配。
enum ScuOcrLite {

    static let charset = "0123456789abcdefghijklmnopqrstuvwxyz"
    static let charH = 8
    static let charW = 6
    static let featDim = charH * charW          // 48
    static let featDimWithAR = featDim + 1      // 49
    static let maxAspectRatio: Double = 2.0
    static let arWeight: Double = 25.0
    static let captchaLength = 4

    private static let lineColorR = 111
    private static let lineColorG = 110
    private static let lineColorB = 112
    private static let lineTolerance = 10
    private static let quantizeStep = 8
    private static let charThreshold = 0.3

    // MARK: - 模型

    /// 质心模型：numClasses × featDimWithAR 个 Float（原始文件为每项 1 字节 /255）
    struct Model {
        let centroids: [Double]
        let numClasses: Int
        let stride: Int

        init?(bytes: [UInt8]) {
            guard bytes.count >= 12 else { return nil }
            let magic = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            guard magic == 0x43554353 else { return nil }  // "SCUC" 小端
            let version = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
            guard version == 1 else { return nil }
            let numClasses = Int(bytes[6])
            let stride = Int(bytes[7])
            guard numClasses > 0, stride > 0, bytes.count >= 12 + numClasses * stride else { return nil }
            self.numClasses = numClasses
            self.stride = stride
            self.centroids = (0..<(numClasses * stride)).map { Double(bytes[12 + $0]) / 255.0 }
        }

        func recognize(_ chars: [CharacterPatch]) -> String {
            guard chars.count == captchaLength else { return "" }
            var result = ""
            for ch in chars {
                var feat = [Double](repeating: 0, count: featDimWithAR)
                for i in 0..<charH {
                    for j in 0..<charW {
                        feat[i * charW + j] = ch.image[i][j]
                    }
                }
                let arNorm = min(max(ch.aspectRatio / maxAspectRatio, 0), 1)
                feat[featDim] = arNorm

                var bestIdx = 0
                var bestDist = Double.infinity
                for c in 0..<numClasses {
                    var pixelDist = 0.0
                    for i in 0..<featDim {
                        let diff = feat[i] - centroids[c * stride + i]
                        pixelDist += diff * diff
                    }
                    let arDiff = feat[featDim] - centroids[c * stride + featDim]
                    let dist = pixelDist + arWeight * arDiff * arDiff
                    if dist < bestDist {
                        bestDist = dist
                        bestIdx = c
                    }
                }
                let idx = charset.index(charset.startIndex, offsetBy: bestIdx)
                result.append(charset[idx])
            }
            return result
        }
    }

    // MARK: - 对外入口

    /// 解码图片数据（PNG/JPEG 等，走 ImageIO）后识别
    static func recognize(imageData: Data, model: Model) throws -> String {
        let image = try RGBImage.decode(imageData)
        return recognize(pixels: image, model: model)
    }

    /// 主入口：裁剪/缩放到 80×26 后分割识别
    static func recognize(pixels image: RGBImage, model: Model) -> String {
        let cropped: RGBImage
        if image.width >= 80 && image.height >= 26 {
            cropped = image.crop(width: 80, height: 26)
        } else {
            cropped = image.resizeNearest(width: 80, height: 26)
        }
        let chars = segmentCharacters(cropped)
        return model.recognize(chars)
    }

    /// 从 bundle 加载 model.scuocr
    static func loadBundledModel() -> Model? {
        guard let url = Bundle.main.url(forResource: "model", withExtension: "scuocr"),
              let bytes = try? [UInt8](Data(contentsOf: url)) else { return nil }
        return Model(bytes: bytes)
    }

    // MARK: - 分割（preprocess.dart 移植）

    struct CharacterPatch {
        var image: [[Double]]  // 8×6
        var aspectRatio: Double
        var xCenter: Int
    }

    static func segmentCharacters(_ src: RGBImage) -> [CharacterPatch] {
        // 去灰色干扰线：|(111,110,112) ± 10| → 白
        let w = src.width, h = src.height
        var cleaned = src
        for y in 0..<h {
            for x in 0..<w {
                let p = src[x, y]
                if abs(Int(p.r) - lineColorR) <= lineTolerance,
                   abs(Int(p.g) - lineColorG) <= lineTolerance,
                   abs(Int(p.b) - lineColorB) <= lineTolerance {
                    cleaned[x, y] = (255, 255, 255)
                }
            }
        }

        // 非白像素收集
        struct CharPixel {
            var x: Int, y: Int, r: Int, g: Int, b: Int
        }
        var charPixels: [CharPixel] = []
        for y in 0..<h {
            for x in 0..<w {
                let p = cleaned[x, y]
                if p.r <= 250 || p.g <= 250 || p.b <= 250 {
                    charPixels.append(CharPixel(x: x, y: y, r: Int(p.r), g: Int(p.g), b: Int(p.b)))
                }
            }
        }
        if charPixels.count < 20 { return [] }

        func quantize(_ v: Int) -> Int { (v / quantizeStep) * quantizeStep }

        // 量化颜色计数，取前 4
        var colorCounts: [String: Int] = [:]
        var colorPixels: [String: [Int]] = [:]
        for (i, cp) in charPixels.enumerated() {
            let key = "\(quantize(cp.r)),\(quantize(cp.g)),\(quantize(cp.b))"
            colorCounts[key, default: 0] += 1
            colorPixels[key, default: []].append(i)
        }
        if colorCounts.count < 4 { return [] }

        let sorted = colorCounts.sorted { $0.value > $1.value }
        let top4Keys = sorted.prefix(4).map(\.key)
        let top4Q: [[Int]] = top4Keys.map { key in
            key.split(separator: ",").map { Int($0) ?? 0 }
        }

        // 每个字符像素归到最近的前 4 色
        var labelMap = [[Int8]](repeating: [Int8](repeating: -1, count: w), count: h)
        for cp in charPixels {
            let q = [quantize(cp.r), quantize(cp.g), quantize(cp.b)]
            var bestLabel = 0
            var bestDist = 255 * 255 * 3
            for (i, c) in top4Q.enumerated() {
                let dr = q[0] - c[0]
                let dg = q[1] - c[1]
                let db = q[2] - c[2]
                let dist = dr * dr + dg * dg + db * db
                if dist < bestDist {
                    bestDist = dist
                    bestLabel = i
                }
            }
            labelMap[cp.y][cp.x] = Int8(bestLabel)
        }

        // 逐类求包围盒 + 二值化 + 缩放
        var patches: [CharacterPatch] = []
        for c in 0..<4 {
            var xs: [Int] = []
            var ys: [Int] = []
            for y in 0..<h {
                for x in 0..<w where labelMap[y][x] == Int8(c) {
                    xs.append(x)
                    ys.append(y)
                }
            }
            if xs.count < 5 { continue }

            let x1 = xs.min()!, x2 = xs.max()!
            let y1 = ys.min()!, y2 = ys.max()!
            let bw = x2 - x1 + 1
            let bh = y2 - y1 + 1

            var charBin = [[Double]](repeating: [Double](repeating: 0, count: bw), count: bh)
            for py in y1...y2 {
                for px in x1...x2 where labelMap[py][px] == Int8(c) {
                    let p = cleaned[px, py]
                    let gray = (0.299 * Double(p.r) + 0.587 * Double(p.g) + 0.114 * Double(p.b)) / 255.0
                    if (1.0 - gray) <= charThreshold { continue }
                    charBin[py - y1][px - x1] = 1.0
                }
            }
            var binary = [[Double]](repeating: [Double](repeating: 0, count: charW), count: charH)
            for sy in 0..<charH {
                for sx in 0..<charW {
                    let srcY = min(sy * bh / charH, bh - 1)
                    let srcX = min(sx * bw / charW, bw - 1)
                    binary[sy][sx] = charBin[srcY][srcX]
                }
            }

            let ar = Double(bw) / Double(max(bh, 1))
            let xCenter = Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded())
            patches.append(CharacterPatch(image: binary, aspectRatio: ar, xCenter: xCenter))
        }

        patches.sort { $0.xCenter < $1.xCenter }
        return patches
    }
}

// MARK: - RGB 像素缓冲

struct RGBImage {
    var width: Int
    var height: Int
    /// RGB 三字节一组
    var pixels: [UInt8]

    subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        get {
            let o = (y * width + x) * 3
            return (pixels[o], pixels[o + 1], pixels[o + 2])
        }
        set {
            let o = (y * width + x) * 3
            pixels[o] = newValue.r
            pixels[o + 1] = newValue.g
            pixels[o + 2] = newValue.b
        }
    }

    init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8) = (255, 255, 255)) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                self[x, y] = fill
            }
        }
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// ImageIO 解码（PNG/JPEG 等），绘制到 RGBA 后拷贝并翻转到左上原点
    static func decode(_ data: Data) throws -> RGBImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw OcrError.decodeFailed
        }
        let w = cg.width, h = cg.height
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let raw = ctx.data else { throw OcrError.decodeFailed }
        let rgba = raw.assumingMemoryBound(to: UInt8.self)
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        let image = RGBImage(width: w, height: h, pixels: rgb)
        return image.flipVertical()
    }

    func flipVertical() -> RGBImage {
        var out = RGBImage(width: width, height: height, pixels: pixels)
        for y in 0..<height {
            for x in 0..<width {
                out[x, y] = self[x, height - 1 - y]
            }
        }
        return out
    }

    func crop(width cw: Int, height ch: Int) -> RGBImage {
        var out = RGBImage(width: cw, height: ch)
        for y in 0..<min(ch, height) {
            for x in 0..<min(cw, width) {
                out[x, y] = self[x, y]
            }
        }
        return out
    }

    /// 最近邻缩放（对齐 Dart image 包 copyResize 默认行为）
    func resizeNearest(width nw: Int, height nh: Int) -> RGBImage {
        var out = RGBImage(width: nw, height: nh)
        for y in 0..<nh {
            for x in 0..<nw {
                let sx = min(x * width / nw, width - 1)
                let sy = min(y * height / nh, height - 1)
                out[x, y] = self[sx, sy]
            }
        }
        return out
    }

    /// 导出 PNG（测试用）。写入时补偿 CG 底朝向原点，产出标准左上原点 PNG，
    /// 与 decode 的翻转互为逆操作，可回环。
    func pngData() -> Data? {
        let rgba = UnsafeMutableRawPointer.allocate(byteCount: width * height * 4, alignment: 4)
        defer { rgba.deallocate() }
        let rgbaBytes = rgba.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let flippedRow = height - 1 - y
            for x in 0..<width {
                let src = (y * width + x) * 3
                let dst = (flippedRow * width + x) * 4
                rgbaBytes[dst] = pixels[src]
                rgbaBytes[dst + 1] = pixels[src + 1]
                rgbaBytes[dst + 2] = pixels[src + 2]
                rgbaBytes[dst + 3] = 255
            }
        }
        let ctx = CGContext(
            data: rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        guard let cg = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

enum OcrError: Error {
    case decodeFailed
}
