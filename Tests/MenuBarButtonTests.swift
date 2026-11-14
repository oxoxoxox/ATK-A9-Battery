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

    func boltImage(_ button: NSButton) -> NSImage? {
        let title = button.attributedTitle
        guard title.length > 0 else { return nil }
        let attachment = title.attribute(.attachment, at: title.length - 1, effectiveRange: nil) as? NSTextAttachment
        return attachment?.image
    }

    let defaultCharging = render(.iconPercentWithBolt, charging)
    check(defaultCharging.attributedTitle.string == "85% \(bolt)", "default shows percent and bolt while charging")
    check(defaultCharging.image != nil && defaultCharging.imagePosition == .imageLeading, "default shows icon left of the text")
    check(defaultCharging.toolTip == "提示", "tooltip is applied")
    check(boltImage(defaultCharging)?.accessibilityDescription == "充电中", "charging shows the solid green bolt")
    check(boltImage(defaultCharging)?.isTemplate == false, "bolt keeps its own color instead of following the menu bar")

    let defaultIdle = render(.iconPercentWithBolt, idle)
    check(defaultIdle.attributedTitle.string == "72% \(bolt)", "default shows a bolt when not charging")
    check(boltImage(defaultIdle)?.accessibilityDescription == "未充电", "not charging shows the hollow gray bolt")

    let defaultStaleCharging = render(.iconPercentWithBolt, charging, stale: true)
    check(defaultStaleCharging.attributedTitle.string == "85% \(bolt)", "stale reading keeps the bolt in its last known state")
    check(boltImage(defaultStaleCharging)?.accessibilityDescription == "充电中", "stale charging reading keeps the green bolt")

    let staleIdle = render(.iconPercentWithBolt, idle, stale: true)
    check(boltImage(staleIdle)?.accessibilityDescription == "未充电", "stale idle reading keeps the hollow bolt")

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
    check(percentIdle.attributedTitle.string == "72% \(bolt)", "percent with bolt shows the hollow bolt when not charging")

    let percentNoReading = render(.percentWithBolt, nil)
    check(percentNoReading.attributedTitle.string == "--", "percent only mode shows a placeholder without a reading")

    let iconPercent = render(.iconPercent, charging)
    check(iconPercent.attributedTitle.string == "85%", "icon and percent never shows the bolt")
    check(iconPercent.image != nil && iconPercent.imagePosition == .imageLeading, "icon and percent keeps icon left of the text")

    let iconPercentNoReading = render(.iconPercent, nil)
    check(iconPercentNoReading.image != nil && iconPercentNoReading.imagePosition == .imageOnly, "icon and percent without a reading shows only the icon")
}
