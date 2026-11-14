import AppKit

// 菜单栏按钮的渲染规则。只依赖 AppKit 与值类型，便于在没有界面的测试里断言。
enum MenuBarButton {
    static func configure(
        _ button: NSButton,
        icon: NSImage?,
        mode: MenuBarDisplay,
        reading: BatteryReading?,
        stale: Bool,
        toolTip: String
    ) {
        // 没有读数时，带图标的模式只显示图标（与旧版一致）；纯文字模式用“--”占位，否则按钮会空白、无法点击。
        let showsText = mode.showsPercent && (reading != nil || !mode.showsIcon)
        // 先设置文字再设置图标位置：AppKit 修改 title 时会改写 imagePosition。
        if showsText {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = attributedTitle(reading, stale: stale, showsBolt: mode.showsBolt, font: font)
        } else {
            button.title = ""
        }
        button.image = mode.showsIcon ? icon : nil
        button.imagePosition = !mode.showsIcon ? .noImage : (showsText ? .imageLeading : .imageOnly)
        button.toolTip = toolTip
    }

    static func attributedTitle(_ reading: BatteryReading?, stale: Bool, showsBolt: Bool, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if reading == nil || stale {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        let title = NSMutableAttributedString(string: reading.map { "\($0.percent)%" } ?? "--", attributes: attributes)
        if showsBolt, let reading {
            let state: BoltState = stale ? .unknown : (reading.isCharging ? .charging : .idle)
            guard let bolt = boltImage(font: font, state: state) else { return title }
            let attachment = NSTextAttachment()
            attachment.image = bolt
            attachment.bounds = CGRect(x: 0, y: -1, width: bolt.size.width, height: bolt.size.height)
            title.append(NSAttributedString(string: " ", attributes: attributes))
            title.append(NSAttributedString(attachment: attachment))
        }
        return title
    }

    private enum BoltState {
        case charging
        case idle
        case unknown
    }

    // 充电时为绿色实心闪电；未充电或未连接（充电状态未知）时为灰色空心闪电。颜色固定，不随菜单栏主题变化，所以不是模板图标。
    private static func boltImage(font: NSFont, state: BoltState) -> NSImage? {
        let charging = state == .charging
        let color: NSColor = charging ? .systemGreen : .secondaryLabelColor
        let description: String
        switch state {
        case .charging: description = "充电中"
        case .idle: description = "未充电"
        case .unknown: description = "未连接，充电状态未知"
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 3, weight: .bold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        let image = NSImage(
            systemSymbolName: charging ? "bolt.fill" : "bolt",
            accessibilityDescription: description
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }
}
