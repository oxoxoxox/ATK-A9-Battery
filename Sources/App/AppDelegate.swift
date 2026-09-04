import AppKit
import IOKit.hid
import ServiceManagement

private let nearcastGroupKey = "nearcastGroupID"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let batteryService = BatteryService()
    private var timer: Timer?
    private var powerSource: PowerSource?
    private var nearcast: NearcastSender?
    private var lastSnapshot: BatterySnapshot?
    private var launchItem: NSMenuItem?
    private var permissionItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        menu.delegate = self
        let permission = NSMenuItem(title: permissionTitle, action: #selector(requestInputMonitoring), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        permissionItem = permission
        let launch = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        launchItem = launch
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseBatteryBridge")
        statusItem.button?.image?.isTemplate = true

        // 首次成功读数前没有 identity，startNearcastIfConfigured 会直接 return；
        // 读数成功后 updateBattery 里会再次调用。
        startNearcastIfConfigured()
        DispatchQueue.main.async { [weak self] in self?.updateBattery() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.lastSnapshot == nil else { return }
            self.updateBattery()
        }
        timer = Timer.scheduledTimer(withTimeInterval: batteryService.queryInterval, repeats: true) { [weak self] _ in
            self?.updateBattery()
        }
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    private var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    private var permissionTitle: String { inputMonitoringGranted ? "输入监控授权（已授权）" : "输入监控授权…" }

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem?.title = permissionTitle
        permissionItem?.isEnabled = !inputMonitoringGranted
        launchItem?.state = launchAtLoginEnabled ? .on : .off
    }

    @objc private func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { return }

        let alert = NSAlert()
        alert.messageText = "需要输入监控权限"
        alert.informativeText = "请在系统设置的“隐私与安全性 → 输入监控”中允许 MouseBatteryBridge。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            launchItem?.state = launchAtLoginEnabled ? .on : .off
        } catch {
            NSLog("MouseBatteryBridge: \(error)")
        }
    }

    private func updateBattery() {
        guard let snapshot = batteryService.update() else { return }
        lastSnapshot = snapshot
        do {
            if powerSource == nil { powerSource = try PowerSource() }
            try powerSource?.publish(identity: snapshot.identity, reading: snapshot.reading)
            startNearcastIfConfigured()
            nearcast?.update(snapshot.reading)
        } catch {
            NSLog("MouseBatteryBridge: \(error)")
        }
    }

    private func startNearcastIfConfigured() {
        guard nearcast == nil,
              let groupID = UserDefaults.standard.string(forKey: nearcastGroupKey),
              let identity = lastSnapshot?.identity ?? batteryService.lastSnapshot?.identity
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
            if let error { NSLog("AirBattery 后台刷新失败：\(error)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard nearcast?.sendOffline() == true else { return }
        Thread.sleep(forTimeInterval: 0.3)
        openAirBatteryRefresh()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
