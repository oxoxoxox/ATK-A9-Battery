import AppKit

func runMenuBarIconTests() {
    check(MenuBarIcon.tone(percent: 72, isCharging: false, stale: false) == .normal, "72% uses the normal colour")
    check(MenuBarIcon.tone(percent: 41, isCharging: false, stale: false) == .normal, "41% is normal, 40% and below turns low")
    check(MenuBarIcon.tone(percent: 40, isCharging: false, stale: false) == .low, "40% turns low")
    check(MenuBarIcon.tone(percent: 21, isCharging: false, stale: false) == .low, "21% is low, 20% and below turns critical")
    check(MenuBarIcon.tone(percent: 20, isCharging: false, stale: false) == .critical, "20% turns critical")
    check(MenuBarIcon.tone(percent: 0, isCharging: false, stale: false) == .critical, "0% is critical")
    check(MenuBarIcon.tone(percent: 91, isCharging: true, stale: false) == .charging, "charging wins over the percentage")
    check(MenuBarIcon.tone(percent: 91, isCharging: true, stale: true) == .unknown, "a stale reading hides the charging state")
    check(MenuBarIcon.tone(percent: nil, isCharging: false, stale: false) == .unknown, "no reading is unknown")

    let image = MenuBarIcon.image(
        percent: 45,
        isCharging: false,
        stale: false,
        appearance: NSAppearance(named: .darkAqua)!
    )
    check(image.size == NSSize(width: 22, height: 22), "the icon keeps its 22pt menu bar canvas")
    check(!image.isTemplate, "the icon keeps its own colours instead of following the template tint")
    let rep = image.representations.compactMap { $0 as? NSBitmapImageRep }.first
    check(rep?.pixelsWide == 44 && rep?.pixelsHigh == 44, "the icon renders at 2x for Retina menu bars")
    check(rep?.hasAlpha == true, "the icon keeps a transparent background")
}
