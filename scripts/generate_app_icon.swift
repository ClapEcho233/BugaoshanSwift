// 生成“不高山下”App 图标：米色底 + 锦红 mountain.2.fill（关于页同款符号，上下倒置）
// 山形左右出血越过画布、底线水平锚定 —— 截断即图标边界本身，呈全景山景构图
// 使用 AppKit 渲染 SF Symbol（宽裕画布防内部裁切 + 像素扫描取字形紧包围盒，精确定位）
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

/// 渲染 SF Symbol 为带 alpha 的 CGImage，并返回字形像素紧包围盒（画布坐标，y 向上）。
/// 画布取标称尺寸 3 倍见方，保证任何宽形符号都不会在渲染阶段被裁切；
/// 先以模板黑绘制，再用 sourceAtop 整面填充着色（仅命中字形像素）。
func renderSymbol(_ name: String, ink: UInt32, pointSize: CGFloat) -> (image: CGImage, bbox: CGRect) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        fatalError("SF Symbol 不存在: \(name)")
    }
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let sym = base.withSymbolConfiguration(cfg) else {
        fatalError("符号配置失败: \(name)")
    }
    let cw = Int(pointSize * 3), ch = Int(pointSize * 3)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: cw, height: ch)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 居中按符号自身尺寸绘制（保持纵横比）
    let r = NSRect(x: (CGFloat(cw) - sym.size.width) / 2,
                   y: (CGFloat(ch) - sym.size.height) / 2,
                   width: sym.size.width, height: sym.size.height)
    sym.draw(in: r)
    // 着色：只覆盖已绘制的字形像素
    nsColor(ink).set()
    NSRect(x: 0, y: 0, width: cw, height: ch).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()

    guard let cg = rep.cgImage else { fatalError("符号位图转换失败") }
    // 扫描 alpha 通道取紧包围盒（去除符号画布的透明边距，供精确定位）
    guard let data = rep.bitmapData else { fatalError("无法读取位图") }
    let bpr = rep.bytesPerRow
    var minX = cw, maxX = 0, minY = ch, maxY = 0
    for y in 0..<ch {
        for x in 0..<cw {
            if data[y * bpr + x * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    let bbox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    return (cg, bbox)
}

// 预渲染符号（三套配色同几何，各着各色）
let pointSize: CGFloat = 1600
let lightSymbol = renderSymbol("mountain.2.fill", ink: lightPalette.ink, pointSize: pointSize)
let darkSymbol = renderSymbol("mountain.2.fill", ink: darkPalette.ink, pointSize: pointSize)
let tintedSymbol = renderSymbol("mountain.2.fill", ink: tintedPalette.ink, pointSize: pointSize)
print(String(format: "字形包围盒: %.0f×%.0f (宽高比 1:%.3f)", lightSymbol.bbox.width, lightSymbol.bbox.height, lightSymbol.bbox.height / lightSymbol.bbox.width))

func drawIcon(_ p: Palette, symbol: (image: CGImage, bbox: CGRect), size: Int = 1024) -> CGImage {
    let ctx = makeContext(size)
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)

    // 背景：对角线柔和渐变（两端同色即纯色）
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [p.bgTop, p.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: S, y: S), options: [])

    // —— 全景出血构图 ——
    // 字形宽度取画布 1.3 倍：左右各出血 15%，山坡自然越出图标边界
    let targetW = S * 1.3
    let scale = targetW / symbol.bbox.width
    let targetH = symbol.bbox.height * scale
    // 旋转后底线（原字形顶边）锚定在画布顶部 20% 处，倒峰向下延伸
    let anchorFromTop: CGFloat = 0.20
    let preRotationBaselineY = S * anchorFromTop
    // 字形目标框（旋转前坐标系：正常朝向、底线即 bbox 底边）
    let dstGlyph = CGRect(x: (S - targetW) / 2, y: preRotationBaselineY,
                          width: targetW, height: targetH)
    // 符号整图对应矩形 = 字形框向外补偿 bbox 原点缩放
    let dstImage = CGRect(x: dstGlyph.minX - symbol.bbox.minX * scale,
                          y: dstGlyph.minY - symbol.bbox.minY * scale,
                          width: CGFloat(symbol.image.width) * scale,
                          height: CGFloat(symbol.image.height) * scale)

    // 整体旋转 180°（「不高山下」品牌方向：倒山、底线在上）
    ctx.saveGState()
    ctx.translateBy(x: S / 2, y: S / 2)
    ctx.rotate(by: .pi)
    ctx.translateBy(x: -S / 2, y: -S / 2)
    ctx.interpolationQuality = .none
    ctx.draw(symbol.image, in: dstImage)
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
