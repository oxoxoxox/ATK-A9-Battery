import AppKit
import IOKit.hid
import ServiceManagement

private let nearcastGroupKey = "nearcastGroupID"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let batteryService = BatteryService()
    private let queryQueue = DispatchQueue(label: "local.atka9.MouseBatteryBridge.query")
    private lazy var model = StatusModel(deviceName: batteryService.fallbackDeviceName)
    private var statusController: StatusItemController?
    private let aboutWindow = AboutWindowController()
    private var isQuerying = false
    private var timer: Timer?
    private var powerSource: PowerSource?
    private var nearcast: NearcastSender?
    private var lastSnapshot: BatterySnapshot?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        statusController = StatusItemController(model: model, actions: makeActions())

        // 首次成功读数前没有 identity，startNearcastIfConfigured 会直接 return；
        // 读数成功后 handle 里会再次调用。
        startNearcastIfConfigured()
        DispatchQueue.main.async { [weak self] in self?.pollBattery() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.lastSnapshot == nil else { return }
            self.pollBattery()
        }
        timer = Timer.scheduledTimer(withTimeInterval: batteryService.queryInterval, repeats: true) { [weak self] _ in
            self?.pollBattery()
        }
    }

    private func makeActions() -> AppActions {
        AppActions(
            willOpenPanel: { [weak self] in self?.refreshSystemState() },
            refresh: { [weak self] in self?.pollBattery() },
            requestInputMonitoring: { [weak self] in self?.requestInputMonitoring() },
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            openLogFolder: { [weak self] in self?.openLogFolder() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { NSApp.terminate(nil) }
        )
    }

    // 没有可见菜单栏，主菜单只为关于窗口和面板提供 ⌘Q、⌘W 快捷键。
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let about = NSMenuItem(title: "关于 MouseBatteryBridge", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 MouseBatteryBridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        return mainMenu
    }

    @objc private func showAbout() {
        aboutWindow.show()
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    private var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    private func refreshSystemState() {
        model.inputMonitoringGranted = inputMonitoringGranted
        model.launchAtLogin = launchAtLoginEnabled
        model.airBattery = airBatteryState
    }

    // 以实际启动的 NearcastSender 为准：配置存在但发送器没启动，说明群组 ID 无效或还没读到第一次电量。
    private var airBatteryState: AirBatteryState {
        guard UserDefaults.standard.string(forKey: nearcastGroupKey) != nil else { return .notConfigured }
        if nearcast != nil { return .enabled }
        return lastSnapshot == nil ? .waitingForReading : .invalidGroup
    }

    private func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            refreshSystemState()
            return
        }

        let alert = NSAlert()
        alert.messageText = "需要输入监控权限"
        alert.informativeText = "请在系统设置的“隐私与安全性 → 输入监控”中允许 MouseBatteryBridge。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            MBLog.log("MouseBatteryBridge: \(error)")
        }
        refreshSystemState()
    }

    // HID 查询会阻塞等待回包（最长数秒），放到后台队列，避免卡住菜单栏和弹出面板。
    private func pollBattery() {
        guard !isQuerying else { return }
        isQuerying = true
        model.isRefreshing = true
        let service = batteryService
        queryQueue.async { [weak self] in
            let update = service.update()
            DispatchQueue.main.async { self?.handle(update) }
        }
    }

    private func handle(_ update: BatteryUpdate) {
        isQuerying = false
        model.apply(update)
        guard case .reading(let snapshot) = update else { return }
        lastSnapshot = snapshot
        do {
            if powerSource == nil { powerSource = try PowerSource() }
            try powerSource?.publish(identity: snapshot.identity, reading: snapshot.reading)
            startNearcastIfConfigured()
            nearcast?.update(snapshot.reading)
        } catch {
            MBLog.log("MouseBatteryBridge: \(error)")
        }
    }

    private func startNearcastIfConfigured() {
        guard nearcast == nil,
              let groupID = UserDefaults.standard.string(forKey: nearcastGroupKey),
              let identity = lastSnapshot?.identity
        else { return }
        guard let sender = NearcastSender(groupID: groupID, identity: identity, requestRefresh: refreshAirBattery) else { return }
        nearcast = sender
        sender.start()
        if let lastSnapshot { sender.update(lastSnapshot.reading) }
    }

    private func refreshAirBattery() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openAirBatteryRefresh()
        }
    }

    private func openAirBatteryRefresh() {
        guard let url = URL(string: "airbattery://reloadwingets") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error { MBLog.log("AirBattery 后台刷新失败：\(error)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard nearcast?.sendOffline() == true else { return }
        Thread.sleep(forTimeInterval: 0.3)
        openAirBatteryRefresh()
    }

    private func openLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([MBLog.logURL])
    }
}
