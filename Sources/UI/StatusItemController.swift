import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: StatusModel
    private let actions: AppActions
    private let popover = NSPopover()
    private let panelHost: NSHostingController<StatusPanelView>
    private var closingEventTime: TimeInterval?
    private var cancellable: AnyCancellable?

    init(model: StatusModel, actions: AppActions) {
        self.model = model
        self.actions = actions
        panelHost = NSHostingController(rootView: StatusPanelView(model: model, actions: actions))
        super.init()

        panelHost.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panelHost
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
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
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
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        popover.performClose(nil)
        actions.willOpenPanel()
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: button)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let summary = NSMenuItem(title: model.summary, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        menu.addItem(menuItem("立即刷新", #selector(refreshNow), key: "r"))
        menu.addItem(.separator())
        let permission = menuItem(
            model.inputMonitoringGranted ? "输入监控已授权" : "输入监控授权…",
            #selector(requestInputMonitoring)
        )
        permission.isEnabled = !model.inputMonitoringGranted
        menu.addItem(permission)
        let launch = menuItem("开机启动", #selector(toggleLaunchAtLogin))
        launch.state = model.launchAtLogin ? .on : .off
        menu.addItem(launch)
        menu.addItem(menuItem("打开日志文件夹…", #selector(openLogFolder)))
        menu.addItem(.separator())
        menu.addItem(menuItem("关于 MouseBatteryBridge", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出", #selector(quit), key: "q"))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refreshNow() { actions.refresh() }
    @objc private func requestInputMonitoring() { actions.requestInputMonitoring() }
    @objc private func toggleLaunchAtLogin() { actions.toggleLaunchAtLogin() }
    @objc private func openLogFolder() { actions.openLogFolder() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func quit() { actions.quit() }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // NSPopover 在鼠标按下时若点在外部即会关闭；同一次按下触发的点击动作只负责关闭，不再重开。
        if let timestamp = NSApp.currentEvent?.timestamp, timestamp == closingEventTime { return }
        actions.willOpenPanel()
        // 先让布局反映刚更新的状态，preferredContentSize 才是最新高度；之后内容变化由 NSPopover 持续跟随。
        panelHost.view.layoutSubtreeIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.bringToFront()
    }

    func popoverWillClose(_ notification: Notification) {
        closingEventTime = NSApp.currentEvent?.timestamp
    }
}
