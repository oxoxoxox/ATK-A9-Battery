import AppKit

func runMenuBarButtonTests() {
    let bolt = "\u{FFFC}"
    let icon = NSImage(size: NSSize(width: 16, height: 16))
    let charging = BatteryReading(percent: 85, isCharging: true)
    let idle = BatteryReading(percent: 72, isCharging: false)

    func render(_ mode: MenuBarDisplay, _ reading: BatteryReading?, stale: Bool = false) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        MenuBarButton.configure(button, icon: icon, mode: mode, reading: reading, stale: stale, toolTip: "提示")
        return button
    }

    let defaultCharging = render(.iconPercentWithBolt, charging)
    check(defaultCharging.attributedTitle.string == "85% \(bolt)", "default shows percent and bolt while charging")
    check(defaultCharging.image != nil && defaultCharging.imagePosition == .imageLeading, "default shows icon left of the text")
    check(defaultCharging.toolTip == "提示", "tooltip is applied")

    let defaultIdle = render(.iconPercentWithBolt, idle)
    check(defaultIdle.attributedTitle.string == "72%", "default hides bolt when not charging")

    let defaultStaleCharging = render(.iconPercentWithBolt, charging, stale: true)
    check(defaultStaleCharging.attributedTitle.string == "85% \(bolt)", "stale charging reading keeps the bolt as before")

    let defaultNoReading = render(.iconPercentWithBolt, nil)
    check(defaultNoReading.attributedTitle.string.isEmpty, "default without a reading has no text")
    check(defaultNoReading.image != nil && defaultNoReading.imagePosition == .imageOnly, "default without a reading shows only the icon")

    let iconOnly = render(.iconOnly, charging)
    check(iconOnly.attributedTitle.string.isEmpty, "icon only has no text")
    check(iconOnly.image != nil && iconOnly.imagePosition == .imageOnly, "icon only keeps imageOnly after the title is cleared")

    let percentCharging = render(.percentWithBolt, charging)
    check(percentCharging.attributedTitle.string == "85% \(bolt)", "percent with bolt shows the bolt while charging")
    check(percentCharging.image == nil && percentCharging.imagePosition == .noImage, "percent with bolt has no icon")

    let percentIdle = render(.percentWithBolt, idle)
    check(percentIdle.attributedTitle.string == "72%", "percent with bolt hides the bolt when not charging")

    let percentNoReading = render(.percentWithBolt, nil)
    check(percentNoReading.attributedTitle.string == "--", "percent only mode shows a placeholder without a reading")

    let iconPercent = render(.iconPercent, charging)
    check(iconPercent.attributedTitle.string == "85%", "icon and percent never shows the bolt")
    check(iconPercent.image != nil && iconPercent.imagePosition == .imageLeading, "icon and percent keeps icon left of the text")

    let iconPercentNoReading = render(.iconPercent, nil)
    check(iconPercentNoReading.image != nil && iconPercentNoReading.imagePosition == .imageOnly, "icon and percent without a reading shows only the icon")
}
