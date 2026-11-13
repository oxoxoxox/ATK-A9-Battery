import Foundation

func runStatusModelTests() {
    let identity = DeviceIdentity(
        displayName: "测试鼠标",
        appName: "MouseBatteryBridge",
        accessoryIdentifier: "TEST",
        deviceType: "Mouse",
        receiverVendorID: 0,
        accessoryProductID: 0
    )
    func reading(_ percent: Int, _ charging: Bool = false) -> BatteryUpdate {
        .reading(BatterySnapshot(identity: identity, reading: BatteryReading(percent: percent, isCharging: charging)))
    }
    func model(permission: Bool = true) -> StatusModel {
        let m = StatusModel(deviceName: "测试鼠标")
        m.inputMonitoringGranted = permission
        return m
    }

    let initial = model()
    check(initial.headline.text == "正在查找接收器", "initial headline is searching")
    check(initial.summary == "正在查找接收器…", "initial summary is searching")
    check(initial.reading == nil && !initial.isStale, "initial model has no reading and is not stale")

    let searchingWithoutPermission = model(permission: false)
    check(searchingWithoutPermission.headline.text == "正在查找接收器", "searching does not claim missing permission yet")

    let normal = model()
    normal.isRefreshing = true
    normal.apply(reading(72))
    check(!normal.isRefreshing, "apply clears refreshing flag")
    check(normal.headline.text == "电量正常", "72% without charging is normal")
    check(normal.ringTone == .good, "normal reading uses good tone")
    check(!normal.isStale, "fresh reading is not stale")
    check(normal.summary == "测试鼠标 · 72%", "summary shows device and percent")

    let charging = model()
    charging.apply(reading(85, true))
    check(charging.headline.text == "充电中", "charging headline")
    check(charging.summary == "测试鼠标 · 85% · 充电中", "summary mentions charging")

    let low = model()
    low.apply(reading(15))
    check(low.headline.text == "电量偏低" && low.ringTone == .warning, "15% is low")

    let critical = model()
    critical.apply(reading(6))
    check(critical.headline.text == "电量极低" && critical.ringTone == .critical, "6% is critical")

    let stale = model()
    stale.apply(reading(64))
    stale.apply(.notFound)
    check(stale.isStale, "receiver lost keeps reading as stale")
    check(stale.headline.text == "未连接接收器", "stale headline says disconnected")
    check(stale.detail.hasPrefix("上次读数"), "stale detail shows last reading time")
    check(stale.ringTone == .neutral, "stale ring is neutral")
    check(stale.summary == "测试鼠标 · 64%（未连接）", "stale summary is marked")

    let notFound = model()
    notFound.apply(.notFound)
    check(notFound.headline.text == "未连接接收器", "not found headline")
    check(notFound.detail == "请确认 2.4G 接收器已插好", "not found without history shows hint")
    check(notFound.summary == "测试鼠标 · 未连接", "not found summary")

    let failed = model()
    failed.apply(.failed("2 秒内未收到有效电量回包"))
    check(failed.headline.text == "读取失败", "failed headline")
    check(failed.detail == "2 秒内未收到有效电量回包", "failed detail is the error message")
    check(failed.summary == "测试鼠标 · 读取失败", "failed summary")

    let failedAfterReading = model()
    failedAfterReading.apply(reading(64))
    failedAfterReading.apply(.failed("2 秒内未收到有效电量回包"))
    check(failedAfterReading.isStale, "failure after a reading keeps it as stale")
    check(failedAfterReading.headline.text == "读取失败", "failure after a reading says read failed")
    check(failedAfterReading.summary == "测试鼠标 · 64%（读取失败）", "failure summary does not say disconnected")

    let noPermission = model(permission: false)
    noPermission.apply(.failed("打开 HID 接收器失败"))
    check(noPermission.headline.text == "需要输入监控授权", "missing permission takes precedence over failure")

    let notFoundWithoutPermission = model(permission: false)
    notFoundWithoutPermission.apply(.notFound)
    check(notFoundWithoutPermission.headline.text == "需要输入监控授权", "missing permission explains a not-found result")

    let permissionButConnected = model(permission: false)
    permissionButConnected.apply(reading(72))
    check(permissionButConnected.headline.text == "电量正常", "live reading wins over stale permission flag")

    check(AirBatteryState.notConfigured.label == "未配置", "AirBattery not configured label")
    check(AirBatteryState.waitingForReading.label == "等待读数", "AirBattery waiting label")
    check(AirBatteryState.enabled.label == "已启用", "AirBattery enabled label")
    check(AirBatteryState.invalidGroup.label == "群组 ID 无效", "AirBattery invalid group label")
}
