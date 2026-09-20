// 生成“不高山下”App 图标：米色底 + 锦红大小双山（大山描线、小山实心）
// 几何与设计稿 MountainAppIcon.svg 一致：24 单位坐标系居中缩放到 832×832
// 画布保持满幅方形 —— iOS 系统会自动应用圆角遮罩，预切圆角违反 Apple 规范
// 运行：swift scripts/generate_app_icon.swift
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S: CGFloat = 1024

struct Palette {
    let bgTop: CGColor
    let bgBottom: CGColor
    let ink: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// 默认：米色底 + 锦红双山（设计稿原色）
let lightPalette = Palette(bgTop: rgb(0xF5EFE5), bgBottom: rgb(0xF5EFE5), ink: rgb(0xC50000))
// 深色：暗底 + 提亮红
let darkPalette = Palette(bgTop: rgb(0x241E1B), bgBottom: rgb(0x15110F), ink: rgb(0xE0483A))
// 着色：灰阶（系统按亮度着色）
let tintedPalette = Palette(bgTop: rgb(0xA8A8A8), bgBottom: rgb(0x787878), ink: rgb(0xFFFFFF))

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // App 图标不允许 alpha 通道
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // 标准位图上下文为 y 向上；PNG 编码后 y=0 位于图像顶行
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func drawIcon(_ p: Palette, size: Int = 1024) -> CGImage {
    let ctx = makeContext(size)
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)

    // 背景：对角线柔和渐变（两端同色即纯色）
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [p.bgTop, p.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: S, y: S), options: [])

    // 双山：SVG transform translate(96 96) scale(832/24)；SVG 是 y 向下坐标系
    // 「不高山下」山体上下倒置：标准做法是 translate(0,24) scale(1,-1) 翻回 y 向上，
    // 再叠加绕 y=12 的镜像（y → 24−y）即为倒置 —— 两次翻转抵消，
    // 故直接在 y 向下坐标系绘制，山峰自然朝下
    ctx.translateBy(x: 96, y: 96)
    ctx.scaleBy(x: 832.0 / 24.0, y: 832.0 / 24.0)
    ctx.setStrokeColor(p.ink)
    ctx.setFillColor(p.ink)
    ctx.setLineWidth(1.5)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    // 大山（描线不填充）：左坡 → 平顶 → 右坡 → 右底角 → 底边（左侧开放）
    let big = CGMutablePath()
    big.move(to: CGPoint(x: 9, y: 12.42))
    big.addLine(to: CGPoint(x: 13.83, y: 5.66))
    big.addLine(to: CGPoint(x: 14.16, y: 5.66))
    big.addLine(to: CGPoint(x: 21.8, y: 18.11))
    big.addLine(to: CGPoint(x: 21.63, y: 18.42))
    big.addLine(to: CGPoint(x: 13, y: 18.42))
    ctx.addPath(big)
    ctx.strokePath()

    // 小山（实心 + 描边）
    let small = CGMutablePath()
    small.move(to: CGPoint(x: 5.84, y: 12.65))
    small.addLine(to: CGPoint(x: 2.2, y: 18.11))
    small.addLine(to: CGPoint(x: 2.37, y: 18.42))
    small.addLine(to: CGPoint(x: 10.16, y: 18.42))
    small.addLine(to: CGPoint(x: 10.31, y: 18.10))
    small.addLine(to: CGPoint(x: 6.16, y: 12.64))
    small.closeSubpath()
    ctx.addPath(small)
    ctx.fillPath()
    ctx.addPath(small)
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
