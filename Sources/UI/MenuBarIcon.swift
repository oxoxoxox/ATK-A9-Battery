import AppKit

// 菜单栏图标：外圈电量环、居中鼠标、底部百分比；充电时环顶放绿色闪电并镂空背后的环。
// 颜色随系统明暗和电量档位变化，所以不能作为模板图标，需要在明暗切换时重绘。
enum MenuBarIcon {
    enum Tone: Equatable {
        case charging
        case normal
        case low
        case critical
        case unknown
    }

    static let size = NSSize(width: 22, height: 22)

    static func tone(percent: Int?, isCharging: Bool, stale: Bool) -> Tone {
        guard let percent, !stale else { return .unknown }
        if isCharging { return .charging }
        if percent <= 20 { return .critical }
        if percent <= 40 { return .low }
        return .normal
    }

    static func image(
        percent: Int?,
        isCharging: Bool,
        stale: Bool,
        appearance: NSAppearance,
        canvas: CGFloat = 22,
        scale: CGFloat = 2
    ) -> NSImage {
        let target = NSSize(width: canvas, height: canvas)
        let image = NSImage(size: target)
        image.isTemplate = false
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width * scale),
            pixelsHigh: Int(target.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }
        rep.size = target

        let tone = tone(percent: percent, isCharging: isCharging, stale: stale)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        // 绘制坐标按 22pt 菜单栏画布写死，面板里用更大的 canvas 时整体缩放。
        context?.cgContext.scaleBy(x: target.width / size.width, y: target.height / size.height)
        appearance.performAsCurrentDrawingAppearance {
            draw(percent: percent, tone: tone, appearance: appearance)
        }
        NSGraphicsContext.restoreGraphicsState()

        image.addRepresentation(rep)
        return image
    }

    // MARK: - 绘制

    private struct Palette {
        let foreground: NSColor
        let track: NSColor
        let accent: NSColor
    }

    private static func palette(tone: Tone, isDark: Bool) -> Palette {
        // 未充电时用黑（浅色菜单栏）或暖白（深色菜单栏），保证在任意壁纸下都能看清。
        let foreground = isDark
            ? NSColor(srgbRed: 0.96, green: 0.94, blue: 0.89, alpha: 1)
            : NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        let dimmed = isDark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
        let track = isDark
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.24)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.16)

        let accent: NSColor
        switch tone {
        case .charging:
            accent = isDark
                ? NSColor(srgbRed: 0.24, green: 0.84, blue: 0.38, alpha: 1)
                : NSColor(srgbRed: 0.10, green: 0.62, blue: 0.24, alpha: 1)
        case .low:
            accent = isDark
                ? NSColor(srgbRed: 0.85, green: 0.68, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.62, green: 0.47, blue: 0.08, alpha: 1)
        case .critical:
            accent = isDark
                ? NSColor(srgbRed: 1.00, green: 0.42, blue: 0.26, alpha: 1)
                : NSColor(srgbRed: 0.85, green: 0.24, blue: 0.11, alpha: 1)
        case .normal:
            accent = foreground
        case .unknown:
            accent = dimmed
        }
        return Palette(foreground: tone == .unknown ? dimmed : foreground, track: track, accent: accent)
    }

    private static func draw(percent: Int?, tone: Tone, appearance: NSAppearance) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let palette = palette(tone: tone, isDark: isDark)

        let center = CGPoint(x: size.width / 2, y: ringCenterY)
        let fraction = CGFloat(min(max(percent ?? 0, 0), 100)) / 100
        let sweep = 360 - bottomGap

        // 底部留缺口放数字；轨道和高亮用同一个缺口，进度从左下角（0%）顺时针经过顶部，到右下角（100%）结束。
        strokeArc(center: center, radius: ringRadius, start: 270 - bottomGap / 2, sweep: sweep, width: ringLineWidth, color: palette.track, context: context)
        if fraction > 0 {
            strokeArc(center: center, radius: ringRadius, start: 270 - bottomGap / 2, sweep: sweep * fraction, width: ringLineWidth, color: palette.accent, context: context)
        }

        let text = percent.map(String.init) ?? "--"
        // 闪电盖在环上时只擦闪电背后的环，数字则落在底部缺口里，不切开缺口两端的半圆。
        if tone == .charging {
            context.saveGState()
            context.setBlendMode(.clear)
            let boltHole = CGRect(x: center.x - 2.9, y: 16.9, width: 5.8, height: 5.8)
            context.addPath(CGPath(roundedRect: boltHole, cornerWidth: 2.9, cornerHeight: 2.9, transform: nil))
            context.fillPath()
            context.restoreGState()
        }

        // 开洞会擦掉已画内容，所以鼠标、数字和闪电放在开洞之后。
        drawMouse(center: CGPoint(x: center.x, y: 12.5), color: palette.foreground)
        drawPercent(text, color: palette.foreground)
        if tone == .charging {
            drawBolt(center: CGPoint(x: center.x, y: 19.5), color: palette.accent)
        }
    }

    private static func strokeArc(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        sweep: CGFloat,
        width: CGFloat,
        color: NSColor,
        context: CGContext
    ) {
        guard sweep > 0 else { return }
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: start * .pi / 180, endAngle: (start - sweep) * .pi / 180, clockwise: true)
        context.strokePath()
        context.restoreGState()
    }

    // 圆环几何：底部缺口放大到 90°（左下角到右下角），三位数也有足够宽度。
    private static let ringCenterY: CGFloat = 11.8
    private static let ringRadius: CGFloat = 8.35
    private static let ringLineWidth: CGFloat = 1.7
    private static let bottomGap: CGFloat = 90
    private static let percentBaseline: CGFloat = 1.3

    private static func drawPercent(_ text: String, color: NSColor) {
        let font = percentFont(text)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = text.size(withAttributes: attributes).width
        text.draw(at: NSPoint(x: size.width / 2 - width / 2, y: percentBaseline), withAttributes: attributes)
    }

    private static func percentFont(_ text: String) -> NSFont {
        let base = NSFont.systemFont(ofSize: text.count > 2 ? 4.8 : 5.2, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private static func drawMouse(center: CGPoint, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 6.8, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let mouse = NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        mouse.isTemplate = false
        let bounds = mouse.size
        mouse.draw(in: NSRect(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2, width: bounds.width, height: bounds.height))
    }

    // 闪电用自绘路径：SF Symbol 在小尺寸下留白太多，自定义形状能精确卡进环顶缺口。
    private static func drawBolt(center: CGPoint, color: NSColor) {
        let scale: CGFloat = 5.0 / 5.4
        let points = [
            CGPoint(x: 0.405, y: 2.70),
            CGPoint(x: -2.295, y: -0.54),
            CGPoint(x: -0.135, y: -0.54),
            CGPoint(x: -0.405, y: -2.70),
            CGPoint(x: 2.295, y: 0.54),
            CGPoint(x: 0.135, y: 0.54),
        ]
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: center.x + point.x * scale, y: center.y + point.y * scale)
            if index == 0 {
                path.move(to: scaled)
            } else {
                path.addLine(to: scaled)
            }
        }
        path.closeSubpath()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }
}
