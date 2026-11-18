import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: StatusModel
    private let actions: AppActions
    private let popover = NSPopover()
    private let panelHost: NSHostingController<StatusPanelView>
    private let appearanceObserver = AppearanceObserverView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    private var closingEventTime: TimeInterval?
    private var cancellable: AnyCancellable?

    // 菜单栏的明暗由壁纸决定，可能与本应用的 appearance 不同，所以监听按钮实际生效的 appearance。
    private final class AppearanceObserverView: NSView {
        var onChange: (() -> Void)?

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            onChange?()
        }
    }

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
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            appearanceObserver.onChange = { [weak self] in
                DispatchQueue.main.async { self?.renderButton() }
            }
            button.addSubview(appearanceObserver)
        }

        // objectWillChange 早于属性写入，切回主队列后再读取即为最新值。
        cancellable = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.renderButton() }
        renderButton()
    }

    private func renderButton() {
        guard let button = statusItem.button else { return }
        let icon = MenuBarIcon.image(
            percent: model.reading?.percent,
            isCharging: model.reading?.isCharging ?? false,
            stale: model.isStale,
            appearance: button.effectiveAppearance
        )
        icon.accessibilityDescription = model.summary
        MenuBarButton.configure(button, icon: icon, toolTip: model.summary)
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
