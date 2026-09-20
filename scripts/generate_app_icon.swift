// 生成“不高山下”App 图标：米色底 + 锦红 mountain.2.fill（关于页同款符号，上下倒置）
// 使用 AppKit 渲染 SF Symbol（保持纵横比、不拉伸变形），sourceAtop 着色后合成到背景
// 画布保持满幅方形、无 alpha 通道 —— iOS 系统会自动应用圆角遮罩，预切圆角违反 Apple 规范
// 运行：swift scripts/generate_app_icon.swift
import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S: CGFloat = 1024

struct Palette {
    let bgTop: CGColor
    let bgBottom: CGColor
    let ink: UInt32
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

func nsColor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// 默认：米色底 + 锦红（设计稿原色）
let lightPalette = Palette(bgTop: rgb(0xF5EFE5), bgBottom: rgb(0xF5EFE5), ink: 0xC50000)
// 深色：暗底 + 提亮红
let darkPalette = Palette(bgTop: rgb(0x241E1B), bgBottom: rgb(0x15110F), ink: 0xE0483A)
// 着色：灰阶（系统按亮度着色）
let tintedPalette = Palette(bgTop: rgb(0xA8A8A8), bgBottom: rgb(0x787878), ink: 0xFFFFFF)

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // App 图标不允许 alpha 通道
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

/// 将 SF Symbol 渲染为指定颜色 CGImage：居中、原始尺寸（保持纵横比，不拉伸），
/// 先以模板黑绘制，再用 sourceAtop 整面填充着色（仅命中字形像素）
func symbolImage(_ name: String, ink: UInt32, pointSize: CGFloat, canvas: Int) -> CGImage {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        fatalError("SF Symbol 不存在: \(name)")
    }
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let sym = base.withSymbolConfiguration(cfg) else {
        fatalError("符号配置失败: \(name)")
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 居中按符号自身尺寸绘制（避免方形 rect 拉伸宽形山形符号）
    let origin = NSPoint(x: (CGFloat(canvas) - sym.size.width) / 2,
                         y: (CGFloat(canvas) - sym.size.height) / 2)
    sym.draw(in: NSRect(origin: origin, size: sym.size))
    // 着色：只覆盖已绘制的字形像素
    nsColor(ink).set()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

// 预渲染符号（三套配色共用同一几何，各着各色）
let symbolCanvas = 2048
let lightSymbol = symbolImage("mountain.2.fill", ink: lightPalette.ink, pointSize: 1600, canvas: symbolCanvas)
let darkSymbol = symbolImage("mountain.2.fill", ink: darkPalette.ink, pointSize: 1600, canvas: symbolCanvas)
let tintedSymbol = symbolImage("mountain.2.fill", ink: tintedPalette.ink, pointSize: 1600, canvas: symbolCanvas)

func drawIcon(_ p: Palette, symbol: CGImage, size: Int = 1024) -> CGImage {
    let ctx = makeContext(size)
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)

    // 背景：对角线柔和渐变（两端同色即纯色）
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [p.bgTop, p.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: S, y: S), options: [])

    // 山形符号居中、上下倒置 180°（「不高山下」品牌方向）
    let side: CGFloat = 860
    let rect = CGRect(x: (S - side) / 2, y: (S - side) / 2, width: side, height: side)
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.rotate(by: .pi)
    ctx.translateBy(x: -rect.midX, y: -rect.midY)
    ctx.interpolationQuality = .none
    ctx.draw(symbol, in: rect)
    ctx.restoreGState()

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

let light = drawIcon(lightPalette, symbol: lightSymbol)
let dark = drawIcon(darkPalette, symbol: darkSymbol)
let tinted = drawIcon(tintedPalette, symbol: tintedSymbol)

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
