import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: StatusModel
    private let actions: AppActions
    private let popover = NSPopover()
    private var closedAt: Date?
    private var cancellable: AnyCancellable?

    init(model: StatusModel, actions: AppActions) {
        self.model = model
        self.actions = actions
        super.init()

        let host = NSHostingController(rootView: StatusPanelView(model: model, actions: actions))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseBatteryBridge")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp])
        }

        // objectWillChange 早于属性写入，切回主队列后再读取即为最新值。
        cancellable = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.renderButton() }
        renderButton()
    }

    private func renderButton() {
        guard let button = statusItem.button else { return }
        if let reading = model.reading {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = Self.menuBarTitle(reading, stale: model.isStale, font: font)
        } else {
            button.title = ""
        }
        button.toolTip = model.summary
    }

    static func menuBarTitle(_ reading: BatteryReading, stale: Bool, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if stale {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        let title = NSMutableAttributedString(string: "\(reading.percent)%", attributes: attributes)
        if reading.isCharging, let bolt = boltImage(font: font) {
            let attachment = NSTextAttachment()
            attachment.image = bolt
            attachment.bounds = CGRect(x: 0, y: -1, width: bolt.size.width, height: bolt.size.height)
            title.append(NSAttributedString(string: " ", attributes: attributes))
            title.append(NSAttributedString(attachment: attachment))
        }
        return title
    }

    private static func boltImage(font: NSFont) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize - 3, weight: .bold)
        let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "充电中")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    @objc private func buttonClicked() {
        togglePanel()
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // 面板因点击状态栏按钮而关闭后，紧随其后的鼠标抬起会再次进入这里，忽略它以免刚关又重开。
        if let closedAt, Date().timeIntervalSince(closedAt) < 0.25 { return }
        actions.willOpenPanel()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.bringToFront()
    }

    func popoverWillClose(_ notification: Notification) {
        closedAt = Date()
    }
}
