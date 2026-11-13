import Foundation

func runSettingsTests() {
    check(
        MenuBarDisplay.iconOnly.showsIcon && !MenuBarDisplay.iconOnly.showsPercent && !MenuBarDisplay.iconOnly.showsBolt,
        "icon only shows just the mouse icon"
    )
    check(
        !MenuBarDisplay.percentWithBolt.showsIcon && MenuBarDisplay.percentWithBolt.showsPercent && MenuBarDisplay.percentWithBolt.showsBolt,
        "percent with bolt shows number and bolt without icon"
    )
    check(
        MenuBarDisplay.iconPercentWithBolt.showsIcon && MenuBarDisplay.iconPercentWithBolt.showsPercent && MenuBarDisplay.iconPercentWithBolt.showsBolt,
        "icon, percent and bolt are all shown"
    )
    check(
        MenuBarDisplay.iconPercent.showsIcon && MenuBarDisplay.iconPercent.showsPercent && !MenuBarDisplay.iconPercent.showsBolt,
        "icon and percent without bolt"
    )
    check(MenuBarDisplay.allCases.count == 4, "exactly four menu bar display options")

    let suite = "local.atka9.MouseBatteryBridge.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let fresh = AppSettings(defaults: defaults)
    check(fresh.menuBarDisplay == .iconPercentWithBolt, "default keeps the current icon, percent and bolt")

    fresh.menuBarDisplay = .percentWithBolt
    check(AppSettings(defaults: defaults).menuBarDisplay == .percentWithBolt, "choice persists across launches")

    defaults.set("unknown", forKey: AppSettings.menuBarDisplayKey)
    check(AppSettings(defaults: defaults).menuBarDisplay == .iconPercentWithBolt, "unknown stored value falls back to default")
}
