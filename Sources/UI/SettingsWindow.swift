import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("菜单栏显示")
                    .font(.system(size: 15, weight: .semibold))
                Text("选择菜单栏上显示的内容，修改后立即生效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(MenuBarDisplay.allCases) { option in
                    DisplayOptionRow(option: option, isSelected: settings.menuBarDisplay == option) {
                        settings.menuBarDisplay = option
                    }
                }
            }
            Text("预览为示例数值 86%（充电中）。闪电：充电时绿色实心，未充电时灰色空心。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct DisplayOptionRow: View {
    let option: MenuBarDisplay
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(option.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                MenuBarPreview(mode: option)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MenuBarPreview: View {
    let mode: MenuBarDisplay

    var body: some View {
        HStack(spacing: 4) {
            if mode.showsIcon {
                Image(systemName: "computermouse")
            }
            if mode.showsPercent {
                Text("86%")
                    .monospacedDigit()
            }
            if mode.showsBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.green)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 84)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }
}

final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "设置"
            window.isReleasedWhenClosed = false
            hosting.view.layoutSubtreeIfNeeded()
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.bringToFront()
        window?.makeKeyAndOrderFront(nil)
    }
}
