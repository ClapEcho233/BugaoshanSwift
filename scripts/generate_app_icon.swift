// 生成「不高山下」App 图标：取原版「不高山上」App 图标，整体旋转 180°（倒山，品牌方向）
// - Light/Dark：倒置原图平铺白底（iOS 图标禁 alpha，忠实保留原版观感）
// - Tinted：灰阶版本（系统按亮度着色，Apple 推荐提供灰阶图）
// 图标源文件：scripts/original-app-icon.png（1024×1024，取自 Flutter 版 Runner 资产；
//   缺失时回退到 Flutter 原仓库绝对路径，并建议重新复制一份入库）
// 画布保持满幅方形、无 alpha 通道 —— iOS 系统会自动应用圆角遮罩，预切圆角违反 Apple 规范
// 运行：swift scripts/generate_app_icon.swift
import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S: CGFloat = 1024

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // App 图标不允许 alpha 通道
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

// MARK: - 读取原版图标

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent()

let candidates = [
    scriptDir.appendingPathComponent("original-app-icon.png"),
    URL(fileURLWithPath: "/Users/clapecho233/Files/Work/Bugaoshan/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"),
]
guard let srcURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
    fatalError("找不到原版图标，尝试过: \(candidates.map(\.path))")
}
guard let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("无法读取原版图标: \(srcURL.path)")
}
print("图标源: \(srcURL.path)")

// MARK: - 倒置 + 平铺

/// 整体旋转 180° 并平铺到白底（去除 alpha 通道）。
/// 180° 旋转是精确像素映射，无重采样损失；非 1024 源会按画布等比缩放绘制。
func flippedOnWhite(_ image: CGImage) -> CGImage {
    let ctx = makeContext(Int(S))
    // 白底（原版图标本身为白底，平铺仅为去除 alpha）
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    // 整体旋转 180°（「不高山下」品牌方向：倒山）
    ctx.saveGState()
    ctx.translateBy(x: S / 2, y: S / 2)
    ctx.rotate(by: .pi)
    ctx.translateBy(x: -S / 2, y: -S / 2)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
    ctx.restoreGState()
    return ctx.makeImage()!
}

/// 去饱和为灰阶（供 Tinted 变体，系统按亮度统一着色）。
func desaturate(_ image: CGImage) -> CGImage {
    let ci = CIImage(cgImage: image)
    let gray = ci.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    guard let out = CIContext().createCGImage(gray, from: ci.extent) else {
        fatalError("灰阶转换失败")
    }
    return out
}

// MARK: - 导出

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("无法创建 \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("写入失败 \(path)") }
    print("✓ \(path)")
}

func resize(_ image: CGImage, to px: Int) -> CGImage {
    let ctx = makeContext(px)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

let appSet = root.appendingPathComponent("BugaoshanSwift/Assets.xcassets/AppIcon.appiconset")
let widgetSet = root.appendingPathComponent("CourseWidget/Assets.xcassets/AppIcon.appiconset")

let light = flippedOnWhite(original)
let dark = light          // 深色模式沿用原版白底画面，忠实还原原版图标
let tinted = desaturate(light)

for set in [appSet, widgetSet] {
    savePNG(light, to: set.appendingPathComponent("AppIcon.png").path)
    savePNG(dark, to: set.appendingPathComponent("AppIconDark.png").path)
    savePNG(tinted, to: set.appendingPathComponent("AppIconTinted.png").path)
}

// widget 图标集含 mac 尺寸，由 1024 光学缩小
let macSizes: [(String, Int)] = [
    ("AppIconMac16.png", 16), ("AppIconMac32.png", 32), ("AppIconMac64.png", 64),
    ("AppIconMac128.png", 128), ("AppIconMac256.png", 256), ("AppIconMac512.png", 512),
    ("AppIconMac1024.png", 1024),
]
for m in macSizes {
    savePNG(resize(light, to: m.1), to: widgetSet.appendingPathComponent(m.0).path)
}

print("完成")
