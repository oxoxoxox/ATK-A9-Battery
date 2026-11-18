import AppKit
import SwiftUI

// 面板顶部的大图标与菜单栏使用同一套绘制规则，按 68pt 画布重新渲染。
struct BatteryRingView: View {
    let percent: Int?
    let isCharging: Bool
    let stale: Bool

    @Environment(\.colorScheme) private var colorScheme

    private static let canvas: CGFloat = 68

    var body: some View {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
        Image(nsImage: MenuBarIcon.image(
            percent: percent,
            isCharging: isCharging,
            stale: stale,
            appearance: appearance,
            canvas: Self.canvas
        ))
        .resizable()
        .interpolation(.high)
        .frame(width: Self.canvas, height: Self.canvas)
        .accessibilityLabel(percent.map { "电量 \($0)%" } ?? "电量未知")
    }
}
