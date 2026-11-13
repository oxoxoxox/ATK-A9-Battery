import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: StatusModel
    private let settings: AppSettings
    private let actions: AppActions
    private let popover = NSPopover()
    private let panelHost: NSHostingController<StatusPanelView>
    private lazy var menuBarIcon: NSImage? = {
        let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseBatteryBridge")
        image?.isTemplate = true
        return image
    }()
    private var closingEventTime: TimeInterval?
    private var cancellable: AnyCancellable?

    init(model: StatusModel, settings: AppSettings, actions: AppActions) {
        self.model = model
        self.settings = settings
        self.actions = actions
        panelHost = NSHostingController(rootView: StatusPanelView(model: model, actions: actions))
        super.init()

        panelHost.sizingOptions = [.preferredContentSize]
        popover.contentViewController = panelHost
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        }

        // objectWillChange 早于属性写入，切回主队列后再读取即为最新值。
        cancellable = Publishers.Merge(model.objectWillChange, settings.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.renderButton() }
        renderButton()
    }

    private func renderButton() {
        guard let button = statusItem.button else { return }
        Self.configure(
            button,
            icon: menuBarIcon,
            mode: settings.menuBarDisplay,
            reading: model.reading,
            stale: model.isStale,
            toolTip: model.summary
        )
    }

    // 按显示模式设置按钮。数值类模式在没有读数时显示占位的“--”，避免按钮变成空白而无法点击。
    static func configure(
        _ button: NSButton,
        icon: NSImage?,
        mode: MenuBarDisplay,
        reading: BatteryReading?,
        stale: Bool,
        toolTip: String
    ) {
        button.image = mode.showsIcon ? icon : nil
        button.imagePosition = mode.showsIcon ? (mode.showsPercent ? .imageLeading : .imageOnly) : .noImage
        if mode.showsPercent {
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.attributedTitle = menuBarTitle(reading, stale: stale, showsBolt: mode.showsBolt, font: font)
        } else {
            button.title = ""
        }
        button.toolTip = toolTip
    }

    static func menuBarTitle(_ reading: BatteryReading?, stale: Bool, showsBolt: Bool, font: NSFont) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if reading == nil || stale {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        let text = reading.map { "\($0.percent)%" } ?? "--"
        let title = NSMutableAttributedString(string: text, attributes: attributes)
        // 过期读数无法判断当前是否在充电，所以不显示闪电。
        if showsBolt, !stale, let reading, reading.isCharging, let bolt = boltImage(font: font) {
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
        menu.addItem(menuItem("设置…", #selector(showSettings), key: ","))
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
    @objc private func showSettings() { actions.showSettings() }
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
