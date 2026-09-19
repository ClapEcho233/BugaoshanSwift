// 生成“不高山上”App 图标：极简圆角红色山（锦绣红 #B4100A），暖白底
// 圆角做在山形上；画布保持满幅方形 —— iOS 系统会自动应用圆角遮罩，预切圆角违反 Apple 规范
// 运行：swift scripts/generate_app_icon.swift
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S: CGFloat = 1024

struct Palette {
    let bgTop: CGColor
    let bgBottom: CGColor
    let mountain: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// 默认：暖白底 + 锦绣红山
let lightPalette = Palette(bgTop: rgb(0xFBF8F2), bgBottom: rgb(0xF0EADD), mountain: rgb(0xB4100A))
// 深色：暗底 + 提亮的锦绣红
let darkPalette = Palette(bgTop: rgb(0x272120), bgBottom: rgb(0x161211), mountain: rgb(0xCE3A30))
// 着色：灰阶（系统按亮度着色）
let tintedPalette = Palette(bgTop: rgb(0xA8A8A8), bgBottom: rgb(0x787878), mountain: rgb(0xFFFFFF))

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // App 图标不允许 alpha 通道
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // 本管线中 user y 直接对应 PNG 行号（自上而下），按 y 向下设计坐标作画
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func drawIcon(_ p: Palette, size: Int = 1024) -> CGImage {
    let ctx = makeContext(size)
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)

    // 背景：对角线柔和渐变
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [p.bgTop, p.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: S, y: S), options: [])

    // 圆角山：三角形路径 + 同色描边（圆角连接）实现圆角顶点
    let r: CGFloat = 56
    let apex = CGPoint(x: 512, y: 336)
    let baseL = CGPoint(x: 216, y: 656)
    let baseR = CGPoint(x: 808, y: 656)
    let path = CGMutablePath()
    path.move(to: apex)
    path.addLine(to: baseR)
    path.addLine(to: baseL)
    path.closeSubpath()
    // 视觉占位：底边 y 656、外缘最宽 ~160..864（69% 宽度），保持在中央 80% 安全区内
    ctx.setFillColor(p.mountain)
    ctx.setStrokeColor(p.mountain)
    ctx.setLineWidth(r * 2)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.addPath(path)
    ctx.strokePath()

    return ctx.makeImage()!
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

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let appSet = root.appendingPathComponent("BugaoshanSwift/Assets.xcassets/AppIcon.appiconset")
let widgetSet = root.appendingPathComponent("CourseWidget/Assets.xcassets/AppIcon.appiconset")

let light = drawIcon(lightPalette)
let dark = drawIcon(darkPalette)
let tinted = drawIcon(tintedPalette)

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
